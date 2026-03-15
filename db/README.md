# Database Schema & Execution Guide
> 본 문서는 DB 스키마 설계 및 실행 순서를 설명한다.  
> 자동 분류/검색 토큰 생성 로직의 상세 구현은 `classification/README.md`에서 다룬다.

---

## 1. 개요
본 데이터베이스는 관세청 공매 데이터의 실제 구조를 분석한 결과를 바탕으로 설계되었다.

공매 데이터는 단순히 **“공매번호 = 물품 1개”** 구조가 아니며,
동일 공매번호/일련번호 내에서도 **여러 물품 라인(cmdtLnNo)** 이 존재할 수 있다.

이를 반영하여 본 스키마는 아래 3개 도메인으로 분리 설계되었다.

- **공매 도메인 (`auction`, `auction_item`, `auction_item_image`)**
  - 공매 상위 메타(기간/세관/보관처/상태)와 라인 단위 물품(물품명/수량/중량/가격), 이미지 메타를 분리 저장
- **분류/검색 도메인 (`item_classification`, `item_search_token`)**
  - ETL 이후 물품명 기반 자동 분류 결과와 검색용 토큰(RAW/SYN/CATEGORY)을 저장
- **사용자 도메인 (`app_user` 계열 테이블)**
  - 회원, 소셜 연동, 관심대상, 알림 규칙/이력 등 사용자 기능 데이터를 저장

### 1-1. 데이터 흐름 한눈에 보기

1. `schema_create.sql`(+선택 `schema_patch_v2.sql`)로 기본 스키마를 준비
2. `schema_app_user_v1.sql`로 사용자 도메인 스키마를 추가
3. seed SQL(category/synonym)로 분류 기준 데이터를 적재
4. ETL(`etl/load_unipass_to_mysql.py`)로 공매/물품/이미지 메타를 적재
5. 분류(`classification/build_classification.py`)로 검색/분류 결과 생성

> 즉, 이 저장소의 DB는 **수집(ETL) → 정규화 저장 → 분류/검색 확장 → 사용자 알림 활용** 흐름을 전제로 설계되어 있다.

---

## 2. 실행 순서 (필수)

### Step 0. (중요) MySQL에서 DB 선택
MySQL Workbench에서 `customs_auction` 스키마를 생성/선택한 뒤 실행한다.
- `Error Code: 1046. No database selected` 발생 시, 좌측 SCHEMAS에서 DB를 더블클릭하여 기본 DB로 선택
- **처음 사용하는 경우 팁**: SQL 파일은 "열어서 실행" 또는 "내용 전체 복사 → Workbench 쿼리 탭에 붙여넣기 후 실행" 둘 다 가능하다.
- Workbench 상단의 **번개 아이콘(Execute)** 을 누르거나 `Ctrl+Shift+Enter`로 현재 탭의 SQL을 실행한다.

---

### Step 1. DB 스키마 생성
MySQL Workbench에서 아래 SQL 파일을 **하나씩 열어 전체 실행**한다.
(
`File > Open SQL Script`로 파일을 열거나,
SQL 파일 내용을 통째로 복사해서 Workbench 쿼리 탭에 붙여넣어 실행해도 된다.
)

1) `schema_create.sql`  
- 기존 테이블을 모두 삭제(DROP)한 뒤, 전체 스키마를 한 번에 생성한다.

1-1) `schema_patch_v2.sql`  
- 재설계 가이드 기준 확장 DDL(ingestion/run/raw payload/change event/queue/collector_source)을 반영한다.
- 기존 데이터가 있는 환경에서는 `schema_create.sql` 대신 `schema_patch_v2.sql`만 적용해도 된다.

1-2) `schema_app_user_v1.sql`  
- `app_user` 도메인(회원/소셜연동/관심대상/알림룰/알림이력) 스키마를 **별도 DB(`app_user`)** 로 생성한다.

1-2-alt) `schema_app_user_unified_v1.sql`  
- 사용자 도메인을 **현재 선택된 단일 DB(예: `customs_auction`)** 에 통합 생성한다.
- D-1 데모처럼 운영 단순화가 필요할 때 사용한다.

---

### Step 2. 카테고리 Seed 입력
아래 파일을 **순서대로 실행**한다. (각 파일은 "전체 선택 후 실행" 권장)

2) `seed_category.sql` (카테고리 기본안)  
3) `seed_category_extend.sql` (프로젝트 진행 중 추가된 카테고리 확장안)

