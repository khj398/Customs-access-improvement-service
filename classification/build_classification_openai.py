import argparse
import hashlib
import json
import os
import re
import time
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple
from urllib import error, request

import pymysql

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "127.0.0.1"),
    "port": int(os.getenv("DB_PORT", "3306")),
    "user": os.getenv("DB_USER", "root"),
    "password": os.getenv("DB_PASSWORD", ""),
    "database": os.getenv("DB_NAME", "customs_auction"),
    "charset": "utf8mb4",
    "cursorclass": pymysql.cursors.DictCursor,
    "autocommit": False,
}

DEFAULT_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
OPENAI_URL = os.getenv("OPENAI_API_URL", "https://api.openai.com/v1/responses")


@dataclass
class CategoryPath:
    path: List[str]
    category_id: int


def normalize_text(text: str) -> str:
    txt = (text or "").upper().strip()
    txt = re.sub(r"[^A-Z0-9]+", " ", txt)
    txt = re.sub(r"\s+", " ", txt).strip()
    return txt


def sha256_key(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def load_category_paths(cur) -> List[CategoryPath]:
    cur.execute("SELECT category_id, parent_id, name_ko FROM category WHERE is_active=1 ORDER BY level, category_id")
    rows = cur.fetchall()
    by_id: Dict[int, Dict] = {int(r["category_id"]): r for r in rows}

    def build_path(cid: int) -> List[str]:
        out = []
        current = by_id.get(cid)
        safety = 0
        while current and safety < 10:
            out.append(current["name_ko"])
            pid = current["parent_id"]
            current = by_id.get(int(pid)) if pid is not None else None
            safety += 1
        return list(reversed(out))

    paths = []
    for cid in by_id:
        p = build_path(cid)
        if len(p) >= 3:
            paths.append(CategoryPath(path=p, category_id=cid))
    return paths


def resolve_fallback(cur) -> int:
    cur.execute(
        """
        SELECT c3.category_id
        FROM category c1
        JOIN category c2 ON c2.parent_id=c1.category_id
        JOIN category c3 ON c3.parent_id=c2.category_id
        WHERE c1.name_ko='기타' AND c2.name_ko='미분류' AND c3.name_ko='기타'
        LIMIT 1
        """
    )
    row = cur.fetchone()
    if not row:
        raise RuntimeError("Fallback category path 기타>미분류>기타 not found")
    return int(row["category_id"])


def openai_classify(cmdt_nm: str, candidate_paths: List[str], model: str) -> Tuple[Optional[str], float, str]:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY is required")

    prompt = {
        "item_name": cmdt_nm,
        "candidate_paths": candidate_paths,
        "instructions": [
            "반드시 candidate_paths 중 1개를 category_path로 선택",
            "확신이 낮으면 confidence를 0.5 이하로 주기",
            "JSON만 응답",
        ],
        "output_schema": {
            "category_path": "문자열, candidate_paths 중 하나",
            "confidence": "0~1 실수",
            "rationale": "짧은 한국어 설명",
        },
    }

    payload = {
        "model": model,
        "input": [
            {
                "role": "system",
                "content": "You are a strict classifier. Output JSON only.",
            },
            {
                "role": "user",
                "content": json.dumps(prompt, ensure_ascii=False),
            },
        ],
        "text": {
            "format": {
                "type": "json_schema",
                "name": "classification",
                "schema": {
                    "type": "object",
                    "properties": {
                        "category_path": {"type": "string"},
                        "confidence": {"type": "number"},
                        "rationale": {"type": "string"},
                    },
                    "required": ["category_path", "confidence", "rationale"],
                    "additionalProperties": False,
                },
            }
        },
    }

    req = request.Request(
        OPENAI_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with request.urlopen(req, timeout=45) as resp:
            body = json.loads(resp.read().decode("utf-8"))
    except error.HTTPError as e:
        details = e.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"OpenAI HTTPError {e.code}: {details[:300]}")

    output = body.get("output", [])
    text = None
    for item in output:
        for c in item.get("content", []):
            if c.get("type") in ("output_text", "text"):
                text = c.get("text")
                break
        if text:
            break

    if not text:
        raise RuntimeError("No text output from OpenAI")

    parsed = json.loads(text)
    return parsed.get("category_path"), float(parsed.get("confidence", 0.0)), parsed.get("rationale", "")


def enqueue_low_confidence(cur, threshold: float) -> int:
    sql = """
    INSERT INTO classification_job_queue (pbac_no, pbac_srno, cmdt_ln_no, status, priority)
    SELECT ic.pbac_no, ic.pbac_srno, ic.cmdt_ln_no, 'PENDING', 100
      FROM item_classification ic
     WHERE ic.model_name='rule' AND (ic.confidence IS NULL OR ic.confidence < %s)
    ON DUPLICATE KEY UPDATE
      status=IF(status='DONE', status, 'PENDING'),
      priority=LEAST(priority, VALUES(priority))
    """
    cur.execute(sql, (threshold,))
    return cur.rowcount


def main():
    parser = argparse.ArgumentParser(description="LLM fallback classifier")
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--model-ver", default="openai-v1")
    parser.add_argument("--limit", type=int, default=30)
    parser.add_argument("--min-confidence", type=float, default=0.60)
    parser.add_argument("--enqueue-low-confidence", action="store_true")
    parser.add_argument("--sleep-ms", type=int, default=200)
    args = parser.parse_args()

    conn = pymysql.connect(**DB_CONFIG)
    processed = 0

    try:
        with conn.cursor() as cur:
            if args.enqueue_low_confidence:
                n = enqueue_low_confidence(cur, args.min_confidence)
                print(f"enqueued/updated rows: {n}")

            paths = load_category_paths(cur)
            path_to_id = {" > ".join(p.path): p.category_id for p in paths}
            candidates = sorted(path_to_id.keys())
            fallback_id = resolve_fallback(cur)

            cur.execute(
                """
                SELECT q.job_id, q.pbac_no, q.pbac_srno, q.cmdt_ln_no, i.cmdt_nm
                  FROM classification_job_queue q
                  JOIN auction_item i
                    ON i.pbac_no=q.pbac_no AND i.pbac_srno=q.pbac_srno AND i.cmdt_ln_no=q.cmdt_ln_no
                 WHERE q.status='PENDING' AND q.retries <= q.max_retries
                 ORDER BY q.priority ASC, q.created_at ASC
                 LIMIT %s
                """,
                (args.limit,),
            )
            jobs = cur.fetchall()

            for j in jobs:
                job_id = int(j["job_id"])
                pbac_no, pbac_srno, cmdt_ln_no = j["pbac_no"], j["pbac_srno"], j["cmdt_ln_no"]
                cmdt_nm = j["cmdt_nm"] or ""

                cur.execute("UPDATE classification_job_queue SET status='RUNNING', lock_owner=%s, locked_at=NOW() WHERE job_id=%s", ("openai-worker", job_id))

                norm = normalize_text(cmdt_nm)
                key = sha256_key(norm)
                cur.execute("SELECT category_id, confidence, rationale FROM llm_classification_cache WHERE cache_key=%s", (key,))
                cache = cur.fetchone()

                try:
                    if cache:
                        category_id = int(cache["category_id"])
                        conf = float(cache["confidence"] or 0.7)
                        rationale = f"[cache] {cache['rationale'] or ''}".strip()
                    else:
                        category_path, conf, rationale = openai_classify(cmdt_nm, candidates, args.model)
                        category_id = path_to_id.get(category_path or "", fallback_id)
                        cur.execute(
                            """
                            INSERT INTO llm_classification_cache
                            (cache_key, cmdt_nm_norm, category_id, category_path, confidence, rationale, model_name, model_ver)
                            VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
                            ON DUPLICATE KEY UPDATE
                              category_id=VALUES(category_id),
                              category_path=VALUES(category_path),
                              confidence=VALUES(confidence),
                              rationale=VALUES(rationale),
                              model_name=VALUES(model_name),
                              model_ver=VALUES(model_ver)
                            """,
                            (key, norm, category_id, category_path or "", conf, rationale, args.model, args.model_ver),
                        )

                    cur.execute(
                        """
                        INSERT INTO item_classification
                        (pbac_no, pbac_srno, cmdt_ln_no, category_id, model_name, model_ver, confidence, rationale)
                        VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
                        ON DUPLICATE KEY UPDATE
                          category_id=VALUES(category_id),
                          model_name=VALUES(model_name),
                          model_ver=VALUES(model_ver),
                          confidence=VALUES(confidence),
                          rationale=VALUES(rationale)
                        """,
                        (pbac_no, pbac_srno, cmdt_ln_no, category_id, args.model, args.model_ver, conf, rationale[:2000]),
                    )

                    cur.execute("UPDATE classification_job_queue SET status='DONE', processed_at=NOW(), last_error=NULL WHERE job_id=%s", (job_id,))
                    processed += 1
                except Exception as e:
                    cur.execute(
                        """
                        UPDATE classification_job_queue
                           SET retries=retries+1,
                               status=IF(retries+1 > max_retries, 'FAILED', 'PENDING'),
                               last_error=%s
                         WHERE job_id=%s
                        """,
                        (str(e)[:1000], job_id),
                    )

                if args.sleep_ms > 0:
                    time.sleep(args.sleep_ms / 1000.0)

        conn.commit()
        print(f"done. processed={processed}")
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
