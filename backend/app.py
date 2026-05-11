"""
CAIS Backend — Search-first API
================================
엔드포인트 목록
  GET /health                              서버 상태
  GET /db/health                           DB 연결 상태
  GET /search                              토큰 기반 검색 (핵심)
  GET /search/autocomplete                 자동완성
  GET /items                               전체 목록 (기존 호환)
  GET /items/{pbac_no}/{pbac_srno}/{cmdt_ln_no}/images  이미지 목록

검색 엔진 설계
──────────────
사용자 입력 (예: "와인 50만원 이하")
  ↓
[파싱]  키워드: "와인" / 필터: price ≤ 500000
  ↓
[토큰 매칭] item_search_token.token LIKE '%<keyword>%'
  ↓
[가중치 집계] SUM(weight) → score DESC, pbac_end_dttm DESC
  ↓
[필터 적용] category / price / customs_office / status
  ↓
[페이징] limit / offset
"""

import os
import re
from contextlib import closing
from datetime import datetime
from typing import Any, Dict, List, Optional

import pymysql
from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware
from pymysql.cursors import DictCursor

app = FastAPI(title="CAIS Backend", version="0.2.0")

# CORS (Flutter Web / HTML 데모 연동)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ──────────────────────────────────────────────
# DB 연결
# ──────────────────────────────────────────────
def get_db_config() -> Dict[str, Any]:
    return {
        "host": os.getenv("DB_HOST", "127.0.0.1"),
        "port": int(os.getenv("DB_PORT", "3306")),
        "user": os.getenv("DB_USER", "root"),
        "password": os.getenv("DB_PASSWORD", "password"),
        "database": os.getenv("DB_NAME", "customs_auction"),
        "charset": "utf8mb4",
        "cursorclass": DictCursor,
        "autocommit": True,
    }


def get_conn():
    return closing(pymysql.connect(**get_db_config()))


# ──────────────────────────────────────────────
# 쿼리 파싱 유틸
# ──────────────────────────────────────────────
PRICE_PATTERN = re.compile(r"(\d[\d,]*)\s*(?:만원|원|만)?")


def parse_price(text: str) -> Optional[int]:
    """'50만원', '500000원', '50만' 등을 정수(원 단위)로 변환."""
    m = PRICE_PATTERN.search(text.replace(" ", ""))
    if not m:
        return None
    raw = int(m.group(1).replace(",", ""))
    if "만" in text:
        return raw * 10_000
    return raw


def split_keywords(q: str) -> List[str]:
    """검색어를 공백 기준으로 분리, 빈 토큰 제거."""
    return [t.strip() for t in q.strip().split() if t.strip()]


