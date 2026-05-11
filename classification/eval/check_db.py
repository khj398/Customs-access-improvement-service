import os, sys, io
if sys.stdout.encoding and sys.stdout.encoding.lower() not in ("utf-8","utf8"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

os.environ.setdefault("DB_HOST","localhost"); os.environ.setdefault("DB_USER","root")
os.environ.setdefault("DB_PASSWORD","1234");  os.environ.setdefault("DB_NAME","customs_auction")

import mysql.connector
conn = mysql.connector.connect(host=os.environ["DB_HOST"], user=os.environ["DB_USER"],
    password=os.environ["DB_PASSWORD"], database=os.environ["DB_NAME"])
cur = conn.cursor(dictionary=True)

print("=== category 테이블 스키마 ===")
cur.execute("DESCRIBE category")
for r in cur.fetchall(): print(r)

print("\n=== 전체 카테고리 ===")
cur.execute("SELECT category_id, parent_id, level, name_ko FROM category ORDER BY level, category_id")
for r in cur.fetchall(): print(r)
conn.close()
