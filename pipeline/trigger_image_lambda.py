"""
이미지 수집 Lambda 트리거 + S3 URL 탐색 → auction_item_image 저장
=====================================================================
사용법:
  python pipeline/trigger_image_lambda.py

필수 환경변수:
  LAMBDA_IMAGE_URL  - AWS Lambda Function URL (GitHub Secret)

선택 환경변수:
  LAMBDA_WAIT_SECONDS - Lambda 완료 대기 시간 (기본: 300초)
  DB_HOST / DB_USER / DB_PASSWORD / DB_NAME
"""

import os
import sys
import time

import pymysql
import pymysql.cursors
import requests

S3_BASE = "https://cais-playwright-images.s3.ap-northeast-2.amazonaws.com"
MAX_IMAGES_PER_ITEM = 10
WAIT_SECONDS = int(os.getenv("LAMBDA_WAIT_SECONDS", "300"))

LAMBDA_URL = os.environ.get("LAMBDA_IMAGE_URL")
if not LAMBDA_URL:
    print("❌ LAMBDA_IMAGE_URL 환경변수가 설정되지 않았습니다.")
    sys.exit(1)


def build_db_conn():
    return pymysql.connect(
        host=os.getenv("DB_HOST", "127.0.0.1"),
        port=int(os.getenv("DB_PORT", "3306")),
        user=os.getenv("DB_USER", "root"),
        password=os.getenv("DB_PASSWORD", ""),
        database=os.getenv("DB_NAME", "customs_auction"),
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=False,
    )


def trigger_lambda(pbac_nos: list[str]) -> None:
    print(f"🚀 Lambda 요청 전송... (대상: {len(pbac_nos)}개)")
    try:
        resp = requests.post(
            LAMBDA_URL,
            json={"targets": pbac_nos},
            headers={"Content-Type": "application/json"},
            timeout=30,
        )
        print(f"   응답: {resp.status_code} {resp.text}")
    except requests.exceptions.ReadTimeout:
        # Lambda가 처리 중 응답 전에 타임아웃 — AWS에서 계속 실행 중
        print("   ⚠️  응답 타임아웃 (Lambda는 AWS에서 계속 실행 중)")


def fetch_items(conn) -> list[dict]:
    with conn.cursor() as cur:
        cur.execute("SELECT DISTINCT pbac_no, pbac_srno, cmdt_ln_no FROM auction_item")
        return cur.fetchall()


def to_s3_key(pbac_no: str) -> str:
    """DB 공매번호(14자, 대시 없음) → S3 경로 키(대시 포함) 변환
    예: '03026029000022' → '030-26-02-900002-2'
    """
    return f"{pbac_no[0:3]}-{pbac_no[3:5]}-{pbac_no[5:7]}-{pbac_no[7:13]}-{pbac_no[13]}"


def probe_images(pbac_no: str, cmdt_ln_no: str) -> list[str]:
    """S3에 실제로 존재하는 이미지 URL 목록 반환 (200이면 존재, 403이면 없음)"""
    s3_key = to_s3_key(pbac_no)
    line_no = str(int(cmdt_ln_no))  # '001' → '1'
    urls = []
    for i in range(MAX_IMAGES_PER_ITEM):
        url = f"{S3_BASE}/{s3_key}/{s3_key}_{line_no}_{i}.gif"
        try:
            res = requests.head(url, timeout=5)
            if res.status_code == 200:
                urls.append(url)
            else:
                break
        except requests.RequestException:
            break
    return urls


SQL_UPSERT = """
INSERT INTO auction_item_image
  (pbac_no, pbac_srno, cmdt_ln_no, image_seq, image_url, source_type)
VALUES (%s, %s, %s, %s, %s, 'S3_LAMBDA')
ON DUPLICATE KEY UPDATE
  image_url  = VALUES(image_url),
  source_type = VALUES(source_type),
  updated_at = CURRENT_TIMESTAMP
"""


def store_images(conn, items: list[dict]) -> int:
    upsert_cnt = 0
    checked = set()

    with conn.cursor() as cur:
        for item in items:
            key = (item["pbac_no"], item["cmdt_ln_no"])
            if key in checked:
                continue
            checked.add(key)

            urls = probe_images(item["pbac_no"], item["cmdt_ln_no"])
            for seq, url in enumerate(urls, start=1):
                cur.execute(SQL_UPSERT, (
                    item["pbac_no"],
                    item["pbac_srno"],
                    item["cmdt_ln_no"],
                    seq,
                    url,
                ))
                upsert_cnt += 1

    conn.commit()
    return upsert_cnt


def main():
    print(f"\n{'='*60}")
    print("▶  이미지 수집 Lambda 트리거 + S3 URL 저장")
    print(f"{'='*60}\n")

    conn = build_db_conn()
    items = fetch_items(conn)

    if not items:
        print("⚠️  auction_item 테이블에 데이터가 없습니다. ETL을 먼저 실행하세요.")
        conn.close()
        return

    pbac_nos = list({item["pbac_no"] for item in items})
    trigger_lambda(pbac_nos)

    print(f"\n⏳ Lambda 처리 대기 중... ({WAIT_SECONDS}초)")
    time.sleep(WAIT_SECONDS)

    print("\n🔍 S3 이미지 탐색 및 DB 저장 중...")
    upsert_cnt = store_images(conn, items)
    conn.close()

    print(f"\n✅ 완료 — {upsert_cnt}개 이미지 URL 저장됨")


if __name__ == "__main__":
    main()
