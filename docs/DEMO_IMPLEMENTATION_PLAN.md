# Demo 구현 실행 계획 v5 (D-1 확정안: OpenAI 보강 + 검색/묶음 + 사용자 설정 위치 기반 추천)

## 0) 이번 데모의 필수 성공 기준 (오늘)
1. 앱에서 물품이 안정적으로 보인다.
2. 검색이 잘 된다(한글/영문/동의어).
3. 묶음 물품(같은 공매/연관 물품)이 잘 보인다.
4. 사용자 기능 최소 시연이 된다.
   - 최근 검색어 저장/삭제/전체삭제
   - 내 목록(입찰/낙찰/유찰) 조회
   - **사용자가 설정한 위치 기준** 가까운 기관/물품 추천

> 정식 서버 배포는 제외. **로컬 DB + 로컬 API + 앱 연동**으로 데모 완성.

---

## 1) 핵심 결정사항 (요청 반영)
- 일정: 데모까지 1일
- 분류: **rule + OpenAI 보강 분류를 1차 데모에 반드시 포함**
- 데이터: 최신 공매 데이터가 적으므로 **최신 + 과거 샘플 혼합**
- UX 우선순위: **물품 노출 > 검색 정확도 > 묶음 노출 > 사용자 부가기능**
- 위치 추천 기준: **실시간 GPS가 아니라 user가 저장한 기본 위치(home/base)**

---

## 2) 데이터 구성 전략 (최신 + 과거 혼합)
### 2-1. 데이터 소스
- 최신: `project/AWSLambda/UNIPASS_LIST_Business.py`, `project/AWSLambda/UNIPASS_LIST_Personal.py`
- 과거: 기존 JSON 백업에서 데모용 샘플 선별
- 이미지(가능 시): `project/AWSLambda/UNIPASS_Image.py`

### 2-2. 혼합 원칙
- 최신 데이터: "현재성" 강조
- 과거 데이터: 카테고리/검색 다양성 확보
- 데모 응답에 `data_source`(`live`/`archive`) 노출해 설명 가능하게 유지

### 2-3. 최소 데모 목표 수량
- 물품 80~150개
- 카테고리 6개 이상
- 검색 시나리오 키워드 10개 이상

---

## 3) 파이프라인 실행 순서 (D-1)
1. MySQL 스키마/시드 반영
2. 최신 데이터 수집
3. 과거 샘플 병합(JSON)
4. ETL 적재: `etl/load_unipass_to_mysql.py`
5. rule 분류: `classification/build_classification.py`
6. OpenAI 보강 분류(필수)
   - 대상: 미분류, 저신뢰, 데모 핵심 품목
   - 결과 저장: `item_classification.model_name/model_ver/confidence/rationale`

---

## 4) 로컬 API 범위 (읽기 중심 + 사용자 기능 최소)
### 4-1. 공매/검색 API
- `GET /health`
- `GET /items?query=&category=&limit=&offset=&sort=`
- `GET /items/{item_id}`
- `GET /categories`
- `GET /items/{item_id}/grouped`
- `GET /search/suggest?q=`

### 4-2. 사용자 기능 API (이번 요청 반영)
- 최근 검색어
  - `GET /users/{user_id}/recent-searches`
  - `POST /users/{user_id}/recent-searches` (저장)
  - `DELETE /users/{user_id}/recent-searches/{history_id}` (개별 삭제)
  - `DELETE /users/{user_id}/recent-searches` (전체 삭제)
- 내 목록(입찰/낙찰/유찰)
  - `GET /users/{user_id}/my-auctions?status=BIDDING|WON|FAILED`
  - `POST /users/{user_id}/my-auctions` (상태 저장/업데이트)
- 사용자 위치 설정(실시간 GPS 아님)
  - `GET /users/{user_id}/location`
  - `PUT /users/{user_id}/location` (기본 위치 저장/수정)

---

## 5) 검색 기능 구현 가이드 (데모 최적화)
### 5-1. 검색 우선순위
1. 물품명 정확 일치
2. 토큰/동의어 일치 (`item_search_token`)
3. 카테고리 일치
4. 최신순 보정

### 5-2. 필수 처리
- query 정규화(소문자/특수문자 제거/공백 정리)
- 0건 시 대체 UX
  - 추천 검색어 노출
  - 유사 카테고리 진입 제공

### 5-3. 데모 키워드 예시
- "와인", "battery", "차량 부품", "주류", "냉장고", "전자"

---

## 6) 묶음 물품(같이 있는 물품) 구현
### 6-1. 1차 기준(빠르고 설명 쉬움)
- **동일 `pbac_no`** 우선
  - 같은 공매번호로 묶어서 노출

### 6-2. 2차 확장 기준
- 동일/인접 카테고리
- 키워드 유사도

> 데모는 1차 기준만으로도 충분히 납득 가능.

---

