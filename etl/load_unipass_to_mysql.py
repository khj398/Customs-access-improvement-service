import json
import re
from datetime import datetime
from typing import Any, Optional

import pymysql


# =========================================================
# 설정
# =========================================================
JSON_PATH = "unipass_all.json"   # 경로 알맞게 수정
DB_CONFIG = {
    "host": "127.0.0.1",
    "user": "root",
    "password": "password",    # ← 수정
    "database": "customs_auction",
    "charset": "utf8mb4",
    "cursorclass": pymysql.cursors.DictCursor,
    "autocommit": False,
}


# =========================================================
# 유틸 함수
# =========================================================
def to_datetime_yyyymmddhhmmss(s: Optional[str]) -> Optional[datetime]:
    if not s:
        return None
    s = str(s).strip()
    if not re.fullmatch(r"\d{14}", s):
        return None
    return datetime.strptime(s, "%Y%m%d%H%M%S")


def as_str(x: Any) -> Optional[str]:
    if x is None:
        return None
    x = str(x).strip()
    return x if x != "" and x.lower() != "null" else None


def as_int(x: Any) -> Optional[int]:
    try:
        return int(x)
    except Exception:
        return None


def as_float(x: Any) -> Optional[float]:
    try:
        return float(x)
    except Exception:
        return None


def infer_unit_kind(field: str) -> str:
    return "QTY" if field == "qty" else "WEIGHT"


def _extract_image_urls(value: Any) -> list[str]:
    urls: list[str] = []

    def walk(v: Any) -> None:
        if isinstance(v, dict):
            for _, child in v.items():
                walk(child)
            return
        if isinstance(v, list):
            for child in v:
                walk(child)
            return
        if not isinstance(v, str):
            return

        for m in re.findall(r"https?://[^\s\"'<>]+", v, flags=re.IGNORECASE):
            low = m.lower()
            if any(h in low for h in ("img", "image", "photo", "thumb")) or low.endswith((".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp")):
                urls.append(m)

    walk(value)
    return list(dict.fromkeys(urls))


def get_image_urls_from_record(r: dict) -> list[str]:
    candidates = [
        r.get("image_urls"),
        r.get("imageUrls"),
        r.get("imgUrls"),
        r.get("images"),
        r.get("imageList"),
        r.get("imgList"),
        r.get("imageUrl"),
        r.get("imgUrl"),
        r.get("thumbnailUrl"),
    ]

    urls: list[str] = []
    for c in candidates:
        if c is None:
            continue
        urls.extend(_extract_image_urls(c))

    # 후보 키에 없어도, 레코드 전체에서 이미지 URL 힌트 스캔
    if not urls:
        urls.extend(_extract_image_urls(r))

    return list(dict.fromkeys(urls))


# =========================================================
# UPSERT SQL
# =========================================================
SQL_UPSERT_CUSTOMS = """
INSERT INTO customs_office (cstm_sgn, cstm_name)
VALUES (%s, %s)
ON DUPLICATE KEY UPDATE
  cstm_name = VALUES(cstm_name),
  updated_at = CURRENT_TIMESTAMP;
"""

SQL_UPSERT_WAREHOUSE = """
INSERT INTO bonded_warehouse (snar_sgn, snar_name, cstm_sgn)
VALUES (%s, %s, %s)
ON DUPLICATE KEY UPDATE
  snar_name = VALUES(snar_name),
  cstm_sgn = COALESCE(VALUES(cstm_sgn), cstm_sgn),
  updated_at = CURRENT_TIMESTAMP;
"""

SQL_UPSERT_CARGO = """
INSERT INTO cargo_type (cargo_tpcd, cargo_name)
VALUES (%s, %s)
ON DUPLICATE KEY UPDATE
  cargo_name = VALUES(cargo_name),
  updated_at = CURRENT_TIMESTAMP;
"""

SQL_UPSERT_UNIT = """
INSERT INTO unit_code (unit_cd, unit_kind)
VALUES (%s, %s)
ON DUPLICATE KEY UPDATE
  unit_kind = VALUES(unit_kind),
  updated_at = CURRENT_TIMESTAMP;
"""

SQL_UPSERT_AUCTION = """
INSERT INTO auction (
  pbac_no, pbac_yy, pbac_dgcnt, pbac_tncnt,
  cstm_sgn, snar_sgn, cargo_tpcd,
  pbac_strt_dttm, pbac_end_dttm,
  bid_rstc_yn, elct_bid_eon
)
VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
ON DUPLICATE KEY UPDATE
  pbac_yy = VALUES(pbac_yy),
  pbac_dgcnt = VALUES(pbac_dgcnt),
  pbac_tncnt = VALUES(pbac_tncnt),
  cstm_sgn = VALUES(cstm_sgn),
  snar_sgn = VALUES(snar_sgn),
  cargo_tpcd = VALUES(cargo_tpcd),
  pbac_strt_dttm = VALUES(pbac_strt_dttm),
  pbac_end_dttm = VALUES(pbac_end_dttm),
  bid_rstc_yn = VALUES(bid_rstc_yn),
  elct_bid_eon = VALUES(elct_bid_eon),
  updated_at = CURRENT_TIMESTAMP;
"""

