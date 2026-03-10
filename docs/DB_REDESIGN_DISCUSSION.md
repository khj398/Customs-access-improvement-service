# 공매 물품 DB + 앱 사용자 DB 재설계 초안 (수정본)

요청사항(수집 코드 변경 반영, 사용자 데이터 분리)을 기준으로 **DB를 2개 도메인으로 분리**한 설계 초안입니다.

- 도메인 A: `auction_core` (공매/물품/분류/검색)
- 도메인 B: `app_user` (회원/관심물품/알림/행동로그)

---

## 1) 왜 분리하나?

1. 수집/적재(ETL) 트래픽과 앱 사용자 트래픽의 성격이 다름
2. 개인정보/인증 데이터는 접근권한과 감사로그 요구사항이 다름
3. 운영 시 스케일링, 백업/복구 단위를 분리하기 쉬움

> 초기에는 한 MySQL 인스턴스에서 스키마만 분리해도 충분하며,
> 트래픽 증가 시 물리 DB 분리로 확장 가능합니다.

---

## 2) 공매 물품 DB(`auction_core`) 제안

기존 `auction`, `auction_item` 구조는 유지하되, 수집 코드 변경 대응을 위해 아래를 보강합니다.

### 2-0. 기존 스키마 유지/이관 원칙 (중요)
"기존 DB 스키마가 많이 사라지는 것 아닌가?"에 대한 답변입니다.

- **유지(그대로 사용)**
  - `auction`, `auction_item`
  - `customs_office`, `bonded_warehouse`, `cargo_type`, `unit_code`
  - `category`, `item_classification`, `synonym_dictionary`, `item_search_token`, `auction_item_image`
- **신규 추가(이번 재설계에서 보강)**
  - `ingestion_run`, `raw_auction_payload`, `auction_item_change_event`
  - (운영 필요 시) `auction_item_hist`, 큐 테이블(`recollect/classification/notification`)
- **명칭 정리 원칙**
  - 기존 `category`/`synonym_dictionary`를 그대로 유지해도 되고,
  - 운영 표준을 위해 `item_category`/`search_synonym_dict`처럼 리네이밍하더라도
    1차에서는 "물리 테이블 드랍"이 아니라 **뷰/별칭 또는 점진 마이그레이션**으로 전환

즉, 현재 문서는 "기존 테이블을 버리고 새로 만든다"가 아니라,
**기존 핵심 테이블을 유지한 상태에서 검색/수집/알림에 필요한 테이블을 확장**하는 설계입니다.

### 2-1. ingestion_run (신규)
- 목적: 수집 실행 단위 추적(언제, 어떤 소스, 성공/실패, 적재 건수)
- 핵심 컬럼
  - `ingestion_run_id` (PK)
  - `source_name` (예: unipass_list)
  - `started_at`, `finished_at`
  - `status` (SUCCESS/FAILED/PARTIAL)
  - `raw_item_count`, `upsert_count`, `error_count`

### 2-2. raw_auction_payload (신규)
- 목적: 원문 JSON 보관(디버깅, 스키마 변경 추적)
- 핵심 컬럼
  - `payload_id` (PK)
  - `ingestion_run_id` (FK)
  - `source_key` (`pbacNo|pbacSrno|cmdtLnNo`)
  - `payload_json` (JSON)
  - `payload_hash` (중복 감지)

### 2-3. auction_item_change_event (신규, 1차 필수)
- 목적: 가격/상태 변경을 이벤트로 기록해서 검색/알림 기능의 트리거로 사용
- 왜 지금 필요?
  - 현재 목표가 “검색/알림 등 필수 기능 동작”이므로 변경 이벤트는 즉시 활용 가능
  - 단, 가격/상태 변경 알림 품질을 높이려면 수집 주기를 구간별로 다르게 가져가야 함(아래 9-1 참고)
- 핵심 컬럼
  - `event_id` (PK)
  - `pbac_no`, `pbac_srno`, `cmdt_ln_no`
  - `event_type` (PRICE_CHANGED / STATUS_CHANGED / NEW_ITEM / REMOVED_ITEM)
  - `before_value_json`, `after_value_json`
  - `detected_at`, `ingestion_run_id`
- 권장 인덱스
  - (`pbac_no`, `pbac_srno`, `cmdt_ln_no`, `detected_at`)
  - (`event_type`, `detected_at`)

