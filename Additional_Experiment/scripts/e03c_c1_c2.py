"""
E03c. C-1(영문 전용 모집단 0건 질의) / C-2(질의당 반환 건수, 신규 측정)
=======================================================================
S108 졸업논문 실험데이터 수집 지침서 v1.0 5장 대응.
검색 로직(meiliModel.js, 토큰 가중치, 인덱스 설정, 랭킹 규칙)은 건드리지 않는다.
기존 E03 결과를 덮어쓰지 않고 별도 디렉터리(results/E03c/)에 저장한다.

실행:
    python Additional_Experiment/scripts/e03c_c1_c2.py
"""
from __future__ import annotations

import csv
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))

import exp_common as C  # noqa: E402

MEILI_LIMIT = 1000  # 전체 794건을 넘는 값으로 설정해 estimatedTotalHits/필터링이 잘리지 않게 한다


def main() -> int:
    conn = C.db_conn()

    en_only_rows = C.fetch_all(
        conn,
        r"SELECT pbac_no, pbac_srno, cmdt_ln_no FROM auction_item WHERE cmdt_nm NOT REGEXP '[가-힣]'",
    )
    en_only_pk = {(r["pbac_no"], r["pbac_srno"], r["cmdt_ln_no"]) for r in en_only_rows}

    queries = C.korean_queries()

    rep = C.Report("E03c", "영문 전용 모집단 0건 질의 및 질의당 반환 건수 (신규 측정)",
                    paper_ref="4.3절 표 5 2·3행", plan_ref="S108 지침서 5장 C-1/C-2")

    rep.section("실험 조건")
    rep.table(
        ["항목", "값"],
        [
            ["영문 전용 모집단 크기", len(en_only_pk)],
            ["질의 수", len(queries)],
            ["Meilisearch limit", f"{MEILI_LIMIT} (estimatedTotalHits 사용, 잘림 방지)"],
        ],
    )

    rows: list[list] = []  # query, population, baseline_count, proposed_count
    b_errors = 0

    rep.section("질의별 반환 건수 (all / en_only)")
    detail_rows = []
    for q in queries:
        kw = q["query"]

        baseline_all = int(C.scalar(
            conn, "SELECT COUNT(*) FROM auction_item WHERE cmdt_nm LIKE CONCAT('%%', %s, '%%')", (kw,)
        ) or 0)

        res = C.meili_search(kw, limit=MEILI_LIMIT)
        proposed_all = res["total"] if res["ok"] else None
        hits = res["hits"] if res["ok"] else []
        if not res["ok"]:
            b_errors += 1

        baseline_en = int(C.scalar(
            conn,
            r"SELECT COUNT(*) FROM auction_item WHERE cmdt_nm LIKE CONCAT('%%', %s, '%%') "
            r"AND cmdt_nm NOT REGEXP '[가-힣]'",
            (kw,),
        ) or 0)

        if res["ok"]:
            proposed_en = sum(
                1 for h in hits
                if (h.get("pbacNo"), h.get("pbacSrno"), h.get("cmdtLnNo")) in en_only_pk
            )
        else:
            proposed_en = None

        rows.append([kw, "all", baseline_all, proposed_all])
        rows.append([kw, "en_only", baseline_en, proposed_en])
        detail_rows.append([kw, baseline_all, proposed_all, baseline_en, proposed_en])

    rep.table(["질의", "all-baseline", "all-proposed", "en_only-baseline", "en_only-proposed"], detail_rows)

    en_rows = [r for r in rows if r[1] == "en_only"]
    a_zero_en = sum(1 for r in en_rows if r[2] == 0)
    b_zero_en = sum(1 for r in en_rows if r[3] == 0)
    all_rows = [r for r in rows if r[1] == "all"]
    a_zero_all = sum(1 for r in all_rows if r[2] == 0)
    b_zero_all = sum(1 for r in all_rows if r[3] == 0)

    rep.section("C-1 요약: 0건 질의 수")
    rep.table(
        ["모집단", "베이스라인 0건", "제안방식 0건"],
        [
            ["all (794건)", f"{a_zero_all}/20", f"{b_zero_all}/20"],
            ["en_only (243건)", f"{a_zero_en}/20", f"{b_zero_en}/20"],
        ],
    )
    if b_errors:
        rep.note(f"경고: Meilisearch 호출이 {b_errors}건 실패했다. 해당 질의는 값이 비어 있다(None).")

    rep.data.update({
        "en_only_population": len(en_only_pk),
        "a_zero_all": a_zero_all,
        "b_zero_all": b_zero_all,
        "a_zero_en_only": a_zero_en,
        "b_zero_en_only": b_zero_en,
        "b_errors": b_errors,
        "rows": [{"query": r[0], "population": r[1], "baseline_count": r[2], "proposed_count": r[3]} for r in rows],
    })

    rep.csv("search_query_counts.csv", ["query", "population", "baseline_count", "proposed_count"], rows)

    q_path = rep.out_dir / "queries_20.txt"
    with open(q_path, "w", encoding="utf-8") as f:
        for q in queries:
            f.write(q["query"] + "\n")
    rep.text(f"저장: {C.rel(q_path)}")

    rep.save()
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
