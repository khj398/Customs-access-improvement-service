"""
DB에서 최신 분류 결과를 가져와 ground_truth.csv의 auto 컬럼을 갱신
"""
import os, csv, sys, io
from pathlib import Path

if sys.stdout.encoding and sys.stdout.encoding.lower() not in ("utf-8", "utf8"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

os.environ.setdefault("DB_HOST", "localhost")
os.environ.setdefault("DB_USER", "root")
os.environ.setdefault("DB_PASSWORD", "1234")
os.environ.setdefault("DB_NAME", "customs_auction")

import mysql.connector

EVAL_DIR = Path(__file__).parent
GT_FILE = EVAL_DIR / "ground_truth.csv"

SQL = """
SELECT
    ai.pbac_no, ai.pbac_srno, ai.cmdt_ln_no,
    CONCAT_WS(' > ', c1.name_ko,
        CASE WHEN c2.name_ko IS NOT NULL THEN c2.name_ko END,
        CASE WHEN c3.name_ko IS NOT NULL THEN c3.name_ko END
    ) AS auto_category_path,
    ic.confidence AS auto_confidence,
    ic.model_name  AS auto_model
FROM item_classification ic
JOIN auction_item ai USING (pbac_no, pbac_srno, cmdt_ln_no)
JOIN category c1 ON c1.category_id = ic.category_id
LEFT JOIN category c2 ON c2.category_id = c1.parent_id
LEFT JOIN category c3 ON c3.category_id = c2.parent_id
"""

def main():
    conn = mysql.connector.connect(
        host=os.environ["DB_HOST"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        database=os.environ["DB_NAME"],
    )
    cur = conn.cursor(dictionary=True)
    cur.execute(SQL)
    rows_db = {(r["pbac_no"], str(r["pbac_srno"]), str(r["cmdt_ln_no"]).zfill(3)): r
               for r in cur.fetchall()}
    conn.close()

    rows_csv = []
    with open(GT_FILE, encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        for row in reader:
            key = (row["pbac_no"], row["pbac_srno"], row["cmdt_ln_no"])
            if key in rows_db:
                db = rows_db[key]
                # 경로가 역순으로 저장돼 있으면 뒤집기
                parts = [p.strip() for p in db["auto_category_path"].split(">") if p.strip()]
                # DB는 leaf→root 순이므로 reverse
                parts.reverse()
                row["auto_category_path"] = " > ".join(parts)
                row["auto_confidence"] = f"{float(db['auto_confidence']):.4f}"
                row["auto_model"] = db["auto_model"]
            rows_csv.append(row)

    with open(GT_FILE, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows_csv)

    print(f"갱신 완료: {len(rows_csv)}건")


if __name__ == "__main__":
    main()