### 2-4. auction_item_hist (선택, 2차)
- 목적: 감사/분석 관점에서 전체 시점 이력 보관(SCD Type-2 유사)
- 참고: 1차에서는 `auction_item_change_event`만으로도 알림/추적은 가능

### 2-5. auction_item_image 보강
- 현재 테이블 유지 + 아래 컬럼 추가 권장
  - `image_type` (THUMB/DETAIL/UNKNOWN)
  - `source` (LIST_API/DETAIL_API/CRAWLER)
  - `last_seen_at`

### 2-5-1. 수집기 3종 반영 체크 (Business/Personal/Image)
현재 수집 코드가 아래 3개로 분리되었다는 점을 스키마에 반영해야 합니다.

- `UNIPASS_LIST_Business.py`: 수입화물 목록 수집
- `UNIPASS_LIST_Personal.py`: 휴대품 목록 수집
- `UNIPASS_Image.py`: 이미지 수집

현재 기준 점검:
1. 이미지 저장 스키마: **있음** (`auction_item_image`)
2. 휴대품/수입화물 구분: `cargo_type`(`pbacTrgtCargTpcd`) 기반으로 **구분 가능**(간접)
3. 전자입찰/일반입찰 구분: `auction.elct_bid_eon`으로 **구분 가능**

보강 권장(1차 DDL):
- `auction`에 `collector_source`(BUSINESS/PERSONAL/UNKNOWN) 필드 추가 고려
- `auction_item_image.source` 또는 `source_type` 값을 표준 enum으로 관리
  - 예: `UNIPASS_IMAGE`, `LIST_BUSINESS`, `LIST_PERSONAL`

### 2-6. 분류/검색 테이블 운영 보강
- `item_classification`: `model_name`, `model_ver`, `confidence` 인덱스 정비
- `item_search_token`: `token_normalized`, `lang`, `token_type` 인덱스 강화
- **카테고리 스키마(1차 포함 권장)**
  - `item_category`(신규): `category_id`, `parent_category_id`, `category_code`, `name_ko`, `name_en`, `depth`, `is_active`
  - `item_category_alias`(신규): 카테고리 별칭/동의어(예: 휴대폰/스마트폰/폰) 저장
  - `auction_item_category_map`(신규): 아이템-카테고리 N:1 또는 N:M 매핑
- **검색 사전(synonym) 스키마(1차 포함 권장)**
  - `search_synonym_dict`(신규): `synonym_id`, `locale`, `term_original`, `term_normalized`, `term_type(BRAND/MODEL/GENERAL)`, `is_active`
  - `search_synonym_map`(신규): 동의어 그룹 관리(`group_key`)로 영문/한글/대소문자 변형을 하나의 검색키로 통합
- 대소문자/언어 대응 원칙
  - 인덱싱 시 `lower()` + 공백/특수문자 정규화로 기본 토큰 생성
  - 동의어 사전으로 영문↔한글 표현을 확장(예: `iPhone`, `아이폰`, `IPHONE`)
- 물품명 표시는 **원문 보존 + 정규화명 병행 노출** 권장
  - `item_name_original`(유니패스 원문 영문/기호 포함)
  - `item_name_normalized_ko`(사용자 친화 표시명, nullable)
  - UI 예: `원문명 (정규화명)` 또는 `정규화명 / 원문명` 토글
- 분류 파이프라인 정책
  - 1차: 규칙기반 분류(사전/정규식/패턴 매칭)
  - 2차: LLM 보조 분류(저신뢰/미분류 건만 재판정)

---

## 3) 앱 사용자 DB(`app_user`) 제안 (결정 반영)

### 3-1. 로그인 방식: **로컬 + 소셜 병행**
- 로컬 계정(email/password)
- 소셜 로그인(KAKAO/GOOGLE/APPLE)
- 같은 이메일에 대해 계정 연동 가능하도록 설계

### 3-2. app_user (신규)
- 회원 기본정보
- 핵심 컬럼
  - `user_id` (PK, bigint or uuid)
  - `email` (UNIQUE)
  - `password_hash` (로컬 로그인용)
  - `status` (ACTIVE/SUSPENDED/DELETED)
  - `created_at`, `updated_at`, `last_login_at`

