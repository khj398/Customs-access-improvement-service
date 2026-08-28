"""
run_all.py — 실험 일괄 실행
============================
사람 손이 필요 없는 자동 실험만 순서대로 실행한다.
사람이 개입해야 하는 단계(E03 P@5 판정, E05 라벨링, E06 사용성 실험, E13 판정)는
안내만 출력하고 건너뛴다.

실행:
    python Additional_Experiment/scripts/run_all.py                # 필수 자동 실험
    python Additional_Experiment/scripts/run_all.py --set all      # 권장·선택까지
    python Additional_Experiment/scripts/run_all.py --set required --dry-run
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))

import exp_common as C  # noqa: E402

SCRIPTS = Path(__file__).resolve().parent

# (스크립트, 인자, 구분, 설명)
AUTO_STEPS = [
    ("e00_preflight.py", [], "사전", "환경 점검"),
    ("e01_dataset_stats.py", [], "필수", "데이터셋 기초 통계 (표 3)"),
    ("e02_classification_coverage.py", [], "필수", "자동 분류 커버리지 (표 4 상단)"),
    ("e03_search_baseline.py", [], "필수", "한글 검색 베이스라인 비교 (표 5)"),
    ("e04_typo_tolerance.py", [], "필수", "오타 허용 검증 (표 5 하단)"),
    ("e07_hybrid_ablation.py", [], "권장", "하이브리드 기여도 (표 4 병합)"),
    ("e08_token_ablation.py", [], "권장", "토큰 유형별 기여도 (4.3 본문)"),
    ("e10_latency.py", [], "선택", "검색 응답시간 p50/p95 (표 5 병합)"),
    ("e11_idempotency.py", [], "선택", "파이프라인 멱등성 (조회 전용 모드)"),
]

# ground_truth_v2.csv 가 있어야 실행 가능한 후속 실험
GT_DEPENDENT = [
    ("e09_confidence_bins.py", [], "권장", "신뢰도 구간별 정확도 (4.2 본문)"),
    ("e12_error_analysis.py", [], "선택", "오분류 정성 분석 (5장 본문)"),
]

MANUAL_STEPS = [
    ("E03 P@5 판정", "results/E03/p5_judgement.csv 를 2인이 독립 판정 후 "
                     "`python Additional_Experiment/scripts/e03b_p5_score.py`"),
    ("E05 블라인드 라벨링", "`e05a_sample_blind.py` → 3인 라벨링 → `e05b_merge_and_evaluate.py`"),
    ("E06 사용성 실험", "`e06_usability_analyze.py --init` → 참가자 8~10명 실험 → "
                        "`e06_usability_analyze.py`"),
    ("E13 LLM 깊이 비교", "`e13_llm_depth.py --run` → 사람 판정 → `e13_llm_depth.py --score`"),
]

SETS = {
    "required": {"사전", "필수"},
    "recommended": {"사전", "필수", "권장"},
    "all": {"사전", "필수", "권장", "선택"},
}


def run(script: str, extra: list[str], dry: bool) -> int:
    cmd = [sys.executable, str(SCRIPTS / script), *extra]
    print("\n" + "=" * 72)
    print(f"$ {' '.join(Path(c).name if c.endswith('.py') else c for c in cmd)}")
    print("=" * 72)
    if dry:
        return 0
    proc = subprocess.run(cmd, cwd=str(C.REPO_ROOT))
    return proc.returncode


def main() -> int:
    ap = argparse.ArgumentParser(description="실험 일괄 실행")
    ap.add_argument("--set", choices=list(SETS), default="required")
    ap.add_argument("--dry-run", action="store_true", help="실행 없이 순서만 출력")
    ap.add_argument("--continue-on-error", action="store_true", default=True)
    ap.add_argument("--stop-on-error", dest="continue_on_error", action="store_false")
    args = ap.parse_args()

    wanted = SETS[args.set]
    results = []

    steps = [s for s in AUTO_STEPS if s[2] in wanted]
    gt_path = C.RESULTS_DIR / "E05" / "ground_truth_v2.csv"
    if gt_path.exists():
        steps += [s for s in GT_DEPENDENT if s[2] in wanted]

    print(f"실행 대상: {len(steps)}건  (set={args.set})")
    for script, extra, kind, desc in steps:
        rc = run(script, extra, args.dry_run)
        results.append([script, kind, desc, "성공" if rc == 0 else f"실패(exit={rc})"])
        if rc != 0 and not args.continue_on_error:
            break

    print("\n" + "=" * 72)
    print("  실행 요약")
    print("=" * 72)
    print(C.console_table(["스크립트", "구분", "설명", "결과"], results))

    if not gt_path.exists():
        print(f"\n[안내] {C.rel(gt_path)} 가 없어 E09 · E12 는 건너뛰었다.")

    print("\n사람이 수행해야 하는 단계:")
    for name, how in MANUAL_STEPS:
        print(f"  - {name}: {how}")

    print("\n결과 취합:  python Additional_Experiment/scripts/collect_results.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
