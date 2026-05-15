import argparse
import io
import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

import pymysql
import yaml

# Windows 콘솔 UTF-8 출력
if sys.stdout.encoding and sys.stdout.encoding.lower() not in ("utf-8", "utf8"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")


# =========================================================
# DB 설정 (환경에 맞게 수정)
# =========================================================
DB_CONFIG = {
    "host": os.getenv("DB_HOST", "127.0.0.1"),
    "port": int(os.getenv("DB_PORT", "3306")),
    "user": os.getenv("DB_USER", "root"),
    "password": os.getenv("DB_PASSWORD", "Staver12^^"),      # <- 수정
    "database": os.getenv("DB_NAME", "customs_auction"),
    "charset": "utf8mb4",
    "cursorclass": pymysql.cursors.DictCursor,
    "autocommit": False,
}


# =========================================================
# SQL
# =========================================================
SQL_FETCH_ITEMS = """
SELECT pbac_no, pbac_srno, cmdt_ln_no, cmdt_nm
FROM auction_item
ORDER BY pbac_no, pbac_srno, cmdt_ln_no
"""

SQL_UPSERT_CLASSIFICATION = """
INSERT INTO item_classification
(pbac_no, pbac_srno, cmdt_ln_no, category_id, model_name, model_ver, confidence, rationale)
VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
ON DUPLICATE KEY UPDATE
  category_id = VALUES(category_id),
  model_name  = VALUES(model_name),
  model_ver   = VALUES(model_ver),
  confidence  = VALUES(confidence),
  rationale   = VALUES(rationale),
  updated_at  = CURRENT_TIMESTAMP
"""

SQL_UPSERT_TOKEN = """
INSERT INTO item_search_token
(pbac_no, pbac_srno, cmdt_ln_no, token, token_type, weight)
VALUES (%s,%s,%s,%s,%s,%s)
ON DUPLICATE KEY UPDATE
  token_type = VALUES(token_type),
  weight     = VALUES(weight)
"""

SQL_FETCH_CATEGORIES = """
SELECT category_id, parent_id, level, name_ko
FROM category
WHERE is_active = 1
"""

SQL_FETCH_SYNONYMS = """
SELECT src_term, norm_term, term_type, weight, is_active
FROM synonym_dictionary
WHERE is_active = 1
"""


# =========================================================
# 유틸
# =========================================================
TOKEN_SPLIT_RE = re.compile(r"[^A-Z0-9]+")


def normalize_text(s: str) -> str:
    # 영문/숫자 중심 정규화: 대문자, 공백/기호 정리
    s = (s or "").upper()
    s = re.sub(r"\s+", " ", s).strip()
    return s


def extract_raw_tokens(norm: str) -> Set[str]:
    # A-Z0-9 기준 토큰 분리
    if not norm:
        return set()
    tokens = set(t for t in TOKEN_SPLIT_RE.split(norm) if t)
    # 너무 짧은 토큰 제거(필요시)
    tokens = {t for t in tokens if len(t) >= 2}
    return tokens


@dataclass
class CategoryNode:
    category_id: int
    parent_id: Optional[int]
    level: int
    name_ko: str


class CategoryResolver:
    """category(name_ko + parent_id) 기반으로 경로 -> category_id 해석 + 역방향(leaf->ancestors) 추적."""

    def __init__(self, nodes: Dict[int, CategoryNode]):
        self.nodes = nodes
        self.by_parent_name: Dict[Tuple[Optional[int], str], int] = {}
        for cid, node in nodes.items():
            self.by_parent_name[(node.parent_id, node.name_ko)] = cid

    def resolve_path(self, path: List[str]) -> Optional[int]:
        """['산업·장비','계측·시험','측정기기'] 같은 한글 경로를 category_id로."""
        parent_id: Optional[int] = None
        cid: Optional[int] = None
        for name in path:
            cid = self.by_parent_name.get((parent_id, name))
            if cid is None:
                return None
            parent_id = cid
        return cid

    def get_ancestors_names(self, category_id: int) -> List[str]:
        """leaf부터 root까지 name_ko를 반환 (leaf->...->root)."""
        names: List[str] = []
        cur = self.nodes.get(category_id)
        while cur:
            names.append(cur.name_ko)
            if cur.parent_id is None:
                break
            cur = self.nodes.get(cur.parent_id)
        return names  # leaf first

    def get_leaf_paths(self) -> List[List[str]]:
        """활성 카테고리 중 leaf 노드들의 root->leaf 경로를 반환."""
        parent_ids = {node.parent_id for node in self.nodes.values() if node.parent_id is not None}
        leaf_ids = sorted(cid for cid in self.nodes.keys() if cid not in parent_ids)
        paths: List[List[str]] = []
        for leaf_id in leaf_ids:
            names_leaf_to_root = self.get_ancestors_names(leaf_id)
            if not names_leaf_to_root:
                continue
            paths.append(list(reversed(names_leaf_to_root)))
        return paths

    def get_mid_paths(self) -> List[List[str]]:
        """중분류(level-2) 노드까지만 경로를 반환.
        - level-2 노드: 대분류 > 중분류 (2단계)
        - level-1 leaf (중분류가 없는 대분류): 대분류 (1단계)
        OpenAI 분류 목표를 소분류가 아닌 중분류로 제한할 때 사용.
        """
        # level-2 자녀를 가진 level-1 노드 ID 집합
        level1_with_children = {
            node.parent_id
            for node in self.nodes.values()
            if node.level == 2 and node.parent_id is not None
        }
        paths: List[List[str]] = []
        seen: set = set()
        for cid, node in sorted(self.nodes.items()):
            if node.level == 2:
                names = self.get_ancestors_names(cid)
                path = list(reversed(names))
                key = " > ".join(path)
                if key not in seen:
                    seen.add(key)
                    paths.append(path)
            elif node.level == 1 and cid not in level1_with_children:
                # 중분류 없는 대분류 (의류·패션잡화, 뷰티·위생 등)
                key = node.name_ko
                if key not in seen:
                    seen.add(key)
                    paths.append([node.name_ko])
        return paths


# =========================================================
# Rule-based 분류
# =========================================================
@dataclass
class Rule:
    name: str
    keywords_any: Set[str]             # 하나라도 포함되면 매칭
    keywords_all: Set[str]             # 전부 포함돼야 매칭
    category_path: List[str]           # category 경로
    base_conf: float                   # 기본 신뢰도
    rationale_hint: str                # 근거 텍스트


def build_rules(rules_path: Optional[str] = None) -> List[Rule]:
    """
    rules.yaml을 읽어 Rule 목록을 반환합니다.
    파일이 없거나 yaml 패키지가 없으면 하드코딩 fallback을 사용합니다.

    rules.yaml 위치 우선순위:
      1. rules_path 인수
      2. 이 스크립트와 같은 디렉터리의 rules.yaml
      3. 하드코딩 fallback
    """
    if rules_path is None:
        rules_path = str(Path(__file__).parent / "rules.yaml")

    try:
        with open(rules_path, encoding="utf-8") as f:
            data = yaml.safe_load(f)
        rules: List[Rule] = []
        for r in sorted(data.get("rules", []), key=lambda x: x.get("priority", 999)):
            rules.append(
                Rule(
                    name=r["id"],
                    keywords_any=set(r.get("keywords_any") or []),
                    keywords_all=set(r.get("keywords_all") or []),
                    category_path=r["category_path"],
                    base_conf=float(r.get("confidence", 0.80)),
                    rationale_hint=r.get("rationale", ""),
                )
            )
        print(f"ℹ️ rules.yaml 로드: {len(rules)}개 Rule ({rules_path})")
        return rules
    except FileNotFoundError:
        print(f"⚠️ rules.yaml 없음 ({rules_path}) → 하드코딩 fallback 사용")
    except Exception as e:
        print(f"⚠️ rules.yaml 로드 실패 ({e}) → 하드코딩 fallback 사용")

    # ── 하드코딩 fallback (rules.yaml 없을 때) ──────────────────────────────
    return [
        # === 식품·음료: 주류 ===
        Rule(
            name="alcohol_wine",
            keywords_any={"WINE", "WHISKY", "WHISKEY", "VODKA", "BEER", "RUM", "GIN", "CHAMPAGNE"},
            keywords_all=set(),
            category_path=["식품·음료", "음료", "주류"],
            base_conf=0.88,
            rationale_hint="alcohol keyword match",
        ),

        # === 배터리 ===
        Rule(
            name="battery_lithium",
            keywords_any={"LITHIUM", "LIION", "LI-ION", "LIPO", "LI-PO"},
            keywords_all={"BATTERY"},
            category_path=["부품·소모품", "배터리·전지", "리튬배터리"],
            base_conf=0.90,
            rationale_hint="lithium + battery",
        ),
        Rule(
            name="battery_general",
            keywords_any={"BATTERY", "CELL"},
            keywords_all=set(),
            category_path=["부품·소모품", "배터리·전지", "일반 배터리"],
            base_conf=0.82,
            rationale_hint="battery keyword match",
        ),

        # === 산업·장비: 계측/시험 ===
        Rule(
            name="industry_meter_gauge",
            keywords_any={"GAUGE", "METER", "CALIBRATOR", "INDICATOR"},
            keywords_all=set(),
            category_path=["산업·장비", "계측·시험", "측정기기"],
            base_conf=0.86,
            rationale_hint="meter/gauge keyword match",
        ),
        Rule(
            name="industry_sensor_instrument",
            keywords_any={"SENSOR", "TRANSMITTER", "INSTRUMENT", "INSTRUMENTATION"},
            keywords_all=set(),
            category_path=["산업·장비", "계측·시험", "센서·계측"],
            base_conf=0.84,
            rationale_hint="sensor/instrument keyword match",
        ),
        Rule(
            name="industry_test_inspection",
            keywords_any={"TEST", "TESTER", "INSPECTION", "ANALYZER", "ANALYSER"},
            keywords_all=set(),
            category_path=["산업·장비", "계측·시험", "시험·검사장비"],
            base_conf=0.83,
            rationale_hint="test/inspection keyword match",
        ),

        # === 산업·장비: 유체/배관 ===
        Rule(
            name="industry_pump",
            keywords_any={"PUMP"},
            keywords_all=set(),
            category_path=["산업·장비", "유체·배관", "펌프"],
            base_conf=0.83,
            rationale_hint="pump keyword match",
        ),
        Rule(
            name="industry_valve",
            keywords_any={"VALVE"},
            keywords_all=set(),
            category_path=["산업·장비", "유체·배관", "밸브"],
            base_conf=0.83,
            rationale_hint="valve keyword match",
        ),
        Rule(
            name="industry_pipe_fitting",
            keywords_any={"PIPE", "PIPES", "FITTING", "FITTINGS", "FLANGE"},
            keywords_all=set(),
            category_path=["산업·장비", "유체·배관", "배관·피팅"],
            base_conf=0.80,
            rationale_hint="pipe/fitting keyword match",
        ),

        # === 전자·전기 ===
        Rule(
            name="electronic_cable_connector",
            keywords_any={"CABLE", "CONNECTOR", "HARNESS"},
            keywords_all=set(),
            category_path=["전자·전기", "전자부품", "커넥터·케이블"],
            base_conf=0.80,
            rationale_hint="cable/connector keyword match",
        ),
        Rule(
            name="electronic_pcb_module",
            keywords_any={"PCB", "BOARD", "MODULE"},
            keywords_all=set(),
            category_path=["전자·전기", "전자부품", "PCB·모듈"],
            base_conf=0.80,
            rationale_hint="pcb/module keyword match",
        ),
        Rule(
            name="electrical_breaker_fuse",
            keywords_any={"BREAKER", "FUSE"},
            keywords_all=set(),
            category_path=["전자·전기", "전기부품", "차단기·퓨즈"],
            base_conf=0.79,
            rationale_hint="breaker/fuse keyword match",
        ),
        Rule(
            name="electrical_switch_relay",
            keywords_any={"SWITCH", "RELAY"},
            keywords_all=set(),
            category_path=["전자·전기", "전기부품", "스위치·릴레이"],
            base_conf=0.79,
            rationale_hint="switch/relay keyword match",
        ),
        Rule(
            name="power_supply",
            keywords_any={"POWER", "SUPPLY", "ADAPTER", "CHARGER"},
            keywords_all=set(),
            category_path=["전자·전기", "전원·변환", "전원공급장치"],
            base_conf=0.75,
            rationale_hint="power supply keyword match",
        ),

        # === 컴퓨터·모바일 ===
        Rule(
            name="computer_server",
            keywords_any={"SERVER", "DESKTOP", "PC", "WORKSTATION"},
            keywords_all=set(),
            category_path=["컴퓨터·모바일", "컴퓨터", "본체·서버"],
            base_conf=0.78,
            rationale_hint="computer/server keyword match",
        ),
        Rule(
            name="computer_peripherals",
            keywords_any={"MONITOR", "KEYBOARD", "MOUSE", "PRINTER"},
            keywords_all=set(),
            category_path=["컴퓨터·모바일", "컴퓨터", "주변기기"],
            base_conf=0.76,
            rationale_hint="peripheral keyword match",
        ),
        Rule(
            name="mobile_phone_tablet",
            keywords_any={"PHONE", "SMARTPHONE", "TABLET", "IPAD", "IPHONE"},
            keywords_all=set(),
            category_path=["컴퓨터·모바일", "모바일", "스마트폰·태블릿"],
            base_conf=0.78,
            rationale_hint="mobile device keyword match",
        ),
        Rule(
            name="storage",
            keywords_any={"SSD", "HDD", "NVME", "RAM", "MEMORY"},
            keywords_all=set(),
            category_path=["컴퓨터·모바일", "저장장치", "HDD·SSD·메모리"],
            base_conf=0.77,
            rationale_hint="storage keyword match",
        ),

        # === 자동차·공구 ===
        Rule(
            name="auto_tire_wheel",
            keywords_any={"TIRE", "TYRE", "WHEEL"},
            keywords_all=set(),
            category_path=["자동차·공구", "자동차부품", "타이어·휠"],
            base_conf=0.78,
            rationale_hint="tire/wheel keyword match",
        ),
        Rule(
            name="tools_power",
            keywords_any={"DRILL", "GRINDER", "SAW"},
            keywords_all=set(),
            category_path=["자동차·공구", "공구", "전동공구"],
            base_conf=0.76,
            rationale_hint="power tool keyword match",
        ),
        Rule(
            name="tools_hand",
            keywords_any={"WRENCH", "SPANNER", "TOOL"},
            keywords_all=set(),
            category_path=["자동차·공구", "공구", "수공구"],
            base_conf=0.72,
            rationale_hint="hand tool keyword match",
        ),

        # 추가 -------------------------------------------------------------------------------
        # 1) LEVEL GAUGES 같은 복수형 대응 (측정기기)
        Rule(
            name="industry_meter_gauges_plural",
            keywords_any={"GAUGES", "METERS"},
            keywords_all=set(),
            category_path=["산업·장비","계측·시험","측정기기"],
            base_conf=0.86,
            rationale_hint="gauges/meters plural keyword match",
            ),

        # 2) GOLD DETECTOR -> 시험/검사장비로 묶기
        Rule(
            name="industry_detector",
            keywords_any={"DETECTOR", "DETECTION"},
            keywords_all=set(),
            category_path=["산업·장비","계측·시험","시험·검사장비"],
            base_conf=0.80,
            rationale_hint="detector keyword match",
        ),

        # 3) SAKE/TEQUILA/LIQUEUR/COCKTAIL/WHISKIES -> 주류
        Rule(
            name="alcohol_more",
            keywords_any={"SAKE","TEQUILA","LIQUEUR","COCKTAIL","WHISKIES","COCKTAILS"},
            keywords_all=set(),
            category_path=["식품·음료","음료","주류"],
            base_conf=0.90,
            rationale_hint="extended alcohol keyword match",
        ),

        # 4) CHEONG JU(청주) -> 토큰이 CHEONG + JU로 나뉨: 둘 다 있어야 매칭
        Rule(
            name="alcohol_cheongju",
            keywords_any=set(),
            keywords_all={"CHEONG","JU"},
            category_path=["식품·음료","음료","주류"],
            base_conf=0.85,
            rationale_hint="CHEONG + JU match",
        ),

        # 5) 차량용 에어컨 -> 자동차부품>냉난방·에어컨
        Rule(
            name="auto_air_conditioning_installation",
            keywords_any={"UNIT", "INSTALLATION"},
            keywords_all={"AIR", "CONDITIONING"},
            category_path=["자동차·공구","자동차부품","냉난방·에어컨"],
            base_conf=0.82,
            rationale_hint="AIR+CONDITIONING with UNIT/INSTALLATION",
        ),


        # 6) CALCIUM CHLORIDE -> 화학물질
        Rule(
            name="chem_calcium_chloride",
            keywords_any=set(),
            keywords_all={"CALCIUM","CHLORIDE"},
            category_path=["부품·소모품","화학·오일·윤활","화학물질"],
            base_conf=0.82,
            rationale_hint="CALCIUM + CHLORIDE match",
        ),

        # 7) POOL / INFLATABLE / FLOATING / MAT -> 풀·물놀이 용품
        Rule(
            name="sports_pool_accessories",
            keywords_any={"POOL","INFLATABLE","FLOATING","MAT"},
            keywords_all=set(),
            category_path=["스포츠·레저","수영·물놀이","풀·물놀이 용품"],
            base_conf=0.78,
            rationale_hint="pool/inflatable/floating keyword match",
        ),

        # 8) AR SMART GLASSES -> 모바일 액세서리로 우선 분류 (추후 웨어러블로 세분화 가능)
        Rule(
            name="wearable_smart_glasses",
            keywords_any={"AR","VR"},
            keywords_all={"SMART","GLASSES"},
            category_path=["컴퓨터·모바일","모바일","액세서리"],
            base_conf=0.78,
            rationale_hint="SMART+GLASSES with AR/VR",
        ),

        # 9) ELECTRIC GUITAR -> 스포츠·레저>취미·악기>악기
        Rule(
            name="hobby_instrument_guitar",
            keywords_any={"GUITAR"},
            keywords_all=set(),
            category_path=["스포츠·레저","취미·악기","악기"],
            base_conf=0.80,
            rationale_hint="guitar keyword match",
        ),

        # 10) BEVERAGE MACHINE / ICE CREAM MAKERS -> 주방가전(커피·음료기기)
        Rule(
            name="kitchen_beverage_icecream_relaxed",
            keywords_any={"BEVERAGE","ICE","CREAM","ICECREAM","MAKER","MAKERS","MACHINE"},
            keywords_all=set(),
            category_path=["가전","주방가전","커피·음료기기"],
            base_conf=0.78,
            rationale_hint="beverage/ice-cream maker keyword match (relaxed)",
        ),
    ]  # end hardcoded fallback


def match_rule(tokens: Set[str], rules: List[Rule]) -> Optional[Tuple[Rule, Set[str]]]:
    """첫 매칭 룰을 반환 + 매칭된 키워드 집합."""
    for rule in rules:
        if rule.keywords_all and not rule.keywords_all.issubset(tokens):
            continue
        matched = tokens.intersection(rule.keywords_any) if rule.keywords_any else set()
        if rule.keywords_any and not matched:
            continue
        # keywords_any가 비어있고 keywords_all만 있는 케이스도 대응
        if not rule.keywords_any and rule.keywords_all:
            matched = set(rule.keywords_all)
        return rule, matched
    return None


# =========================================================
# SYN 사전 로딩/매칭
# =========================================================
@dataclass
class SynEntry:
    src_term: str
    norm_term: str
    term_type: str
    weight: float


def load_synonyms(cur) -> List[SynEntry]:
    cur.execute(SQL_FETCH_SYNONYMS)
    rows = cur.fetchall()
    out: List[SynEntry] = []
    for r in rows:
        out.append(
            SynEntry(
                src_term=(r["src_term"] or "").strip(),
                norm_term=(r["norm_term"] or "").strip(),
                term_type=r["term_type"],
                weight=float(r["weight"] or 1.0),
            )
        )
    return out


def synonym_tokens_from_text(norm_text: str, raw_tokens: Set[str], dict_entries: List[SynEntry]) -> List[Tuple[str, str, float]]:
    """
    사전 기반 동의어/번역 토큰 생성.
    - src_term이 raw token에 직접 포함되거나, norm_text substring으로 포함되면 매칭
    - token_type은 SYN로 통일(원하면 TRANSLATION은 KO로 분리 가능)
    """
    out: List[Tuple[str, str, float]] = []
    for e in dict_entries:
        src = e.src_term.upper()
        if not src:
            continue
        if src in raw_tokens or src in norm_text:
            token_type = "SYN"
            out.append((e.norm_term, token_type, float(e.weight)))
    return out


# =========================================================
# CATEGORY 토큰 (분류 결과 기반)  ✅ A안: token_type은 CATEGORY만 사용
# - leaf->root 개별 토큰 + root->leaf 경로 토큰( ' > ' 포함 )을 CATEGORY로 저장
# =========================================================
def category_tokens(resolver: "CategoryResolver", leaf_category_id: int) -> List[Tuple[str, str, float]]:
    """
    Returns CATEGORY tokens for a leaf category.
    1) 개별 카테고리 토큰: leaf -> root
    2) 경로(path) 토큰: root -> leaf 를 ' > '로 join (token_type='CATEGORY')
       - 경로 토큰은 token에 ' > '가 포함되므로 쿼리에서 쉽게 구분 가능
    """

    # --- 1) leaf -> root 를 안전하게 직접 구성 (중복/순환 방지)
    names_leaf_to_root: List[str] = []
    visited = set()
    cur_id = leaf_category_id

    while cur_id is not None and cur_id not in visited:
        visited.add(cur_id)
        node = resolver.nodes.get(int(cur_id))  # CategoryResolver 내부 nodes 사용
        if not node:
            break
        name = (node.name_ko or "").strip()
        if name:
            # 연속 중복 제거 (예: 같은 이름이 연속으로 들어오는 경우)
            if not names_leaf_to_root or names_leaf_to_root[-1] != name:
                names_leaf_to_root.append(name)
        cur_id = node.parent_id

    # --- 2) 개별 토큰 (leaf가 가장 중요)
    tokens: List[Tuple[str, str, float]] = []
    for i, name in enumerate(names_leaf_to_root):
        if name in CATEGORY_STOPWORDS:
            continue
        weight = 2.0 if i == 0 else 1.5 if i == 1 else 1.2
        tokens.append((name, "CATEGORY", weight))

    # --- 3) 경로 토큰 (root -> leaf)
    names_root_to_leaf = list(reversed(names_leaf_to_root))

    # 경로에서도 stopword 제거 (원하면 유지해도 되지만 보통 제거 권장)
    names_root_to_leaf = [n for n in names_root_to_leaf if n and n not in CATEGORY_STOPWORDS]

    # 혹시 중간에 같은 이름이 반복되면 제거 (비연속 포함)
    # 예: ['식품·음료','음료','주류','음료'] 같은 비정상 케이스 방지
    compact: List[str] = []
    seen_names = set()
    for n in names_root_to_leaf:
        if n in seen_names:
            continue
        seen_names.add(n)
        compact.append(n)

    path = " > ".join(compact)
    if path:
        # path는 leaf 토큰보다 약하게
        tokens.append((path, "CATEGORY", 1.35))

    return tokens



CATEGORY_STOPWORDS = {"기타", "미분류"}


# =========================================================
# OpenAI 분류기 (rule fallback 보강)
# =========================================================
@dataclass
class LLMClassification:
    category_path: List[str]
    confidence: float
    rationale: str


class OpenAIClassifier:
    def __init__(self, model_name: str, resolver: CategoryResolver, target_level: int = 2):
        self.model_name = model_name
        self.resolver = resolver
        self.client = None
        self.client_mode: Optional[str] = None
        self.init_error: Optional[str] = None
        self.disabled_reason: Optional[str] = None
        # target_level=1 → 대분류만, target_level=2 → 중분류까지, target_level=3 → 소분류까지
        self.target_level = target_level
        if target_level >= 3:
            self.leaf_paths = resolver.get_leaf_paths()
        elif target_level == 2:
            self.leaf_paths = resolver.get_mid_paths()
        else:  # target_level == 1
            self.leaf_paths = [
                [node.name_ko]
                for node in sorted(resolver.nodes.values(), key=lambda n: n.category_id)
                if node.level == 1
            ]

        api_key = os.getenv("OPENAI_API_KEY", "").strip()
        if not api_key:
            self.init_error = "OPENAI_API_KEY is not set"
            return

        try:
            from openai import OpenAI

            self.client = OpenAI(api_key=api_key)
            self.client_mode = "v1"
            print(f"ℹ️ OpenAI fallback enabled (model={self.model_name}, sdk=v1)")
            return
        except ImportError as e:
            if "No module named 'openai'" in str(e):
                self.init_error = "No module named 'openai'"
                print("⚠️ OpenAI client init failed: No module named 'openai'")
                print("   Install dependency with one of the commands below and rerun.")
                print(f"   - {sys.executable} -m pip install openai")
                print("   - pip install openai")
                print("   - conda install -c conda-forge openai")
                print("   Verify install target with:")
                print(f"   - {sys.executable} -m pip show openai")
                self.client = None
                return

            # openai 패키지는 있으나 구버전(0.x)이라 OpenAI 심볼이 없는 경우
            try:
                import openai as legacy_openai

                legacy_openai.api_key = api_key
                self.client = legacy_openai
                self.client_mode = "legacy"
                print(f"ℹ️ OpenAI fallback enabled (model={self.model_name}, sdk=legacy)")
                print("   Tip: 최신 SDK 사용 권장 -> python -m pip install -U openai")
                return
            except Exception as legacy_e:
                self.init_error = f"{e}; legacy fallback failed: {legacy_e}"
                print(f"⚠️ OpenAI client init failed: {self.init_error}")
                self.client = None
                return
        except Exception as e:
            self.init_error = str(e)
            print(f"⚠️ OpenAI client init failed: {e}")
            self.client = None

    @property
    def enabled(self) -> bool:
        return self.client is not None

    def _create_completion(self, sys_prompt: str, user_prompt: dict):
        if self.client_mode == "legacy":
            return self.client.ChatCompletion.create(
                model=self.model_name,
                temperature=0,
                messages=[
                    {"role": "system", "content": sys_prompt},
                    {"role": "user", "content": json.dumps(user_prompt, ensure_ascii=False)},
                ],
            )

        return self.client.chat.completions.create(
            model=self.model_name,
            temperature=0,
            response_format={"type": "json_object"},
            messages=[
                {"role": "system", "content": sys_prompt},
                {"role": "user", "content": json.dumps(user_prompt, ensure_ascii=False)},
            ],
        )

    def _disable_on_quota_error(self, err: Exception) -> bool:
        text = str(err).lower()
        is_quota = (
            "insufficient_quota" in text
            or "exceeded your current quota" in text
            or "billing" in text and "quota" in text
        )
        if not is_quota:
            return False

        self.client = None
        self.disabled_reason = "insufficient_quota"
        print("⚠️ OpenAI disabled for remaining items: insufficient_quota")
        print("   Check OpenAI billing/usage and rerun after quota is available.")
        return True

    def classify(self, cmdt_nm: str, raw_tokens: Set[str]) -> Optional[LLMClassification]:
        """
        OpenAI API로 물품명 분류.

        설계서(CLASSIFICATION_LOGIC_DESIGN.md) §5 기준:
        - 시스템 프롬프트: 분류 절차 4단계 명시
        - 사용자 프롬프트: extracted_keywords + candidate_categories 포함
        - 출력: category_path / confidence / matched_keywords / reason / alternative
        - 재시도: JSON 파싱 실패 시 1회 재시도
        """
        if not self.enabled:
            return None

        allowed_paths = [" > ".join(p) for p in self.leaf_paths if p]
        if not allowed_paths:
            return None

        # ── 시스템 프롬프트 ────────────────────────────────────────────────
        depth_guide = (
            "대분류 또는 '대분류 > 중분류' 두 단계 경로"
            if self.target_level <= 2
            else "대분류 > 중분류 > 소분류 세 단계 경로"
        )
        sys_prompt = (
            "당신은 세관 공매 물품 자동 분류 전문가입니다.\n"
            "주어진 영문 물품명을 분석하여 제공된 카테고리 목록 중 정확히 하나로 분류하세요.\n\n"
            "분류 절차:\n"
            "1. 물품명의 핵심 명사/형용사 키워드를 추출하세요\n"
            "2. 추출한 키워드와 카테고리명을 비교하여 가장 적합한 경로를 선택하세요\n"
            f"3. 분류 깊이: {depth_guide}로 분류하세요\n"
            "4. 확신도(confidence)를 0~1 사이로 평가하세요:\n"
            "   - 0.85 이상: 키워드가 카테고리와 명확히 일치\n"
            "   - 0.70~0.84: 맥락상 합리적이나 다른 해석 가능\n"
            "   - 0.70 미만: 불확실 → alternative에 차선 경로 기재\n"
            "5. category_path는 반드시 candidate_categories 목록 중 하나여야 합니다\n"
            "6. [중요] 어떤 카테고리에도 명확히 속하지 않는 물품(장식품·잡화·불명 물품 등)은\n"
            "   억지로 관련 없는 카테고리에 배치하지 말고 반드시 '기타 > 미분류'를 선택하고\n"
            "   confidence를 0.60 이하로 설정하세요.\n\n"
            "반드시 아래 JSON 형식으로만 응답하세요. 다른 텍스트는 절대 포함하지 마세요."
        )

        # ── 사용자 프롬프트 ────────────────────────────────────────────────
        token_upper = {t.upper() for t in raw_tokens}
        def path_relevance(p: List[str]) -> int:
            joined = " ".join(p).upper()
            return sum(1 for t in token_upper if t in joined)

        scored = sorted(allowed_paths, key=lambda p: path_relevance(p.split(" > ")), reverse=True)
        candidate_paths = scored[:20] if len(scored) > 20 else scored

        depth_schema = (
            ["대분류"] if self.target_level == 1
            else ["대분류", "중분류"] if self.target_level <= 2
            else ["대분류", "중분류", "소분류"]
        )
        user_prompt = {
            "item_name": cmdt_nm,
            "extracted_keywords": sorted(raw_tokens),
            "candidate_categories": candidate_paths,
            "output_schema": {
                "category_path": depth_schema,
                "confidence": "0.0~1.0 실수",
                "matched_keywords": ["분류 근거가 된 키워드 목록"],
                "reason": "한 줄 근거 (매칭된 키워드 반드시 포함)",
                "alternative": "확신도 낮을 때 차선 카테고리 경로 문자열, 없으면 null",
            },
        }

        # ── API 호출 (실패 시 1회 재시도) ────────────────────────────────
        parsed = None
        for attempt in range(2):
            try:
                resp = self._create_completion(sys_prompt, user_prompt)
                content = (resp.choices[0].message.content or "{}").strip()
                # JSON 블록 감싸진 경우 처리 (```json ... ```)
                if content.startswith("```"):
                    content = content.split("```")[1]
                    if content.startswith("json"):
                        content = content[4:]
                parsed = json.loads(content)
                break
            except json.JSONDecodeError as e:
                if attempt == 0:
                    print(f"⚠️ OpenAI JSON 파싱 실패 (1차), 재시도: {e}")
                    continue
                print(f"⚠️ OpenAI JSON 파싱 실패 (2차), 포기: {e}")
                return None
            except Exception as e:
                if self._disable_on_quota_error(e):
                    return None
                print(f"⚠️ OpenAI classification failed: {e}")
                return None

        if parsed is None:
            return None

        # ── 응답 파싱 ─────────────────────────────────────────────────────
        path = parsed.get("category_path") or []
        raw_confidence = parsed.get("confidence", 0.0)
        matched_kws = parsed.get("matched_keywords") or []
        reason = str(parsed.get("reason") or "openai classification")
        alternative = parsed.get("alternative")

        try:
            confidence = float(raw_confidence or 0.0)
        except (TypeError, ValueError):
            print(f"⚠️ invalid confidence={raw_confidence!r}")
            return None

        if not isinstance(path, list) or not path:
            return None

        normalized = [str(x).strip() for x in path if str(x).strip()]
        path_str = " > ".join(normalized)
        if path_str not in allowed_paths:
            # 허용 경로에 없으면 alternative 시도
            if alternative and isinstance(alternative, str):
                alt_parts = [p.strip() for p in alternative.split(">") if p.strip()]
                if " > ".join(alt_parts) in allowed_paths:
                    normalized = alt_parts
                    confidence = max(0.55, confidence - 0.10)
                    reason = f"[alt] {reason}"
                else:
                    return None
            else:
                return None

        # 근거에 matched_keywords 포함
        if matched_kws:
            rationale = f"{reason} | matched={sorted(matched_kws)}"
        else:
            rationale = reason

        confidence = max(0.0, min(0.99, confidence))
        return LLMClassification(
            category_path=normalized,
            confidence=confidence,
            rationale=rationale[:500],
        )

# =========================================================
# 메인
# =========================================================
def main():
    parser = argparse.ArgumentParser(description="Rule-based classification + search token builder")
    parser.add_argument("--limit", type=int, default=0, help="Process only N items (0=all)")
    parser.add_argument("--dry-run", action="store_true", help="Do not write to DB")
    parser.add_argument("--model-ver", type=str, default="rule-v1", help="Model version tag")
    parser.add_argument("--use-openai", action="store_true", help="Enable OpenAI fallback classifier")
    parser.add_argument("--openai-model", type=str, default="gpt-4o-mini", help="OpenAI model name")
    parser.add_argument(
        "--openai-target-level", type=int, default=2, choices=[1, 2, 3],
        help="OpenAI 분류 깊이: 1=대분류, 2=중분류(기본), 3=소분류",
    )
    parser.add_argument(
        "--strict-openai",
        action="store_true",
        help="Fail fast when --use-openai is set but OpenAI client cannot be initialized",
    )
    parser.add_argument(
        "--rules-file",
        type=str,
        default=None,
        help="rules.yaml 경로 (기본: classification/rules.yaml)",
    )
    parser.add_argument(
        "--rule-only-update",
        action="store_true",
        help="Rule 매칭된 물품만 DB 업데이트. 미매칭 시 기존 분류 결과 유지 (OpenAI 결과 보호)",
    )
    args = parser.parse_args()

    try:
        conn = pymysql.connect(**DB_CONFIG)
    except pymysql.err.OperationalError as e:
        if getattr(e, "args", None) and len(e.args) >= 2 and e.args[0] == 1045:
            host = DB_CONFIG.get("host")
            port = DB_CONFIG.get("port")
            user = DB_CONFIG.get("user")
            db_name = DB_CONFIG.get("database")
            raise RuntimeError(
                "MySQL 인증 실패(1045): DB 계정/호스트 권한을 확인하세요.\n"
                f"- 현재 설정: user={user}, host={host}, port={port}, db={db_name}\n"
                "- 실행 전 환경변수로 지정 가능: DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME\n"
                "- Windows PowerShell 예시:\n"
                "  $env:DB_HOST='127.0.0.1'; $env:DB_PORT='3306'; $env:DB_USER='root'; $env:DB_PASSWORD='<비밀번호>'; $env:DB_NAME='customs_auction'\n"
                "- MySQL에서 root@localhost만 있고 root@127.0.0.1 권한이 없으면 실패할 수 있습니다. 이 경우 DB_HOST를 localhost로 바꿔 재시도하세요."
            ) from e
        raise

    rules = build_rules(args.rules_file)

    processed = 0
    classified = 0
    classified_openai = 0
    fallbacked = 0
    token_written = 0

    try:
        with conn.cursor() as cur:
            # Load categories
            cur.execute(SQL_FETCH_CATEGORIES)
            cat_rows = cur.fetchall()
            nodes: Dict[int, CategoryNode] = {}
            for r in cat_rows:
                nodes[int(r["category_id"])] = CategoryNode(
                    category_id=int(r["category_id"]),
                    parent_id=int(r["parent_id"]) if r["parent_id"] is not None else None,
                    level=int(r["level"]),
                    name_ko=r["name_ko"],
                )
            resolver = CategoryResolver(nodes)
            llm_classifier = (
                OpenAIClassifier(args.openai_model, resolver, target_level=args.openai_target_level)
                if args.use_openai else None
            )
            if args.use_openai and llm_classifier and not llm_classifier.enabled:
                msg = (
                    f"OpenAI fallback requested but unavailable: {llm_classifier.init_error or 'unknown reason'}"
                )
                if args.strict_openai:
                    raise RuntimeError(msg)
                print(f"⚠️ {msg}")
                print("   Continuing with rule/fallback only. Use --strict-openai to fail fast.")

            # Resolve fallback category: 기타 > 미분류 > 기타
            fallback_id = resolver.resolve_path(["기타", "미분류", "기타"])
            if fallback_id is None:
                raise RuntimeError("Fallback category path not found: ['기타','미분류','기타'] (seed_category.sql 실행 확인)")

            # Load synonym dict (optional)
            dict_entries = load_synonyms(cur)

            # Fetch items
            cur.execute(SQL_FETCH_ITEMS)
            items = cur.fetchall()

            if args.limit and args.limit > 0:
                items = items[: args.limit]

            for it in items:
                pbac_no = it["pbac_no"]
                pbac_srno = it["pbac_srno"]
                cmdt_ln_no = it["cmdt_ln_no"]
                cmdt_nm = it["cmdt_nm"] or ""

                norm = normalize_text(cmdt_nm)
                raw_tokens = extract_raw_tokens(norm)

                # --- classify
                m = match_rule(raw_tokens, rules)
                model_name = "rule"
                model_ver = args.model_ver
                rule_matched = False

                if m:
                    rule, matched_keywords = m
                    cid = resolver.resolve_path(rule.category_path)
                    if cid is None:
                        # 카테고리 seed 누락 시 fallback
                        cid = fallback_id
                        conf = 0.50
                        rationale = f"[fallback] category path not found: {rule.category_path}"
                        fallbacked += 1
                    else:
                        # keyword 수에 따라 confidence 약간 가중
                        conf = min(0.99, rule.base_conf + 0.02 * max(0, len(matched_keywords) - 1))
                        rationale = f"[{rule.name}] {rule.rationale_hint} | matched={sorted(matched_keywords)}"
                        classified += 1
                        rule_matched = True
                else:
                    llm_result = llm_classifier.classify(cmdt_nm, raw_tokens) if llm_classifier else None
                    if llm_result:
                        cid = resolver.resolve_path(llm_result.category_path)
                        if cid is not None:
                            conf = max(0.55, llm_result.confidence)
                            rationale = f"[openai] {llm_result.rationale} | path={' > '.join(llm_result.category_path)}"
                            model_name = "openai"
                            model_ver = args.openai_model
                            classified_openai += 1
                        else:
                            cid = fallback_id
                            conf = 0.55
                            rationale = "[fallback] openai path not found in category tree"
                            fallbacked += 1
                    else:
                        cid = fallback_id
                        conf = 0.55
                        rationale = "[fallback] no rule matched"
                        fallbacked += 1

                # --rule-only-update: Rule 미매칭 시 기존 분류 결과 보존
                skip_write = args.rule_only_update and not rule_matched

                # --- write classification
                if not args.dry_run and not skip_write:
                    cur.execute(
                        SQL_UPSERT_CLASSIFICATION,
                        (
                            pbac_no,
                            pbac_srno,
                            cmdt_ln_no,
                            cid,
                            model_name,
                            model_ver,
                            conf,
                            rationale,
                        ),
                    )

                                # --- tokens: RAW + SYN + CATEGORY
                tokens_to_write: List[Tuple[str, str, float]] = []

                # RAW tokens (대문자 원문 토큰)
                for t in sorted(raw_tokens):
                    tokens_to_write.append((t[:100], "RAW", 1.00))

                # SYN tokens (사전 기반)
                syns = synonym_tokens_from_text(norm, raw_tokens, dict_entries)
                for tok, ttype, w in syns:
                    if tok:
                        tokens_to_write.append((tok[:100], ttype, float(w)))

                # CATEGORY tokens (분류 결과 기반)  ✅ '기타/미분류' 제외 + 경로 토큰 포함
                for tok, ttype, w in category_tokens(resolver, cid):
                    if not tok:
                        continue
                    # 개별 stopword는 category_tokens 내부에서도 걸렀지만 한 번 더 안전장치
                    if ttype == "CATEGORY" and tok in CATEGORY_STOPWORDS:
                        continue
                    tokens_to_write.append((tok[:100], ttype, float(w)))

                # Dedup: (token, token_type) 기준으로 weight 큰 것 유지
                best: Dict[Tuple[str, str], float] = {}
                for tok, ttype, w in tokens_to_write:
                    tok = tok.strip()
                    if not tok:
                        continue
                    key = (tok, ttype)
                    if key not in best or w > best[key]:
                        best[key] = w

                if not args.dry_run and not skip_write:
                    # 🔥 이전 실행에서 남아있던 CATEGORY 토큰을 먼저 제거 (핵심)
                    cur.execute(
                        """
                        DELETE FROM item_search_token
                        WHERE pbac_no=%s AND pbac_srno=%s AND cmdt_ln_no=%s
                          AND token_type='CATEGORY'
                        """,
                        (pbac_no, pbac_srno, cmdt_ln_no),
                    )

                    # UPSERT tokens
                    for (tok, ttype), w in best.items():
                        cur.execute(
                            SQL_UPSERT_TOKEN,
                            (pbac_no, pbac_srno, cmdt_ln_no, tok, ttype, float(w)),
                        )
                        token_written += 1



                processed += 1

        if not args.dry_run:
            conn.commit()

        print("✅ build_classification done")
        print(f"- processed items: {processed}")
        print(f"- classified by rule: {classified}")
        print(f"- classified by openai: {classified_openai}")
        print(f"- fallback: {fallbacked}")
        print(f"- tokens upserted: {token_written}")
        print("Tip: rerun is safe (UPSERT).")

    except Exception:
        if not args.dry_run:
            conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