### 3-3. user_auth_provider (신규)
- 소셜 계정 연동용 분리 테이블(로컬+소셜 병행 구조에 적합)
- 핵심 컬럼
  - `user_id` (FK)
  - `provider` (LOCAL/KAKAO/GOOGLE/APPLE)
  - `provider_user_key` (소셜 고유 식별자)
  - `connected_at`
- 제약
  - UNIQUE(`provider`, `provider_user_key`)

### 3-4. user_profile (신규)
- 앱 표시용 프로필
- `user_id` (PK/FK), `nickname`, `locale`, `timezone`, `marketing_opt_in`

### 3-5. user_watchlist_target (신규, 관심대상 2레벨)
관심물품 키 이슈를 해결하기 위해 **LOT(공매) 단위 + ITEM(라인) 단위를 함께 지원**합니다.

- 필드
  - `watch_target_id` (PK)
  - `user_id` (FK)
  - `target_level` (LOT / ITEM)
  - LOT 키: `pbac_no`
  - ITEM 키: `pbac_no`, `pbac_srno`, `cmdt_ln_no`
  - `notify_enabled`, `memo`, `created_at`
- 제약
  - LOT 관심: UNIQUE(`user_id`, `target_level`, `pbac_no`)
  - ITEM 관심: UNIQUE(`user_id`, `target_level`, `pbac_no`, `pbac_srno`, `cmdt_ln_no`)

> 이렇게 하면 “컵을 찾고 싶어서 라인 단위로 저장”도 가능하고,
> “실제 구매는 공매번호 단위로 이뤄지니 묶음 전체 추적”도 가능해집니다.

### 3-6. user_notification_rule / event (신규)
- 알림 조건 + 발송 이력
- **알림 채널은 1차로 APP_PUSH만 사용**
- 이메일/SMS는 컬럼 확장 여지만 두고 비활성

---

## 4) 핵심 고민 정리: 묶음 구매 vs 라인 검색/분류

질문 요약:
- 데이터는 라인(`pbac_no`,`pbac_srno`,`cmdt_ln_no`)으로 분리되어 있는데,
- 실제 구매는 `pbac_no` 묶음(LOT) 단위면,
- 검색/분류/관심물품을 라인 기준으로 할지 LOT 기준으로 할지?

권장안: **표시는 라인 중심 + 거래맥락은 LOT 병행 노출**

1. 검색/분류 인덱스는 라인(ITEM) 기준 유지
   - 사용자는 "컵"을 찾고 싶으므로 라인 기준 탐색성이 중요
2. 상세 화면에서 LOT 구성품을 함께 표시
   - "이 물품은 LOT 구매이며 함께 포함된 물품: 휴지 5, 컵 3" 안내
3. 관심대상도 2레벨 지원
   - ITEM 관심: 내가 찾던 컵 중심 알림
   - LOT 관심: 실제 입찰 단위 전체 변동 알림
4. 알림 메시지 정책
   - ITEM 관심 등록자에게도 "해당 ITEM이 포함된 LOT 변경"으로 안내

---

## 5) 원문 JSON 보관 정책 (하루 1회 수집 가정)

하루 1회 업데이트 기준 추천:

- 기본: **180일(6개월) 보관**
  - 운영 이슈/파싱 오류 역추적, 계절성 데이터 비교에 충분
- 압축/아카이브:
  - 30일 이내: DB 원본 유지
  - 31~180일: gzip 압축 저장(또는 object storage)
  - 180일 초과: 삭제(필요시 주간 스냅샷만 보존)

초기 보수안(리소스 여유 시): 1년 보관도 가능하지만,
현재 단계에서는 6개월 + 스냅샷이 비용/운영 균형이 좋습니다.

---

## 6) 추가로 필요할 가능성이 높은 것(토론 포인트)

> 현재 목표가 MVP(검색/알림 필수 기능 동작)이므로, **앱 보안용 권한/감사 로그는 일단 범위 제외**합니다.

1. **가격변동/상태변경 이벤트 테이블 (도입 확정)**
   - `auction_item_change_event`를 1차 스키마에 포함
2. **중복/동일물품 클러스터링 키**
   - 서로 다른 공매번호라도 사실상 같은 품목(예: 동일 모델명/스펙/이미지 해시)인지 탐지
3. **배치 작업 큐**
   - 실패 재시도 + 비동기 처리 순서 제어 + 과부하 방지
   - 예: 분류 대기, 알림 대기, 재수집 대기
4. **데이터 보존정책**
   - 원문 payload + 이벤트 + 사용자 검색이력/알림이력의 TTL 기준

