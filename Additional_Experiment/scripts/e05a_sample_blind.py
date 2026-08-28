"""
E05-a. 분류 정확도 블라인드 재평가 — 표본 추출  [필수 · E05의 1단계]
=====================================================================
목적  기존 100% 수치(자동 결과와 일치하는 50건만 라벨링 -> 선택 편향)를 대체할,
      편향 없는 정확도 산출을 위한 블라인드 라벨링 표본을 만든다.

핵심 규칙
    - 라벨링 CSV에 자동 분류 결과(auto_category_path/confidence/model)를 넣지 않는다.
    - 재현성을 위해 RAND(42) 로 시드를 고정한다.
    - 애매한 건은 비워두지 말고 반드시 「기타 > 미분류 > 기타」를 정답으로 명시한다.

산출
    results/E05/eval_label_blank.csv        전체 표본 (배포용 원본)
    results/E05/labels/label_<라벨러>.csv   라벨러별 배포 파일 (공통 문항 포함)
    results/E05/category_reference.csv      정답 카테고리 경로 목록 (라벨링 참고용)

논문 대응  4.2절 표 4 (하단)
실험계획서  6장 E5

실행:
    python Additional_Experiment/scripts/e05a_sample_blind.py
    python Additional_Experiment/scripts/e05a_sample_blind.py --n 100 --seed 42 \
        --labelers KHJ,KDH,PJY --common 20
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))

import exp_common as C  # noqa: E402

BLANK_HEADERS = ["pbac_no", "pbac_srno", "cmdt_ln_no", "cmdt_nm",
                 "true_category_path", "labeler", "note"]


def main() -> int:
    ap = argparse.ArgumentParser(description="E05-a 블라인드 라벨링 표본 추출")
    ap.add_argument("--n", type=int, default=100, help="표본 크기 (기본 100)")
    ap.add_argument("--seed", type=int, default=42, help="RAND() 시드 (기본 42, 재현성)")
    ap.add_argument("--labelers", default="KHJ,KDH,PJY", help="라벨러 코드 (쉼표 구분)")
    ap.add_argument("--common", type=int, default=20,
                    help="라벨러 간 일치도 계산용 공통 문항 수 (기본 20)")
    args = ap.parse_args()

    rep = C.Report("E05", "분류 정확도 블라인드 재평가 — 표본 추출",
                   paper_ref="4.2절 표 4 (하단)", plan_ref="6장 E5")
    conn = C.db_conn()

    # ── 표본 추출 ─────────────────────────────────────
    rows = C.fetch_all(conn, """
        SELECT ai.pbac_no, ai.pbac_srno, ai.cmdt_ln_no, ai.cmdt_nm
        FROM auction_item ai
        ORDER BY RAND(%s)
        LIMIT %s
    """, (args.seed, args.n))

    rep.section("표본")
    rep.table(["항목", "값"],
              [["표본 크기", len(rows)],
               ["시드", f"RAND({args.seed})"],
               ["모집단", f"{int(C.scalar(conn, 'SELECT COUNT(*) FROM auction_item') or 0):,}건 (auction_item 전체)"]])

    blank = [[r["pbac_no"], r["pbac_srno"], r["cmdt_ln_no"], r["cmdt_nm"], "", "", ""] for r in rows]
    rep.csv("eval_label_blank.csv", BLANK_HEADERS, blank)

    # ── 라벨러별 배포 파일 ────────────────────────────
    labelers = [s.strip() for s in args.labelers.split(",") if s.strip()]
    common_n = min(args.common, len(rows))
    common = blank[:common_n]
    rest = blank[common_n:]

    assign: dict[str, list] = {lab: list(common) for lab in labelers}
    for i, row in enumerate(rest):
        assign[labelers[i % len(labelers)]].append(row)

    labels_dir = rep.out_dir / "labels"
    labels_dir.mkdir(parents=True, exist_ok=True)
    dist_rows = []
    for lab, items in assign.items():
        prefilled = [[*r[:5], lab, r[6]] for r in items]   # labeler 열 미리 채움
        path = C.write_csv(labels_dir / f"label_{lab}.csv", BLANK_HEADERS, prefilled)
        dist_rows.append([lab, len(items), common_n, len(items) - common_n,
                          C.rel(path)])

    rep.section("라벨러별 배포")
    rep.table(["라벨러", "담당 건수", "공통 문항", "단독 문항", "파일"], dist_rows)
    rep.note(f"공통 문항 {common_n}건은 전원이 동일하게 라벨링한다 -> 라벨러 간 일치도 계산에 사용. "
             f"단독 문항은 {len(rest)}건을 {len(labelers)}인이 나눠 맡아 표본 {len(rows)}건 전체를 덮는다.")

    # ── 카테고리 참고표 ───────────────────────────────
    cats = C.fetch_all(conn, """
        SELECT c3.category_id                                  AS category_id,
               c1.name_ko                                      AS lv1,
               c2.name_ko                                      AS lv2,
               c3.name_ko                                      AS lv3
        FROM category c3
        JOIN category c2 ON c2.category_id = c3.parent_id
        JOIN category c1 ON c1.category_id = c2.parent_id
        WHERE c3.level = 3 AND c3.is_active = 1
        ORDER BY c1.name_ko, c2.name_ko, c3.name_ko
    """)
    ref_rows = [[c["category_id"], f"{c['lv1']} > {c['lv2']} > {c['lv3']}",
                 c["lv1"], c["lv2"], c["lv3"]] for c in cats]
    mids = C.fetch_all(conn, """
        SELECT c2.category_id AS category_id, c1.name_ko AS lv1, c2.name_ko AS lv2
        FROM category c2
        JOIN category c1 ON c1.category_id = c2.parent_id
        WHERE c2.level = 2 AND c2.is_active = 1
        ORDER BY c1.name_ko, c2.name_ko
    """)
    ref_rows += [[m["category_id"], f"{m['lv1']} > {m['lv2']}", m["lv1"], m["lv2"], ""] for m in mids]

    rep.section("정답 카테고리 참고표")
    rep.table(["항목", "값"],
              [["소분류(level 3) 경로 수", len(cats)],
               ["중분류(level 2) 경로 수", len(mids)]])
    rep.csv("category_reference.csv",
            ["category_id", "category_path", "대분류", "중분류", "소분류"], ref_rows)

    rep.data.update({
        "sample_size": len(rows),
        "seed": args.seed,
        "labelers": labelers,
        "common_items": common_n,
        "assignment": {lab: len(items) for lab, items in assign.items()},
        "category_leaf_paths": len(cats),
    })

    # ── 라벨링 지침 ───────────────────────────────────
    rep.section("라벨링 지침 (라벨러에게 그대로 전달)")
    for line in [
        "1. 자동 분류 결과를 절대 먼저 보지 않는다. 물품명(cmdt_nm)만 보고 판단한다.",
        "2. 정답은 category_reference.csv 의 경로를 그대로 복사해 쓴다(오타·공백 주의).",
        "3. 판단이 애매해도 비워두지 않는다. 애매하면 「기타 > 미분류 > 기타」로 명시한다.",
        "   - 이것이 기존 평가의 선택 편향을 없애는 핵심 규칙이다.",
        "4. 소분류 판단이 불가능하면 중분류 경로(대 > 중)까지만 적고 note 에 사유를 남긴다.",
        "5. 다른 라벨러와 상의하지 않는다. 공통 문항 일치도가 곧 방법론의 근거다.",
        "6. 완료 파일은 results/E05/labels/ 에 같은 파일명으로 덮어쓴다.",
    ]:
        rep.text(line)

    rep.save()
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
