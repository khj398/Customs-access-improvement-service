# Customs-access-improvement-service
세관 공매 접근성 향상 서비스

# UI FIGMA
https://www.figma.com/make/CxI03B2B15V6nULnvc7FGT/Customs-Auction-Service-App?p=f&t=7kcQGVfZrxPRRMOW-0

---

## 📌 프로젝트 개요
본 프로젝트는 관세청 유니패스 공매 데이터를 기반으로,
기존 공매 사이트의 **모호한 분류 체계와 낮은 접근성 문제**를 개선하기 위한 서비스이다.

특히 공매 물품명이 대부분 영문으로 제공되고,
대분류 중심의 제한적인 분류만 제공되는 기존 시스템의 한계를 극복하기 위해
**Rule 기반 자동 분류 + 다국어/동의어 검색(한글 검색 포함)** 을 핵심 기능으로 설계한다.

---

## 🎯 프로젝트 목표
- 공매 물품 **자동 카테고리 분류** (대/중/소/세)
- 영문 물품명 기반 **한글/동의어 검색 지원**
- 공매 물품 탐색 효율 향상
- (추후) 관심 물품 알림 기능 확장

---

## 🏗 시스템 전체 흐름
1. **Crawler**
   - 유니패스 공매 사이트에서 공매 물품 데이터 수집
   - JSON 형태로 저장

2. **ETL**
   - 수집된 JSON 데이터를 정규화하여 MySQL 데이터베이스에 적재
   - 공매 상위(auction) / 물품 라인(auction_item) 구조 반영
   - UPSERT 기반(재실행 안전)

3. **Classification**
   - 물품명 기반 자동 분류(rule 기반) 수행
   - 분류 결과/신뢰도/근거 저장 (item_classification)

4. **Search Tokenization**
   - 검색 토큰 생성 (RAW/SYN/CATEGORY)
   - 영문 + 한글/동의어 검색 지원 (item_search_token)

5. **Frontend**
   - Flutter 프론트엔드

6. **Backend (예정)**
   - API 제공
   - 검색/필터/알림 기능 연동

---

