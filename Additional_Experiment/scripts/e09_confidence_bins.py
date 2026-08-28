"""
E09. 신뢰도 구간별 정확도  [권장 · 20분]  ★ 신규
=================================================
목적  설계서의 신뢰도 기준표(0.90 이상 검수 불필요 / 0.70 미만 수동 분류)가
      실제로 타당한지 검증한다. E05 의 라벨 결과를 재활용하므로 추가 비용이 없다.

판정  구간이 높을수록 정확도가 단조 증가하면 신뢰도 지표가 유효하다는 뜻이고,
      그렇지 않으면 "신뢰도 보정이 향후 과제"로 5장에 기술한다.
      어느 쪽이든 논문에 쓸 문장이 나온다.

논문 대응  4.2절 본문 (문장)
실험계획서  6장 E9

실행:
    python Additional_Experiment/scripts/e09_confidence_bins.py
    python Additional_Experiment/scripts/e09_confidence_bins.py --gt <경로>
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))

import exp_common as C  # noqa: E402

BINS = [
    ("0.90 이상", 0.90, 1.01),
    ("0.70~0.89", 0.70, 0.90),
    ("0.70 미만", 0.00, 0.70),
]


def norm_path(p: str) -> str:
    return " > ".join(s.strip() for s in (p or "").split(">") if s.strip())


def top1(p: str) -> str:
    return norm_path(p).split(">")[0].strip()


def main() -> int:
    ap = argparse.ArgumentParser(description="E09 신뢰도 구간별 정확도")
    ap.add_argument("--gt", default=str(C.RESULTS_DIR / "E05" / "ground_truth_v2.csv"))
    args = ap.parse_args()

    gt_path = Path(args.gt)
    if not gt_path.exists():
        C.die(f"ground_truth_v2.csv 가 없습니다: {gt_path}\n"
              "   먼저 e05a -> 라벨링 -> e05b 순서로 진행하세요.")

    rep = C.Report("E09", "신뢰도 구간별 정확도", paper_ref="4.2절 본문", plan_ref="6장 E9")
    rows = [r for r in C.read_csv(gt_path) if (r.get("true_category_path") or "").strip()]
    if not rows:
        C.die("라벨된 행이 없습니다.")

    rep.section("입력")
    rep.table(["항목", "값"],
              [["ground truth", C.rel(gt_path)],
               ["라벨 완료 행", len(rows)]])

    # ── 구간별 정확도 ─────────────────────────────────
    rep.section("신뢰도 구간별 정확도")
    table_rows = []
    accs = []
    data_bins = []
    for label, lo, hi in BINS:
        sub = []
        for r in rows:
            try:
                conf = float(r.get("auto_confidence") or 0)
            except ValueError:
                conf = 0.0
            if lo <= conf < hi:
                sub.append(r)
        if not sub:
            table_rows.append([label, 0, "-", "-", "-"])
            data_bins.append({"bin": label, "n": 0, "accuracy": None, "top1_accuracy": None})
            continue
        exact = sum(1 for r in sub
                    if norm_path(r["auto_category_path"]) == norm_path(r["true_category_path"]))
        t1 = sum(1 for r in sub if top1(r["auto_category_path"]) == top1(r["true_category_path"]))
        acc = exact / len(sub)
        accs.append((label, acc))
        table_rows.append([label, len(sub), f"{exact}/{len(sub)}",
                           f"{acc * 100:.1f}%", f"{t1 / len(sub) * 100:.1f}%"])
        data_bins.append({"bin": label, "n": len(sub), "accuracy": round(acc * 100, 1),
                          "top1_accuracy": round(t1 / len(sub) * 100, 1)})
    rep.table(["신뢰도 구간", "건수", "정확 일치", "전체 정확도", "대분류 정확도"], table_rows)
    rep.data["bins"] = data_bins

    # ── 모델 x 구간 교차 ──────────────────────────────
    rep.section("모델 × 신뢰도 구간")
    cross_rows = []
    for model in sorted({(r.get("auto_model") or "unknown") for r in rows}):
        for label, lo, hi in BINS:
            sub = []
            for r in rows:
                if (r.get("auto_model") or "unknown") != model:
                    continue
                try:
                    conf = float(r.get("auto_confidence") or 0)
                except ValueError:
                    conf = 0.0
                if lo <= conf < hi:
                    sub.append(r)
            if not sub:
                continue
            exact = sum(1 for r in sub
                        if norm_path(r["auto_category_path"]) == norm_path(r["true_category_path"]))
            cross_rows.append([model, label, len(sub), f"{exact / len(sub) * 100:.1f}%"])
    rep.table(["모델", "신뢰도 구간", "건수", "정확도"], cross_rows)

    # ── 단조성 판정 ───────────────────────────────────
    rep.section("판정")
    ordered = [a for _, a in accs]                      # BINS 는 높은 구간부터
    monotonic = all(ordered[i] >= ordered[i + 1] for i in range(len(ordered) - 1))
    rep.data["monotonic"] = monotonic
    if len(ordered) < 2:
        rep.note("비교 가능한 구간이 1개뿐이라 단조성을 판정할 수 없다. 표본을 늘리거나 "
                 "구간 경계를 조정한다.")
    elif monotonic:
        rep.note("신뢰도가 높은 구간일수록 정확도가 높다 -> 신뢰도 지표가 유효하다. "
                 "논문 4.2절에 \"confidence 0.90 이상 구간의 정확도는 N%로, 설계서의 "
                 "검수 기준(0.90 이상 검수 불필요)이 타당함을 확인하였다\"로 기술한다.")
    else:
        rep.note("정확도가 신뢰도 순으로 증가하지 않는다 -> 신뢰도 보정을 5장 향후 과제로 기술한다. "
                 "\"현재 confidence 값은 룰의 base_conf 에서 파생되어 실제 정확도와 "
                 "선형적으로 대응하지 않는다\"가 정직한 서술이다.")

    rep.save()
    return 0


if __name__ == "__main__":
    sys.exit(main())
