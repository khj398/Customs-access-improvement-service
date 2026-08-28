"""
snapshot_db.py — mysqldump 대체 백업 (실험계획서 5.2)
=====================================================
mysqldump 가 PATH 에 없을 때 사용하는 대체 백업.
주요 테이블을 CSV 로 내보내고 행 수를 기록한다.

한계: 스키마·인덱스·트리거는 저장하지 않는다. 완전한 복구용 백업이 필요하면
      mysqldump 를 설치해 make_snapshot.ps1 을 다시 실행할 것.
      (스키마는 db/*.sql 로 재생성 가능하므로 실험 재현에는 CSV로 충분하다)

실행:
    python Additional_Experiment/snapshot/snapshot_db.py --out <폴더>
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))

import exp_common as C  # noqa: E402

TABLES = [
    "auction", "auction_item", "auction_item_image", "customs_office",
    "bonded_warehouse", "cargo_type", "unit_code",
    "category", "item_classification", "item_search_token", "synonym_dictionary",
]
OPTIONAL_TABLES = ["ingestion_run", "raw_payload", "change_event"]


def main() -> int:
    ap = argparse.ArgumentParser(description="MySQL CSV 백업")
    ap.add_argument("--out", required=True, help="출력 폴더")
    args = ap.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    conn = C.db_conn()

    manifest = {"created_at": C.now_stamp(), "database": C.db_config()["database"], "tables": {}}
    print(f"CSV 백업 -> {out}")

    for table in TABLES + OPTIONAL_TABLES:
        if not C.table_exists(conn, table):
            print(f"  [건너뜀] {table} (없음)")
            continue
        rows = C.fetch_all(conn, f"SELECT * FROM `{table}`")
        path = out / f"{table}.csv"
        headers = list(rows[0].keys()) if rows else []
        if not headers:
            cols = C.fetch_all(conn, f"SHOW COLUMNS FROM `{table}`")
            headers = [c["Field"] for c in cols]
        with open(path, "w", encoding="utf-8-sig", newline="") as f:
            w = csv.writer(f)
            w.writerow(headers)
            for r in rows:
                w.writerow([r.get(h) for h in headers])
        manifest["tables"][table] = len(rows)
        print(f"  [저장] {table}: {len(rows):,}행")

    (out / "MANIFEST.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
    print(f"\n완료: {out / 'MANIFEST.json'}")
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
