"""미분류(기타) 물품 목록 출력 스크립트."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "classification"))
from build_classification import DB_CONFIG
import pymysql

conn = pymysql.connect(**DB_CONFIG)
cur = conn.cursor()

cur.execute("""
SELECT
    ai.cmdt_nm,
    ic.model_name,
    ROUND(ic.confidence, 2) AS conf,
    ic.rationale
FROM item_classification ic
JOIN auction_item ai
  ON ic.pbac_no=ai.pbac_no AND ic.pbac_srno=ai.pbac_srno AND ic.cmdt_ln_no=ai.cmdt_ln_no
WHERE ic.category_id IN (
    SELECT c3.category_id FROM category c1
    JOIN category c2 ON c2.parent_id=c1.category_id
    JOIN category c3 ON c3.parent_id=c2.category_id
    WHERE c1.name_ko='기타'
    UNION
    SELECT c2.category_id FROM category c1
    JOIN category c2 ON c2.parent_id=c1.category_id
    WHERE c1.name_ko='기타'
    UNION
    SELECT c1.category_id FROM category c1
    WHERE c1.name_ko='기타' AND c1.parent_id IS NULL
)
ORDER BY ic.model_name, ai.cmdt_nm
""")

rows = cur.fetchall()
print(f"총 미분류 물품: {len(rows)}개\n")
print(f"{'물품명':<55} {'모델':<8} {'신뢰도':<6} 사유")
print("-" * 120)
for r in rows:
    nm = (r['cmdt_nm'] or '')[:53]
    print(f"{nm:<55} {r['model_name']:<8} {r['conf']:<6} {(r['rationale'] or '')[:50]}")

conn.close()
