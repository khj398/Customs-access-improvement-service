"""
E01. 데이터셋 기초 통계  [필수 · 30분]
======================================
목적  논문 1장의 문제 제기("물품명이 영문 위주라 한글 검색이 불가능하다")를
      추측이 아니라 실측치로 뒷받침하고, 4.1절 표 3을 채운다.

논문 대응  4.1절 표 3 (데이터셋 기초 통계)
실험계획서  6장 E1

실행:
    python Additional_Experiment/scripts/e01_dataset_stats.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))

import exp_common as C  # noqa: E402


def main() -> int:
    rep = C.Report("E01", "데이터셋 기초 통계", paper_ref="4.1절 표 3", plan_ref="6장 E1")
    conn = C.db_conn()

    # ── (1) 전체 규모 ──────────────────────────────────
    rep.section("(1) 전체 규모")
    scale = C.fetch_one(conn, """
        SELECT (SELECT COUNT(*) FROM auction)             AS auctions,
               (SELECT COUNT(*) FROM auction_item)        AS items,
               (SELECT COUNT(*) FROM customs_office)      AS customs_offices,
               (SELECT COUNT(*) FROM auction_item_image)  AS images
    """)
    rep.table(
        ["항목", "건수"],
        [
            ["공매(auction)", f"{scale['auctions']:,}"],
            ["물품(auction_item)", f"{scale['items']:,}"],
            ["세관(customs_office)", f"{scale['customs_offices']:,}"],
            ["이미지(auction_item_image)", f"{scale['images']:,}"],
        ],
    )
    rep.data["scale"] = scale

    # 수집 기준일 (논문 4.1절에 명시할 값)
    period = C.fetch_one(conn, """
        SELECT MIN(pbac_strt_dttm) AS first_start,
               MAX(pbac_end_dttm)  AS last_end,
               MAX(updated_at)     AS last_updated
        FROM auction
    """)
    rep.table(
        ["항목", "값"],
        [
            ["최초 공매 시작일시", period["first_start"]],
            ["최종 공매 종료일시", period["last_end"]],
            ["DB 최종 갱신 시각", period["last_updated"]],
        ],
    )
    rep.data["period"] = period
    rep.note("논문 4.1절에 \"수집 기준일: YYYY-MM-DD, 물품 N건\" 형태로 기재한다. "
             "기준일은 스냅샷(5.2) 커밋 일자를 쓴다.")

    # ── (2) 물품명 언어 구성  ← 서론의 핵심 근거 ────────
    rep.section("(2) 물품명 언어 구성 (서론 핵심 근거)")
    lang = C.fetch_one(conn, """
        SELECT COUNT(*)                                   AS total,
               SUM(cmdt_nm REGEXP '[가-힣]')              AS ko_included,
               SUM(NOT (cmdt_nm REGEXP '[가-힣]'))        AS en_only,
               ROUND(AVG(CHAR_LENGTH(cmdt_nm)), 1)        AS avg_len,
               MAX(CHAR_LENGTH(cmdt_nm))                  AS max_len
        FROM auction_item
    """)
    total = int(lang["total"] or 0)
    ko = int(lang["ko_included"] or 0)
    en = int(lang["en_only"] or 0)
    rep.table(
        ["구분", "건수", "비율"],
        [
            ["한글 포함", f"{ko:,}", f"{ko / total * 100:.1f}%" if total else "-"],
            ["영문 전용", f"{en:,}", f"{en / total * 100:.1f}%" if total else "-"],
            ["평균 물품명 길이", lang["avg_len"], ""],
            ["최대 물품명 길이", lang["max_len"], ""],
        ],
    )
    rep.data["language"] = {
        "total": total, "ko_included": ko, "en_only": en,
        "en_only_ratio": round(en / total * 100, 1) if total else 0,
        "avg_len": float(lang["avg_len"] or 0), "max_len": int(lang["max_len"] or 0),
    }

    # ── (2b) 수집 출처별 언어 구성 (E1 판정 기준) ───────
    rep.section("(2b) 수집 출처별 한글 포함 비율 (판정 기준)")
    by_src = C.fetch_all(conn, """
        SELECT COALESCE(a.collector_source, '(미상)')       AS source,
               COUNT(*)                                     AS items,
               SUM(ai.cmdt_nm REGEXP '[가-힣]')             AS ko_included,
               ROUND(AVG(CHAR_LENGTH(ai.cmdt_nm)), 1)       AS avg_len
        FROM auction a
        JOIN auction_item ai ON ai.pbac_no = a.pbac_no
        GROUP BY a.collector_source
        ORDER BY items DESC
    """)
    rows = []
    for r in by_src:
        n, k = int(r["items"]), int(r["ko_included"] or 0)
        rows.append([r["source"], f"{n:,}", f"{k:,}", f"{k / n * 100:.1f}%" if n else "-", r["avg_len"]])
    rep.table(["수집 출처", "물품 수", "한글 포함", "한글 포함률", "평균 길이"], rows)
    rep.data["by_source_language"] = [dict(r) for r in by_src]
    rep.note("수입화물(BUSINESS)의 한글 포함률이 0%에 가까우면 서론의 주장이 그대로 성립한다. "
             "휴대품(PERSONAL)은 한글이 섞여 있으므로, 분류 규칙이 영문 토큰 룰과 "
             "한글 부분문자열 룰 두 갈래인 이유를 3.3절에서 이 수치로 설명한다.")

    # ── (3) 수집 출처별 분포 ───────────────────────────
    rep.section("(3) 수집 출처별 공매/물품 분포")
    src_dist = C.fetch_all(conn, """
        SELECT COALESCE(a.collector_source, '(미상)') AS source,
               COUNT(DISTINCT a.pbac_no)              AS auctions,
               COUNT(ai.cmdt_ln_no)                   AS items
        FROM auction a
        LEFT JOIN auction_item ai ON a.pbac_no = ai.pbac_no
        GROUP BY a.collector_source
        ORDER BY items DESC
    """)
    rep.table(["수집 출처", "공매 수", "물품 수"],
              [[r["source"], f"{r['auctions']:,}", f"{r['items']:,}"] for r in src_dist])
    rep.data["by_source"] = [dict(r) for r in src_dist]

    # ── (4) 공매당 물품 라인 수 ────────────────────────
    rep.section("(4) 공매당 물품 라인 수 (복합 PK 설계 근거)")
    lines = C.fetch_one(conn, """
        SELECT ROUND(AVG(cnt), 2) AS avg_lines,
               MAX(cnt)           AS max_lines,
               MIN(cnt)           AS min_lines
        FROM (SELECT pbac_no, COUNT(*) cnt FROM auction_item GROUP BY pbac_no) t
    """)
    rep.table(["항목", "값"],
              [["평균 라인 수", lines["avg_lines"]],
               ["최대 라인 수", lines["max_lines"]],
               ["최소 라인 수", lines["min_lines"]]])
    rep.data["lines_per_auction"] = lines

    # ── (5) 예정가 분포 ────────────────────────────────
    rep.section("(5) 예정가 분포")
    price = C.fetch_one(conn, """
        SELECT MIN(pbac_prng_prc)          AS min_price,
               MAX(pbac_prng_prc)          AS max_price,
               ROUND(AVG(pbac_prng_prc))   AS avg_price,
               COUNT(pbac_prng_prc)        AS priced_items
        FROM auction_item
    """)
    rep.table(
        ["항목", "값(원)"],
        [
            ["최저 예정가", f"{int(price['min_price'] or 0):,}"],
            ["최고 예정가", f"{int(price['max_price'] or 0):,}"],
            ["평균 예정가", f"{int(price['avg_price'] or 0):,}"],
            ["예정가 보유 물품 수", f"{int(price['priced_items'] or 0):,}"],
        ],
    )
    rep.data["price"] = {k: (int(v) if v is not None else None) for k, v in price.items()}

    # ── 논문 표 3 초안 ─────────────────────────────────
    rep.section("논문 표 3 초안 (그대로 옮겨 쓸 수 있는 형태)")
    rep.table(
        ["항목", "값"],
        [
            ["공매 건수", f"{scale['auctions']:,}건"],
            ["물품 건수", f"{scale['items']:,}건"],
            ["대상 세관 수", f"{scale['customs_offices']:,}개"],
            ["물품 이미지 수", f"{scale['images']:,}건"],
            ["영문 전용 물품명 비율", f"{en / total * 100:.1f}%" if total else "-"],
            ["평균 물품명 길이", f"{lang['avg_len']}자"],
            ["공매당 평균 물품 라인 수", f"{lines['avg_lines']}건"],
            ["예정가 범위", f"{int(price['min_price'] or 0):,} ~ {int(price['max_price'] or 0):,}원"],
        ],
    )

    rep.save()
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
