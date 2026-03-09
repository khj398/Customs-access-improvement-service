# Automatic Item Classification Guide

## 1. 자동 분류 도입 배경
관세청 유니패스 공매 사이트는 공매 물품에 대해 제한적인 분류 정보를 제공한다.
기존 분류 체계는 대분류 위주로 구성되어 있으며, 분류 기준이 명확하지 않아
사용자가 원하는 물품을 탐색하는 데 많은 시간과 노력이 필요하다.

또한 공매 물품명은 대부분 영문으로 제공되며,
동일하거나 유사한 물품임에도 불구하고 표기 방식이 제각각인 경우가 많다.
이로 인해 단순 키워드 검색만으로는 원하는 물품을 정확히 찾기 어렵고,
한글 키워드(예: “와인”, “배터리”)로는 검색이 불가능하다는 문제가 존재한다.

본 프로젝트에서는 이러한 문제를 해결하기 위해
공매 물품명을 기반으로 한 **자동 분류 시스템**을 도입한다.
자동 분류를 통해 물품을 의미 단위의 카테고리로 정리하고,
이를 검색·필터·알림 기능의 기반 데이터로 활용하는 것을 목표로 한다.

---

## 2. 자동 분류의 목표와 범위

### 2.1 분류 대상
자동 분류의 대상은 공매 물품 테이블(`auction_item`)에 저장된 **물품 라인 단위 데이터**이다.

실제 데이터 분석 결과,
하나의 공매번호 및 일련번호 내에서도 여러 개의 물품 라인(`cmdtLnNo`)이 존재할 수 있으므로,
본 프로젝트에서는 다음 조합을 하나의 분류 단위로 정의한다.

- **(pbac_no, pbac_srno, cmdt_ln_no)**

이는 실제 공매 물품 1건을 안정적으로 식별하기 위한 최소 단위이다.

### 2.2 분류 결과의 활용 범위
자동 분류 결과는 다음 기능에 활용된다.

- 카테고리 기반 물품 탐색
- 검색 필터링 (대/중/소/세 단위)
- 검색 토큰 생성 (한글/동의어 검색)
- 관심 물품 알림 조건 설정

분류 결과는 원본 데이터를 직접 수정하지 않고,
별도의 테이블(`item_classification`)에 저장하여 관리한다.
이를 통해 분류 로직이나 모델이 변경되더라도 원본 데이터의 무결성을 유지할 수 있다.

---

## 3. 자동 분류 파이프라인 개요
자동 분류는 다음 단계로 구성된다.

1. **원본 데이터 입력**
   - `auction_item.cmdt_nm` (영문 물품명)
2. **전처리**
   - 대소문자 통일, 특수문자 제거, 토큰화(Tokenization)
3. **분류 로직 적용**
   - Rule-based 분류 (키워드 기반)
   - (확장 예정) AI/NLP 기반 분류
4. **분류 결과 저장**
   - `category_id`, `model_name`, `model_ver`, `confidence`, `rationale`
5. **검색 토큰 생성**
   - RAW / SYN / CATEGORY 토큰 생성 후 `item_search_token`에 저장

---

## 4. 실행 방법

### 4.1 사전 준비(필수)
- DB 스키마 및 seed 입력이 완료되어 있어야 한다.  
  (`db/schema_create.sql`, `db/seed_category*.sql`, `db/seed_synonym*.sql`)
- `auction_item` 테이블에 ETL로 데이터가 적재되어 있어야 한다.  
  (`etl/load_unipass_to_mysql.py`)

### 4.2 실행
분류 + 토큰 생성은 아래 스크립트 하나로 수행된다.

```bash
pip install pymysql
python classification/build_classification.py

옵션
python classification/build_classification.py --limit 20
python classification/build_classification.py --dry-run --limit 20

### 4.3 결과 저장 테이블
item_classification : 품목(라인)별 분류 결과 저장(UPSERT)
item_search_token : 검색 토큰 저장(UPSERT)
RAW: 원문(영문) 토큰
SYN: synonym_dictionary 기반 동의어/번역 토큰
CATEGORY: 분류 결과 카테고리 경로 토큰
본 스크립트는 UPSERT 기반이므로 재실행해도 안전하다.

---

## 5. 룰 기반 분류 설계 원칙

### 5.1 룰 정의 방식
룰은 build_classification.py 내부 build_rules()에서 관리한다.
keywords_all: 반드시 포함되어야 하는 토큰 집합
keywords_any: 하나라도 포함되면 매칭되는 토큰 집합
category_path: DB의 category 트리 경로(한글)
base_conf: 기본 신뢰도
rationale_hint: 근거 문구

### 5.2 룰 우선순위(중요)
룰은 리스트의 위에서부터 순서대로 처음 매칭되는 룰이 적용된다.
따라서 다음 원칙을 권장한다.
구체적인 룰을 위에 배치
예: CAR/VEHICLE + AIR + CONDITIONING
일반적인(완화된) 룰은 아래에 배치
예: AIR + CONDITIONING만 있는 케이스

### 5.3 토큰화 특징 및 흔한 실수
하이픈(AIR-CONDITIONING)은 보통 토큰이 AIR, CONDITIONING으로 분리될 수 있다.
복수형(GAUGES, COCKTAILS, MAKERS)은 단수형 룰만 있으면 매칭이 누락될 수 있다.
룰이 매칭되었는데도 분류가 fallback으로 저장될 경우,
category_path가 DB에 존재하지 않는 경우가 많다.
해결: db/seed_category_extend.sql에 해당 경로를 추가

---

## 6. 검색 토큰(SYN) 사전 확장 가이드

### 6.1 synonym_dictionary의 역할
synonym_dictionary는 영문 키워드를 한글/동의어로 확장하여
한글 검색(예: “와인”, “배터리”)을 가능하게 한다.
예: WINE → 와인 / 술 / 주류
예: GAUGES → 게이지 / 측정기 / 계측기

### 6.2 확장 방법
사전은 db/seed_synonym.sql / db/seed_synonym_extend.sql에 추가한다.
seed 실행 후 build_classification.py를 재실행하면 SYN 토큰이 생성된다.

## 7. 결과 검증(추천)
DB 결과 검증은 db/feedback.sql 사용을 권장한다.
분류 성공/미분류(fallback) 개수 확인
fallback 항목의 RAW 토큰 TOP 분석 → 룰/사전 확장 근거
특정 검색어(와인/술/주류 등) 토큰 존재 여부 확인


---

## 8. LLM 분류(Fallback) 실행

`build_classification_openai.py`는 rule 분류 결과 중 저신뢰 항목을 큐에 넣고 OpenAI로 재분류한다.

```bash
python classification/build_classification_openai.py --enqueue-low-confidence --min-confidence 0.60 --limit 30
```

환경 변수:
- `OPENAI_API_KEY` (필수)
- `OPENAI_MODEL` (선택, 기본: `gpt-4o-mini`)
- `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`

작동 방식:
1. `classification_job_queue`에서 `PENDING` 작업 조회
2. 동일 물품명은 `llm_classification_cache`에서 캐시 재사용
3. 결과를 `item_classification`에 UPSERT
4. 큐 상태를 `DONE/FAILED`로 갱신