# ──────────────────────────────────────────────
# 검색 핵심 쿼리 빌더
# ──────────────────────────────────────────────
def build_search_sql(
    keywords: List[str],
    category_id: Optional[int],
    price_max: Optional[int],
    price_min: Optional[int],
    cstm_sgn: Optional[str],
    status: Optional[str],          # "active" | "ended" | None(전체)
    sort: str,                      # "score" | "price_asc" | "price_desc" | "newest"
    limit: int,
    offset: int,
):
    """
    검색 흐름:
      1) item_search_token 에서 키워드 토큰 매칭
      2) weight 합산 → score 계산
      3) auction_item / auction / item_classification / category JOIN
      4) 필터(가격/카테고리/세관/공매상태) 적용
      5) 정렬 + 페이징
    """
    # ── WHERE 절 (토큰 매칭) ──────────────────
    token_conditions = []
    params: List[Any] = []

    for kw in keywords:
        token_conditions.append("ist.token LIKE %s")
        params.append(f"%{kw}%")

    token_where = " OR ".join(token_conditions) if token_conditions else "1=1"

    # ── 메인 쿼리 ────────────────────────────
    sql = f"""
        SELECT
            ai.pbac_no,
            ai.pbac_srno,
            ai.cmdt_ln_no,
            ai.cmdt_nm,
            ai.pbac_prng_prc,
            ai.cmdt_qty,
            ai.cmdt_qty_ut_cd,
            ai.cmdt_wght,
            ai.cmdt_wght_ut_cd,
            a.pbac_strt_dttm,
            a.pbac_end_dttm,
            a.cstm_sgn,
            co.cstm_name,
            a.snar_sgn,
            c.name_ko   AS category_name,
            pc.name_ko  AS parent_category_name,
            COALESCE(ic.confidence, 0) AS confidence,
            ROUND(SUM(ist.weight), 2)  AS score
        FROM item_search_token ist
        JOIN auction_item ai
          ON ai.pbac_no = ist.pbac_no
         AND ai.pbac_srno = ist.pbac_srno
         AND ai.cmdt_ln_no = ist.cmdt_ln_no
        JOIN auction a ON a.pbac_no = ai.pbac_no
        LEFT JOIN customs_office co ON co.cstm_sgn = a.cstm_sgn
        LEFT JOIN item_classification ic
          ON ic.pbac_no = ai.pbac_no
         AND ic.pbac_srno = ai.pbac_srno
         AND ic.cmdt_ln_no = ai.cmdt_ln_no
        LEFT JOIN category c ON c.category_id = ic.category_id
        LEFT JOIN category pc ON pc.category_id = c.parent_id
        WHERE ({token_where})
    """

    # ── 추가 필터 ─────────────────────────────
    if category_id:
        sql += " AND ic.category_id = %s"
        params.append(category_id)

    if price_min is not None:
        sql += " AND ai.pbac_prng_prc >= %s"
        params.append(price_min)

    if price_max is not None:
        sql += " AND ai.pbac_prng_prc <= %s"
        params.append(price_max)

    if cstm_sgn:
        sql += " AND a.cstm_sgn = %s"
        params.append(cstm_sgn)

    now_str = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
    if status == "active":
        sql += " AND a.pbac_end_dttm >= %s"
        params.append(now_str)
    elif status == "ended":
        sql += " AND a.pbac_end_dttm < %s"
        params.append(now_str)

    # ── GROUP BY ─────────────────────────────
    sql += """
        GROUP BY
            ai.pbac_no, ai.pbac_srno, ai.cmdt_ln_no,
            ai.cmdt_nm, ai.pbac_prng_prc,
            ai.cmdt_qty, ai.cmdt_qty_ut_cd,
            ai.cmdt_wght, ai.cmdt_wght_ut_cd,
            a.pbac_strt_dttm, a.pbac_end_dttm,
            a.cstm_sgn, co.cstm_name, a.snar_sgn,
            c.name_ko, pc.name_ko, ic.confidence
    """

    # ── 정렬 ─────────────────────────────────
    order_map = {
        "score":      "score DESC, a.pbac_end_dttm DESC",
        "price_asc":  "ai.pbac_prng_prc ASC, score DESC",
        "price_desc": "ai.pbac_prng_prc DESC, score DESC",
        "newest":     "a.pbac_strt_dttm DESC, score DESC",
    }
    sql += f" ORDER BY {order_map.get(sort, order_map['score'])}"

    # ── 페이징 ───────────────────────────────
    sql += " LIMIT %s OFFSET %s"
    params.extend([limit, offset])

    return sql, params


# ──────────────────────────────────────────────
# 엔드포인트
# ──────────────────────────────────────────────
@app.get("/health")
def health() -> Dict[str, str]:
    return {"status": "ok"}


@app.get("/db/health")
def db_health() -> Dict[str, str]:
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1 AS ok")
                row = cur.fetchone()
        if row and row.get("ok") == 1:
            return {"status": "ok"}
        return {"status": "error"}
    except Exception as exc:
        return {"status": "error", "message": str(exc)}