---

## 7) 이번 논의 기준으로 확정된 항목

1. 로그인 방식: **로컬 + 소셜 병행**
2. 알림 채널: **APP_PUSH만 1차 적용**
3. 관심물품: **LOT/ITEM 2레벨 지원**
4. 변경 이벤트 수집주기: **현재는 1일 1회 수집, 2차에 경매 시작~종료 구간 실시간 수집 추가**
5. 원문 JSON/이벤트 TTL: **공매 종료 시점 기준으로 시작**
6. 변경 이벤트: **`auction_item_change_event` 1차 도입 확정**
7. 배치 작업 큐: **큐별 분리 + 재시도 4회(1분→5분→10분→포기)**
8. 물품명 정책: **원문명+정규화명 병행 표기(원문 보존 필수)**
9. 정규화명 생성 정책: **규칙기반 우선 + LLM 보조**
10. 실시간 수집(2차): **경매 시작~종료 구간 1분 폴링**
11. 실시간 수집 보호기준(확정): **API 한도 100건/호출, 실패율 5% 초과 시 한도/주기 재조정**
12. 권한/감사 로그: **MVP 범위에서는 제외**
13. 카테고리/동의어(synonym) 스키마: **`auction_core` 내 1차 포함**

---

## 8) 제안 브랜치/작업 순서

1. `plan/db-redesign-auction-user` (현재): 논의/ERD 확정
2. `feat/db-auction-core-v2`: ingestion/raw/change_event (필수) + hist(선택) 테이블 추가
3. `feat/db-app-user-v1`: user/auth/watchlist/notification 스키마 추가
4. `feat/api-user-watchlist-notify`: 백엔드 API 연동



---

## 9) 리뷰 코멘트 Q&A 반영

### 9-1. 가격/상태 변경 이벤트를 쓰면 하루 1회 수집으로 충분한가?
현 상황(실시간 입찰가격 수집 코드 부재, 현장입찰 업데이트 불확실성) 기준으로는
**우선 하루 1회 수집으로 운영**하는 것이 맞습니다.

정리:
1. 현재(1차): 하루 1회 수집 + change_event는 "일 단위 변경 감지"에 사용
2. 추후(2차): **경매 시작시간~종료시간 구간 1분 폴링** 실시간(준실시간) 수집 추가
3. 정책 원칙: 수집 가능성과 데이터 신뢰도를 먼저 확보한 뒤 주기를 높임

### 9-2. “서로 다른 공매번호라도 같은 품목”은 무슨 뜻인가?
의미는 다음과 같습니다.
- 공매번호 A: `IPHONE 13 128GB BLACK`
- 공매번호 B: `Apple iPhone13 128G Black`

공매번호는 다르지만, 사용자 입장에서는 사실상 같은 물건일 수 있습니다.
이걸 묶어두면 추천/유사검색/관심알림 확장에 유리합니다.

클러스터링 2차 정밀 기준은 **당장은 미도입**하고, 이후 단계에서 순차 반영합니다.

참고로 도입 시 후보 기준은 아래와 같습니다.
- `normalized_name`(정규화 물품명)
- 주요 속성(브랜드/모델/용량/규격/재질 등)

여기서 "속성"은 카테고리와 별개로 물품을 더 정확히 식별하는 정보입니다.
예: 브랜드, 모델명, 용량(128GB), 규격(55inch), 재질(스테인리스) 등

### 9-3. 배치 작업 큐는 수집 실패 처리용인가?
**그 용도도 포함되지만, 더 넓은 오케스트레이션 용도**입니다.

이번 합의안(확정):
- 큐는 **용도별 분리**
  - `recollect_job_queue` / `classification_job_queue` / `notification_job_queue`
- 재시도 정책(최대 4회)
  1) 1회 실패 → 1분 후 재시도
  2) 2회 실패 → 5분 후 재시도
  3) 3회 실패 → 10분 후 재시도
  4) 4회 실패 → 포기(FAILED 고정, 수동 확인 대상)
- 큐 공통 최소 컬럼(확정)
  - `status`, `retry_count`, `next_retry_at`, `last_error`

주요 용도:
1. 실패 재시도(수집/분류/알림)
2. 작업 순서 보장(수집 완료 → 분류 → 알림)
3. 대량 처리 시 속도제한/백오프
4. 운영 가시성(대기/진행/실패 건수 모니터링)

