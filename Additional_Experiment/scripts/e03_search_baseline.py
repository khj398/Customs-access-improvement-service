"""
E03. 한글 검색 베이스라인 비교  [필수 · 1시간]  ★ 최우선
=========================================================
목적  본 논문의 핵심 주장("영문 물품명에 한글 검색이 불가능했다 -> 가능해졌다")을 증명한다.

설계  동일 질의 20개(부록 A)에 대해 두 방식을 비교한다.
      (A) 베이스라인 : cmdt_nm LIKE '%질의%'  — 유니패스와 동등한 단순 문자열 매칭
      (B) 제안 방식   : 검색 토큰 + Meilisearch (cais_back /api/items/search)

측정 지표
      (1) 질의별 결과 건수
      (2) 0건을 반환한 질의 수
      (3) 상위 5건 중 질의에 실제로 부합하는 건수(P@5) — 사람이 판정

판정 기준  A의 0건 질의 수 >= 15, B의 0건 질의 수 <= 3 이면 주장 성립.
          B의 평균 P@5 는 설계서 목표 0.80 이상.

논문 대응  4.3절 표 5 (핵심)
실험계획서  6장 E3

이 스크립트는 (1)(2)를 자동 수집하고, (3)의 판정지(p5_judgement.csv)를 생성한다.
판정지는 2인이 독립적으로 채운 뒤 e03b_p5_score.py 로 집계한다.

실행:
    python Additional_Experiment/scripts/e03_search_baseline.py
    python Additional_Experiment/scripts/e03_search_baseline.py --count-limit 200
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))

import exp_common as C  # noqa: E402

CRITERIA_A_ZERO_MIN = 15
CRITERIA_B_ZERO_MAX = 3
CRITERIA_P5 = 0.80


def main() -> int:
    ap = argparse.ArgumentParser(description="E03 한글 검색 베이스라인 비교")
    ap.add_argument("--count-limit", type=int, default=100,
                    help="제안 방식 결과 건수 집계 상한 (기본 100)")
    ap.add_argument("--topk", type=int, default=5, help="P@k 의 k (기본 5)")
    ap.add_argument("--use-meili-direct", action="store_true",
                    help="cais_back API 대신 Meilisearch를 직접 조회")
    args = ap.parse_args()

    rep = C.Report("E03", "한글 검색 베이스라인 비교", paper_ref="4.3절 표 5 (핵심)", plan_ref="6장 E3")
    conn = C.db_conn()
    queries = C.korean_queries()

    rep.section("실험 조건")
    rep.table(
        ["항목", "값"],
        [
            ["질의 수", len(queries)],
            ["베이스라인(A)", "SELECT COUNT(*) FROM auction_item WHERE cmdt_nm LIKE '%질의%'"],
            ["제안 방식(B)", ("Meilisearch 직접 조회" if args.use_meili_direct
                              else f"{C.api_base()}/api/items/search")],
            ["건수 집계 상한", args.count_limit],
            ["P@k", args.topk],
        ],
    )

    rows = []
    judge_rows = []
    a_zero = b_zero = 0
    b_errors = 0

    for q in queries:
        kw = q["query"]

        # (A) 베이스라인 — 단순 LIKE
        a_cnt = int(C.scalar(
            conn,
            "SELECT COUNT(*) FROM auction_item WHERE cmdt_nm LIKE CONCAT('%%', %s, '%%')",
            (kw,),
        ) or 0)

        # (B) 제안 방식
        if args.use_meili_direct:
            res = C.meili_search(kw, limit=args.count_limit)
            ok = res["ok"]
            hits = res["hits"]
            b_cnt = res["total"] if ok else 0
            names = [h.get("cmdtNm", "") for h in hits[: args.topk]]
            keys = [(h.get("pbacNo"), h.get("pbacSrno"), h.get("cmdtLnNo")) for h in hits[: args.topk]]
            err = res["error"]
        else:
            res = C.api_search(kw, limit=args.count_limit)
            ok = res["ok"]
            items = res["items"]
            b_cnt = len(items)
            names = [i.get("cmdtNm", "") for i in items[: args.topk]]
            keys = [(i.get("pbacNo"), i.get("pbacSrno"), i.get("cmdtLnNo")) for i in items[: args.topk]]
            err = res["error"]

        if not ok:
            b_errors += 1

        if a_cnt == 0:
            a_zero += 1
        if ok and b_cnt == 0:
            b_zero += 1

        rows.append([
            q["no"], kw, q["expected_en"], f"{a_cnt:,}",
            (f"{b_cnt:,}" + ("+" if b_cnt >= args.count_limit else "")) if ok else f"ERR({err})",
            "O" if a_cnt == 0 else "",
            "O" if (ok and b_cnt == 0) else "",
        ])

        for rank, (nm, key) in enumerate(zip(names, keys), start=1):
            judge_rows.append([q["no"], kw, rank, nm, key[0], key[1], key[2], "", "", ""])
        # 결과가 topk 미만이면 빈 행으로 자리를 남겨 판정지 구조를 유지
        for rank in range(len(names) + 1, args.topk + 1):
            judge_rows.append([q["no"], kw, rank, "(결과 없음)", "", "", "", "X", "X", "결과 없음"])

    # ── 결과 표 ────────────────────────────────────────
    rep.section("질의별 결과 건수")
    rep.table(
        ["#", "질의", "기대 영문 토큰", "(A) LIKE 건수", "(B) 제안 건수", "A 0건", "B 0건"],
        rows,
    )

    rep.section("요약")
    summary = [
        ["(A) 0건 질의 수", f"{a_zero} / {len(queries)}", f"기준: {CRITERIA_A_ZERO_MIN} 이상",
         "충족" if a_zero >= CRITERIA_A_ZERO_MIN else "미충족"],
        ["(B) 0건 질의 수", f"{b_zero} / {len(queries)}", f"기준: {CRITERIA_B_ZERO_MAX} 이하",
         "충족" if b_zero <= CRITERIA_B_ZERO_MAX else "미충족"],
    ]
    rep.table(["지표", "값", "판정 기준", "판정"], summary)
    both_zero = sum(1 for r in rows if r[5] == "O" and r[6] == "O")
    rep.table(["항목", "값"],
              [["A·B 모두 0건인 질의 수", both_zero],
               ["(B) 호출 실패 질의 수", b_errors]])

    rep.data.update({
        "queries": len(queries),
        "a_zero": a_zero,
        "b_zero": b_zero,
        "both_zero": both_zero,
        "b_errors": b_errors,
        "criteria_a_met": a_zero >= CRITERIA_A_ZERO_MIN,
        "criteria_b_met": b_zero <= CRITERIA_B_ZERO_MAX,
        "rows": [
            {"no": r[0], "query": r[1], "expected_en": r[2],
             "like_count": r[3], "proposed_count": r[4]}
            for r in rows
        ],
    })

    rep.csv("e03_counts.csv",
            ["no", "query", "expected_en", "like_count", "proposed_count", "a_zero", "b_zero"],
            rows)

    # ── P@5 판정지 생성 ────────────────────────────────
    rep.section("P@5 판정지")
    judge_path = rep.csv(
        "p5_judgement.csv",
        ["no", "query", "rank", "cmdt_nm", "pbac_no", "pbac_srno", "cmdt_ln_no",
         "judge1_OX", "judge2_OX", "note"],
        judge_rows,
    )
    rep.note("판정 절차: judge1 / judge2 두 명이 서로 보지 않고 각각 O(적합) / X(부적합)를 채운다. "
             "채운 뒤 `python Additional_Experiment/scripts/e03b_p5_score.py` 로 집계하면 "
             "질의별 P@5, 평균 P@5, 판정자 간 일치도가 산출된다.")
    rep.note(f"판정지 경로: {C.rel(judge_path)}")

    if b_errors:
        rep.note(f"경고: 제안 방식 호출이 {b_errors}건 실패했다. cais_back(3000) / Meilisearch(7700) "
                 "기동 상태를 확인한 뒤 재실행할 것. 실패 상태의 수치는 논문에 쓸 수 없다.")
    if both_zero > 5:
        rep.note(f"경고: A·B 모두 0건인 질의가 {both_zero}개다(기준 5개 초과). "
                 "실험계획서 부록 A 지침에 따라 질의셋 재선정을 검토한다.")

    rep.save()
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
