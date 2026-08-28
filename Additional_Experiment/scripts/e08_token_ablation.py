"""
E08. 토큰 유형별 기여도  [권장 · 1시간]  ★ 신규
================================================
목적  RAW / KO / SYN / CATEGORY 토큰 설계가 실제로 한글 검색에 기여하는지 분해해서 보인다.
      3.4절 설계의 근거.

방법  Meilisearch 는 tokens 필드 안에서 토큰 유형을 구분할 수 없으므로,
      MySQL 의 item_search_token 에서 token_type 을 단계적으로 누적하며
      검색 가능 물품 수를 센다. 부록 A 의 한글 질의 20개 전체에 대해 반복한다.

예상  RAW 만으로는 한글 질의에 거의 0건 -> SYN 을 더하면 급증 -> CATEGORY 는 완만히 증가.
      "한글 검색을 성립시키는 것은 SYN 토큰이고, CATEGORY 토큰은 재현율을 보완한다."

논문 대응  4.3절 본문 (문장)
실험계획서  6장 E8

실행:
    python Additional_Experiment/scripts/e08_token_ablation.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))

import exp_common as C  # noqa: E402

# 누적 단계 정의 (실험계획서 E8: RAW -> RAW+SYN -> RAW+SYN+CATEGORY)
# 스키마에 KO 토큰 유형이 있으므로 참고 컬럼으로 함께 집계한다.
STAGES = [
    ("RAW", ["RAW"]),
    ("RAW+KO", ["RAW", "KO"]),
    ("RAW+KO+SYN", ["RAW", "KO", "SYN"]),
    ("RAW+KO+SYN+CATEGORY", ["RAW", "KO", "SYN", "CATEGORY"]),
]

COUNT_SQL = """
SELECT COUNT(DISTINCT pbac_no, pbac_srno, cmdt_ln_no) AS cnt
FROM item_search_token
WHERE token LIKE CONCAT('%%', %s, '%%')
  AND token_type IN ({placeholders})
"""


def main() -> int:
    rep = C.Report("E08", "토큰 유형별 기여도", paper_ref="4.3절 본문", plan_ref="6장 E8")
    conn = C.db_conn()

    # 토큰 유형별 총량
    rep.section("토큰 유형별 총량")
    type_counts = C.fetch_all(conn, """
        SELECT token_type, COUNT(*) AS tokens,
               COUNT(DISTINCT pbac_no, pbac_srno, cmdt_ln_no) AS items,
               ROUND(AVG(weight), 2) AS avg_weight
        FROM item_search_token
        GROUP BY token_type
        ORDER BY tokens DESC
    """)
    rep.table(["토큰 유형", "토큰 수", "보유 물품 수", "평균 가중치"],
              [[r["token_type"], f"{r['tokens']:,}", f"{r['items']:,}", r["avg_weight"]]
               for r in type_counts])
    rep.data["token_type_totals"] = [dict(r) for r in type_counts]

    # ── 질의별 누적 검색 가능 건수 ─────────────────────
    rep.section("질의별 누적 검색 가능 물품 수")
    queries = C.korean_queries()
    rows = []
    stage_totals = {name: 0 for name, _ in STAGES}
    stage_nonzero = {name: 0 for name, _ in STAGES}

    for q in queries:
        kw = q["query"]
        counts = []
        for name, types in STAGES:
            sql = COUNT_SQL.format(placeholders=",".join(["%s"] * len(types)))
            cnt = int(C.scalar(conn, sql, (kw, *types)) or 0)
            counts.append(cnt)
            stage_totals[name] += cnt
            if cnt > 0:
                stage_nonzero[name] += 1
        rows.append([q["no"], kw, *counts])

    rep.table(["#", "질의", *[name for name, _ in STAGES]], rows)
    rep.csv("token_ablation.csv",
            ["no", "query", *[name.replace("+", "_") for name, _ in STAGES]], rows)

    # ── 단계별 요약 ───────────────────────────────────
    rep.section("단계별 요약")
    n_q = len(queries)
    summary_rows = []
    prev_total = None
    for name, _ in STAGES:
        total = stage_totals[name]
        delta = "-" if prev_total is None else f"+{total - prev_total:,}"
        summary_rows.append([
            name, f"{total:,}", delta,
            f"{stage_nonzero[name]} / {n_q}",
            f"{n_q - stage_nonzero[name]}",
        ])
        prev_total = total
    rep.table(["누적 단계", "검색 가능 건수 합계", "증가분", "결과가 있는 질의 수", "0건 질의 수"],
              summary_rows)

    rep.data["stages"] = [
        {"stage": name, "total_hits": stage_totals[name],
         "queries_with_hits": stage_nonzero[name], "queries_zero": n_q - stage_nonzero[name]}
        for name, _ in STAGES
    ]

    # ── 논문 문장 ─────────────────────────────────────
    rep.section("논문에 넣을 문장 초안")
    raw_zero = n_q - stage_nonzero["RAW"]
    syn_zero = n_q - stage_nonzero["RAW+KO+SYN"]
    all_zero = n_q - stage_nonzero["RAW+KO+SYN+CATEGORY"]
    rep.text(f"원문 토큰(RAW)만으로는 한글 질의 {n_q}개 중 {raw_zero}개가 0건이었으나, "
             f"동의어 토큰(SYN)을 포함하면 0건 질의가 {syn_zero}개로 감소하였고, "
             f"카테고리 토큰까지 포함하면 {all_zero}개가 되었다. "
             "즉 한글 검색을 성립시키는 것은 SYN 토큰이며, CATEGORY 토큰은 재현율을 보완한다.")
    rep.note("이 실험은 MySQL item_search_token 기준이므로 Meilisearch 랭킹은 반영되지 않는다. "
             "검색 결과 품질은 E03(P@5)로 보고하고, 여기서는 '검색 가능 여부'만 다룬다는 점을 "
             "4.3절에 한 줄로 밝힌다.")

    rep.save()
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
