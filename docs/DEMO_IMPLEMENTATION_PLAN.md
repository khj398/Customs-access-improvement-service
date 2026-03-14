# Demo 구현 실행 계획 (로컬 중심: DB 구축 + 데이터 수집 + OpenAI 자동 분류)

## 1) 현재 GitHub 작업 기준 진단
현재 저장소는 **수집(JSON) → ETL(MySQL) → Rule 기반 분류/토큰화**까지는 잘 구성되어 있습니다.
데모를 빠르게 완성하려면 서버 배포보다, **로컬에서 반복 실행 가능한 파이프라인**을 먼저 고정하는 게 효율적입니다.

- API 서버 고도화보다 로컬 재현성(같은 입력 → 같은 결과) 확보가 우선
- OpenAI 기반 분류 파이프라인은 rule 분류 뒤에 보강 단계로 추가
- 운영 문서도 “배포”보다는 “로컬 리허설/검증” 중심으로 정리

즉, 기존 구조를 유지하면서 **rule 1차 + OpenAI 2차 보강**을 로컬 실행 플로우에 붙이는 방식이 가장 안전합니다.

---

## 1-1) 현재 수집에서 이미지를 가져오는가?
현재 수집기는 아래 3개 스크립트로 분리되어 있습니다.
- `project/AWSLambda/UNIPASS_LIST_Business.py`
- `project/AWSLambda/UNIPASS_LIST_Personal.py`
- `project/AWSLambda/UNIPASS_Image.py`

그리고 ETL(`etl/load_unipass_to_mysql.py`)은 아래를 반영합니다.
- 목록 JSON: `unipass_all_2b.json`, `unipass_all_2c.json`
- 이미지 메타 JSON: `unipass_image.json`(있으면)
- 로컬 이미지 폴더: `downloaded_images/<pbac_no>/...`

---

## 2) 권장 아키텍처 (로컬 데모 우선)
1. **수집 레이어 (로컬 실행)**
   - 기존 수집기 3종을 로컬에서 순차 실행
   - 산출물: `unipass_all_2b.json`, `unipass_all_2c.json`, `unipass_image.json`

2. **적재 레이어 (로컬 MySQL)**
   - `etl/load_unipass_to_mysql.py` 실행
   - `auction`, `auction_item`, `auction_item_image` UPSERT

3. **분류 레이어 (2단계)**
   - 1단계: `classification/build_classification.py` (rule)
   - 2단계: OpenAI 분류기(추가 스크립트)
     - rule 미매칭/저신뢰 항목만 재분류
     - `item_classification`에 `model_name` 구분 저장

4. **조회/검증 레이어 (서버 없이 SQL 중심)**
   - `db/feedback.sql` + 추가 검증 SQL로 품질 점검
   - 필요 시 로컬 스크립트/노트북으로 검색 시나리오 재현

---

## 3) DB 구축 전/중 필요한 변경 포인트
### A. 분류 결과 이력 관리 강화 (권장)
`item_classification` 컬럼 정책을 명확히 유지합니다.
- `model_name`: `rule-v1`, `openai-gpt-5-mini` 등
- `model_ver`: 프롬프트/버전 식별자
- `confidence`: 0~1
- `rationale`: 분류 사유 요약

### B. 재처리 큐 테이블 활용
`schema_patch_v2.sql`의 큐 테이블을 활용해 로컬 재시도 흐름을 단순화합니다.
- 상태: `PENDING/RUNNING/DONE/FAILED`
- 재시도 횟수, 마지막 에러 메세지 기록

### C. 분류 평가용 샘플 정답셋(golden set) 확보
- 빈도 높은 품목 200건 수작업 라벨링
- rule vs OpenAI 비교
- 정확도뿐 아니라 검색 체감 품질을 함께 평가

---

## 4) 로컬 구현 순서 (2주 압축안)
### Week 1
1. 로컬 MySQL 스키마/시드 적용
2. 수집 스크립트 3종 실행 → JSON 생성
3. ETL 실행으로 DB 적재
4. rule 분류 실행 및 결과 확인
5. OpenAI 분류기 프로토타입(스크립트형) 작성

### Week 2
1. 저신뢰/미분류 항목만 OpenAI 재분류
2. 결과 UPSERT + 비용/실패 로그 기록
3. 검색 검증 SQL/노트북 정리
4. 데모 시나리오 고정
   - 예: “와인”, “배터리”, “차량 부품”

---

## 5) OpenAI 분류 설계 가이드 (실무형)
### 입력 프롬프트 원칙
- 카테고리 트리 전체 대신 후보군(top-N)만 전달
- 출력 JSON 스키마 강제 (`category_path`, `confidence`, `reason`)
- 기준 미달 시 `UNCLASSIFIED` 허용

### 비용/성능 최적화
- rule 분류 후 필요한 케이스만 LLM 호출
- 동일 `cmdt_nm` 캐시로 중복 호출 방지
- 배치 시 rate limit 대응(지수 백오프)

### 안전장치
- DB 반영 전 `category_path` 유효성 검사
- 오류 경로는 fallback 카테고리로 저장
- 프롬프트 버전 관리

---

## 6) 지금 코드베이스에서 우선 바꾸면 좋은 점
1. **README 실행 절차를 로컬 기준으로 고정**
   - 수집 → ETL → 분류 → 검증 순서 명확화
2. **로컬 오케스트레이션 스크립트 추가**
   - 예: `scripts/run_local_demo.sh`
3. **OpenAI 분류기 분리 스크립트 추가**
   - 예: `classification/build_classification_openai.py`
4. **검증 SQL 세트 강화**
   - 미분류율/카테고리 커버리지/검색 적중률 확인

---

## 7) 바로 실행 가능한 다음 액션 (우선순위)
1. 로컬 DB 초기화 + 시드 적용
2. 수집 스크립트 3종 실행
3. ETL + rule 분류 실행
4. OpenAI 보강 분류 스크립트 연결
5. `db/feedback.sql`로 결과 검증 후 데모 리허설

---

## 8) 브랜치 전략 제안
- `plan/demo-local-openai` : 로컬 데모 계획/문서
- `feat/openai-classifier-local` : OpenAI 분류기 스크립트
- `chore/local-demo-orchestration` : 로컬 실행 스크립트/검증 자동화

위 순서대로 PR을 분리하면 리뷰/롤백이 쉬워집니다.