즉 “실패 복구 + 작업 파이프라인 제어”가 핵심입니다.

### 9-4. 데이터 보존정책은 유저 DB 때문에 필요한가?
**유저 DB만의 이슈는 아닙니다. 두 도메인 모두 필요합니다.**

- `auction_core`: 원문 JSON, 변경 이벤트, 수집 로그의 저장기간 필요(스토리지/운영비)
- `app_user`: 검색이력/알림이력/계정 관련 데이터의 저장기간 필요(개인정보 최소보관)

따라서 보존정책은 공매/유저 DB 공통 운영정책으로 관리하는 것이 맞습니다.



### 9-5. 같은 품목 묶음을 카테고리로만 하면 안 되나?
좋은 접근이고 **1차 필터로는 매우 유효**합니다. 다만 카테고리만으로는 너무 넓게 묶일 수 있습니다.

예시:
- 둘 다 `전자기기>휴대폰` 카테고리
- 하지만 iPhone 13과 iPhone 15는 다른 품목

권장안:
1. 1차: `category_path`로 후보군 축소
2. 2차(추가 예정): `normalized_name` + 주요 속성(브랜드/모델/용량/규격/재질)으로 정밀 매칭

즉, 카테고리는 “큰 바구니”, 정밀 키는 “같은 물건 판별”에 사용합니다.

그리고 프로젝트 동기(모호한 분류 개선) 관점에서도,
카테고리는 탐색성 개선용으로 적극 활용하되 “동일품목 판정 키”와 역할을 분리하는 것이 안전합니다.

### 9-6. 배치 작업 큐는 필요하겠네?
네, 현재 요구사항 기준으로 **필요한 편**입니다.

최소 큐 3종 권장:
- `recollect_job_queue`: 활성 경매 1분 재수집 스케줄(2차)
- `classification_job_queue`: 신규/변경 item 재분류
- `notification_job_queue`: 조건 일치 사용자에게 푸시 발송

MVP는 단일 DB 테이블 큐 + 워커 1개부터 시작해도 충분합니다.

### 9-7. 물품명을 정규화해서 보여주면 유니패스에서 찾기 어려워지지 않나?
우려가 맞습니다. 그래서 **원문을 절대 버리지 않고 병행 표기**가 정답에 가깝습니다.

권장 UI/데이터 정책:
1. 목록 기본: 정규화명 우선(가독성)
2. 보조 표기: 원문명 항상 같이 노출
3. 상세 화면: `공매번호(pbac_no)` + `원문명` + `정규화명` 모두 표시
4. 검색: 공매번호/원문명/정규화명 모두 검색 가능
5. 외부 이동 버튼: "유니패스에서 원문으로 보기" 제공

이렇게 하면 접근성은 높이면서도, 실제 결제/입찰을 위해 유니패스로 넘어갈 때 식별 혼란을 줄일 수 있습니다.


### 9-8. 카테고리/동의어(synonym) 스키마가 안 보이는데 괜찮은가?
결론: **별도 DB를 추가로 만들기보다 `auction_core` 안에 스키마를 추가**하는 것이 1차 구현에 가장 적합합니다.

정리:
1. 지금 문서에는 분류/검색 테이블 보강 방향만 있었고, 카테고리/사전 테이블 정의가 구체적이지 않았음
2. 이번에 `item_category`, `item_category_alias`, `auction_item_category_map`, `search_synonym_dict`, `search_synonym_map`을 1차 포함 대상으로 명시
3. 검색은 `item_search_token` + synonym 사전을 함께 사용해 영문 대소문자/한글 검색을 모두 지원
4. 분류 전략은 **규칙기반 우선 + LLM 보조**로 운영(LLM은 저신뢰건 재판정 위주)

즉, "지금 있는데 내가 모르는가?"에 대한 답은
- 일부 기반(`item_classification`, `item_search_token`)은 있었고,
- 카테고리/사전 스키마는 이번에 명시적으로 보강한 상태입니다.


---

## 10) 데이터 보존정책 자세히 (운영용 초안)

보존정책은 “무조건 오래 보관”이 아니라, **필요한 만큼만 보관**해서 비용/성능/개인정보 리스크를 줄이는 운영 규칙입니다.

