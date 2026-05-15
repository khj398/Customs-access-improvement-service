"""
CAIS 파이프라인 오케스트레이터
================================
ETL → 분류 → 통계 리포트를 순차 실행합니다.

사용법:
  python pipeline/run_pipeline.py                        # ETL + Rule 분류
  python pipeline/run_pipeline.py --use-openai           # ETL + Rule + OpenAI fallback
  python pipeline/run_pipeline.py --mode classify-only   # 분류만 (ETL 생략)
  python pipeline/run_pipeline.py --mode etl-only        # ETL만 (분류 생략)
  python pipeline/run_pipeline.py --rule-only-update     # Rule 매칭 물품만 갱신 (OpenAI 결과 보존)
"""

import argparse
import contextlib
import io
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

# Windows 콘솔 UTF-8 출력 보정
if sys.stdout.encoding and sys.stdout.encoding.lower() not in ("utf-8", "utf8"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
if sys.stderr.encoding and sys.stderr.encoding.lower() not in ("utf-8", "utf8"):
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

# ── 경로 ──────────────────────────────────────────────────────────────
ROOT = Path(__file__).resolve().parent.parent
ETL_SCRIPT = ROOT / "etl" / "load_unipass_to_mysql.py"
CLASSIFY_SCRIPT = ROOT / "classification" / "build_classification.py"
AUTO_RULE_SCRIPT = ROOT / "classification" / "auto_rule_builder.py"

# ── 환경변수 기본값 ───────────────────────────────────────────────────
os.environ.setdefault("DB_HOST", "localhost")
os.environ.setdefault("DB_USER", "root")
os.environ.setdefault("DB_PASSWORD", "1234")
os.environ.setdefault("DB_NAME", "customs_auction")


# ──────────────────────────────────────────────────────────────────────
# 유틸
# ──────────────────────────────────────────────────────────────────────
def run_step(label: str, cmd: list) -> bool:
    """서브프로세스로 단계 실행 후 성공 여부 반환."""
    print(f"\n{'='*60}")
    print(f"▶  {label}")
    print(f"   cmd: {' '.join(str(c) for c in cmd)}")
    print("=" * 60)
    t0 = time.time()
    result = subprocess.run(cmd, env=os.environ.copy())
    elapsed = time.time() - t0
    ok = result.returncode == 0
    print(f"\n{'✅ 성공' if ok else f'❌ 실패 (exit={result.returncode})'}  [{elapsed:.1f}s]")
    return ok


def print_stats():
    """DB 현황 수치를 조회해 출력."""
    try:
        import mysql.connector

        conn = mysql.connector.connect(
            host=os.environ["DB_HOST"],
            user=os.environ["DB_USER"],
            password=os.environ["DB_PASSWORD"],
            database=os.environ["DB_NAME"],
        )
        cur = conn.cursor(dictionary=True)

        cur.execute("SELECT COUNT(*) AS total FROM auction_item")
        total = cur.fetchone()["total"]

        cur.execute(
            "SELECT COUNT(*) AS cls,"
            " SUM(model_name='rule') AS by_rule,"
            " SUM(model_name='openai') AS by_openai"
            " FROM item_classification"
        )
        cls = cur.fetchone()

        cur.execute(
            "SELECT COUNT(*) AS new7 FROM auction"
            " WHERE created_at >= NOW() - INTERVAL 7 DAY"
        )
        new7 = cur.fetchone()["new7"]

        cur.execute(
            """
            SELECT c1.name_ko AS category, COUNT(*) AS cnt
            FROM item_classification ic
            JOIN category c  ON ic.category_id = c.category_id
            JOIN category c1 ON c1.category_id = COALESCE(
                CASE WHEN c.level=3 THEN (SELECT parent_id FROM category WHERE category_id=c.parent_id)
                     WHEN c.level=2 THEN c.parent_id
                     ELSE c.category_id END,
                c.category_id
            )
            GROUP BY c1.name_ko
            ORDER BY cnt DESC
            LIMIT 10
            """
        )
        rows = cur.fetchall()
        conn.close()

        classified = cls["cls"] or 0
        by_rule = int(cls["by_rule"] or 0)
        by_openai = int(cls["by_openai"] or 0)

        print("\n" + "=" * 60)
        print("  📊 데이터 현황 리포트")
        print("=" * 60)
        print(f"  전체 물품 수     : {total:,}건")
        if total:
            print(f"  분류 완료        : {classified:,}건  ({classified/total*100:.1f}%)")
            print(f"    - Rule         : {by_rule}건")
            print(f"    - OpenAI       : {by_openai}건")
        print(f"  미분류           : {total - classified:,}건")
        print(f"  최근 7일 신규    : {new7:,}건")
        print("\n  카테고리별 분포 (상위 10개):")
        for r in rows:
            bar = "█" * min((r["cnt"] * 2), 30)
            print(f"    {r['category']:22s} {r['cnt']:4d}건  {bar}")
        print("=" * 60)
    except Exception as exc:
        print(f"⚠️  통계 조회 실패: {exc}")


def save_stats_report(path: Path, run_meta: dict):
    """print_stats() 출력을 캡처해 accuracy_report.txt로 저장."""
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        header = (
            f"CAIS 파이프라인 실행 리포트\n"
            f"실행 시각 : {run_meta['started']:%Y-%m-%d %H:%M:%S}\n"
            f"실행 모드 : {run_meta['mode']}"
            + (" + OpenAI fallback" if run_meta.get("use_openai") else "")
            + f"\n소요 시간 : {run_meta['elapsed']:.1f}초\n"
        )
        print(header)
        print_stats()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(buf.getvalue(), encoding="utf-8")
    # 파일 내용을 콘솔에도 출력
    print(buf.getvalue())
    print(f"📄 리포트 저장 완료: {path}")


# ──────────────────────────────────────────────────────────────────────
# 메인
# ──────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="CAIS 데이터 파이프라인 오케스트레이터")
    parser.add_argument(
        "--mode",
        choices=["full", "etl-only", "classify-only"],
        default="full",
        help="실행 모드 (기본: full = ETL + 분류)",
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
        "--rule-only-update",
        action="store_true",
        help="Rule 매칭 물품만 업데이트 (OpenAI 결과 보존)",
    )
    parser.add_argument(
        "--auto-rules",
        action="store_true",
        help="분류 완료 후 fallback 자동 규칙 생성 실행 (OPENAI_API_KEY 필요)",
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

    started = datetime.now()
    print(f"\n🚀 CAIS 파이프라인 시작  [{started:%Y-%m-%d %H:%M:%S}]")
    print(f"   모드: {args.mode}" + (" + OpenAI fallback" if args.use_openai else ""))

    results = {}

    # ── STEP 1: ETL ──────────────────────────────────────────────────
    if args.mode in ("full", "etl-only"):
        ok = run_step(
            "ETL — 유니패스 JSON → MySQL",
            [sys.executable, str(ETL_SCRIPT)],
        )
        results["ETL"] = ok
        if not ok and args.mode == "full":
            print("\n⚠️  ETL 실패. 분류 단계를 건너뜁니다.")
            print_stats()
            return

    # ── STEP 2: 분류 ─────────────────────────────────────────────────
    if args.mode in ("full", "classify-only"):
        classify_cmd = [sys.executable, str(CLASSIFY_SCRIPT)]
        if args.rule_only_update:
            classify_cmd.append("--rule-only-update")
        if args.use_openai:
            classify_cmd += [
                "--use-openai",
                "--openai-model", args.openai_model,
                "--openai-target-level", "2",
            ]
        label = "분류 — Rule-based" + (" + OpenAI fallback" if args.use_openai else "")
        ok = run_step(label, classify_cmd)
        results["분류"] = ok

    # ── 최종 요약 ─────────────────────────────────────────────────────
    elapsed = (datetime.now() - started).total_seconds()
    print(f"\n⏱  총 소요 시간: {elapsed:.1f}초")
    print("\n  단계별 결과:")
    for step, ok in results.items():
        print(f"    {'✅' if ok else '❌'}  {step}")

    report_path = ROOT / "classification" / "eval" / "accuracy_report.txt"
    save_stats_report(report_path, {
        "started": started,
        "mode": args.mode,
        "use_openai": args.use_openai,
        "elapsed": elapsed,
    })

    # ── STEP 3: 자동 규칙 생성 ───────────────────────────────────────────
    if args.auto_rules and args.mode in ("full", "classify-only"):
        auto_cmd = [
            sys.executable,
            str(AUTO_RULE_SCRIPT),
            "--min-count", str(args.auto_rules_min_count),
            "--confidence", str(args.auto_rules_confidence),
        ]
        if args.use_openai:
            auto_cmd += ["--openai-model", args.openai_model]
        ok = run_step("자동 규칙 생성 — auto_rule_builder", auto_cmd)
        results["자동규칙"] = ok

    sys.exit(0 if all(results.values()) else 1)


if __name__ == "__main__":
    main()