## 7) 사용자 설정 위치 기반 가까운 공매 기관 추천 기능
요청 기능은 1차 데모에서 **사용자 저장 위치 기준**으로 구현한다.

### 7-1. 필요한 데이터
- 기관(세관) 위치 좌표 테이블(수동 입력 가능)
- `app_user`에 저장된 사용자 기본 위치(lat/lng)

### 7-2. 계산 방식
- 사용자 저장 위치와 기관 좌표의 Haversine 거리 계산
- 가까운 기관 Top-N 선택 후 해당 기관 물품 추천

### 7-3. API 제안 (user_id 기반)
- `GET /users/{user_id}/nearby-agencies?radius_km=`
- `GET /users/{user_id}/nearby-items?radius_km=&limit=`

### 7-4. 데모 현실안
- 초기에는 주요 기관 좌표만 수동 등록(예: 10~20개)
- 반경 30km/50km 프리셋 버튼 제공
- user 위치가 없으면 "위치 설정 후 추천" 안내

---

## 8) 사용자 테이블/관련 테이블 추가안 (이번 요청 핵심)
현재 `schema_app_user_v1.sql`에는 관심대상(watchlist)은 있으나,
최근 검색어/내 입찰목록/설정 위치 저장 구조가 부족합니다.

### 8-1. 사용자 기본 위치 컬럼 (기존 `app_user` 확장)
`app_user.app_user`에 아래 컬럼 추가
- `base_latitude` DECIMAL(10,7) NULL
  - 의미: 사용자가 설정한 기준 위치의 위도
  - 용도: 기관/물품 거리 계산(Haversine)의 시작점
  - 예시: `37.5665350`
- `base_longitude` DECIMAL(10,7) NULL
  - 의미: 사용자가 설정한 기준 위치의 경도
  - 용도: 위도와 함께 위치 기반 추천 계산
  - 예시: `126.9779692`
- `base_location_label` VARCHAR(100) NULL
  - 의미: 사용자가 붙인 위치 이름
  - 용도: UI 표시("집", "회사", "자주 가는 곳")
  - 예시: `"집"`
- `base_location_updated_at` DATETIME NULL
  - 의미: 기준 위치를 마지막으로 저장한 시각
  - 용도: 데이터 최신성/감사 로그 확인
  - 예시: `2026-03-14 10:25:00`

> 대안: 별도 `user_location_profile` 테이블로 분리 가능하나,
> D-1 데모는 `app_user` 확장이 가장 빠름.

### 8-2. 최근 검색어 테이블 (신규)
`app_user.user_recent_search`
- `history_id` BIGINT PK
  - 의미: 검색 이력 식별자
  - 용도: 개별 삭제(`DELETE /recent-searches/{history_id}`)
- `user_id` BIGINT NOT NULL
  - 의미: 검색어를 저장한 사용자
  - 용도: 사용자별 이력 분리/조회
- `query_text` VARCHAR(200) NOT NULL
  - 의미: 사용자가 입력한 원문 검색어
  - 용도: UI 그대로 노출
- `query_normalized` VARCHAR(200) NOT NULL
  - 의미: 정규화된 검색어(소문자/공백정리 등)
  - 용도: 중복 검색어 병합/재검색 최적화
- `created_at` DATETIME NOT NULL
  - 의미: 저장/갱신 시각
  - 용도: 최신순 정렬
- 인덱스: `(user_id, created_at DESC)`, `(user_id, query_normalized)`
  - 목적: 최근 목록 조회와 중복 체크 성능 확보
- 정책:
  - 사용자당 최근 20~30개 유지(초과분 오래된 순 삭제)
  - 동일 검색어 재검색 시 upsert-like로 최신시각 갱신

### 8-3. 내 목록(입찰/낙찰/유찰) 테이블 (신규)
`app_user.user_auction_activity`
- `activity_id` BIGINT PK
  - 의미: 사용자 활동 레코드 식별자
  - 용도: 추후 이력 관리/감사 추적
- `user_id` BIGINT NOT NULL
  - 의미: 상태를 보유한 사용자
  - 용도: 내 목록 조회 키
- `pbac_no`, `pbac_srno`, `cmdt_ln_no` (물품 식별)
  - 의미: 공매 물품 고유 키
  - 용도: 어떤 물품에 대한 상태인지 명확히 식별
- `activity_status` ENUM('BIDDING','WON','FAILED') NOT NULL
  - 의미: 사용자 기준 현재 상태(입찰중/낙찰/유찰)
  - 용도: 탭별 목록 조회
- `bid_amount` BIGINT NULL
  - 의미: 사용자가 기록한 입찰 금액(선택)
  - 용도: 내 활동 상세 정보 제공
- `external_source` VARCHAR(30) NULL  (예: 'MANUAL', 'UNIPASS_IMPORT')
  - 의미: 상태 입력 출처
  - 용도: 수동 입력 vs 외부 동기화 구분
- `occurred_at` DATETIME NOT NULL
  - 의미: 해당 상태가 발생한 시점
  - 용도: 이력 타임라인 표시