### 10-1. 왜 필요한가?
1. 스토리지 비용 통제
2. 조회 성능 유지(테이블 비대화 방지)
3. 개인정보 최소보관 원칙 대응
4. 장애 분석에 필요한 최소 이력 보장

### 10-2. 도메인별 권장 TTL
- `auction_core.raw_auction_payload`: **공매 종료일 기준 +180일**
- `auction_core.auction_item_change_event`: **공매 종료일 기준 +365일**
- `auction_core.ingestion_run`: 실행일 기준 365일
- `app_user.user_search_history`: 90일
- `app_user.user_notification_event`: 180일
- 삭제/휴면 사용자 식별정보: 정책에 따라 비식별화 또는 별도 보관

### 10-3. 보관 단계(Hot/Warm/Cold)
1. Hot(즉시조회): 최근 30일, DB 원본
2. Warm(가끔조회): 31~180일, 압축 저장
3. Cold(장기보관/선택): 통계 스냅샷만 남기고 원문 삭제

### 10-4. 운영 방식
- 매일 새벽 TTL 배치 실행(현재는 1일 1회 수집 전제)
- TTL 기준 시각은 `auction_end_at`(공매 종료 시점) **단일 기준 컬럼**으로 계산
  - 의미: TTL 계산 시 여러 날짜 컬럼을 섞지 않고 `auction_end_at` 하나만 기준으로 사용
- 상태값(`OPEN/CLOSED/CANCELLED` 등) 정의를 먼저 고정한 뒤 삭제 배치를 연결
- 삭제 전 집계 스냅샷 생성(일/주 단위)
- 정책 변경 시 문서+코드(배치 SQL) 함께 버전관리

저장소 권장:
- 초기(서버 추가 전): 애플리케이션 서버 로컬 디스크 저장도 가능(단기)
- 권장(서버 추가 후): **오브젝트 스토리지(S3/MinIO/NAS) 분리 저장**
  - 이유: 앱 서버와 수명주기 분리, 백업/복구/확장성 유리
  - 주의: 앱 서버 로컬만 사용 시 서버 장애/재배포 시 스냅샷 유실 위험

권장안(공매 서비스 특성 기준):
1. 삭제 정책
   - 운영 DB: **하드삭제** 권장(TTL 경과 시 행 삭제)  
   - 보존 필요 데이터: 삭제 전 스냅샷으로 보관
2. 스냅샷 포맷
   - 기본: **CSV.gz** (운영 단순성/호환성 우수)
   - 분석 확장 시: **Parquet** 병행 도입
3. 스냅샷 범위
   - `raw_auction_payload`, `auction_item_change_event`, `ingestion_run` 우선
   - 파티션 키: **월별(`ym=YYYY-MM`) 고정**
   - 파일명 규칙: `table_name/ym=YYYY-MM/part-*.csv.gz`

---

## 11) 현 시점 정리 (완료/미완/토론/QnA 분리)

### 11-1. 지금까지 완료된 것 (확정사항)
1. DB 도메인 분리 방향 확정
   - `auction_core` / `app_user` 2도메인
2. MVP 핵심 기능 중심 범위 확정
   - 검색/알림 우선, 권한/감사로그는 MVP 범위 제외
3. 이벤트 기반 모델 확정
   - `auction_item_change_event` 1차 스키마 포함
4. 수집 주기 전략 확정
   - 현재는 하루 1회 수집, 2차에 경매 시작~종료 구간 실시간 수집 추가
5. 사용자/알림 기본 정책 확정
   - 로컬+소셜 로그인 병행, APP_PUSH 우선
6. 물품명 노출 정책 확정
   - 원문명 보존 + 정규화명 병행 표기
7. 정규화명 생성 정책 확정
   - 규칙기반 우선 + LLM 보조
8. 큐/재시도 정책 확정
   - 큐별 분리 + 4회 재시도(1분→5분→10분→포기)
9. 카테고리/검색 사전 정책 확정
   - `auction_core` 내 category/synonym 스키마 추가, 규칙기반+LLM 보조 분류 적용

### 11-2. 아직 완료되지 않은 고민 (미확정)
1. 동일품목 클러스터링 2차 정밀 기준
   - 이번 단계에서는 보류, 후속 단계에서 `normalized_name` + 주요 속성 기준으로 도입
2. 보존정책 실제 적용안
   - TTL 기준은 `auction_end_at` 단일 컬럼, 스냅샷 파티션 키는 월별(`ym`)로 확정
   - 남은 과제: 저장소 위치/수명주기 정책(Lifecycle) 확정
