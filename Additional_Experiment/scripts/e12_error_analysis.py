"""
E12. 오분류 정성 분석  [선택 · 40분]  ★ 신규
=============================================
목적  5장 향후 과제를 "막연한 개선"이 아니라 관찰된 실패 유형에 근거해 쓴다.
      E05 의 오분류 목록을 재활용한다.

유형 (실험계획서 6장 E12)
    (1) 문맥 의존형        물품명만으로는 판별 불가 (예: hand pump 가 자전거용인지 공업용인지)
    (2) 포장재·용기 표기형  내용물이 아니라 포장 규격만 적힌 경우 (예: EXPRESS BOX, PAPER BOX)
    (3) 복수 품목 묶음명형  "… 등(14품목)"처럼 대표명만 적힌 경우
    (4) 카테고리 부재형     트리에 해당 카테고리가 없어 기타로 떨어진 경우 (예: 티슈·냅킨)

이 스크립트는 키워드 휴리스틱으로 1차 분류한 CSV를 만든다.
최종 유형은 사람이 확인해 error_type 열을 확정한다(자동 분류는 초안일 뿐이다).

논문 대응  5장 본문
실험계획서  6장 E12

실행:
    python Additional_Experiment/scripts/e12_error_analysis.py
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))

import exp_common as C  # noqa: E402

PACKAGING_KEYWORDS = [
    "BOX", "CARTON", "PACK", "PACKING", "BAG(", "POUCH", "CASE", "CONTAINER",
    "PALLET", "WRAP", "박스", "포장", "상자",
]
BUNDLE_PATTERNS = [
    r"등\s*\(?\d+\s*품목", r"외\s*\d+\s*종", r"ETC", r"ASSORT", r"MIXED", r"MISC",
    r"SET\b", r"기타\s*\d+",
]
CONTEXT_KEYWORDS = [
    "PUMP", "PART", "PARTS", "MODULE", "UNIT", "KIT", "COMPONENT", "ACCESSORY",
    "ADAPTER", "HOLDER", "COVER", "부품", "부속",
]


def norm_path(p: str) -> str:
    return " > ".join(s.strip() for s in (p or "").split(">") if s.strip())


def guess_type(cmdt_nm: str, auto: str, true: str) -> str:
    name = (cmdt_nm or "").upper()
    if any(k in name for k in PACKAGING_KEYWORDS):
        return "포장재·용기 표기형"
    if any(re.search(p, name) for p in BUNDLE_PATTERNS):
        return "복수 품목 묶음명형"
    if "미분류" in true or "기타" in norm_path(true).split(">")[0]:
        return "카테고리 부재형"
    if any(k in name for k in CONTEXT_KEYWORDS):
        return "문맥 의존형"
    return "미분류(수동 확인 필요)"


def main() -> int:
    ap = argparse.ArgumentParser(description="E12 오분류 정성 분석")
    ap.add_argument("--gt", default=str(C.RESULTS_DIR / "E05" / "ground_truth_v2.csv"))
    args = ap.parse_args()

    gt_path = Path(args.gt)
    if not gt_path.exists():
        C.die(f"ground_truth_v2.csv 가 없습니다: {gt_path}\n"
              "   먼저 e05a -> 라벨링 -> e05b 순서로 진행하세요.")

    rep = C.Report("E12", "오분류 정성 분석", paper_ref="5장 본문", plan_ref="6장 E12")
    rows = [r for r in C.read_csv(gt_path) if (r.get("true_category_path") or "").strip()]
    mismatches = [r for r in rows
                  if norm_path(r["auto_category_path"]) != norm_path(r["true_category_path"])]

    rep.section("개요")
    rep.table(["항목", "값"],
              [["라벨 완료 건수", len(rows)],
               ["오분류 건수", len(mismatches)],
               ["오분류율", f"{len(mismatches) / len(rows) * 100:.1f}%" if rows else "-"]])

    if not mismatches:
        rep.note("오분류가 없다. 표본이 작거나 라벨링이 자동 결과에 영향을 받았을 가능성을 점검할 것 "
                 "(기존 100% 리포트가 그렇게 나왔다).")
        rep.save()
        return 0

    # ── 유형 추정 ─────────────────────────────────────
    out_rows = []
    counter = Counter()
    for r in mismatches:
        t = guess_type(r.get("cmdt_nm", ""), r.get("auto_category_path", ""),
                       r.get("true_category_path", ""))
        counter[t] += 1
        out_rows.append([
            r.get("cmdt_nm", ""),
            norm_path(r.get("auto_category_path", "")),
            norm_path(r.get("true_category_path", "")),
            r.get("auto_model", ""), r.get("auto_confidence", ""),
            t, "",  # 사람이 확정할 error_type / 비고
        ])

    rep.section("유형별 분포 (휴리스틱 초안)")
    rep.table(["오분류 유형", "건수", "비율"],
              [[t, n, f"{n / len(mismatches) * 100:.1f}%"] for t, n in counter.most_common()])
    rep.data["mismatch_total"] = len(mismatches)
    rep.data["type_counts"] = dict(counter)

    rep.csv("misclassification_cases.csv",
            ["cmdt_nm", "auto_category_path", "true_category_path", "auto_model",
             "auto_confidence", "type_guess", "type_confirmed"],
            out_rows)

    # ── 대표 사례 ─────────────────────────────────────
    rep.section("유형별 대표 사례 (각 최대 3건)")
    shown = Counter()
    sample_rows = []
    for row in out_rows:
        t = row[5]
        if shown[t] >= 3:
            continue
        shown[t] += 1
        sample_rows.append([t, row[0][:40], row[1][:28], row[2][:28], row[3]])
    rep.table(["유형", "물품명", "자동 분류", "정답", "모델"], sample_rows)

    # ── 향후 과제 문장 초안 ───────────────────────────
    rep.section("5장 향후 과제 문장 초안")
    hints = {
        "문맥 의존형": "같은 공매번호 내 다른 물품을 참조하는 로트 단위 공동 분류",
        "포장재·용기 표기형": "포장 규격 표기를 걸러내는 전처리 규칙 추가",
        "복수 품목 묶음명형": "묶음 표기 파싱 후 대표 품목 기준 다중 카테고리 부여",
        "카테고리 부재형": "카테고리 트리 확장(예: 생활용품 > 위생용품 > 티슈·냅킨)",
    }
    for t, n in counter.most_common():
        if t in hints:
            rep.text(f"- {t} {n}건 → 개선 방향: {hints[t]}")
    rep.note("type_guess 는 키워드 휴리스틱 결과다. misclassification_cases.csv 의 "
             "type_confirmed 열을 사람이 채워 확정한 뒤 논문에 인용한다.")

    rep.save()
    return 0


if __name__ == "__main__":
    sys.exit(main())