## 📁 디렉토리 구조
```text
CUSTOMS-ACCESS-IMPROVEMENT-SERVICE/
├─ project/AWSLambda/
│  └─ unipass_list.py                  # 유니패스 공매 데이터 수집(JSON 생성)
├─ etl/
│  └─ load_unipass_to_mysql.py         # JSON → MySQL 적재(UPSERT)
├─ classification/
│  ├─ build_classification.py          # 자동 분류 + 검색 토큰 생성(UPSERT)
│  └─ README.md                        # 자동 분류/룰/사전 확장 가이드
├─ db/
│  ├─ schema_create.sql                # DB 스키마 생성(기존 테이블 DROP 포함)
│  ├─ seed_category.sql                # 카테고리 기본 seed
│  ├─ seed_category_extend.sql         # 카테고리 확장 seed
│  ├─ seed_synonym.sql                 # 동의어/번역 사전 기본 seed
│  ├─ seed_synonym_extend.sql          # 동의어/번역 사전 확장 seed
│  ├─ queries.sql                      # 참고용 쿼리 모음
│  ├─ feedback.sql                     # 실행 결과 검증 쿼리
│  └─ README.md                        # DB 실행 순서/설계 근거
├─ cais_frontend/                      # Flutter 프론트엔드
├─ backend/                            # API 서버 (예정)
└─ README.md

--- ===================================================================================================



## 🔍 이미지 수집 현황
- 수집 스크립트(`project/AWSLambda/unipass_list.py`)가 각 품목에 대해 `image_urls` / `image_count` 필드를 함께 저장하도록 확장되었다.
- 목록 응답에 이미지 힌트가 없으면 `image_urls`는 빈 배열이며, 향후 상세 API/상세 페이지 크롤링으로 보강 가능하다.
- ETL(`etl/load_unipass_to_mysql.py`)은 `image_urls`뿐 아니라 `downloaded_images/<pbac_no>/...`의 `.gif` 파일도 `auction_item_image`에 UPSERT할 수 있다 (레거시 단일 폴더일 때만 `UNIPASS_IMAGE_PBAC_NO` 필요).

---

## 🧩 Backend MVP (DB 구축과 병행)
- DB 구축 단계부터 API 서버를 같이 띄울 수 있도록 `backend/`에 FastAPI MVP를 추가했다.
- 자세한 실행 방법은 `backend/README.md` 참고.

---

## 🗺 데모 구현 계획 문서
- DB 구축 + 데이터 수집 + OpenAI 자동 분류 + 백엔드 API 단계별 계획: `docs/DEMO_IMPLEMENTATION_PLAN.md`

---

## End-to-End 실행 순서 (처음 실행 기준)

### Step 0) (선택) 유니패스 데이터 수집 → JSON 생성
이미 목록 JSON(`unipass_all_2b.json`/`unipass_all_2c.json`)이 있으면 생략 가능하다.
python project/AWSLambda/unipass_list.py

이미지 상세 수집은 미리 수집한 목록 JSON(`unipass_all_2b.json`, `unipass_all_2c.json`)의 공매번호를 자동 순회한다.
python project/AWSLambda/UNIPASS_Image.py

파일명은 `downloaded_images/<pbacNo digits>/0_{cmdtLnNo(앞0제거)}_{index}.gif` 규칙으로 저장된다.
목록 JSON의 공매번호가 하이픈 없이 저장되어 있어도(예: `02026019000031`) 수집 시 자동으로 하이픈 포맷으로 보정해 조회한다.
목록 JSON이 비어있는 경우는 오류로 처리하지 않고, 수집 대상이 없다는 메시지만 출력 후 종료한다.

---

### Step 1) DB 스키마 생성 + Seed 입력
MySQL Workbench에서 아래 SQL 파일을 순서대로 실행한다.
db/schema_create.sql
db/seed_category.sql
db/seed_category_extend.sql
db/seed_synonym.sql
db/seed_synonym_extend.sql

⚠️ Workbench에서 Error Code: 1046. No database selected가 뜨면
좌측 SCHEMAS에서 customs_auction을 더블클릭하여 기본 DB로 선택한 후 실행한다.

---

### Step 2) ETL 실행 (JSON → MySQL 적재)
ETL은 auction, auction_item 테이블을 채운다.
python etl/load_unipass_to_mysql.py
(레거시 단일 폴더 구조를 쓸 때만 `UNIPASS_IMAGE_PBAC_NO` 필요)
ETL은 UPSERT 기반이므로 재실행해도 안전하다.

---

### Step 3) 자동 분류 + 검색 토큰 생성
분류 및 검색 토큰 생성은 아래 스크립트 하나로 수행된다.
python classification/build_classification.py

생성/갱신되는 테이블:
item_classification : 물품 라인 단위 분류 결과
item_search_token : 검색 토큰 (RAW/SYN/CATEGORY)

분류/토큰 생성도 UPSERT 기반이므로 재실행해도 안전하다.

---

### Step 4) 결과 검증
MySQL Workbench에서 아래 파일을 실행하여 분류/토큰 결과를 점검한다.
db/feedback.sql

---

📚 문서
DB 설계 및 SQL 실행 가이드: db/README.md
자동 분류(룰/사전 확장) 가이드: classification/README.md

🔧 운영/개발 팁 (자주 하는 작업)
Seed 업데이트만 반영하고 싶을 때
카테고리 경로 추가/수정: db/seed_category_extend.sql 실행
동의어/번역 추가: db/seed_synonym_extend.sql 실행
이후 python classification/build_classification.py 재실행

분류 룰을 확장하고 싶을 때
classification/build_classification.py의 build_rules()에 룰 추가

룰에서 사용하는 category_path가 DB에 존재하는지 확인
→ 없으면 db/seed_category_extend.sql에 카테고리 경로를 추가

재실행: python classification/build_classification.py
