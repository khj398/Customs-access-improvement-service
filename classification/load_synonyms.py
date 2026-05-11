"""
synonyms.yaml → synonym_dictionary DB 로더
실행: python classification/load_synonyms.py [--dry-run]
"""
import argparse, io, os, sys
from pathlib import Path

if sys.stdout.encoding and sys.stdout.encoding.lower() not in ("utf-8", "utf8"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

os.environ.setdefault("DB_HOST", "localhost")
os.environ.setdefault("DB_USER", "root")
os.environ.setdefault("DB_PASSWORD", "1234")
os.environ.setdefault("DB_NAME", "customs_auction")

import mysql.connector
import yaml

YAML_PATH = Path(__file__).parent / "synonyms.yaml"

SQL_INSERT = """
INSERT IGNORE INTO synonym_dictionary (src_term, norm_term, lang, term_type, weight)
VALUES (%s, %s, 'MIX', %s, %s)
"""

SQL_COUNT = "SELECT COUNT(*) AS cnt FROM synonym_dictionary"

VALID_TYPES = {"SYN", "TRANSLATION", "BRAND", "MODEL", "CATEGORY_HINT"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--yaml", default=str(YAML_PATH))
    args = parser.parse_args()

    with open(args.yaml, encoding="utf-8") as f:
        data = yaml.safe_load(f)

    entries = []
    for item in data.get("synonyms", []):
        src = (item.get("src") or "").strip().upper()
        if not src:
            continue
        for t in item.get("terms", []):
            text   = (t.get("text") or "").strip()
            ttype  = (t.get("type") or "SYN").upper()
            weight = float(t.get("weight", 1.0))
            if not text or ttype not in VALID_TYPES:
                continue
            entries.append((src, text, ttype, weight))

    print(f"synonyms.yaml 항목: {len(entries)}건")

    if args.dry_run:
        for e in entries:
            print(f"  [DRY] {e[0]:20s} → {e[1]:15s}  ({e[2]}, {e[3]})")
        return

    conn = mysql.connector.connect(
        host=os.environ["DB_HOST"], user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"], database=os.environ["DB_NAME"],
    )
    cur = conn.cursor()

    cur.execute(SQL_COUNT)
    before = cur.fetchone()[0]

    added = 0
    skipped = 0
    for row in entries:
        cur.execute(SQL_INSERT, row)
        if cur.rowcount > 0:
            added += 1
        else:
            skipped += 1

    conn.commit()
    cur.execute(SQL_COUNT)
    after = cur.fetchone()[0]
    conn.close()

    print(f"완료: 추가 {added}건 / 이미 존재(skip) {skipped}건")
    print(f"총 동의어: {before}건 → {after}건")


if __name__ == "__main__":
    main()
