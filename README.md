# Customs Access Improvement Service
세관 공매 접근성 향상 서비스

기존 유니패스 공매 서비스의 탐색 불편(영문 물품명 중심, 제한적인 분류/검색)을 개선하기 위해,
공매 데이터를 수집·정규화하고 자동 분류/검색 토큰을 생성하는 프로젝트입니다.

---

## 프로젝트 개요
핵심 문제:
- 물품명이 영문/약어 위주라 검색 장벽이 큼
- 대분류 중심 UI로 원하는 물품을 찾기 어려움

핵심 해결 방식:
- 유니패스 공매 데이터 수집(JSON)
- MySQL 정규화 적재(`auction`/`auction_item`/`auction_item_image`)
- Rule 기반 자동 분류(`item_classification`)
- 한글/동의어 기반 검색 토큰 생성(`item_search_token`)

---

## 주요 목표
- 공매 물품 자동 카테고리 분류(대/중/소/세)
- 영문 물품명 기반 한글/동의어 검색 지원
- 공매 탐색 효율 및 사용자 접근성 향상
- 관심 물품/조건 기반 알림 기능 확장(사용자 도메인)

---

## 시스템 흐름
1. **Crawler**: 유니패스에서 공매 데이터를 수집해 JSON 저장
2. **DB Schema/Seed**: 스키마 생성 및 분류 기준(seed) 로딩
3. **ETL**: JSON/이미지 메타를 MySQL에 UPSERT 적재
4. **Classification**: 자동 분류 + 검색 토큰 생성
5. **Backend/API**: 조회/검색/필터/알림 기능 제공
6. **Frontend**: 사용자 탐색 UI 제공

---

## 디렉터리 구조
```text
CUSTOMS-ACCESS-IMPROVEMENT-SERVICE/
├─ project/AWSLambda/                 # 유니패스 데이터 수집 스크립트
├─ db/                                # DB 스키마/시드/검증 SQL + DB 가이드
├─ etl/                               # JSON/이미지 -> MySQL 적재 스크립트 + ETL 가이드
├─ classification/                    # 자동 분류/토큰 생성 스크립트 + 룰 가이드
├─ backend/                           # FastAPI 기반 API 서버
├─ cais_front/                        # Flutter 프론트엔드
├─ docs/                              # 설계/계획 문서
└─ README.md
```

---

## 빠른 시작 (처음 실행)

### 0) (선택) 공매 데이터 수집
기존 `unipass_all_2b.json`, `unipass_all_2c.json`이 있으면 생략 가능합니다.

```bash
python project/AWSLambda/unipass_list.py
```

이미지 수집(선택):

```bash
python project/AWSLambda/UNIPASS_Image.py
```

---

### 1) DB 스키마/시드 적용
아래 파일을 MySQL Workbench에서 순서대로 실행합니다.

1. `db/schema_create.sql`
2. `db/schema_patch_v2.sql` (기존 운영 DB 보강 시)
3. `db/schema_app_user_v1.sql`
4. `db/seed_category.sql`
5. `db/seed_category_extend.sql`
6. `db/seed_synonym.sql`
7. `db/seed_synonym_extend.sql`

> `Error Code: 1046. No database selected` 발생 시 `customs_auction` 스키마를 먼저 선택하세요.

---

### 2) ETL 실행 (JSON/이미지 -> MySQL)

```bash
python etl/load_unipass_to_mysql.py
```

- 기본 탐색: `unipass_all_2b.json`, `unipass_all_2c.json`, `unipass_image.json`(존재 시), `downloaded_images` 폴더(존재 시)
- 재실행 안전: UPSERT 기반

---

### 3) 자동 분류 + 검색 토큰 생성

```bash
python classification/build_classification.py
```

생성/갱신 테이블:
- `item_classification`
- `item_search_token`

---

### 4) 결과 검증

MySQL Workbench에서:
- `db/feedback.sql`

---

## 문서 바로가기
- DB 실행/설계 가이드: [`db/README.md`](db/README.md)
- ETL 실행 가이드: [`etl/README.md`](etl/README.md)
- 분류 룰/사전 확장 가이드: [`classification/README.md`](classification/README.md)
- 백엔드 실행 가이드: [`backend/README.md`](backend/README.md)
- 데모 구현 계획: [`docs/DEMO_IMPLEMENTATION_PLAN.md`](docs/DEMO_IMPLEMENTATION_PLAN.md)

---

## UI 기획(Figma)
https://www.figma.com/make/CxI03B2B15V6nULnvc7FGT/Customs-Auction-Service-App?p=f&t=7kcQGVfZrxPRRMOW-0