3. 실시간 수집 도입 세부
   - 1분 폴링 + API 한도 100건/호출 + 실패율 5% 초과 시 재조정 규칙의 운영값 검증 필요

### 11-3. 추가 토론 포인트 (회의용 아젠다)
1. 유니패스 연계 UX
   - 앱 상세 화면에서 유니패스 이동 시 어떤 식별자(공매번호/원문명)를 최우선 노출할지
2. 실시간 수집 비용/정확도 밸런스
   - 1분 폴링 고정 + API 한도 100건/호출 기준에서 실패율이 5%를 넘으면 한도/주기를 즉시 재조정
3. 알림 피로도 제어
   - 동일 LOT 내 다건 변경 시 묶음 알림(digest) 정책 필요 여부
4. 데이터 품질 지표
   - 분류 정확도/미분류율/알림 적중률을 어떤 쿼리로 지속 모니터링할지

### 11-4. QnA 요약 (빠른 참조)
1. Q: change_event 쓰면 하루 1회 수집으로 충분한가?
   - A: 현재는 하루 1회 운영, 2차에 경매 시작~종료 구간 1분 폴링 추가 예정.
2. Q: 카테고리로 같은 품목 묶으면 안 되나?
   - A: 카테고리는 1차 후보군 축소용. 동일품목 클러스터링 정밀 기준은 2차에 추가 예정.
3. Q: 배치 작업 큐는 실패 복구용인가?
   - A: 실패 복구 + 작업 순서 제어 + 운영 모니터링이며, 큐별 분리와 4회 재시도 정책 적용.
4. Q: 보존정책은 유저 DB만 해당되나?
   - A: 아님. `auction_core`와 `app_user` 모두 필요.
5. Q: 정규화명 보여주면 유니패스에서 찾기 어려운가?
   - A: 원문 병행 표기로 해결 가능(원문/정규화/공매번호 동시 제공).
6. Q: TTL 단일 기준이 뭔가?
   - A: TTL 계산 시 기준 날짜를 `auction_end_at` 하나로 고정해 혼선을 줄이는 것.
7. Q: 스냅샷은 서버 로컬에 저장해도 되나?
   - A: 초기엔 가능하지만 장기적으로는 스토리지 분리(S3/MinIO/NAS) 권장. 로컬만 쓰면 유실 위험이 큼.
8. Q: API 한도 100건/호출은 적절한가?
   - A: 현재 물품 수(약 100건) 기준으로 적절. 실패율이 5%를 넘으면 한도/주기를 재조정.
9. Q: 물품이 100개 내외면 어디에 저장하는 게 좋은가?
   - A: 운영 데이터는 MySQL(`auction`, `auction_item`, `auction_item_change_event`)에 저장하고, 삭제 전 스냅샷은 분리 저장소(S3/MinIO/NAS)에 보관하는 구성이 가장 안전함.
10. Q: 카테고리/동의어 검색을 위해 DB를 따로 만들어야 하나?
   - A: 별도 DB보다는 `auction_core` 내부에 category/synonym 테이블을 추가하는 것이 운영 단순성과 조인 성능 측면에서 유리함.
11. Q: 기존 DB에 있던 스키마가 많이 없어지는 것 아닌가?
   - A: 아님. `auction`, `auction_item`, 마스터 테이블, 기존 분류/검색(`category`, `item_classification`, `synonym_dictionary`, `item_search_token`)은 유지가 기본이며, 이번 재설계는 ingestion/change_event/큐 등 운영 스키마를 "추가"하는 방향임.
12. Q: 실행 추천안으로 바로 진행해도 되나? 리네이밍은 나중에 해도 되나?
   - A: 가능함. 1차는 기존 유지 + 필수 추가 스키마로 진행하고, 리네이밍은 View/alias 등 호환 계층을 둔 점진 전환으로 처리하는 것이 안전함.
13. Q: Business/Personal/Image 수집기 분리 기준으로 스키마가 나뉘어 있나?
   - A: 이미지 저장은 `auction_item_image`로 이미 존재하고, 휴대품/수입화물은 `cargo_type`으로 구분 가능하며, 전자/일반입찰은 `elct_bid_eon`으로 구분 가능. 다만 운영 편의를 위해 `collector_source` 명시 컬럼 추가를 권장.

---