SQL_UPSERT_ITEM = """
INSERT INTO auction_item (
  pbac_no, pbac_srno, cmdt_ln_no,
  cmdt_nm, cmdt_qty, cmdt_qty_ut_cd,
  cmdt_wght, cmdt_wght_ut_cd,
  pbac_prng_prc,
  atnt_cmdt, atnt_cmdt_nm,
  pbac_cond_cn
)
VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
ON DUPLICATE KEY UPDATE
  cmdt_nm = VALUES(cmdt_nm),
  cmdt_qty = VALUES(cmdt_qty),
  cmdt_qty_ut_cd = VALUES(cmdt_qty_ut_cd),
  cmdt_wght = VALUES(cmdt_wght),
  cmdt_wght_ut_cd = VALUES(cmdt_wght_ut_cd),
  pbac_prng_prc = VALUES(pbac_prng_prc),
  atnt_cmdt = VALUES(atnt_cmdt),
  atnt_cmdt_nm = VALUES(atnt_cmdt_nm),
  pbac_cond_cn = VALUES(pbac_cond_cn),
  updated_at = CURRENT_TIMESTAMP;
"""

SQL_UPSERT_ITEM_IMAGE = """
INSERT INTO auction_item_image (
  pbac_no, pbac_srno, cmdt_ln_no, image_seq, image_url, source_type
)
VALUES (%s,%s,%s,%s,%s,%s)
ON DUPLICATE KEY UPDATE
  image_url = VALUES(image_url),
  source_type = VALUES(source_type),
  updated_at = CURRENT_TIMESTAMP;
"""


# =========================================================
# 메인 로직
# =========================================================
def main():
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        records = json.load(f)

    conn = pymysql.connect(**DB_CONFIG)
    auction_cnt = 0
    item_cnt = 0

    try:
        with conn.cursor() as cur:
            for r in records:
                pbac_no = as_str(r.get("pbacNo"))
                pbac_srno = as_str(r.get("pbacSrno"))
                cmdt_ln_no = as_str(r.get("cmdtLnNo"))

                if not (pbac_no and pbac_srno and cmdt_ln_no):
                    continue  # 핵심 키 없으면 스킵

                # ---- 마스터 적재 ----
                cstm_sgn = as_str(r.get("pbacCstmSgn"))
                cstm_nm = as_str(r.get("pbacCstmSgnNm"))
                if cstm_sgn and cstm_nm:
                    cur.execute(SQL_UPSERT_CUSTOMS, (cstm_sgn, cstm_nm))

                snar_sgn = as_str(r.get("snarSgn"))
                snar_nm = as_str(r.get("snarSgnNm"))
                if snar_sgn and snar_nm:
                    cur.execute(SQL_UPSERT_WAREHOUSE, (snar_sgn, snar_nm, cstm_sgn))

                cargo_cd = as_str(r.get("pbacTrgtCargTpcd"))
                cargo_nm = as_str(r.get("pbacTrgtCargTpNm"))
                if cargo_cd and cargo_nm:
                    cur.execute(SQL_UPSERT_CARGO, (cargo_cd, cargo_nm))

                qty_unit = as_str(r.get("cmdtQtyUtCd"))
                if qty_unit:
                    cur.execute(SQL_UPSERT_UNIT, (qty_unit, infer_unit_kind("qty")))

                wght_unit = as_str(r.get("cmdtWghtUtCd"))
                if wght_unit:
                    cur.execute(SQL_UPSERT_UNIT, (wght_unit, infer_unit_kind("wght")))

                # ---- auction (상위) ----
                cur.execute(
                    SQL_UPSERT_AUCTION,
                    (
                        pbac_no,
                        as_str(r.get("pbacYy")),
                        as_str(r.get("pbacDgcnt")),
                        as_str(r.get("pbacTncnt")),
                        cstm_sgn,
                        snar_sgn,
                        cargo_cd,
                        to_datetime_yyyymmddhhmmss(as_str(r.get("pbacStrtDttm"))),
                        to_datetime_yyyymmddhhmmss(as_str(r.get("pbacEndDttm"))),
                        as_str(r.get("bidRstcYn")),
                        as_str(r.get("elctBidEon")),
                    ),
                )
                auction_cnt += 1

                # ---- auction_item (하위) ----
                cur.execute(
                    SQL_UPSERT_ITEM,
                    (
                        pbac_no,
                        pbac_srno,
                        cmdt_ln_no,
                        as_str(r.get("cmdtNm")) or "UNKNOWN",
                        as_int(r.get("cmdtQty")),
                        qty_unit,
                        as_float(r.get("cmdtWght")),
                        wght_unit,
                        as_int(r.get("pbacPrngPrc")),
                        as_str(r.get("atntCmdt")),
                        as_str(r.get("atntCmdtNm")),
                        as_str(r.get("pbacCondCn")),
                    ),
                )

                image_urls = get_image_urls_from_record(r)
                for seq, image_url in enumerate(image_urls, start=1):
                    cur.execute(
                        SQL_UPSERT_ITEM_IMAGE,
                        (pbac_no, pbac_srno, cmdt_ln_no, seq, image_url, "LIST_API"),
                    )

                item_cnt += 1

        conn.commit()
        print(f"✅ ETL complete | auctions processed: {auction_cnt}, items processed: {item_cnt}")
        print("Tip: rerun is safe (UPSERT with 3-column PK).")

    except Exception as e:
        conn.rollback()
        raise e
    finally:
        conn.close()


if __name__ == "__main__":
    main()
