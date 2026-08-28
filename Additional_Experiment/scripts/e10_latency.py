"""
E10. 검색 응답시간 p50/p95  [선택 · 30분]
=========================================
목적  설계서 목표(검색 p95 300ms, 자동완성 p95 100ms)를 검증한다.
      측정하지 않은 채 "달성"이라고 쓰면 안 되므로, 재거나 향후 과제로 내리거나 둘 중 하나다.

방법  질의 20개 x 각 20회 반복, p50/p95 산출.
      (A) MySQL LIKE  (B) cais_back API(Meilisearch)  (C) 자동완성 API

유의  현재 데이터 규모(수백~수천 건)에서는 두 방식 모두 빠르게 나온다.
      규모가 작아 차이가 드러나지 않았다는 점을 정직하게 쓰고,
      1만 건 이상에서의 확장성은 향후 과제로 넘긴다.

논문 대응  4.3절 표 5 (병합)
실험계획서  6장 E10

실행:
    python Additional_Experiment/scripts/e10_latency.py
    python Additional_Experiment/scripts/e10_latency.py --repeat 20 --warmup 3
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))

import exp_common as C  # noqa: E402

TARGET_SEARCH_P95 = 300.0      # ms (docs/SEARCH_ENGINE_DESIGN.md)
TARGET_AUTOCOMPLETE_P95 = 100.0  # ms


def main() -> int:
    ap = argparse.ArgumentParser(description="E10 검색 응답시간 측정")
    ap.add_argument("--repeat", type=int, default=20, help="질의당 반복 횟수 (기본 20)")
    ap.add_argument("--warmup", type=int, default=3, help="측정 제외 워밍업 횟수 (기본 3)")
    ap.add_argument("--limit", type=int, default=20, help="검색 결과 limit")
    ap.add_argument("--skip-autocomplete", action="store_true")
    args = ap.parse_args()

    rep = C.Report("E10", "검색 응답시간 p50/p95", paper_ref="4.3절 표 5 (병합)", plan_ref="6장 E10")
    conn = C.db_conn()
    queries = C.korean_queries()

    rep.section("측정 조건")
    rep.table(["항목", "값"],
              [["질의 수", len(queries)],
               ["질의당 반복", args.repeat],
               ["워밍업(측정 제외)", args.warmup],
               ["결과 limit", args.limit],
               ["API", C.api_base()],
               ["측정 환경 주의", "동일 머신에서 DB·Meili·API가 함께 동작하면 네트워크 지연이 배제됨을 명시"]])

    like_all: list[float] = []
    api_all: list[float] = []
    ac_all: list[float] = []
    per_query_rows = []

    for q in queries:
        kw = q["query"]
        like_times, api_times, ac_times = [], [], []

        for i in range(args.repeat + args.warmup):
            # (A) MySQL LIKE
            t0 = time.perf_counter()
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT pbac_no, pbac_srno, cmdt_ln_no, cmdt_nm FROM auction_item "
                    "WHERE cmdt_nm LIKE CONCAT('%%', %s, '%%') LIMIT %s", (kw, args.limit))
                cur.fetchall()
            dt = (time.perf_counter() - t0) * 1000
            if i >= args.warmup:
                like_times.append(dt)

            # (B) 제안 방식 API
            r = C.api_search(kw, limit=args.limit)
            if i >= args.warmup and r["ok"]:
                api_times.append(r["elapsed_ms"])

            # (C) 자동완성
            if not args.skip_autocomplete:
                a = C.api_autocomplete(kw[:2])
                if i >= args.warmup and a["ok"]:
                    ac_times.append(a["elapsed_ms"])

        like_all += like_times
        api_all += api_times
        ac_all += ac_times
        per_query_rows.append([
            q["no"], kw,
            f"{C.percentile(like_times, 50):.1f}", f"{C.percentile(like_times, 95):.1f}",
            f"{C.percentile(api_times, 50):.1f}" if api_times else "-",
            f"{C.percentile(api_times, 95):.1f}" if api_times else "-",
        ])

    rep.section("질의별 응답시간 (ms)")
    rep.table(["#", "질의", "LIKE p50", "LIKE p95", "제안 p50", "제안 p95"], per_query_rows)
    rep.csv("latency_per_query.csv",
            ["no", "query", "like_p50_ms", "like_p95_ms", "proposed_p50_ms", "proposed_p95_ms"],
            per_query_rows)

    # ── 전체 요약 ─────────────────────────────────────
    rep.section("전체 요약")
    def stat_row(label, values, target=None):
        if not values:
            return [label, 0, "-", "-", "-", "-", "-"]
        p50, p95 = C.percentile(values, 50), C.percentile(values, 95)
        verdict = "-" if target is None else ("달성" if p95 <= target else "미달")
        return [label, len(values), f"{C.mean(values):.1f}", f"{p50:.1f}", f"{p95:.1f}",
                f"{max(values):.1f}", verdict]

    rows = [
        stat_row("(A) MySQL LIKE", like_all),
        stat_row("(B) 제안 방식 (API+Meili)", api_all, TARGET_SEARCH_P95),
    ]
    if ac_all:
        rows.append(stat_row("(C) 자동완성 API", ac_all, TARGET_AUTOCOMPLETE_P95))
    rep.table(["방식", "표본 수", "평균", "p50", "p95", "최대", "목표 대비"], rows)

    rep.data.update({
        "repeat": args.repeat,
        "like": {"n": len(like_all), "mean": round(C.mean(like_all), 1),
                 "p50": round(C.percentile(like_all, 50), 1), "p95": round(C.percentile(like_all, 95), 1)},
        "proposed": {"n": len(api_all), "mean": round(C.mean(api_all), 1),
                     "p50": round(C.percentile(api_all, 50), 1), "p95": round(C.percentile(api_all, 95), 1),
                     "target_p95": TARGET_SEARCH_P95,
                     "target_met": bool(api_all) and C.percentile(api_all, 95) <= TARGET_SEARCH_P95},
        "autocomplete": {"n": len(ac_all), "p50": round(C.percentile(ac_all, 50), 1),
                         "p95": round(C.percentile(ac_all, 95), 1),
                         "target_p95": TARGET_AUTOCOMPLETE_P95,
                         "target_met": bool(ac_all) and C.percentile(ac_all, 95) <= TARGET_AUTOCOMPLETE_P95}
        if ac_all else None,
    })

    rep.section("해석 지침")
    rep.note("(A)는 SQL 실행 시간만, (B)는 HTTP 왕복+MySQL 상세조회까지 포함하므로 "
             "두 값을 직접 비교해 '제안 방식이 느리다/빠르다'로 단정하지 않는다. "
             "논문에는 (B)가 목표치(p95 300ms)를 만족하는지만 기재하고, "
             "LIKE 방식이 인덱스를 타지 못한다는 서술은 실행계획(EXPLAIN)으로 뒷받침한다.")
    total_items = int(C.scalar(conn, "SELECT COUNT(*) FROM auction_item") or 0)
    rep.note(f"현재 데이터 규모는 {total_items:,}건이다. 규모가 작아 두 방식의 차이가 드러나지 "
             "않았다는 점을 정직하게 쓰고, 1만 건 이상에서의 확장성은 향후 과제로 넘긴다.")

    # EXPLAIN 근거
    rep.section("참고: LIKE '%%키워드%%' 실행계획")
    try:
        plan = C.fetch_all(conn,
                           "EXPLAIN SELECT * FROM auction_item WHERE cmdt_nm LIKE CONCAT('%%', %s, '%%')",
                           ("와인",))
        if plan:
            keys = list(plan[0].keys())
            rep.table(keys, [[r[k] for k in keys] for r in plan])
            rep.data["explain_type"] = plan[0].get("type")
    except Exception as e:  # noqa: BLE001
        rep.note(f"EXPLAIN 실패: {e}")

    rep.save()
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
