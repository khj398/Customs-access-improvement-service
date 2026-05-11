"""
분류 정확도 평가 스크립트
=========================
사용법:
    python classification/eval/evaluate.py

사전 조건:
    - classification/eval/ground_truth.csv 에
      true_category_path 컬럼이 채워져 있어야 합니다.
    - 라벨이 비어있는 행은 평가에서 제외됩니다.

출력:
    - 전체 정확도 (Accuracy)
    - 대분류 정확도
    - 모델별(rule / openai) 정확도
    - 오분류 케이스 목록
    - 카테고리별 정밀도(Precision) / 재현율(Recall)
"""

import csv
import io
import os
import sys
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Tuple

# Windows 콘솔 UTF-8 출력
if sys.stdout.encoding and sys.stdout.encoding.lower() not in ("utf-8", "utf8"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

# ──────────────────────────────────────────────
# 설정
# ──────────────────────────────────────────────
EVAL_DIR = Path(__file__).parent
GT_FILE = EVAL_DIR / "ground_truth.csv"
REPORT_FILE = EVAL_DIR / "accuracy_report.txt"

# 목표 정확도 기준
TARGET_OVERALL = 0.80   # 전체 정확도 목표
TARGET_TOP1 = 0.90      # 대분류 정확도 목표
TARGET_RULE = 0.95      # Rule 분류 정확도 목표
TARGET_OPENAI = 0.75    # OpenAI 분류 정확도 목표


# ──────────────────────────────────────────────
# 유틸
# ──────────────────────────────────────────────
def get_top_category(path: str) -> str:
    """'식품·음료 > 음료 > 주류' → '식품·음료'"""
    return path.split(">")[0].strip() if path else ""


def normalize_path(path: str) -> str:
    """공백 통일"""
    return " > ".join(p.strip() for p in path.split(">") if p.strip())


# ──────────────────────────────────────────────
# 데이터 로딩
# ──────────────────────────────────────────────
def load_ground_truth(csv_path: Path) -> List[Dict]:
    if not csv_path.exists():
        print(f"❌ ground_truth.csv 없음: {csv_path}")
        print("   먼저 아래 명령을 실행해 파일을 생성하세요:")
        print("   python -c \"...\"  (README 또는 CLASSIFICATION_LOGIC_DESIGN.md 참고)")
        sys.exit(1)

    rows = []
    with open(csv_path, encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)

    labeled = [r for r in rows if r.get("true_category_path", "").strip()]
    print(f"ℹ️ 전체 {len(rows)}건 중 라벨 완료 {len(labeled)}건 평가")
    return labeled


# ──────────────────────────────────────────────
# 평가 로직
# ──────────────────────────────────────────────
def evaluate(rows: List[Dict]) -> Dict:
    total = len(rows)
    if total == 0:
        print("⚠️ 라벨된 데이터가 없습니다. ground_truth.csv의 true_category_path 컬럼을 채워주세요.")
        sys.exit(0)

    exact_match = 0          # 전체 경로 일치
    top1_match = 0           # 대분류 일치
    mismatches = []
    by_model: Dict[str, Dict] = defaultdict(lambda: {"total": 0, "correct": 0})
    by_true_cat: Dict[str, Dict] = defaultdict(lambda: {"tp": 0, "fp": 0, "fn": 0})
    by_auto_cat: Dict[str, int] = defaultdict(int)

    for row in rows:
        auto = normalize_path(row.get("auto_category_path", ""))
        true = normalize_path(row.get("true_category_path", ""))
        model = row.get("auto_model", "unknown")
        cmdt_nm = row.get("cmdt_nm", "")
        conf = float(row.get("auto_confidence", 0) or 0)

        auto_top = get_top_category(auto)
        true_top = get_top_category(true)

        is_exact = (auto == true)
        is_top1 = (auto_top == true_top)

        if is_exact:
            exact_match += 1
        if is_top1:
            top1_match += 1

        by_model[model]["total"] += 1
        if is_exact:
            by_model[model]["correct"] += 1

        # Precision / Recall
        by_true_cat[true]["fn"] += 0 if is_exact else 1
        by_true_cat[true]["tp"] += 1 if is_exact else 0
        by_auto_cat[auto] += 1
        if not is_exact:
            by_auto_cat[auto]  # fp는 아래에서 계산

        if not is_exact:
            mismatches.append({
                "cmdt_nm": cmdt_nm,
                "auto": auto,
                "true": true,
                "auto_top": auto_top,
                "true_top": true_top,
                "model": model,
                "confidence": conf,
            })

    # FP 계산 (auto_path로 예측했으나 true가 다른 것)
    for row in rows:
        auto = normalize_path(row.get("auto_category_path", ""))
        true = normalize_path(row.get("true_category_path", ""))
        if auto != true:
            by_auto_cat[auto] += 0  # already counted above
            # 실제 fp는 auto 카테고리에 잘못 분류된 수
            if auto in by_true_cat:
                by_true_cat[auto]["fp"] = by_true_cat[auto].get("fp", 0)

    # Precision/Recall per category
    cat_metrics = {}
    all_cats = set(list(by_true_cat.keys()))
    for cat in all_cats:
        tp = by_true_cat[cat]["tp"]
        fn = by_true_cat[cat]["fn"]
        # fp: 이 카테고리로 예측됐으나 실제로는 다른 것
        fp = sum(1 for r in rows
                 if normalize_path(r.get("auto_category_path", "")) == cat
                 and normalize_path(r.get("true_category_path", "")) != cat)
        precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
        recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
        cat_metrics[cat] = {"tp": tp, "fp": fp, "fn": fn,
                             "precision": precision, "recall": recall}

    return {
        "total": total,
        "exact_match": exact_match,
        "top1_match": top1_match,
        "accuracy": exact_match / total,
        "top1_accuracy": top1_match / total,
        "by_model": dict(by_model),
        "mismatches": mismatches,
        "cat_metrics": cat_metrics,
    }


# ──────────────────────────────────────────────
# 리포트 출력
# ──────────────────────────────────────────────
def print_report(result: Dict, save_path: Path = None):
    lines = []

    def p(s=""):
        lines.append(s)
        print(s)

    p("=" * 65)
    p("  분류 정확도 평가 리포트")
    p("=" * 65)
    p()
    p(f"  평가 건수    : {result['total']}건")
    p(f"  전체 정확도  : {result['accuracy']*100:.1f}%  (목표: {TARGET_OVERALL*100:.0f}%)  "
      f"{'✅' if result['accuracy'] >= TARGET_OVERALL else '❌'}")
    p(f"  대분류 정확도: {result['top1_accuracy']*100:.1f}%  (목표: {TARGET_TOP1*100:.0f}%)  "
      f"{'✅' if result['top1_accuracy'] >= TARGET_TOP1 else '❌'}")
    p()

    p("─" * 65)
    p("  모델별 정확도")
    p("─" * 65)
    for model, m in sorted(result["by_model"].items()):
        acc = m["correct"] / m["total"] if m["total"] > 0 else 0
        target = TARGET_RULE if model == "rule" else TARGET_OPENAI
        flag = "✅" if acc >= target else "❌"
        p(f"  {model:<10}: {acc*100:.1f}%  ({m['correct']}/{m['total']}건)  {flag}  (목표 {target*100:.0f}%)")
    p()

    p("─" * 65)
    p("  카테고리별 Precision / Recall")
    p("─" * 65)
    p(f"  {'카테고리':<35} {'P':>7} {'R':>7} {'TP':>5} {'FP':>5} {'FN':>5}")
    for cat, m in sorted(result["cat_metrics"].items(), key=lambda x: -x[1]["tp"]):
        p(f"  {cat[:35]:<35} {m['precision']*100:>6.1f}% {m['recall']*100:>6.1f}%"
          f" {m['tp']:>5} {m['fp']:>5} {m['fn']:>5}")
    p()

    if result["mismatches"]:
        p("─" * 65)
        p(f"  오분류 케이스 ({len(result['mismatches'])}건)")
        p("─" * 65)
        for mm in result["mismatches"][:20]:
            p(f"  [{mm['model']}|conf={mm['confidence']:.2f}]")
            p(f"    물품명 : {mm['cmdt_nm'][:60]}")
            p(f"    자동   : {mm['auto']}")
            p(f"    정답   : {mm['true']}")
            p()
        if len(result["mismatches"]) > 20:
            p(f"  ... 외 {len(result['mismatches'])-20}건")
    else:
        p("  오분류 없음 🎉")

    p("=" * 65)

    if save_path:
        with open(save_path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))
        print(f"\n📄 리포트 저장: {save_path}")


# ──────────────────────────────────────────────
# 메인
# ──────────────────────────────────────────────
def main():
    import argparse
    parser = argparse.ArgumentParser(description="분류 정확도 평가")
    parser.add_argument("--gt", default=str(GT_FILE), help="ground_truth.csv 경로")
    parser.add_argument("--save", action="store_true", help="리포트를 accuracy_report.txt에 저장")
    args = parser.parse_args()

    rows = load_ground_truth(Path(args.gt))
    result = evaluate(rows)
    print_report(result, save_path=REPORT_FILE if args.save else None)


if __name__ == "__main__":
    main()