> 분류 룰에서 사용하는 `category_path`는 seed_category(+extend) 기준으로 관리된다.

---

### Step 3. 동의어/번역 사전 Seed 입력
아래 파일을 **순서대로 실행**한다. (순서가 바뀌면 일부 분류 결과가 기대와 달라질 수 있다)

4) `seed_synonym.sql` (동의어/번역 사전 기본안)  
5) `seed_synonym_extend.sql` (프로젝트 진행 중 확장된 사전)

> 영어 물품명 기반 검색을 “한글/동의어”로 확장하기 위해 synonym_dictionary를 사용한다.

---

### Step 4. ETL 실행 (JSON → MySQL 적재)
ETL은 `auction`, `auction_item`을 채운다.

- 실행 파일: `etl/load_unipass_to_mysql.py`
- 기본 입력 JSON(자동 탐색):
  - `unipass_all_2b.json` (BUSINESS)
  - `unipass_all_2c.json` (PERSONAL)
- 이미지 입력(기본): `downloaded_images/<pbac_no>/...` 폴더를 자동 탐색해 `auction_item_image`에 적재
  - 레거시 단일 폴더 구조(`downloaded_images` 바로 아래 이미지 파일)도 지원
- 커스텀 입력(선택): `UNIPASS_JSON_FILES` 환경변수 사용
  - 형식: `path[:collector_source[:source_name]]`를 콤마로 연결
  - `collector_source`는 `BUSINESS`, `PERSONAL`, `IMAGE` 중 하나

```bash
python etl/load_unipass_to_mysql.py

# 예시: 파일/소스 직접 지정
UNIPASS_JSON_FILES="unipass_all_2b.json:BUSINESS:unipass_list_business,unipass_all_2c.json:PERSONAL:unipass_list_personal" \
python etl/load_unipass_to_mysql.py

# 예시: 이미지 디렉터리 경로를 별도로 지정
UNIPASS_IMAGE_DIR="downloaded_images" python etl/load_unipass_to_mysql.py
```

---

### Step 5. 분류 + 검색 토큰 생성
분류/토큰은 한 번에 수행된다.

실행 파일: classification/build_classification.py
결과 테이블:
item_classification (분류 결과)
item_search_token (검색 토큰: RAW/SYN/CATEGORY)

```bash
python classification/build_classification.py
```

- 실행 전 확인: ETL(Step 4)이 먼저 완료되어 `auction_item`에 데이터가 있어야 한다.
- 실행 후에는 Step 6의 `feedback.sql`로 분류/검색 토큰 품질을 꼭 확인한다.

---

### Step 6. 결과 검증
아래 SQL 파일을 실행하여 분류/토큰 결과를 점검한다.
`feedback.sql`

- 확인 방법 예시:
  1) `feedback.sql` 파일 내용을 복사/붙여넣기 후 실행
  2) 결과 Grid에서 분류 누락/비정상 토큰 여부 확인
  3) 필요 시 seed/category/synonym 파일 보정 후 Step 3~6 재실행

---

## 2-1. 처음 실행하는 사람을 위한 최소 실행 체크리스트

1. `customs_auction` 스키마 생성 및 기본 DB 선택
2. `schema_create.sql` 실행 (기존 데이터 유지가 필요하면 `schema_patch_v2.sql` 우선 검토)
3. `schema_app_user_v1.sql` 실행
4. `seed_category.sql` → `seed_category_extend.sql` 순서 실행
5. `seed_synonym.sql` → `seed_synonym_extend.sql` 순서 실행
6. `python etl/load_unipass_to_mysql.py` 실행
7. `python classification/build_classification.py` 실행
8. `feedback.sql` 실행 후 결과 확인

> 핵심: SQL은 "파일 실행"과 "복사/붙여넣기 실행" 둘 다 같은 결과를 낸다. 익숙한 방법을 사용하면 된다.


# 3. “이렇게 설계한 이유” 정리 (나중에 보고서/README에 붙이기 좋은 버전)

## 3-1. 왜 `auction` / `auction_item`으로 나눴나?

- 유니패스 데이터는 **공매번호(pbacNo)** 아래에 여러 개의 물품 라인이 달리는 구조일 수 있음
- 공매 자체의 메타정보(기간, 세관, 보관처, 화물유형)는 상위 개념
- 물품명/중량/수량/가격은 하위(라인) 개념
    
    → 그래서 1:N 구조로 분리하면 **중복 제거 + 조회/통계/알림 로직이 깔끔**해짐
    

