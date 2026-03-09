# DB Redesign Discussion (Auction Core v2)

## 목표
- 공매 물품 라인 단위 키 `(pbac_no, pbac_srno, cmdt_ln_no)`를 기준으로 데이터 무결성 확보
- 규칙 기반 분류 결과를 기본값으로 저장하고, LLM 분류로 fallback/저신뢰 항목 보강
- 재처리 가능한 큐 기반 운영 구조 확보

## 핵심 설계
1. **정규화된 공매 스키마 유지**
   - `auction`(상위 이벤트) / `auction_item`(라인 물품) 1:N
2. **분류 결과 단일 대표 저장**
   - `item_classification` 1행/물품
   - `model_name`, `model_ver`, `confidence`, `rationale`로 추적성 확보
3. **운영 테이블 추가**
   - `classification_job_queue`: LLM 재처리 대상 큐
   - `llm_classification_cache`: 동일 품목명 중복 호출 방지 캐시

## 분류 파이프라인
1. `classification/build_classification.py`
   - 규칙 기반 분류 + 검색 토큰 생성
2. `classification/build_classification_openai.py`
   - queue에서 `PENDING` 대상 조회
   - OpenAI 호출 후 category 경로 검증
   - `item_classification` UPSERT
   - 성공/실패를 queue 상태로 기록

## 큐 처리 정책
- 상태: `PENDING`, `RUNNING`, `DONE`, `FAILED`
- `max_retries` 이하에서는 실패 시 `PENDING`으로 되돌려 재시도
- 카테고리 경로가 DB에 없으면 fallback 카테고리(`기타 > 미분류 > 기타`) 적용

## 운영 권장 순서
1. `db/schema_create.sql`
2. `db/seed_category.sql`
3. `db/seed_category_extend.sql`
4. `db/seed_synonym.sql`
5. `db/seed_synonym_extend.sql`
6. `python etl/load_unipass_to_mysql.py`
7. `python classification/build_classification.py`
8. `python classification/build_classification_openai.py --enqueue-low-confidence`
