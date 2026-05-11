"""
생활·주방 카테고리 DB 추가 + 재분류 + 평가 스크립트
실행: python classification/eval/db_setup_kitchen.py
"""
import os, sys, io, csv
from pathlib import Path

if sys.stdout.encoding and sys.stdout.encoding.lower() not in ("utf-8", "utf8"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

os.environ.setdefault("DB_HOST", "localhost")
os.environ.setdefault("DB_USER", "root")
os.environ.setdefault("DB_PASSWORD", "1234")
os.environ.setdefault("DB_NAME", "customs_auction")

import mysql.connector

EVAL_DIR = Path(__file__).parent
GT_FILE  = EVAL_DIR / "ground_truth.csv"

# ─────────────────────────────────────────────────────────────
# 1. 카테고리 계층 추가
#    생활·주방 (대분류)
#      └─ 주방·식탁 (중분류)
#           ├─ 식기류     (소분류)  ← PLATE/BOWL/MUG/CUP/GLASS/SPOON/FORK
#           └─ 주방용품   (소분류)  ← BOTTLE/TUMBLER/TRAY/JUG/JAR/BASKET/NAPKIN
# ─────────────────────────────────────────────────────────────
CATEGORY_TREE = [
    # (name_ko, parent_name_ko, level)  — 생활·주방(id=7)은 이미 존재
    ("주방·식탁",   "생활·주방", 2),
    ("식기류",      "주방·식탁", 3),
    ("주방용품",    "주방·식탁", 3),
]

# 재라벨링할 항목: (pbac_no, pbac_srno, cmdt_ln_no) → true_category_path
KITCHEN_LABELS = {
    # 900003 Cherry Blossom 묶음
    ("02026019000031", "900003", "003"): "생활·주방 > 주방·식탁 > 식기류",   # PLATE PP CHERRY BLOSSOM
    ("02026019000031", "900003", "008"): "생활·주방 > 주방·식탁 > 식기류",   # MUG WITH HANDLE BUNNY
    ("02026019000031", "900003", "009"): "생활·주방 > 주방·식탁 > 식기류",   # BOWL SHAPE AS CHICKEN
    ("02026019000031", "900003", "012"): "생활·주방 > 주방·식탁 > 주방용품", # BOTTLE DRINKING 550ML
    ("02026019000031", "900003", "017"): "생활·주방 > 주방·식탁 > 주방용품", # TUMBLER WITH HANDLE
    # 900051 Flower 묶음
    ("02026019000511", "900051", "001"): "생활·주방 > 주방·식탁 > 주방용품", # TRAY WATER HYACINTH
    ("02026019000511", "900051", "003"): "생활·주방 > 주방·식탁 > 식기류",   # GLASS DRINKING WITH DOTS
    ("02026019000511", "900051", "005"): "생활·주방 > 주방·식탁 > 식기류",   # MUG SHAPE AS FLOWER
    ("02026019000511", "900051", "006"): "생활·주방 > 주방·식탁 > 식기류",   # BOWL FLOWER STONEWARE
    ("02026019000511", "900051", "007"): "생활·주방 > 주방·식탁 > 식기류",   # PLATE FLOWER STONEWARE
    ("02026019000511", "900051", "020"): "생활·주방 > 주방·식탁 > 식기류",   # MUG WITH HANDLE FLOWER
}


def get_conn():
    return mysql.connector.connect(
        host=os.environ["DB_HOST"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        database=os.environ["DB_NAME"],
    )


def insert_categories(conn) -> dict:
    """카테고리를 삽입하고 name_ko → category_id 맵을 반환"""
    cur = conn.cursor(dictionary=True)

    # 기존 카테고리 조회
    cur.execute("SELECT category_id, name_ko FROM category")
    existing = {r["name_ko"]: r["category_id"] for r in cur.fetchall()}

    name_to_id = dict(existing)

    for name_ko, parent_name, level in CATEGORY_TREE:
        if name_ko in existing:
            print(f"  [skip] 이미 존재: {name_ko} (id={existing[name_ko]})")
            continue
        parent_id = name_to_id[parent_name] if parent_name else None
        cur.execute(
            "INSERT INTO category (name_ko, parent_id, level) VALUES (%s, %s, %s)",
            (name_ko, parent_id, level),
        )
        conn.commit()
        new_id = cur.lastrowid
        name_to_id[name_ko] = new_id
        print(f"  [추가] {name_ko} (id={new_id}, parent_id={parent_id})")

    cur.close()
    return name_to_id


def update_ground_truth(new_labels: dict):
    """ground_truth.csv의 true_category_path 업데이트"""
    rows = []
    with open(GT_FILE, encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        for row in reader:
            key = (row["pbac_no"], row["pbac_srno"], row["cmdt_ln_no"])
            if key in new_labels:
                row["true_category_path"] = new_labels[key]
                row["labeler"] = "sample"
                row["note"] = "생활·주방 카테고리 신설 후 재라벨링"
            rows.append(row)

    with open(GT_FILE, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"  ground_truth.csv 업데이트: {len(new_labels)}건 재라벨링")


def show_category_tree(conn):
    cur = conn.cursor(dictionary=True)
    cur.execute("""
        SELECT c.category_id, c.name_ko, c.parent_id, p.name_ko AS parent_name
        FROM category c
        LEFT JOIN category p ON p.category_id = c.parent_id
        ORDER BY COALESCE(c.parent_id, c.category_id), c.parent_id, c.category_id
    """)
    rows = cur.fetchall()
    cur.close()
    print("\n현재 카테고리 트리:")
    for r in rows:
        indent = "    └─ " if r["parent_id"] else ""
        parent_info = f" (parent: {r['parent_name']})" if r["parent_name"] else " [대분류]"
        print(f"  {indent}{r['category_id']:>3}. {r['name_ko']}{parent_info}")


def main():
    print("=" * 55)
    print("  생활·주방 카테고리 추가 스크립트")
    print("=" * 55)

    conn = get_conn()

    # 1. 카테고리 삽입
    print("\n[1단계] 카테고리 삽입")
    name_to_id = insert_categories(conn)

    # 2. ground_truth.csv 재라벨링
    print("\n[2단계] ground_truth.csv 재라벨링")
    update_ground_truth(KITCHEN_LABELS)

    # 3. 카테고리 트리 출력
    show_category_tree(conn)

    conn.close()
    print("\n완료. 다음 단계:")
    print("  python classification/run_classification.py --rule-only-update")
    print("  python classification/eval/refresh_auto.py")
    print("  python classification/eval/evaluate.py --save")


if __name__ == "__main__":
    main()
