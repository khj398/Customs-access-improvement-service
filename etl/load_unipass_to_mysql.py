import hashlib
import json
import os
import re
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Optional
from pathlib import Path

import pymysql


# =========================================================
# 설정
# =========================================================
DB_CONFIG = {
    "host": "127.0.0.1",
    "user": "root",
    "password": "password",  # ← 수정
    "database": "customs_auction",
    "charset": "utf8mb4",
    "cursorclass": pymysql.cursors.DictCursor,
    "autocommit": False,
}


@dataclass
class DataSource:
    path: str
    collector_source: str
    source_name: str
    image_source_type: str
    source_kind: str = "json"


DEFAULT_SOURCES = [
    DataSource("unipass_all_2b.json", "BUSINESS", "unipass_list_business", "LIST_BUSINESS"),
    DataSource("unipass_all_2c.json", "PERSONAL", "unipass_list_personal", "LIST_PERSONAL"),
    DataSource("unipass_image.json", "IMAGE", "unipass_image", "UNIPASS_IMAGE_JSON"),
]


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


def make_source_key(pbac_no: str, pbac_srno: str, cmdt_ln_no: str) -> str:
    return f"{pbac_no}|{pbac_srno}|{cmdt_ln_no}"


def make_payload_hash(record: dict) -> str:
    canonical = json.dumps(record, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def resolve_sources() -> list[DataSource]:
    """
    환경변수 UNIPASS_JSON_FILES로 입력 파일을 지정할 수 있다.
    형식: path[:collector_source[:source_name]] 를 콤마로 연결
    예: unipass_all_2b.json:BUSINESS:unipass_list_business,unipass_all_2c.json:PERSONAL
    """
    env = os.getenv("UNIPASS_JSON_FILES", "").strip()
    if env:
        out: list[DataSource] = []
        for chunk in env.split(","):
            chunk = chunk.strip()
            if not chunk:
                continue
            parts = [x.strip() for x in chunk.split(":")]
            path = parts[0]
            collector = parts[1].upper() if len(parts) >= 2 and parts[1] else "UNKNOWN"
            source_name = parts[2] if len(parts) >= 3 and parts[2] else f"unipass_{collector.lower()}"
            out.append(DataSource(path, collector, source_name, f"LIST_{collector}", "json"))
        return out

    sources = [s for s in DEFAULT_SOURCES if os.path.exists(s.path)]

    image_dir = os.getenv("UNIPASS_IMAGE_DIR", "downloaded_images").strip()
    if image_dir and os.path.isdir(image_dir):
        sources.append(DataSource(image_dir, "IMAGE", "unipass_image_dir", "UNIPASS_IMAGE_FILE", "image_dir"))

    return sources


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

    if not urls:
        urls.extend(_extract_image_urls(r))

    return list(dict.fromkeys(urls))


# =========================================================
# UPSERT SQL
# =========================================================
SQL_INSERT_INGESTION_RUN = """
INSERT INTO ingestion_run (
  source_name, collector_source, started_at, status, raw_item_count
)
VALUES (%s, %s, NOW(), 'RUNNING', %s);
"""

SQL_FINISH_INGESTION_RUN = """
UPDATE ingestion_run
SET
  finished_at = NOW(),
  status = %s,
  upsert_count = %s,
  error_count = %s,
  error_message = %s
WHERE ingestion_run_id = %s;
"""

SQL_INSERT_RAW_PAYLOAD = """
INSERT INTO raw_auction_payload (
  ingestion_run_id, source_name, source_key, payload_json, payload_hash
)
VALUES (%s, %s, %s, %s, %s)
ON DUPLICATE KEY UPDATE
  ingestion_run_id = VALUES(ingestion_run_id),
  payload_json = VALUES(payload_json),
  collected_at = CURRENT_TIMESTAMP;
"""

SQL_SELECT_EXISTING_ITEM = """
SELECT pbac_prng_prc, atnt_cmdt
FROM auction_item
WHERE pbac_no = %s AND pbac_srno = %s AND cmdt_ln_no = %s;
"""

SQL_INSERT_CHANGE_EVENT = """
INSERT INTO auction_item_change_event (
  pbac_no, pbac_srno, cmdt_ln_no,
  event_type, before_value_json, after_value_json,
  detected_at, ingestion_run_id
)
VALUES (%s,%s,%s,%s,%s,%s,NOW(),%s);
"""

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
  cstm_sgn, snar_sgn, cargo_tpcd, collector_source,
  pbac_strt_dttm, pbac_end_dttm,
  bid_rstc_yn, elct_bid_eon
)
VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
ON DUPLICATE KEY UPDATE
  pbac_yy = VALUES(pbac_yy),
  pbac_dgcnt = VALUES(pbac_dgcnt),
  pbac_tncnt = VALUES(pbac_tncnt),
  cstm_sgn = VALUES(cstm_sgn),
  snar_sgn = VALUES(snar_sgn),
  cargo_tpcd = VALUES(cargo_tpcd),
  collector_source = VALUES(collector_source),
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