## 3-2. 왜 `auction_item` PK가 (pbacNo, pbacSrno, cmdtLnNo)인가?

- 실제 JSON을 확인해보니 **(pbacNo, pbacSrno)가 같아도 cmdtLnNo가 다르고 물품 정보도 달랐음**
- 따라서 `(pbacNo, pbacSrno)`만 PK로 잡으면 UPSERT 과정에서 **서로 다른 물품이 덮어 써져 데이터 손실**이 발생
- 라인까지 포함한 `(pbacNo, pbacSrno, cmdtLnNo)`가 **물품 1건을 안정적으로 식별**함

## 3-3. 왜 마스터 테이블(customs_office / bonded_warehouse / cargo_type / unit_code)을 분리했나?

- 세관명/창고명/유형명/단위코드는 반복됨
- 마스터로 분리하면:
    - 데이터 중복 감소
    - 값 표준화(오타/변형 방지)
    - 필터/통계에서 조인으로 정확하게 집계 가능
    - 추후 “세관별 알림”, “창고별 인기 물품” 같은 기능 확장이 쉬움

## 3-4. created_at / updated_at을 넣은 이유

- 공매 정보는 시간이 지나면서 바뀔 수 있음(상태/가격/전자입찰 여부 등)
- ETL 재실행 시 **언제 갱신되었는지 추적**해야
    - 변경 감지(알림)
    - 데이터 신뢰성 확보
    - 운영/디버깅이 쉬워짐

---

---

---

# 4) “어떤 정보가 어디로 가는지” 예시로 설명

샘플에서 핵심 값들만 뽑아보면:

### ✅ 기관/보관 정보 → 마스터 + auction에 FK

- `pbacCstmSgn = "021"` / `pbacCstmSgnNm = "수원세관"`
    - `customs_office(cstm_sgn="021", cstm_name="수원세관")`
    - `auction.cstm_sgn = "021"`
- `snarSgn = "02111013"` / `snarSgnNm = "지엘에스 보세창고"`
    - `bonded_warehouse(snar_sgn="02111013", snar_name="지엘에스 보세창고")`
    - `auction.snar_sgn = "02111013"`

### ✅ 유형 정보 → 마스터 + auction에 FK

- `pbacTrgtCargTpcd="1"` / `pbacTrgtCargTpNm="수입화물"`
    - `cargo_type(cargo_tpcd="1", cargo_name="수입화물")`
    - `auction.cargo_tpcd = "1"`

### ✅ 공매 상위 정보(기간/전자입찰 등) → auction

- `pbacNo="02125029000781"`
- `pbacStrtDttm="20260109100000"` / `pbacEndDttm="20260109130000"`
- `bidRstcYn="N"`, `elctBidEon="N"`

👉 전부 `auction`으로

### ✅ 물품(라인) 정보 → auction_item

- `pbacSrno="900078"` (+ `cmdtLnNo="002"`)
- `cmdtNm="LEVEL GAUGES"`
- `cmdtQty=1`, `cmdtQtyUtCd="GT"`
- `cmdtWght=10`, `cmdtWghtUtCd="KG"`
- `pbacPrngPrc=18935950`
- `atntCmdt="N"`

👉 전부 `auction_item(pbac_no, pbac_srno, cmdt_ln_no)`로

### ✅ 단위코드 → unit_code

- `KG`는 WEIGHT
- `GT`는 QTY(정확한 단위명은 나중에 채워도 됨)




## 5. 물품 이미지 메타 테이블
- `auction_item_image`는 `(pbac_no, pbac_srno, cmdt_ln_no, image_seq)`를 키로 물품별 이미지 경로/URL을 저장한다.
- ETL(`etl/load_unipass_to_mysql.py`)은 두 경로를 지원한다: (1) JSON의 `image_urls`, (2) `downloaded_images/<pbac_no>/0_{cmdt_ln_no(앞0제거)}_{idx}.gif` 파일 구조.
- 폴더 구조가 `downloaded_images/<pbac_no>/...`이면 공매번호별 자동 매핑된다.
- 레거시 단일 폴더(`downloaded_images` 바로 아래 GIF)인 경우에만 `UNIPASS_IMAGE_PBAC_NO`가 필요하다.
