"""
auto_rule_builder.py
====================
Fallback(기타/미분류) 물품 패턴을 분석해 rules.yaml에 규칙을 자동 추가합니다.

동작 순서:
  Phase 1 — DB에서 fallback 물품 조회
  Phase 2 — 키워드 빈도 분석 (단일·2-gram)
  Phase 3 — OpenAI로 카테고리 제안 요청
  Phase 4 — 조건 충족 시 rules.yaml에 자동 추가, 미달 시 review 파일 기록
  Phase 5 — 새 규칙이 추가된 경우 --rule-only-update 재분류 실행

사용법:
  python classification/auto_rule_builder.py --dry-run
  python classification/auto_rule_builder.py --min-count 3 --confidence 0.80
  python classification/auto_rule_builder.py --no-rerun

의존성: pymysql, yaml, openai (선택)
"""

import argparse
import io
import json
import os
import re
import shutil
import subprocess
import sys
from collections import Counter, defaultdict
from datetime import datetime
from itertools import combinations
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

import pymysql
import yaml

# Windows 콘솔 UTF-8
if sys.stdout.encoding and sys.stdout.encoding.lower() not in ("utf-8", "utf8"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

# ── 경로 ─────────────────────────────────────────────────────────────────
ROOT = Path(__file__).resolve().parent.parent
CLASSIFY_SCRIPT = ROOT / "classification" / "build_classification.py"
RULES_PATH = ROOT / "classification" / "rules.yaml"
EVAL_DIR = ROOT / "classification" / "eval"
REVIEW_FILE = EVAL_DIR / "rule_suggestions.txt"
MAX_BACKUPS = 5

# ── build_classification.py 공유 함수 import ──────────────────────────────
sys.path.insert(0, str(Path(__file__).parent))
from build_classification import (  # noqa: E402
    CategoryNode,
    CategoryResolver,
    DB_CONFIG,
    normalize_text,
    extract_raw_tokens,
)

TOKEN_STOP = {"THE", "OF", "AND", "IN", "FOR", "TO", "A", "AN", "WITH", "OR", "NO", "BY"}
CATEGORY_STOP = {"기타", "미분류"}

# ── DB ────────────────────────────────────────────────────────────────────
SQL_FALLBACK = """
SELECT ai.pbac_no, ai.pbac_srno, ai.cmdt_ln_no, ai.cmdt_nm,
       ic.confidence, ic.model_name
FROM auction_item ai
LEFT JOIN item_classification ic
  ON ic.pbac_no = ai.pbac_no AND ic.pbac_srno = ai.pbac_srno AND ic.cmdt_ln_no = ai.cmdt_ln_no
LEFT JOIN category c ON ic.category_id = c.category_id
WHERE ic.category_id IS NULL
   OR c.name_ko = '기타'
   OR c.name_ko = '미분류'
ORDER BY ai.cmdt_nm
"""

SQL_CATEGORIES = """
SELECT category_id, parent_id, level, name_ko FROM category ORDER BY level, category_id
"""


def get_db_connection():
    return pymysql.connect(**DB_CONFIG)


# ── Phase 1: Fallback 물품 조회 ──────────────────────────────────────────
def fetch_fallback_items(cur) -> List[dict]:
    cur.execute(SQL_FALLBACK)
    return cur.fetchall()


# ── Phase 2: 패턴 추출 ───────────────────────────────────────────────────
def extract_patterns(
    items: List[dict], min_count: int
) -> List[Tuple[Tuple[str, ...], List[str]]]:
    """
    Returns list of (token_tuple, sample_names) for patterns meeting min_count.
    token_tuple is either (single_token,) or (tok1, tok2) bigram.
    """
    single_counter: Counter = Counter()
    bigram_counter: Counter = Counter()
    single_names: Dict[str, List[str]] = defaultdict(list)
    bigram_names: Dict[tuple, List[str]] = defaultdict(list)

    for item in items:
        name = item["cmdt_nm"] or ""
        norm = normalize_text(name)
        tokens = extract_raw_tokens(norm) - TOKEN_STOP
        if not tokens:
            continue

        for t in tokens:
            single_counter[t] += 1
            single_names[t].append(name)

        sorted_tokens = sorted(tokens)
        for t1, t2 in combinations(sorted_tokens, 2):
            key = (t1, t2)
            bigram_counter[key] += 1
            bigram_names[key].append(name)

    candidates = []
    seen_names: Set[str] = set()

    # Bigrams first (more specific)
    for bigram, count in bigram_counter.most_common():
        if count < min_count:
            continue
        if any(t in CATEGORY_STOP for t in bigram):
            continue
        names = bigram_names[bigram][:5]
        name_key = " ".join(bigram)
        if name_key not in seen_names:
            seen_names.add(name_key)
            candidates.append((bigram, names))

    # Single tokens
    for token, count in single_counter.most_common():
        if count < min_count:
            continue
        if token in CATEGORY_STOP:
            continue
        # Skip if already covered by a bigram candidate
        already_covered = any(token in bg for bg, _ in candidates)
        if already_covered:
            continue
        names = single_names[token][:5]
        if token not in seen_names:
            seen_names.add(token)
            candidates.append(((token,), names))

    return candidates


# ── Phase 3: OpenAI 카테고리 제안 ────────────────────────────────────────
def suggest_with_openai(
    candidates: List[Tuple[Tuple[str, ...], List[str]]],
    resolver: CategoryResolver,
    model: str,
) -> List[dict]:
    """
    Returns list of {pattern, category_path, confidence, reason} per candidate.
    """
    try:
        import openai as _openai
        client = _openai.OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))
    except ImportError:
        print("⚠️  openai 패키지 없음 — OpenAI 제안 건너뜀")
        return []
    except Exception as e:
        print(f"⚠️  OpenAI 초기화 실패: {e}")
        return []

    mid_paths = resolver.get_mid_paths()
    allowed_str = "\n".join("  - " + " > ".join(p) for p in mid_paths)

    pattern_list = [
        {"pattern": " ".join(tpl), "sample_items": names}
        for tpl, names in candidates
    ]

    prompt_user = (
        "아래 각 키워드 패턴에 대해 한국 세관 공매 시스템의 카테고리를 제안해 주세요.\n"
        "반드시 allowed categories 중에서만 선택하고, "
        "JSON 형식으로만 답변하세요.\n\n"
        f"Allowed categories:\n{allowed_str}\n\n"
        f"Patterns: {json.dumps(pattern_list, ensure_ascii=False)}\n\n"
        "Response format:\n"
        '{"results": [{"pattern": "...", "category_path": ["대분류", "중분류"], '
        '"confidence": 0.0-1.0, "reason": "..."}]}'
    )

    try:
        resp = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": "한국 세관 공매 분류 전문가입니다."},
                {"role": "user", "content": prompt_user},
            ],
            temperature=0.1,
            response_format={"type": "json_object"},
        )
        raw = resp.choices[0].message.content or "{}"
        data = json.loads(raw)
        return data.get("results", [])
    except json.JSONDecodeError:
        print("⚠️  OpenAI 응답 JSON 파싱 실패")
        return []
    except Exception as e:
        print(f"⚠️  OpenAI 호출 실패: {e}")
        return []


