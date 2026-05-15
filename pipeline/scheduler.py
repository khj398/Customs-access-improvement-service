"""
CAIS 파이프라인 스케줄러
=========================
매일 지정된 시각에 자동으로 파이프라인을 실행합니다.

사용법:
  python pipeline/scheduler.py                     # 기본 (매일 02:00)
  python pipeline/scheduler.py --time 03:30        # 매일 03:30 실행
  python pipeline/scheduler.py --use-openai        # OpenAI fallback 포함
  python pipeline/scheduler.py --run-now           # 즉시 1회 실행 후 스케줄 유지

의존성:
  pip install schedule
"""

import argparse
import logging
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

# ── 경로 ──────────────────────────────────────────────────────────────
ROOT = Path(__file__).resolve().parent.parent
PIPELINE_SCRIPT = Path(__file__).resolve().parent / "run_pipeline.py"
AUTO_RULE_SCRIPT = ROOT / "classification" / "auto_rule_builder.py"
LOG_DIR = ROOT / "logs"
LOG_DIR.mkdir(exist_ok=True)

# ── 로깅 ──────────────────────────────────────────────────────────────
log_file = LOG_DIR / f"scheduler_{datetime.now():%Y%m}.log"
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler(log_file, encoding="utf-8"),
    ],
)
log = logging.getLogger("cais.scheduler")


def run_pipeline(use_openai: bool, openai_model: str):
    """파이프라인 1회 실행."""
    log.info("파이프라인 시작 ─────────────────────────────")
    cmd = [sys.executable, str(PIPELINE_SCRIPT), "--mode", "full"]
    if use_openai:
        cmd += ["--use-openai", "--openai-model", openai_model]

    t0 = time.time()
    try:
        result = subprocess.run(cmd, env=os.environ.copy())
        elapsed = time.time() - t0
        if result.returncode == 0:
            log.info(f"파이프라인 완료 ✅  ({elapsed:.1f}s)")
        else:
            log.error(f"파이프라인 실패 ❌  (exit={result.returncode}, {elapsed:.1f}s)")
    except Exception as exc:
        log.exception(f"파이프라인 예외 발생: {exc}")


def run_auto_rule_builder(openai_model: str, min_count: int, confidence: float):
    """Fallback 자동 규칙 생성 1회 실행."""
    if not os.environ.get("OPENAI_API_KEY"):
        log.warning("OPENAI_API_KEY 없음 — auto_rule_builder 건너뜀")
        return
    log.info("auto_rule_builder 시작 ─────────────────────────────")
    cmd = [
        sys.executable,
        str(AUTO_RULE_SCRIPT),
        "--min-count", str(min_count),
        "--confidence", str(confidence),
        "--openai-model", openai_model,
    ]
    t0 = time.time()
    try:
        result = subprocess.run(cmd, env=os.environ.copy())
        elapsed = time.time() - t0
        if result.returncode == 0:
            log.info(f"auto_rule_builder 완료 ✅  ({elapsed:.1f}s)")
        else:
            log.error(f"auto_rule_builder 실패 ❌  (exit={result.returncode}, {elapsed:.1f}s)")
    except Exception as exc:
        log.exception(f"auto_rule_builder 예외 발생: {exc}")


def main():
    parser = argparse.ArgumentParser(description="CAIS 파이프라인 스케줄러")
    parser.add_argument(
        "--time",
        default="02:00",
        help="매일 실행 시각 HH:MM (기본: 02:00 KST)",
    )
    parser.add_argument(
        "--use-openai",
        action="store_true",
        help="OpenAI fallback 분류 활성화",
    )
    parser.add_argument(
        "--openai-model",
        default="gpt-4o-mini",
        help="OpenAI 모델 (기본: gpt-4o-mini)",
    )
    parser.add_argument(
        "--run-now",
        action="store_true",
        help="즉시 1회 실행 후 스케줄 유지",
    )
    parser.add_argument(
        "--auto-rules",
        action="store_true",
        help="파이프라인 완료 후 fallback 자동 규칙 생성 실행 (OPENAI_API_KEY 필요)",
    )
    parser.add_argument(
        "--auto-rules-min-count",
        type=int,
        default=5,
        help="자동 규칙 추가 최소 물품 수 (기본: 5)",
    )
    parser.add_argument(
        "--auto-rules-confidence",
        type=float,
        default=0.85,
        help="자동 규칙 추가 최소 confidence (기본: 0.85)",
    )
    args = parser.parse_args()

    try:
        import schedule
    except ImportError:
        print("오류: 'schedule' 패키지가 없습니다.")
        print("실행: pip install schedule")
        sys.exit(1)

    log.info(
        f"스케줄러 시작 — 매일 {args.time} 실행"
        + (" (OpenAI 포함)" if args.use_openai else "")
        + (" + 자동규칙" if args.auto_rules else "")
    )
    log.info(f"로그 파일: {log_file}")

    def job():
        run_pipeline(args.use_openai, args.openai_model)
        if args.auto_rules:
            run_auto_rule_builder(
                args.openai_model,
                args.auto_rules_min_count,
                args.auto_rules_confidence,
            )

    schedule.every().day.at(args.time).do(job)
    log.info(f"다음 실행 예정: {schedule.next_run()}")

    if args.run_now:
        log.info("--run-now 플래그 → 즉시 1회 실행")
        job()

    log.info("스케줄 대기 중... (Ctrl+C로 종료)")
    while True:
        schedule.run_pending()
        time.sleep(60)


if __name__ == "__main__":
    main()
