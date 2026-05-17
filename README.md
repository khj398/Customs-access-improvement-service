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
4. **Classification**: 자동 분류 + 검색 토큰 생성 (Rule 기반 + OpenAI fallback + 한글 키워드 룰)
5. **Meilisearch 동기화**: MySQL 물품 데이터를 검색 인덱스로 동기화
6. **Backend/API**: 조회/검색/필터/알림 기능 제공
7. **Frontend**: 사용자 탐색 UI 제공 (Flutter Web/Mobile)

---

## 디렉터리 구조
```text
CUSTOMS-ACCESS-IMPROVEMENT-SERVICE/
├─ project/AWSLambda/          # 유니패스 데이터 수집 Lambda 스크립트
├─ db/                         # DB 스키마·시드·검증 SQL
├─ etl/                        # JSON/이미지 → MySQL 적재 스크립트
├─ classification/             # 자동 분류 엔진 + 규칙 파일 + 자동 규칙 생성기
├─ pipeline/                   # 파이프라인 오케스트레이터 + 스케줄러
├─ cais_back/                  # Node.js (Express) REST API 서버
├─ cais_front/                 # Flutter 모바일 앱
├─ backend/                    # (구) FastAPI 서버 (레거시)
├─ docs/                       # 설계/계획 문서
└─ README.md
```

각 디렉토리의 파일 상세 설명은 해당 폴더의 README를 참조하세요.

| 디렉토리 | 문서 |
|----------|------|
| `cais_back/` | [`cais_back/README.md`](cais_back/README.md) |
| `cais_front/` | [`cais_front/STRUCTURE.md`](cais_front/STRUCTURE.md) |
| `classification/` | [`classification/README.md`](classification/README.md) |
| `pipeline/` | [`pipeline/README.md`](pipeline/README.md) |
| `etl/` | [`etl/README.md`](etl/README.md) |
| `db/` | [`db/README.md`](db/README.md) |

---

## 빠른 시작 (처음 실행)

### 0) (선택) 공매 데이터 수집
기존 `unipass_all_2b.json`, `unipass_all_2c.json`이 있으면 생략 가능합니다.

```bash
python project/AWSLambda/UNIPASS_LIST_Business.py
python project/AWSLambda/UNIPASS_LIST_Personal.py
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

### 4) Meilisearch 실행 및 동기화

Docker가 설치되어 있어야 합니다.

```bash
# Meilisearch 컨테이너 실행
docker run -d --name meilisearch \
  -p 7700:7700 \
  -e MEILI_MASTER_KEY=cais-search-key \
  getmeili/meilisearch:latest

# MySQL 물품 데이터 동기화 (cais_back 디렉터리에서 실행)
cd cais_back
node scripts/sync_meili.js
```

> 물품 데이터가 변경(추가/수정)될 때마다 `sync_meili.js`를 재실행해야 검색 결과가 최신으로 유지됩니다.

---

### 5) Node.js 백엔드 실행

```bash
cd cais_back
npm install
node server.js   # 포트 3000
```

환경변수 설정 (`.env` 또는 셸):
```
DB_HOST=127.0.0.1
DB_USER=root
DB_PASSWORD=<비밀번호>
DB_NAME=customs_auction
JWT_SECRET=<임의 문자열>
MEILI_HOST=http://localhost:7700
MEILI_MASTER_KEY=cais-search-key
```

---

### 6) Flutter 앱 실행

```bash
cd cais_front
flutter pub get
flutter run   # Android 에뮬레이터: 백엔드를 10.0.2.2:3000으로 자동 연결
```

실기기 사용 시:
```bash
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:3000
```

---

### 7) (선택) 자동 분류 파이프라인

```bash
# 매일 자동 실행 (스케줄러)
python pipeline/scheduler.py --use-openai --auto-rules

# 1회만 즉시 실행
python pipeline/run_pipeline.py --use-openai --auto-rules
```

---

## 문서 바로가기
- DB 실행/설계 가이드: [`db/README.md`](db/README.md)
- ETL 실행 가이드: [`etl/README.md`](etl/README.md)
- 분류 룰/사전 확장 가이드: [`classification/README.md`](classification/README.md)
- 파이프라인/스케줄러 가이드: [`pipeline/README.md`](pipeline/README.md)
- Node.js 백엔드 가이드: [`cais_back/README.md`](cais_back/README.md)
- Flutter 앱 구조: [`cais_front/STRUCTURE.md`](cais_front/STRUCTURE.md)
- 데모 구현 계획: [`docs/DEMO_IMPLEMENTATION_PLAN.md`](docs/DEMO_IMPLEMENTATION_PLAN.md)

---

## UI 기획(Figma)
https://www.figma.com/make/CxI03B2B15V6nULnvc7FGT/Customs-Auction-Service-App?p=f&t=7kcQGVfZrxPRRMOW-0
