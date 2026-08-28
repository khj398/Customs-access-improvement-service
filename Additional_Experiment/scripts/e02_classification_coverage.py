"""
E02. 자동 분류 커버리지  [필수 · 10분]
======================================
목적  라벨링 없이도 산출되는 지표로, 규칙 기반과 LLM 보완이 각각 얼마나
      부담하는지 보여준다. 논문 표 4의 상단 절반.

논문 대응  4.2절 표 4 (상단)
실험계획서  6장 E2

주의  이 스크립트는 SELECT만 수행한다. DB를 변경하지 않는다.

실행:
    python Additional_Experiment/scripts/e02_classification_coverage.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))

import exp_common as C  # noqa: E402

MISC_THRESHOLD = 5.0  # 미분류 비율 경고 기준 (%)


def main() -> int:
    rep = C.Report("E02", "자동 분류 커버리지", paper_ref="4.2절 표 4 (상단)", plan_ref="6장 E2")
    conn = C.db_conn()

    total_items = int(C.scalar(conn, "SELECT COUNT(*) FROM auction_item") or 0)
    total_cls = int(C.scalar(conn, "SELECT COUNT(*) FROM item_classification") or 0)

    # ── (1) 모델별 분류 건수 및 평균 신뢰도 ────────────
    rep.section("(1) 모델별 분류 건수 및 평균 신뢰도")
    by_model = C.fetch_all(conn, """
        SELECT model_name,
               COUNT(*)                     AS cnt,
               ROUND(AVG(confidence), 3)    AS avg_conf,
               MIN(confidence)              AS min_conf,
               MAX(confidence)              AS max_conf
        FROM item_classification
        GROUP BY model_name
        ORDER BY cnt DESC
    """)
    rep.table(
        ["모델", "건수", "비율", "평균 신뢰도", "최소", "최대"],
        [[r["model_name"], f"{r['cnt']:,}",
          f"{r['cnt'] / total_cls * 100:.1f}%" if total_cls else "-",
          r["avg_conf"], r["min_conf"], r["max_conf"]] for r in by_model],
    )
    rep.data["by_model"] = [dict(r) for r in by_model]
    rep.data["total_items"] = total_items
    rep.data["total_classified"] = total_cls
    rep.table(
        ["항목", "값"],
        [["전체 물품 수", f"{total_items:,}"],
         ["분류 레코드 수", f"{total_cls:,}"],
         ["분류 적재율", f"{total_cls / total_items * 100:.1f}%" if total_items else "-"]],
    )

    # ── (2) 신뢰도 구간 분포 ───────────────────────────
    rep.section("(2) 신뢰도 구간 분포")
    bins = C.fetch_all(conn, """
        SELECT CASE WHEN confidence >= 0.90 THEN '0.90 이상'
                    WHEN confidence >= 0.70 THEN '0.70~0.89'
                    ELSE '0.70 미만' END AS conf_bin,
               COUNT(*) AS cnt
        FROM item_classification
        GROUP BY conf_bin
        ORDER BY conf_bin DESC
    """)
    rep.table(["신뢰도 구간", "건수", "비율"],
              [[r["conf_bin"], f"{r['cnt']:,}",
                f"{r['cnt'] / total_cls * 100:.1f}%" if total_cls else "-"] for r in bins])
    rep.data["confidence_bins"] = [dict(r) for r in bins]

    # ── (3) 미분류(기타) 건수 ──────────────────────────
    rep.section("(3) 미분류(기타 > 미분류) 건수")
    misc = C.fetch_all(conn, """
        SELECT c.name_ko                          AS category,
               COUNT(*)                           AS cnt,
               ROUND(AVG(ic.confidence), 3)       AS avg_conf
        FROM item_classification ic
        JOIN category c ON c.category_id = ic.category_id
        WHERE c.name_ko IN ('미분류', '기타')
           OR c.category_id IN (
                SELECT category_id FROM category
                WHERE parent_id IN (SELECT category_id FROM category WHERE name_ko = '기타')
           )
        GROUP BY c.name_ko
        ORDER BY cnt DESC
    """)
    misc_total = sum(int(r["cnt"]) for r in misc)
    misc_ratio = misc_total / total_cls * 100 if total_cls else 0
    rep.table(["카테고리", "건수", "평균 신뢰도"],
              [[r["category"], f"{r['cnt']:,}", r["avg_conf"]] for r in misc] or [["(없음)", 0, "-"]])
    rep.data["misc_total"] = misc_total
    rep.data["misc_ratio"] = round(misc_ratio, 2)
    rep.table(["항목", "값"],
              [["미분류 합계", f"{misc_total:,}"], ["미분류 비율", f"{misc_ratio:.1f}%"]])

    # 미분류 물품명 목록 (check_misc.py 와 동일한 목적)
    misc_items = C.fetch_all(conn, """
        SELECT ai.pbac_no, ai.pbac_srno, ai.cmdt_ln_no, ai.cmdt_nm,
               ic.model_name, ic.confidence
        FROM item_classification ic
        JOIN auction_item ai USING (pbac_no, pbac_srno, cmdt_ln_no)
        JOIN category c ON c.category_id = ic.category_id
        WHERE c.name_ko IN ('미분류', '기타')
        ORDER BY ai.cmdt_nm
    """)
    if misc_items:
        rep.csv("misc_items.csv",
                ["pbac_no", "pbac_srno", "cmdt_ln_no", "cmdt_nm", "model_name", "confidence"],
                [[r["pbac_no"], r["pbac_srno"], r["cmdt_ln_no"], r["cmdt_nm"],
                  r["model_name"], r["confidence"]] for r in misc_items])

    # ── (4) 대분류별 물품 분포 ─────────────────────────
    rep.section("(4) 대분류별 물품 분포 (12개 대분류 커버 여부)")
    top_dist = C.fetch_all(conn, """
        SELECT c1.name_ko AS top_category, COUNT(*) AS cnt
        FROM item_classification ic
        JOIN category cl ON cl.category_id = ic.category_id
        LEFT JOIN category cp ON cp.category_id = cl.parent_id
        LEFT JOIN category cg ON cg.category_id = cp.parent_id
        JOIN category c1 ON c1.category_id = COALESCE(cg.category_id, cp.category_id, cl.category_id)
        GROUP BY c1.name_ko
        ORDER BY cnt DESC
    """)
    rep.table(["대분류", "물품 수", "비율"],
              [[r["top_category"], f"{r['cnt']:,}",
                f"{r['cnt'] / total_cls * 100:.1f}%" if total_cls else "-"] for r in top_dist])
    rep.data["top_categories"] = [dict(r) for r in top_dist]

    total_top = int(C.scalar(conn, "SELECT COUNT(*) FROM category WHERE level = 1") or 0)
    rep.table(["항목", "값"],
              [["정의된 대분류 수", total_top],
               ["실제 물품이 배정된 대분류 수", len(top_dist)]])
    rep.data["top_category_defined"] = total_top
    rep.data["top_category_used"] = len(top_dist)

    # ── 논문 표 4 상단 초안 ────────────────────────────
    rep.section("논문 표 4 (상단) 초안")
    rows = []
    for r in by_model:
        rows.append([r["model_name"], f"{r['cnt']:,}건",
                     f"{r['cnt'] / total_cls * 100:.1f}%" if total_cls else "-", r["avg_conf"]])
    rows.append(["미분류(기타)", f"{misc_total:,}건", f"{misc_ratio:.1f}%", "-"])
    rep.table(["분류 경로", "건수", "비율", "평균 신뢰도"], rows)

    # ── 판정 ──────────────────────────────────────────
    rep.section("판정")
    if misc_ratio > MISC_THRESHOLD:
        rep.note(f"미분류 비율 {misc_ratio:.1f}% > {MISC_THRESHOLD}% — "
                 "classification/rules.yaml 을 보강한 뒤 재측정한다. "
                 "재분류 시 --rule-only-update 를 사용해 기존 OpenAI 결과를 보호할 것.")
    else:
        rep.note(f"미분류 비율 {misc_ratio:.1f}% ≤ {MISC_THRESHOLD}% — 기준 충족.")
    rep.note("이전 리포트(93건 기준: 룰 76.3% / OpenAI 22.6% / 미분류 1.1%)는 "
             "위 수치로 대체한다.")

    rep.save()
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