@app.get("/search")
def search(
    q: str = Query(..., description="검색어 (예: 와인, BATTERY, 측정기)"),
    category_id: Optional[int] = Query(default=None, description="카테고리 ID 필터"),
    price_min: Optional[int] = Query(default=None, description="최저 가격(원)"),
    price_max: Optional[int] = Query(default=None, description="최고 가격(원)"),
    cstm_sgn: Optional[str] = Query(default=None, description="세관 부호 필터"),
    status: Optional[str] = Query(default=None, description="active(진행중) | ended(종료)"),
    sort: str = Query(default="score", description="score | price_asc | price_desc | newest"),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> Dict[str, Any]:
    """
    토큰 기반 검색 엔진.

    - 한글/영문/동의어 모두 검색 가능 (item_search_token 활용)
    - 쿠팡/G마켓 방식: 키워드 가중치 합산 → score 정렬
    - 필터: 카테고리 / 가격 범위 / 세관 / 진행상태
    - 정렬: score(기본) / 가격 오름차순 / 가격 내림차순 / 최신순
    """
    keywords = split_keywords(q)
    if not keywords:
        return {"total": 0, "items": [], "keywords": [], "query": q}

    sql, params = build_search_sql(
        keywords=keywords,
        category_id=category_id,
        price_max=price_max,
        price_min=price_min,
        cstm_sgn=cstm_sgn,
        status=status,
        sort=sort,
        limit=limit,
        offset=offset,
    )

    # COUNT 쿼리 (페이징 total)
    count_sql = f"""
        SELECT COUNT(*) AS cnt FROM (
            SELECT ai.pbac_no
            FROM item_search_token ist
            JOIN auction_item ai
              ON ai.pbac_no = ist.pbac_no
             AND ai.pbac_srno = ist.pbac_srno
             AND ai.cmdt_ln_no = ist.cmdt_ln_no
            JOIN auction a ON a.pbac_no = ai.pbac_no
            LEFT JOIN item_classification ic
              ON ic.pbac_no = ai.pbac_no
             AND ic.pbac_srno = ai.pbac_srno
             AND ic.cmdt_ln_no = ai.cmdt_ln_no
            WHERE ({" OR ".join(["ist.token LIKE %s"] * len(keywords))})
            {"AND ic.category_id = %s" if category_id else ""}
            {"AND ai.pbac_prng_prc >= %s" if price_min is not None else ""}
            {"AND ai.pbac_prng_prc <= %s" if price_max is not None else ""}
            {"AND a.cstm_sgn = %s" if cstm_sgn else ""}
            GROUP BY ai.pbac_no, ai.pbac_srno, ai.cmdt_ln_no
        ) sub
    """
    count_params: List[Any] = [f"%{kw}%" for kw in keywords]
    if category_id:
        count_params.append(category_id)
    if price_min is not None:
        count_params.append(price_min)
    if price_max is not None:
        count_params.append(price_max)
    if cstm_sgn:
        count_params.append(cstm_sgn)

    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(count_sql, count_params)
            total = (cur.fetchone() or {}).get("cnt", 0)

            cur.execute(sql, params)
            items = cur.fetchall()

    # datetime 직렬화
    for item in items:
        for k in ("pbac_strt_dttm", "pbac_end_dttm"):
            if isinstance(item.get(k), datetime):
                item[k] = item[k].isoformat()

    return {
        "total": total,
        "limit": limit,
        "offset": offset,
        "keywords": keywords,
        "query": q,
        "items": items,
    }


@app.get("/search/autocomplete")
def autocomplete(
    q: str = Query(..., description="자동완성 입력어"),
    limit: int = Query(default=10, ge=1, le=30),
) -> Dict[str, Any]:
    """
    자동완성 API.
    - item_search_token 에서 입력어로 시작하는 토큰을 가중치 순으로 반환
    - SYN/CATEGORY 토큰 우선 (한글 자동완성 지원)
    - 쿠팡식: 한글 입력 → 한글 후보어 노출
    """
    if not q or len(q.strip()) < 1:
        return {"suggestions": []}

    kw = q.strip()
    sql = """
        SELECT
            ist.token,
            ist.token_type,
            MAX(ist.weight) AS max_weight,
            COUNT(DISTINCT ist.pbac_no) AS item_count
        FROM item_search_token ist
        WHERE ist.token LIKE %s
          AND ist.token_type IN ('SYN', 'CATEGORY', 'RAW')
        GROUP BY ist.token, ist.token_type
        ORDER BY
            CASE ist.token_type
                WHEN 'SYN'      THEN 1
                WHEN 'CATEGORY' THEN 2
                ELSE                 3
            END,
            max_weight DESC,
            item_count DESC
        LIMIT %s
    """

    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, (f"{kw}%", limit))
            rows = cur.fetchall()

    # 중복 token 제거 (token_type 다르더라도 같은 텍스트면 하나만)
    seen = set()
    suggestions = []
    for row in rows:
        token = row["token"]
        if token not in seen:
            seen.add(token)
            suggestions.append({
                "token": token,
                "token_type": row["token_type"],
                "item_count": row["item_count"],
            })

    return {"query": q, "suggestions": suggestions}


