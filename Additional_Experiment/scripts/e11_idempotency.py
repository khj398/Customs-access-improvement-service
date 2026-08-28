"""
E11. 파이프라인 멱등성 · 처리시간 검증  [선택 · 40분]  ★ 신규
==============================================================
목적  2차 평가 피드백 "데이터 갱신 전략 수립"에 대한 대응이 실제로 동작함을 보인다.
      3.2절 본문 한 문장.

검증
    1. ETL 을 연속 2회 실행한 뒤 auction / auction_item 건수가 동일한지
       (복합 PK + ON DUPLICATE KEY UPDATE 의 멱등성)
    2. ingestion_run 테이블에서 두 실행의 status / raw_item_count / upsert_count 비교
    3. ETL 처리 시간 측정

★ 주의  이 실험만 DB에 쓰기가 발생한다(같은 스냅샷 JSON을 다시 적재하므로 내용은 변하지 않음).
        실험계획서 5.2에 따라 스냅샷을 고정하고 DB 백업을 마친 뒤 실행할 것.
        기본 모드는 조회만 하며, 실제 ETL 실행은 --run-etl 을 명시해야 수행된다.

논문 대응  3.2절 본문 (문장)
실험계획서  6장 E11

실행:
    python Additional_Experiment/scripts/e11_idempotency.py             # 현재 상태 조회만
    python Additional_Experiment/scripts/e11_idempotency.py --run-etl   # ETL 2회 실행 + 비교
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))

import exp_common as C  # noqa: E402

COUNT_TABLES = ["auction", "auction_item", "auction_item_image",
                "item_classification", "item_search_token"]


def snapshot_counts(conn) -> dict[str, int]:
    return {t: int(C.scalar(conn, f"SELECT COUNT(*) FROM `{t}`") or 0) for t in COUNT_TABLES}


def run_etl(label: str, log_dir: Path) -> tuple[float, int, str]:
    script = C.REPO_ROOT / "etl" / "load_unipass_to_mysql.py"
    print(f"\n$ python {C.rel(script)}   ({label})")
    t0 = time.perf_counter()
    proc = subprocess.run([sys.executable, str(script)], capture_output=True, text=True,
                          encoding="utf-8", errors="replace", cwd=str(C.REPO_ROOT))
    elapsed = time.perf_counter() - t0
    out = (proc.stdout or "") + (("\n[stderr]\n" + proc.stderr) if proc.stderr else "")
    log_dir.mkdir(parents=True, exist_ok=True)
    (log_dir / f"etl_{label}.log").write_text(out, encoding="utf-8")
    print(out[-1500:])
    return elapsed, proc.returncode, out


def main() -> int:
    ap = argparse.ArgumentParser(description="E11 파이프라인 멱등성 검증")
    ap.add_argument("--run-etl", action="store_true", help="ETL 을 실제로 2회 실행한다(DB 쓰기 발생)")
    ap.add_argument("--yes", action="store_true", help="확인 프롬프트 생략")
    args = ap.parse_args()

    rep = C.Report("E11", "파이프라인 멱등성 · 처리시간 검증", paper_ref="3.2절 본문", plan_ref="6장 E11")
    conn = C.db_conn()

    before = snapshot_counts(conn)
    rep.section("실행 전 건수")
    rep.table(["테이블", "건수"], [[t, f"{n:,}"] for t, n in before.items()])
    rep.data["before"] = before

    if not args.run_etl:
        rep.note("조회 전용 모드입니다. 멱등성 검증을 실제로 수행하려면 --run-etl 을 붙여 실행하세요. "
                 "실행 전 반드시 스냅샷 고정(5.2)과 DB 백업을 마칠 것.")
    else:
        if not args.yes:
            print("\n[확인] ETL 을 2회 실행합니다. DB 쓰기가 발생합니다.")
            print("       스냅샷 고정과 DB 백업이 완료되었습니까? 계속하려면 'yes' 입력:")
            try:
                answer = input("> ").strip().lower()
            except EOFError:
                answer = ""
            if answer != "yes":
                rep.note("사용자가 실행을 취소했다.")
                rep.save()
                conn.close()
                return 1

        t1, rc1, _ = run_etl("run1", rep.out_dir)
        conn.close()
        conn = C.db_conn()          # ETL 이 커밋한 결과를 새 트랜잭션에서 조회
        mid = snapshot_counts(conn)

        t2, rc2, _ = run_etl("run2", rep.out_dir)
        conn.close()
        conn = C.db_conn()
        after = snapshot_counts(conn)

        rep.section("연속 2회 실행 결과")
        rep.table(
            ["테이블", "실행 전", "1회 후", "2회 후", "1→2회 변화", "멱등"],
            [[t, f"{before[t]:,}", f"{mid[t]:,}", f"{after[t]:,}",
              f"{after[t] - mid[t]:+,}", "O" if after[t] == mid[t] else "X"]
             for t in COUNT_TABLES],
        )
        idempotent = all(after[t] == mid[t] for t in COUNT_TABLES)
        rep.table(["항목", "값"],
                  [["1회차 소요", f"{t1:.1f}초 (exit={rc1})"],
                   ["2회차 소요", f"{t2:.1f}초 (exit={rc2})"],
                   ["멱등성 판정", "통과" if idempotent else "실패"]])
        rep.data.update({"mid": mid, "after": after, "idempotent": idempotent,
                         "etl_run1_sec": round(t1, 1), "etl_run2_sec": round(t2, 1)})
        if idempotent:
            rep.note("동일 입력으로 ETL 을 2회 실행해도 레코드 수가 변하지 않았다 -> "
                     "복합 PK + ON DUPLICATE KEY UPDATE 기반 UPSERT 의 멱등성이 확인된다.")
        else:
            rep.note("2회차 실행에서 건수가 변했다. 어떤 테이블에서 변했는지 확인하고 "
                     "원인(중복 키 누락, 이미지 시퀀스 등)을 3.2절/5장에 기술한다.")

    # ── ingestion_run 이력 ────────────────────────────
    rep.section("ingestion_run 최근 이력")
    if C.table_exists(conn, "ingestion_run"):
        runs = C.fetch_all(conn, """
            SELECT ingestion_run_id, source_name, status, raw_item_count, upsert_count,
                   started_at, finished_at,
                   TIMESTAMPDIFF(SECOND, started_at, finished_at) AS elapsed_sec
            FROM ingestion_run
            ORDER BY ingestion_run_id DESC
            LIMIT 6
        """)
        if runs:
            keys = ["ingestion_run_id", "source_name", "status", "raw_item_count",
                    "upsert_count", "elapsed_sec", "started_at"]
            rep.table(["run_id", "source", "status", "raw", "upsert", "소요(초)", "시작"],
                      [[r[k] for k in keys] for r in runs])
            rep.csv("ingestion_runs.csv", keys, [[r[k] for k in keys] for r in runs])
            rep.data["ingestion_runs"] = [dict(r) for r in runs]
        else:
            rep.note("ingestion_run 이력이 없다. ETL 을 한 번도 실행하지 않았거나 기록이 초기화된 상태.")
    else:
        rep.note("ingestion_run 테이블이 없다. db/schema_patch_v2.sql 을 적용해야 이력이 기록된다.")

    # ── 파이프라인 전체 소요 참고 ─────────────────────
    rep.section("파이프라인 전체 소요 측정 방법")
    for line in [
        "수집 -> ETL -> 분류 -> 색인 전체 소요는 아래 순서로 각 단계 시간을 재어 합산한다.",
        "",
        "```bash",
        "python etl/load_unipass_to_mysql.py",
        "python classification/build_classification.py --use-openai --openai-target-level 2",
        "node cais_back/scripts/sync_meili.js",
        "```",
        "",
        "각 단계의 시작·종료 시각을 기록지에 남기고, 논문 3.2절에는 총 소요만 한 문장으로 쓴다.",
    ]:
        rep.text(line)

    rep.save()
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
