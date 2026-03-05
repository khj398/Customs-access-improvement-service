# Demo 구현 실행 계획 (DB 구축 + 데이터 수집 + OpenAI 자동 분류 백엔드)

## 1) 현재 GitHub 작업 기준 진단
현재 저장소는 **수집(JSON) → ETL(MySQL) → Rule 기반 분류/토큰화**까지는 잘 구성되어 있습니다.
다만 데모를 빠르게 완성하려면 아래 공백을 먼저 메꿔야 합니다.

- 백엔드 API 서버 부재 (`backend/`는 README 상 예정 단계)
- OpenAI 기반 분류 파이프라인 부재 (현재는 rule 기반 중심)
- 운영 기준(재처리, 실패 복구, 비용 제어, 평가 지표) 문서화 부족

즉, 지금 구조를 버리기보다 **기존 rule 파이프라인을 1차 필터로 재사용**하고,
**OpenAI 분류를 2차 보강 단계로 추가**하는 방식이 가장 안전하고 빠릅니다.

---


## 1-1) 현재 수집에서 이미지를 가져오는가?
`project/AWSLambda/unipass_list.py`는 목록 응답(`retrievePbacCmdt.do`)의 각 item에서 이미지 URL 패턴을 스캔해
`image_urls` / `image_count`를 함께 저장합니다.

다만 목록 응답에 이미지 관련 필드가 없으면 결과는 빈 배열이므로, 실사용에서는 아래 보강이 필요합니다.
- 상세 API 호출(공매 상세/첨부) 추가 수집
- 상세 페이지 크롤링으로 이미지 URL 추출
- 이미지 메타는 `auction_item_image` 테이블로 관리(ETL 연동)

---

## 2) 권장 아키텍처 (데모 우선)

1. **수집 레이어**
   - 기존 `project/AWSLambda/unipass_list.py` 유지
   - 스케줄 실행 결과를 `unipass_all.json`으로 저장

2. **적재 레이어(ETL)**
   - 기존 `etl/load_unipass_to_mysql.py` 유지
   - `auction`, `auction_item` UPSERT

3. **분류 레이어 (2단계)**
   - 1단계: 기존 `classification/build_classification.py` rule 분류
   - 2단계: OpenAI 분류기
     - rule 미매칭(fallback) 또는 low confidence 항목만 재분류
     - 결과를 `item_classification`에 `model_name='openai-gpt'`로 UPSERT

4. **API 레이어 (신규)**
   - `backend/`에 검색/상세/필터 API 제공
   - MVP 엔드포인트 예시
     - `GET /items?q=...&category=...`
     - `GET /items/{pbac_no}/{pbac_srno}/{cmdt_ln_no}`
     - `GET /categories/tree`

5. **검증 레이어**
   - 기존 `db/feedback.sql` + OpenAI 평가 쿼리 추가
   - 지표: 미분류율, 카테고리 커버리지, 검색 적중률

---

## 3) DB 구축 전/중 필요한 변경 포인트

### A. 분류 결과 이력 관리 강화 (권장)
현재 `item_classification`을 그대로 쓰되, 아래 컬럼 정책을 명확히 둡니다.
- `model_name`: `rule-v1`, `openai-gpt-5-mini` 등
- `model_ver`: 프롬프트/버전 식별자
- `confidence`: 0~1
- `rationale`: LLM 사유 요약 (짧게)

> 핵심: “어떤 모델이 분류했는지”를 남겨야, 나중에 룰/LLM 품질 비교가 가능합니다.

### B. 재처리 큐 테이블 추가 (권장)
데모 운영 안정성을 위해 `classification_job_queue` 같은 테이블을 추가합니다.
- 대상 키: `(pbac_no, pbac_srno, cmdt_ln_no)`
- 상태: `PENDING/RUNNING/DONE/FAILED`
- 재시도 횟수, 마지막 에러 메세지

> 초기엔 간단히 만들어도 OpenAI API 실패/타임아웃 복구가 쉬워집니다.

### C. 분류 평가용 샘플 정답셋(golden set) 확보
- 빈도 높은 품목 200건 수작업 라벨링
- 룰 분류 vs OpenAI 분류 비교
- 정확도보다 우선순위는 “데모 검색 품질 개선 체감”

---

## 4) 백엔드 구현 순서 (2주 압축안)

### Week 1
1. FastAPI(또는 Flask) 골격 생성
2. MySQL 읽기 API (`/items`, `/categories/tree`) 구현
3. 기존 rule 파이프라인 실행을 배치 스크립트화
4. OpenAI 분류기 프로토타입 작성
   - 입력: `cmdt_nm`, 기존 토큰, 후보 카테고리
   - 출력: `category_path`, `confidence`, `rationale`

### Week 2
1. fallback/저신뢰 항목만 OpenAI 재분류
2. 결과 UPSERT + 로그/비용 집계
3. 검색 API에서 `item_search_token` 활용한 한글 검색 최적화
4. 데모 시나리오 고정
   - 예: “와인”, “배터리”, “차량 부품” 검색/필터

---

## 5) OpenAI 분류 설계 가이드 (실무형)

### 입력 프롬프트 원칙
- 카테고리 트리 전체를 무작정 넣지 말고, **후보군(top-N)** 만 전달
- 출력 스키마 JSON 강제 (`category_path`, `confidence`, `reason`)
- `confidence`가 기준 미달이면 `UNCLASSIFIED` 허용

### 비용/성능 최적화
- 먼저 rule 분류 실행 후, 필요한 케이스만 LLM 호출
- 동일 `cmdt_nm`은 캐시 테이블로 중복 호출 방지
- 배치 처리 시 rate limit 대응(지수 백오프)

### 안전장치
- DB 반영 전 category_path 유효성 검사
- 잘못된 경로면 fallback 카테고리로 저장
- 프롬프트 버전 고정 + 변경 이력 관리

---

## 6) 지금 코드베이스에서 “바꾸면 좋은 점” 요약

1. **README 구조 개선**
   - “현재 완료/진행 중/다음 단계”를 분리해 신규 기여자가 상태를 빠르게 이해하도록 개선

2. **backend 디렉토리 실체화**
   - 최소 서버 실행 코드 + DB 연결 + 헬스체크 추가

3. **classification 모듈 분리**
   - `build_classification.py`를
     - 규칙 엔진,
     - 토크나이저,
     - 저장소 레이어로 분리
   - 이후 OpenAI 분류기 플러그인처럼 연결 가능

4. **운영 스크립트 일원화**
   - `scripts/run_pipeline.sh`로
     - ETL → rule 분류 → openai 분류 → 검증
   - 데모 전 리허설 자동화

---

## 7) 바로 실행 가능한 다음 액션 (우선순위)

1. `backend/` MVP 서버 시작 (조회 API 2개)
2. OpenAI 분류기 1개 스크립트 추가 (`classification/build_classification_openai.py`)
3. `db/`에 큐 테이블 SQL 추가
4. `README`에 데모 실행 시나리오(샘플 쿼리/기대 결과) 추가

---

## 8) 브랜치 전략 제안
- `plan/demo-db-openai-backend` : 계획/설계 문서
- `feat/backend-mvp-api` : 백엔드 API 구현
- `feat/openai-classifier` : OpenAI 분류기 구현
- `chore/db-queue-and-metrics` : 운영 테이블/평가 쿼리

위 순서대로 PR을 분리하면 리뷰/롤백이 쉬워집니다.
