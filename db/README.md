# Database Schema & Execution Guide
> 본 문서는 DB 스키마 설계 및 실행 순서를 설명한다.  
> 자동 분류/검색 토큰 생성 로직의 상세 구현은 `classification/README.md`에서 다룬다.

---

## 1. 개요
본 데이터베이스는 관세청 공매 데이터의 실제 구조를 분석한 결과를 바탕으로 설계되었다.

공매 데이터는 단순히 **“공매번호 = 물품 1개”** 구조가 아니며,
동일 공매번호/일련번호 내에서도 **여러 물품 라인(cmdtLnNo)** 이 존재할 수 있다.

이를 반영하여 본 스키마는 아래와 같이 분리 설계되었다.

- **auction (상위 / 공매 단위)**
- **auction_item (하위 / 라인 단위 물품)**

---

## 2. 실행 순서 (필수)

### Step 0. (중요) MySQL에서 DB 선택
MySQL Workbench에서 `customs_auction` 스키마를 생성/선택한 뒤 실행한다.
- `Error Code: 1046. No database selected` 발생 시, 좌측 SCHEMAS에서 DB를 더블클릭하여 기본 DB로 선택

---

### Step 1. DB 스키마 생성
MySQL Workbench에서 아래 SQL 파일 실행:

1) `schema_create.sql`  
- 기존 테이블을 모두 삭제(DROP)한 뒤, 전체 스키마를 한 번에 생성한다.

---

### Step 2. 카테고리 Seed 입력
아래 파일을 **순서대로 실행**한다.

2) `seed_category.sql` (카테고리 기본안)  
3) `seed_category_extend.sql` (프로젝트 진행 중 추가된 카테고리 확장안)

> 분류 룰에서 사용하는 `category_path`는 seed_category(+extend) 기준으로 관리된다.

---

### Step 3. 동의어/번역 사전 Seed 입력
아래 파일을 **순서대로 실행**한다.

4) `seed_synonym.sql` (동의어/번역 사전 기본안)  
5) `seed_synonym_extend.sql` (프로젝트 진행 중 확장된 사전)

> 영어 물품명 기반 검색을 “한글/동의어”로 확장하기 위해 synonym_dictionary를 사용한다.

---

### Step 4. ETL 실행 (JSON → MySQL 적재)
ETL은 `auction`, `auction_item`을 채운다.

- 실행 파일: `etl/load_unipass_to_mysql.py`
- 입력 JSON: 레포 루트의 `unipass_all.json`

```bash
python etl/load_unipass_to_mysql.py

---

### Step 5. 분류 + 검색 토큰 생성
분류/토큰은 한 번에 수행된다.

실행 파일: classification/build_classification.py
결과 테이블:
item_classification (분류 결과)
item_search_token (검색 토큰: RAW/SYN/CATEGORY)

---

### Step 6. 결과 검증
아래 SQL 파일을 실행하여 분류/토큰 결과를 점검한다.
feedback.sql


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
- `auction_item_image`는 `(pbac_no, pbac_srno, cmdt_ln_no, image_seq)`를 키로 물품별 이미지 URL을 저장한다.
- ETL(`etl/load_unipass_to_mysql.py`)에서 `image_urls` 필드를 읽어 UPSERT한다.
- 목록 응답에서 이미지가 없을 수 있으므로, 추후 상세 수집 로직으로 보강 가능하다.

## 6. LLM 분류 운영 테이블

`schema_create.sql`에는 아래 운영용 테이블이 추가되었다.

- `classification_job_queue`
  - LLM 재분류 대상 관리(PENDING/RUNNING/DONE/FAILED)
  - 재시도(`retries`, `max_retries`) 및 오류(`last_error`) 추적
- `llm_classification_cache`
  - 정규화된 물품명 해시를 키로 OpenAI 분류 결과 캐시
  - 동일 물품명 반복 호출 비용 절감

권장 실행 흐름:
1. `build_classification.py`로 rule 1차 분류
2. `build_classification_openai.py --enqueue-low-confidence`로 저신뢰 항목 큐잉 + LLM 보강