- `updated_at` DATETIME NOT NULL
  - 의미: 레코드 최종 수정 시점
  - 용도: 최신 상태 정렬
- UNIQUE: `(user_id, pbac_no, pbac_srno, cmdt_ln_no)`
  - 목적: 사용자-물품당 상태 레코드 1건 유지
- 인덱스: `(user_id, activity_status, updated_at DESC)`
  - 목적: 상태 탭 조회 성능 확보

### 8-4. 상태/위치 정보를 "어떻게 저장"할지
현실적으로 2가지 경로 혼합이 필요합니다.
1. 수동 저장(데모 즉시 가능)
   - 사용자 위치(기본 위치), 내 입찰/낙찰/유찰 상태를 앱에서 직접 저장
2. 외부 동기화(2차)
   - 추후 유니패스/외부 이벤트 연동으로 자동 업데이트

> 1차 데모는 수동 저장 방식으로 기능 체감을 먼저 확보하고,
> 2차에서 자동 동기화로 고도화하는 전략이 가장 안전.

---

## 9) OpenAI 분류 데모 포함 가능 여부 + 구현 방법 (현실성 판단)
### 9-1. 결론
**현실적으로 가능**합니다. 다만 "전체 물품 전량 OpenAI"는 D-1에서 비현실적일 수 있으므로,
**rule 1차 + OpenAI 선별 보강** 방식으로 가야 안정적으로 끝낼 수 있습니다.

### 9-2. 구현 순서(권장)
1. `classification/build_classification.py`로 rule 분류 선반영
2. OpenAI 대상 선별 SQL 추출
   - `UNCLASSIFIED` 항목
   - `confidence` 낮은 항목
   - 데모 키워드 관련 항목
3. OpenAI 호출 스크립트 실행(배치)
4. 결과 검증
   - category_path 유효성 검사
   - confidence 최소 기준 미달 시 rule 유지
5. `item_classification` upsert
   - `model_name`, `model_ver`, `confidence`, `rationale` 기록

### 9-3. API/스크립트 구현 포인트
- 입력: `cmdt_nm`, 기존 rule 분류 결과, 후보 카테고리(top-N)
- 출력(JSON 강제):
  - `category_path`
  - `confidence`
  - `reason`
- 실패 처리:
  - 타임아웃/429/5xx 시 재시도(지수 백오프)
  - 최종 실패 시 rule 결과 fallback

### 9-4. D-1 현실 범위(강력 권장)
- OpenAI 대상 수: **상위 100~300건**
- 배치 크기: 20~50건 단위
- 목표 시간: 1~2시간 내 처리 완료
- 비용 통제: 동일 `cmdt_nm` 캐시 재사용

### 9-5. "불가능"해지는 조건(사전 체크)
- OpenAI API 키/네트워크 미준비
- 카테고리 체계 미정(유효성 검증 불가)
- 전량 처리 고집(시간 초과 위험)

### 9-6. 데모용 최소 성공 기준
- rule 대비 OpenAI 보강된 사례 3~5개를 화면에서 설명 가능
- 실패 케이스도 fallback으로 서비스가 깨지지 않음

---

## 10) 프론트 데모 화면 (필수)
1. 목록(검색/필터/정렬)
2. 상세(물품 + 분류 + 이미지)
3. 묶음(같은 공매)
4. 내 화면
   - 최근 검색어 관리
   - 입찰/낙찰/유찰 탭
   - 기본 위치 설정 및 위치 기반 추천

---

## 11) D-1 타임라인
### 오전
- 최신 수집 + 과거 병합 + ETL + rule 분류

### 오후 초반
- OpenAI 보강 분류 실행
- 검색 쿼리/추천어 점검

### 오후 후반
- 사용자 기능(최근검색어/내목록/위치설정) API + 앱 연결
- 묶음/위치추천 연결

### 마감 전
- 데모 시나리오 리허설
- 실패 시 대체 시나리오 준비

---

## 12) 오늘 바로 합의할 항목
1. OpenAI 보강 분류 대상 개수(N건)
2. 최신:과거 데이터 혼합 비율
3. 위치 추천 반경 기본값(30km/50km)
4. 내 목록 상태 저장 방식(1차 수동, 2차 자동) 확정
5. 사용자 위치 저장 방식(`app_user` 컬럼 확장 vs 별도 테이블) 확정

---

## 13) 액션 아이템 (즉시 실행)
1. DB에 사용자 위치 저장 컬럼(`base_latitude`, `base_longitude`) 추가 설계 확정
2. DB에 `user_recent_search`, `user_auction_activity` 추가 설계 확정
3. 최근 검색어 CRUD API 구현
4. 사용자 위치 설정 API + 위치 기반 추천 API 구현(user_id 기준)
5. 내 목록(status 기반) 저장/조회 API 구현
6. 앱에서 검색/묶음/내목록/위치추천 시연 시나리오 고정
