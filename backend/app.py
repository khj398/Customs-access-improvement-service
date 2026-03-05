import os
from contextlib import closing
from typing import Any, Dict, List

import pymysql
from fastapi import FastAPI, Query
from pymysql.cursors import DictCursor


app = FastAPI(title="CAIS Backend MVP", version="0.1.0")


def get_db_config() -> Dict[str, Any]:
    return {
        "host": os.getenv("DB_HOST", "127.0.0.1"),
        "port": int(os.getenv("DB_PORT", "3306")),
        "user": os.getenv("DB_USER", "root"),
        "password": os.getenv("DB_PASSWORD", "password"),
        "database": os.getenv("DB_NAME", "customs_auction"),
        "charset": "utf8mb4",
        "cursorclass": DictCursor,
        "autocommit": True,
    }


@app.get("/health")
def health() -> Dict[str, str]:
    return {"status": "ok"}


@app.get("/db/health")
def db_health() -> Dict[str, str]:
    try:
        with closing(pymysql.connect(**get_db_config())) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1 AS ok")
                row = cur.fetchone()
        if row and row.get("ok") == 1:
            return {"status": "ok"}
        return {"status": "error"}
    except Exception as exc:
        return {"status": "error", "message": str(exc)}


@app.get("/items")
def list_items(
    q: str | None = Query(default=None, description="검색어(물품명 contains)"),
    limit: int = Query(default=20, ge=1, le=100),
) -> Dict[str, List[Dict[str, Any]]]:
    sql = """
        SELECT
            ai.pbac_no,
            ai.pbac_srno,
            ai.cmdt_ln_no,
            ai.cmdt_nm,
            ai.pbac_prng_prc,
            a.pbac_strt_dttm,
            a.pbac_end_dttm
        FROM auction_item ai
        JOIN auction a ON a.pbac_no = ai.pbac_no
    """
    params: List[Any] = []

    if q:
        sql += " WHERE ai.cmdt_nm LIKE %s"
        params.append(f"%{q}%")

    sql += " ORDER BY a.pbac_end_dttm DESC LIMIT %s"
    params.append(limit)

    with closing(pymysql.connect(**get_db_config())) as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            items = cur.fetchall()

    return {"items": items}


@app.get("/items/{pbac_no}/{pbac_srno}/{cmdt_ln_no}/images")
def item_images(pbac_no: str, pbac_srno: str, cmdt_ln_no: str) -> Dict[str, List[Dict[str, Any]]]:
    sql = """
        SELECT
            image_seq,
            image_url,
            source_type,
            updated_at
        FROM auction_item_image
        WHERE pbac_no=%s AND pbac_srno=%s AND cmdt_ln_no=%s
        ORDER BY image_seq ASC
    """

    with closing(pymysql.connect(**get_db_config())) as conn:
        with conn.cursor() as cur:
            cur.execute(sql, (pbac_no, pbac_srno, cmdt_ln_no))
            images = cur.fetchall()

    return {"images": images}
