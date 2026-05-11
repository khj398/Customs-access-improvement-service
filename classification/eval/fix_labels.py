"""BOTTLE DRINKING / TUMBLER 레이블 주방용품 → 식기류 수정"""
import csv, os
from pathlib import Path

GT = Path(__file__).parent / "ground_truth.csv"

FIXES = {
    ("02026019000031", "900003", "012"): "생활·주방 > 주방·식탁 > 식기류",   # BOTTLE DRINKING 550ML
    ("02026019000031", "900003", "017"): "생활·주방 > 주방·식탁 > 식기류",   # TUMBLER WITH HANDLE
}

rows = []
changed = 0
with open(GT, encoding="utf-8-sig", newline="") as f:
    reader = csv.DictReader(f)
    fieldnames = reader.fieldnames
    for row in reader:
        key = (row["pbac_no"], row["pbac_srno"], row["cmdt_ln_no"])
        if key in FIXES:
            old = row["true_category_path"]
            row["true_category_path"] = FIXES[key]
            row["note"] = "식기류로 재분류 (음용 용기)"
            print(f"  {row['cmdt_nm'][:40]:40s}  {old} → {FIXES[key]}")
            changed += 1
        rows.append(row)

with open(GT, "w", encoding="utf-8-sig", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)

print(f"\n{changed}건 수정 완료")