def insert_change_event(cur, pbac_no: str, pbac_srno: str, cmdt_ln_no: str, event_type: str, before_obj: dict, after_obj: dict, ingestion_run_id: int) -> None:
    cur.execute(
        SQL_INSERT_CHANGE_EVENT,
        (
            pbac_no,
            pbac_srno,
            cmdt_ln_no,
            event_type,
            json.dumps(before_obj, ensure_ascii=False),
            json.dumps(after_obj, ensure_ascii=False),
            ingestion_run_id,
        ),
    )




def _load_items_by_cmdt_ln_no(cur, pbac_no: str) -> dict[str, list[dict]]:
    cur.execute(
        """
        SELECT pbac_srno, cmdt_ln_no
        FROM auction_item
        WHERE pbac_no = %s
        """,
        (pbac_no,),
    )
    items = cur.fetchall()

    by_norm_cmdt_ln_no: dict[str, list[dict]] = {}
    for item in items:
        cmdt_ln_no_str = str(item["cmdt_ln_no"])
        norm = str(int(cmdt_ln_no_str)) if cmdt_ln_no_str.isdigit() else cmdt_ln_no_str
        by_norm_cmdt_ln_no.setdefault(norm, []).append(item)

    return by_norm_cmdt_ln_no


def _upsert_image_files_for_pbac(cur, pbac_no: str, image_files: list[Path], source_type: str) -> tuple[int, int]:
    pattern = re.compile(r"^0_(\d+)_(\d+)\.gif$", re.IGNORECASE)
    by_norm_cmdt_ln_no = _load_items_by_cmdt_ln_no(cur, pbac_no)

    upsert_cnt = 0
    error_cnt = 0

    for file in image_files:
        m = pattern.match(file.name)
        if not m:
            continue

        norm_cmdt_ln_no = str(int(m.group(1)))
        image_seq = int(m.group(2)) + 1
        candidates = by_norm_cmdt_ln_no.get(norm_cmdt_ln_no, [])

        if not candidates:
            error_cnt += 1
            continue
        if len(candidates) > 1:
            error_cnt += 1
            continue

        item = candidates[0]
        cur.execute(
            SQL_UPSERT_ITEM_IMAGE,
            (
                pbac_no,
                item["pbac_srno"],
                item["cmdt_ln_no"],
                image_seq,
                str(file.as_posix()),
                source_type,
            ),
        )
        upsert_cnt += 1

    return upsert_cnt, error_cnt