@app.get("/search/filters")
def search_filters() -> Dict[str, Any]:
    """
    검색 필터 옵션 조회.
    - 세관 목록, 대분류 카테고리 목록 반환 (필터 패널 구성용)
    """
    sql_customs = "SELECT cstm_sgn, cstm_name FROM customs_office ORDER BY cstm_name"
    sql_categories = """
        SELECT category_id, name_ko
        FROM category
        WHERE level = 1 AND is_active = 1
        ORDER BY name_ko
    """

    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(sql_customs)
            customs = cur.fetchall()
            cur.execute(sql_categories)
            categories = cur.fetchall()

    return {
        "customs_offices": customs,
        "top_categories": categories,
    }


@app.get("/items")
def list_items(
    q: Optional[str] = Query(default=None, description="물품명 검색어"),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> Dict[str, Any]:
    """기존 호환용 물품 목록 엔드포인트. 신규 개발은 /search 사용 권장."""
    sql = """
        SELECT
            ai.pbac_no,
            ai.pbac_srno,
            ai.cmdt_ln_no,
            ai.cmdt_nm,
            ai.pbac_prng_prc,
            a.pbac_strt_dttm,
            a.pbac_end_dttm
        FROM auction_item ai
        JOIN auction a ON a.pbac_no = ai.pbac_no
    """
    params: List[Any] = []

    if q:
        sql += " WHERE ai.cmdt_nm LIKE %s"
        params.append(f"%{q}%")

    sql += " ORDER BY a.pbac_end_dttm DESC LIMIT %s OFFSET %s"
    params.extend([limit, offset])

    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            items = cur.fetchall()

    for item in items:
        for k in ("pbac_strt_dttm", "pbac_end_dttm"):
            if isinstance(item.get(k), datetime):
                item[k] = item[k].isoformat()

    return {"items": items}


@app.get("/items/{pbac_no}/{pbac_srno}/{cmdt_ln_no}/images")
def item_images(
    pbac_no: str, pbac_srno: str, cmdt_ln_no: str
) -> Dict[str, List[Dict[str, Any]]]:
    sql = """
        SELECT image_seq, image_url, source_type, updated_at
        FROM auction_item_image
        WHERE pbac_no=%s AND pbac_srno=%s AND cmdt_ln_no=%s
        ORDER BY image_seq ASC
    """
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, (pbac_no, pbac_srno, cmdt_ln_no))
            images = cur.fetchall()

    for img in images:
        if isinstance(img.get("updated_at"), datetime):
            img["updated_at"] = img["updated_at"].isoformat()

    return {"images": images}