# ── Phase 4: 결정 로직 ───────────────────────────────────────────────────
def _make_rule_id(tokens: Tuple[str, ...]) -> str:
    pattern_slug = "_".join(t.lower() for t in tokens)
    return f"auto_{pattern_slug}_{datetime.now():%Y%m%d}"


def _load_existing_rule_ids() -> Set[str]:
    if not RULES_PATH.exists():
        return set()
    with open(RULES_PATH, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    return {r["id"] for r in data.get("rules", [])}


def _backup_rules():
    """rules.yaml 백업 (최근 MAX_BACKUPS개 유지)."""
    if not RULES_PATH.exists():
        return
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = RULES_PATH.with_suffix(f".yaml.bak.{ts}")
    shutil.copy2(RULES_PATH, backup)

    # 오래된 백업 정리
    backups = sorted(RULES_PATH.parent.glob("rules.yaml.bak.*"))
    for old in backups[:-MAX_BACKUPS]:
        old.unlink(missing_ok=True)


def _append_rule_to_yaml(rule_block: str):
    """rules.yaml 파일 끝에 규칙 텍스트 블록을 추가 (comment 보존)."""
    with open(RULES_PATH, "a", encoding="utf-8") as f:
        f.write("\n")
        f.write(rule_block)


def decide_and_apply(
    candidates: List[Tuple[Tuple[str, ...], List[str]]],
    suggestions: List[dict],
    resolver: CategoryResolver,
    min_count: int,
    confidence_threshold: float,
    dry_run: bool,
) -> Tuple[int, int]:
    """
    Returns (auto_added_count, review_count).
    """
    # suggestions를 pattern 키로 인덱싱
    sugg_by_pattern: Dict[str, dict] = {s["pattern"]: s for s in suggestions}
    existing_ids = _load_existing_rule_ids()
    item_counts = _get_pattern_item_counts(candidates)

    auto_added = 0
    for_review = []

    for tokens, sample_names in candidates:
        pattern_str = " ".join(tokens)
        count = item_counts.get(tokens, len(sample_names))
        sugg = sugg_by_pattern.get(pattern_str)
        if not sugg:
            continue

        path = sugg.get("category_path", [])
        confidence = float(sugg.get("confidence", 0.0))
        reason = sugg.get("reason", "")

        # 카테고리 경로 DB 존재 확인
        cat_id = resolver.resolve_path(path) if path else None

        rule_id = _make_rule_id(tokens)

        if (
            count >= min_count
            and confidence >= confidence_threshold
            and cat_id is not None
            and not any(t in CATEGORY_STOP for t in path)
            and rule_id not in existing_ids
        ):
            # 자동 추가
            kw_any = list(tokens) if len(tokens) == 1 else []
            kw_all = list(tokens) if len(tokens) > 1 else []

            block = (
                f"  - id: {rule_id}\n"
                f"    priority: 500\n"
                f"    keywords_any: {json.dumps(kw_any, ensure_ascii=False)}\n"
                f"    keywords_all: {json.dumps(kw_all, ensure_ascii=False)}\n"
                f"    category_path: {json.dumps(path, ensure_ascii=False)}\n"
                f"    confidence: {confidence:.2f}\n"
                f'    rationale: "Auto-generated: {count}건 fallback; '
                f'OpenAI confidence={confidence:.2f}"\n'
            )
            if not dry_run:
                _append_rule_to_yaml(block)
                existing_ids.add(rule_id)
                print(f"  ✅ 자동 추가: {rule_id}  ({pattern_str} → {' > '.join(path)})")
            else:
                print(f"  [dry-run] 추가 예정: {rule_id}  ({pattern_str} → {' > '.join(path)})")
            auto_added += 1
        else:
            reason_tag = ""
            if cat_id is None:
                reason_tag = "CATEGORY NOT FOUND"
            elif confidence < confidence_threshold:
                reason_tag = f"BELOW THRESHOLD (confidence={confidence:.2f} < {confidence_threshold})"
            elif count < min_count:
                reason_tag = f"FEW ITEMS ({count} < {min_count})"
            elif rule_id in existing_ids:
                reason_tag = "DUPLICATE RULE ID"

            kw_any = list(tokens) if len(tokens) == 1 else []
            kw_all = list(tokens) if len(tokens) > 1 else []
            yaml_block = (
                f"  - id: {rule_id}\n"
                f"    priority: 500\n"
                f"    keywords_any: {json.dumps(kw_any, ensure_ascii=False)}\n"
                f"    keywords_all: {json.dumps(kw_all, ensure_ascii=False)}\n"
                f"    category_path: {json.dumps(path, ensure_ascii=False)}\n"
                f"    confidence: {confidence:.2f}\n"
                f'    rationale: "Suggested: {count}건 fallback"\n'
            )
            for_review.append({
                "pattern": pattern_str,
                "count": count,
                "path": path,
                "confidence": confidence,
                "reason_tag": reason_tag,
                "reason": reason,
                "samples": sample_names,
                "yaml_block": yaml_block,
            })

    if for_review:
        _write_review_file(for_review, dry_run)

    return auto_added, len(for_review)


def _get_pattern_item_counts(
    candidates: List[Tuple[Tuple[str, ...], List[str]]]
) -> Dict[Tuple[str, ...], int]:
    return {tokens: len(names) for tokens, names in candidates}


def _write_review_file(for_review: List[dict], dry_run: bool):
    EVAL_DIR.mkdir(parents=True, exist_ok=True)
    lines = [
        f"# auto_rule_builder 검토 필요 목록",
        f"# 생성: {datetime.now():%Y-%m-%d %H:%M:%S}"
        + (" [dry-run]" if dry_run else ""),
        "",
    ]
    for r in for_review:
        lines += [
            "=" * 48,
            f"Pattern    : {r['pattern']}",
            f"Item count : {r['count']}",
            f"Suggested  : {' > '.join(r['path']) if r['path'] else '(없음)'}",
            f"Confidence : {r['confidence']:.2f}  [{r['reason_tag']}]",
            f"OpenAI 근거: {r['reason']}",
            "Sample items:",
        ] + [f"  - {n}" for n in r["samples"]] + [
            "Rule YAML block (rules.yaml에 복사하려면 아래를 추가하세요):",
            r["yaml_block"],
        ]
    content = "\n".join(lines)
    if not dry_run:
        REVIEW_FILE.write_text(content, encoding="utf-8")
        print(f"\n📄 검토 파일 저장: {REVIEW_FILE}")
    else:
        print(f"\n[dry-run] 검토 파일 출력 ({len(for_review)}건):\n")
        print(content)


# ── Phase 5: 재분류 ──────────────────────────────────────────────────────
def rerun_classification(model: str):
    print("\n🔄 신규 규칙 기반 재분류 실행 (--rule-only-update)...")
    cmd = [
        sys.executable,
        str(CLASSIFY_SCRIPT),
        "--rule-only-update",
    ]
    result = subprocess.run(cmd, env=os.environ.copy())
    if result.returncode == 0:
        print("  ✅ 재분류 완료")
    else:
        print(f"  ❌ 재분류 실패 (exit={result.returncode})")


# ── 메인 ─────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="Fallback 물품 자동 규칙 생성기")
    parser.add_argument("--min-count", type=int, default=5,
                        help="자동 추가 최소 물품 수 (기본: 5)")
    parser.add_argument("--confidence", type=float, default=0.85,
                        help="자동 추가 최소 confidence (기본: 0.85)")
    parser.add_argument("--openai-model", default="gpt-4o-mini",
                        help="OpenAI 모델 (기본: gpt-4o-mini)")
    parser.add_argument("--dry-run", action="store_true",
                        help="DB/파일 미수정, 제안 결과만 출력")
    parser.add_argument("--no-rerun", action="store_true",
                        help="규칙 추가 후 재분류 건너뜀")
    args = parser.parse_args()

    if not os.environ.get("OPENAI_API_KEY"):
        print("⚠️  OPENAI_API_KEY 환경변수 없음 — OpenAI 제안 없이 패턴만 분석합니다")

    print(f"\n🔍 auto_rule_builder 시작  [{datetime.now():%Y-%m-%d %H:%M:%S}]")
    print(f"   min_count={args.min_count}, confidence≥{args.confidence}"
          + (" [dry-run]" if args.dry_run else ""))

    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            # ── 카테고리 로드 ───────────────────────────────────────────
            cur.execute(SQL_CATEGORIES)
            rows = cur.fetchall()
            nodes = {
                r["category_id"]: CategoryNode(
                    category_id=r["category_id"],
                    parent_id=r["parent_id"],
                    level=r["level"],
                    name_ko=r["name_ko"],
                )
                for r in rows
            }
            resolver = CategoryResolver(nodes)

            # ── Phase 1 ─────────────────────────────────────────────────
            print("\n[Phase 1] Fallback 물품 조회...")
            items = fetch_fallback_items(cur)
            print(f"  → {len(items)}건 fallback 물품")
            if not items:
                print("  분류가 필요한 fallback 물품이 없습니다.")
                return

            # ── Phase 2 ─────────────────────────────────────────────────
            print(f"\n[Phase 2] 키워드 패턴 추출 (min_count={args.min_count})...")
            candidates = extract_patterns(items, args.min_count)
            print(f"  → {len(candidates)}개 후보 패턴")
            if not candidates:
                print("  기준을 충족하는 패턴이 없습니다.")
                return
            for tpl, names in candidates[:10]:
                print(f"     {' '.join(tpl):30s}  ({len(names)}건)")
            if len(candidates) > 10:
                print(f"     ... 외 {len(candidates)-10}개")

            # ── Phase 3 ─────────────────────────────────────────────────
            print("\n[Phase 3] OpenAI 카테고리 제안...")
            suggestions = suggest_with_openai(candidates, resolver, args.openai_model)
            print(f"  → {len(suggestions)}개 제안 수신")

            # ── Phase 4 ─────────────────────────────────────────────────
            print(f"\n[Phase 4] 규칙 결정 및 적용 (threshold={args.confidence})...")
            if not args.dry_run:
                _backup_rules()
            added, reviewed = decide_and_apply(
                candidates,
                suggestions,
                resolver,
                min_count=args.min_count,
                confidence_threshold=args.confidence,
                dry_run=args.dry_run,
            )
            print(f"\n  자동 추가: {added}건 / 검토 필요: {reviewed}건")

            # ── Phase 5 ─────────────────────────────────────────────────
            if added > 0 and not args.dry_run and not args.no_rerun:
                rerun_classification(args.openai_model)

    finally:
        conn.close()

    print(f"\n✅ auto_rule_builder 완료  [{datetime.now():%Y-%m-%d %H:%M:%S}]")


if __name__ == "__main__":
    main()
