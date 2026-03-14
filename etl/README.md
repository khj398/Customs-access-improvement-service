# ETL Guide: `load_unipass_to_mysql.py`

`load_unipass_to_mysql.py`는 유니패스 공매 원천 데이터를 MySQL(`customs_auction`)에 적재하는 스크립트입니다.

- 공매/물품 데이터 적재: `auction`, `auction_item`
- 이미지 메타 적재: `auction_item_image`
- 이력/운영 테이블 적재: `ingestion_run`, `raw_auction_payload`, `auction_item_change_event`

---

## 1) 실행 전 준비

1. DB 스키마가 먼저 생성되어 있어야 합니다. (`db/schema_create.sql`, 필요 시 `db/schema_patch_v2.sql`)
2. Python 의존성을 준비합니다.

```bash
pip install pymysql
```

3. 기본 DB 접속 환경변수(선택)를 확인합니다.

- `MYSQL_HOST` (기본: `127.0.0.1`)
- `MYSQL_PORT` (기본: `3306`)
- `MYSQL_USER` (기본: `root`)
- `MYSQL_PASSWORD` (기본: `password`)
- `MYSQL_DATABASE` (기본: `customs_auction`)

---

## 2) 기본 실행

프로젝트 루트에서 실행합니다.

```bash
python etl/load_unipass_to_mysql.py
```

기본적으로 아래 입력을 자동 탐색합니다.

- `unipass_all_2b.json` (BUSINESS)
- `unipass_all_2c.json` (PERSONAL)
- `unipass_image.json` (IMAGE, 파일이 있을 때만)
- `downloaded_images` 디렉터리(있을 때만)

> `downloaded_images/<pbac_no>/...` 구조가 있으면 이미지 파일명을 기준으로 `auction_item_image`를 매핑합니다.

---

## 3) 커스텀 입력 지정

### 3-1. JSON 입력을 명시적으로 지정

`UNIPASS_JSON_FILES` 형식:
`path[:collector_source[:source_name]]` 를 콤마(`,`)로 연결

- `collector_source`: `BUSINESS` | `PERSONAL` | `IMAGE`

```bash
UNIPASS_JSON_FILES="unipass_all_2b.json:BUSINESS:unipass_list_business,unipass_all_2c.json:PERSONAL:unipass_list_personal" \
python etl/load_unipass_to_mysql.py
```

### 3-2. 이미지 디렉터리 경로 지정

```bash
UNIPASS_IMAGE_DIR="downloaded_images" python etl/load_unipass_to_mysql.py
```

### 3-3. 레거시 단일 폴더 이미지 보정

이미지가 `downloaded_images` 바로 아래(하위 `pbac_no` 폴더 없음) 있고,
파일명 접두 공매번호가 `0` 등으로 매칭이 어려운 경우:

```bash
UNIPASS_IMAGE_PBAC_NO="0202601900003" python etl/load_unipass_to_mysql.py
```

---

## 4) 이미지 파일명 규칙

이미지 파일은 아래 패턴으로 인식합니다.

- `^<pbac_no>_<cmdt_ln_no>_<index>.(gif|jpg|jpeg|png|webp|bmp)$`
- 예: `0202601900003_1_0.gif`

`index`는 0부터 시작해도 DB에는 `image_seq = index + 1`로 저장됩니다.

---

## 5) 스크립트 동작 요약

- JSON 1레코드마다 `pbacNo`, `pbacSrno`, `cmdtLnNo`가 없으면 skip/error 처리
- 마스터 테이블(`customs_office`, `bonded_warehouse`, `cargo_type`, `unit_code`) UPSERT
- `auction`, `auction_item` UPSERT
- 물품 상태/가격 변화 감지 시 `auction_item_change_event` 기록
- 원본 payload는 `raw_auction_payload`에 해시와 함께 저장
- 실행 이력은 `ingestion_run`에 `SUCCESS/PARTIAL/FAILED`로 기록

> 동일 데이터 재실행은 UPSERT 기반으로 안전하게 처리됩니다.

---

## 6) 실행 결과 확인

정상 종료 시 콘솔에 아래와 유사한 로그가 출력됩니다.

- `✅ ETL complete | auctions processed: <n>, items processed: <n>, skipped/errors: <n>`

권장 후속 작업:
1. `db/feedback.sql`로 품질 점검
2. `python classification/build_classification.py` 실행