def run_image_dir_source(conn, source: DataSource) -> tuple[int, int, int]:
    pattern = re.compile(r"^0_(\d+)_(\d+)\.gif$", re.IGNORECASE)
    root = Path(source.path)

    # 우선순위 1) 하위 폴더별 처리: downloaded_images/<pbac_no>/0_x_y.gif
    pbac_dirs = [d for d in root.iterdir() if d.is_dir()]

    # 우선순위 2) 레거시 단일 폴더 + 환경변수 지정
    legacy_pbac_no = os.getenv("UNIPASS_IMAGE_PBAC_NO", "").strip()

    with conn.cursor() as cur:
        total_file_count = 0
        if pbac_dirs:
            for d in pbac_dirs:
                total_file_count += len([f for f in d.iterdir() if f.is_file() and pattern.match(f.name)])
        else:
            total_file_count = len([f for f in root.iterdir() if f.is_file() and pattern.match(f.name)])

        cur.execute(SQL_INSERT_INGESTION_RUN, (source.source_name, source.collector_source, total_file_count))
        ingestion_run_id = cur.lastrowid
    conn.commit()

    total_upsert_cnt = 0
    total_error_cnt = 0

    try:
        with conn.cursor() as cur:
            if pbac_dirs:
                for pbac_dir in sorted(pbac_dirs):
                    pbac_no = pbac_dir.name.strip()
                    if not pbac_no:
                        continue
                    image_files = sorted([f for f in pbac_dir.iterdir() if f.is_file() and pattern.match(f.name)])
                    upsert_cnt, error_cnt = _upsert_image_files_for_pbac(cur, pbac_no, image_files, source.image_source_type)
                    total_upsert_cnt += upsert_cnt
                    total_error_cnt += error_cnt
            else:
                if not legacy_pbac_no:
                    print("⚠️  SKIP image_dir source: 폴더 구조(downloaded_images/<pbac_no>/...)가 없으면 UNIPASS_IMAGE_PBAC_NO가 필요합니다.")
                    total_error_cnt += 1
                else:
                    image_files = sorted([f for f in root.iterdir() if f.is_file() and pattern.match(f.name)])
                    upsert_cnt, error_cnt = _upsert_image_files_for_pbac(cur, legacy_pbac_no, image_files, source.image_source_type)
                    total_upsert_cnt += upsert_cnt
                    total_error_cnt += error_cnt

            final_status = "PARTIAL" if total_error_cnt > 0 else "SUCCESS"
            cur.execute(SQL_FINISH_INGESTION_RUN, (final_status, total_upsert_cnt, total_error_cnt, None, ingestion_run_id))

        conn.commit()
        return 0, total_upsert_cnt, total_error_cnt

    except Exception as e:
        conn.rollback()
        with conn.cursor() as cur:
            cur.execute(SQL_FINISH_INGESTION_RUN, ("FAILED", total_upsert_cnt, total_error_cnt + 1, str(e)[:1000], ingestion_run_id))
        conn.commit()
        raise