## 12) 지금 시점 기준 네이밍/스키마 정리 가이드 (DDL 전 확정 권장)

질문: "지금 명칭 리네이밍 해야 되는 것/불필요한 스키마/추가 고려사항이 있는가?"

### 12-1. 리네이밍 "지금 바로" 필요한 것
1. **도메인 Prefix 일관화**
   - 권장: 공매 도메인은 `auction_`, 사용자 도메인은 `user_` prefix로 통일
   - 예: `category` -> `item_category`(또는 `auction_item_category`), `synonym_dictionary` -> `search_synonym_dict`
2. **시간 컬럼 명칭 통일**
   - `*_at` 규칙으로 고정(`created_at`, `updated_at`, `detected_at`, `next_retry_at`)
3. **상태값 컬럼 통일**
   - `status` enum 값은 테이블 간 공통 사전 정의 필요(`PENDING/RUNNING/SUCCESS/FAILED` 등)

### 12-2. 리네이밍은 "하면 좋지만" 점진 적용 권장
1. 기존 `category`, `synonym_dictionary`를 즉시 드랍/교체하지 않기
2. 1차는 아래 둘 중 하나로 호환 유지
   - (A) 기존 테이블 유지 + 신규 명칭은 View로 노출
   - (B) 신규 테이블 생성 + 배치 동기화(dual-write는 2차)
3. API/배치가 모두 신규 명칭을 쓰는 시점에만 최종 전환

### 12-3. 현재 기준 불필요/중복 가능성이 있는 스키마
1. **`search_synonym_map`**
   - `synonym_dictionary`에 `group_key`를 넣어도 같은 역할 수행 가능
   - 데이터량이 작으면 1테이블(`synonym_dictionary`)로 시작하는 게 운영 단순
2. **`auction_item_hist`(2차 선택)**
   - 현재는 `auction_item_change_event`로 MVP 요구(검색/알림) 충족 가능
3. **큐 3종 분리의 물리 테이블**
   - 초기 트래픽이 작으면 단일 `job_queue` + `job_type`으로 시작 후 분리 가능

> 정리: "당장 불필요"라기보다 **MVP 단계에서는 단순화 가능한 후보**입니다.

### 12-4. 추가 고려해야 할 것 (실제 DDL 품질 이슈)
1. **FK/인덱스 명명 규칙**
   - 예: `fk_<child>__<parent>`, `idx_<table>__<col1>_<col2>`로 통일
2. **문자 정규화 규칙을 DB/앱 중 어디서 책임질지**
   - `lower()/trim/특수문자 제거`를 ETL에서 고정할지, DB generated column으로 둘지 결정 필요
3. **카테고리 버전관리**
   - 분류 체계가 바뀔 수 있으므로 `category_version` 또는 `valid_from/valid_to` 고려
4. **LLM 보조 분류 감사 가능성**
   - `item_classification.rationale`에 rule/LLM 입력 요약/근거키를 남겨 재현성 확보
5. **마이그레이션 롤백 계획**
   - rename 전환 시 rollback SQL(뷰 복귀/동기화 중지) 스크립트를 함께 준비

### 12-5. 실행 추천안 (가장 안전한 경로)
1. 1차 DDL: 기존 테이블 유지 + `ingestion_run/raw_auction_payload/change_event` 추가
2. 검색/분류: 기존 `category/synonym_dictionary` 중심으로 우선 구현
3. 네이밍 정리: 뷰/alias 방식으로 신규 명칭 제공
4. 안정화 후: 실제 물리 리네이밍(또는 통합) 진행

### 12-6. 질문에 대한 결론 (바로 실행 여부 / 리네이밍 시점)
결론: **네, 실행 추천안으로 지금 진행해도 됩니다.**

- 지금(1차): 기존 스키마 유지 + 필수 추가 스키마(`ingestion_run`, `raw_auction_payload`, `auction_item_change_event`) 중심으로 진행
- 리네이밍: **나중에 해도 됩니다.** 단, 아래 조건을 지키는 것을 권장합니다.
  1. 호환 계층 유지(View/alias 또는 동기화 테이블)
  2. API/배치가 신규 명칭으로 전환 완료된 뒤 최종 cutover
  3. rollback SQL(이전 명칭 복귀) 사전 준비

즉, 현재 단계에서는 "기능 안정화 우선, 리네이밍은 점진 적용"이 가장 안전합니다.