def run_source(conn, source: DataSource) -> tuple[int, int, int]:
    with open(source.path, "r", encoding="utf-8") as f:
        records = json.load(f)

    with conn.cursor() as cur:
        cur.execute(SQL_INSERT_INGESTION_RUN, (source.source_name, source.collector_source, len(records)))
        ingestion_run_id = cur.lastrowid
    conn.commit()

    auction_cnt = 0
    item_cnt = 0
    error_cnt = 0

    try:
        with conn.cursor() as cur:
            for r in records:
                pbac_no = as_str(r.get("pbacNo"))
                pbac_srno = as_str(r.get("pbacSrno"))
                cmdt_ln_no = as_str(r.get("cmdtLnNo"))

                if not (pbac_no and pbac_srno and cmdt_ln_no):
                    error_cnt += 1
                    continue

                source_key = make_source_key(pbac_no, pbac_srno, cmdt_ln_no)
                payload_hash = make_payload_hash(r)
                cur.execute(
                    SQL_INSERT_RAW_PAYLOAD,
                    (
                        ingestion_run_id,
                        source.source_name,
                        source_key,
                        json.dumps(r, ensure_ascii=False),
                        payload_hash,
                    ),
                )

                cur.execute(SQL_SELECT_EXISTING_ITEM, (pbac_no, pbac_srno, cmdt_ln_no))
                existing = cur.fetchone()

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
                        source.collector_source,
                        to_datetime_yyyymmddhhmmss(as_str(r.get("pbacStrtDttm"))),
                        to_datetime_yyyymmddhhmmss(as_str(r.get("pbacEndDttm"))),
                        as_str(r.get("bidRstcYn")),
                        as_str(r.get("elctBidEon")),
                    ),
                )
                auction_cnt += 1

                price_now = as_int(r.get("pbacPrngPrc"))
                atnt_now = as_str(r.get("atntCmdt"))

                # ---- auction_item (하위) ----
                cur.execute(
                    SQL_UPSERT_ITEM,
                    (
                        pbac_no,
                        pbac_srno,
                        cmdt_ln_no,
                        as_str(r.get("cmdtNm")),
                        as_int(r.get("cmdtQty")),
                        qty_unit,
                        as_float(r.get("cmdtWght")),
                        wght_unit,
                        price_now,
                        atnt_now,
                        as_str(r.get("atntCmdtNm")),
                        as_str(r.get("pbacCondCn")),
                    ),
                )

                if existing is None:
                    insert_change_event(
                        cur,
                        pbac_no,
                        pbac_srno,
                        cmdt_ln_no,
                        "NEW_ITEM",
                        {},
                        {"pbac_prng_prc": price_now, "atnt_cmdt": atnt_now},
                        ingestion_run_id,
                    )
                else:
                    before_price = existing.get("pbac_prng_prc")
                    before_atnt = existing.get("atnt_cmdt")
                    if before_price != price_now:
                        insert_change_event(
                            cur,
                            pbac_no,
                            pbac_srno,
                            cmdt_ln_no,
                            "PRICE_CHANGED",
                            {"pbac_prng_prc": before_price},
                            {"pbac_prng_prc": price_now},
                            ingestion_run_id,
                        )
                    if before_atnt != atnt_now:
                        insert_change_event(
                            cur,
                            pbac_no,
                            pbac_srno,
                            cmdt_ln_no,
                            "STATUS_CHANGED",
                            {"atnt_cmdt": before_atnt},
                            {"atnt_cmdt": atnt_now},
                            ingestion_run_id,
                        )

                image_urls = get_image_urls_from_record(r)
                for seq, image_url in enumerate(image_urls, start=1):
                    cur.execute(
                        SQL_UPSERT_ITEM_IMAGE,
                        (pbac_no, pbac_srno, cmdt_ln_no, seq, image_url, source.image_source_type),
                    )

                item_cnt += 1

            final_status = "PARTIAL" if error_cnt > 0 else "SUCCESS"
            cur.execute(SQL_FINISH_INGESTION_RUN, (final_status, item_cnt, error_cnt, None, ingestion_run_id))

        conn.commit()
        return auction_cnt, item_cnt, error_cnt

    except Exception as e:
        conn.rollback()
        with conn.cursor() as cur:
            cur.execute(
                SQL_FINISH_INGESTION_RUN,
                ("FAILED", item_cnt, error_cnt + 1, str(e)[:1000], ingestion_run_id),
            )
        conn.commit()
        raise


# =========================================================
# 메인 로직
# =========================================================
def main():
    sources = resolve_sources()
    if not sources:
        raise FileNotFoundError(
            "입력 소스가 없습니다. 기본 JSON(unipass_all_2b.json / unipass_all_2c.json / unipass_image.json) 또는 downloaded_images/<pbac_no>/... (레거시: UNIPASS_IMAGE_PBAC_NO), UNIPASS_JSON_FILES 환경변수를 확인하세요."
        )

    conn = pymysql.connect(**DB_CONFIG)
    total_auctions = 0
    total_items = 0
    total_errors = 0

    try:
        for source in sources:
            print(f"▶ loading source: {source.path} ({source.collector_source})")
            if source.source_kind == "image_dir":
                auction_cnt, item_cnt, err_cnt = run_image_dir_source(conn, source)
            else:
                auction_cnt, item_cnt, err_cnt = run_source(conn, source)
            total_auctions += auction_cnt
            total_items += item_cnt
            total_errors += err_cnt

        print(
            "✅ ETL complete | "
            f"auctions processed: {total_auctions}, "
            f"items processed: {total_items}, "
            f"skipped/errors: {total_errors}"
        )
        print("Tip: rerun is safe (UPSERT with 3-column PK).")

    finally:
        conn.close()


if __name__ == "__main__":
    main()
