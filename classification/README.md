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
   - OpenAI fallback 분류 (룰 미매칭 시 선택적으로 적용)
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

### 4.1.1 DB 접속 설정(중요)
`build_classification.py`는 기본값으로 `127.0.0.1:3306`, `root`, `customs_auction`에 접속한다.
로컬 환경이 다르면 실행 전에 환경변수로 DB 접속 정보를 지정한다.

```bash
# macOS/Linux bash
export DB_HOST=127.0.0.1
export DB_PORT=3306
export DB_USER=root
export DB_PASSWORD=<YOUR_DB_PASSWORD>
export DB_NAME=customs_auction

# Windows PowerShell
$env:DB_HOST="127.0.0.1"
$env:DB_PORT="3306"
$env:DB_USER="root"
$env:DB_PASSWORD="<YOUR_DB_PASSWORD>"
$env:DB_NAME="customs_auction"
```

`Access denied for user 'root'@'localhost' (1045)`가 나오면 비밀번호뿐 아니라 계정의 허용 호스트(`localhost` vs `127.0.0.1`) 권한도 확인해야 한다.

### 4.2 실행
분류 + 토큰 생성은 아래 스크립트 하나로 수행된다.

```bash
pip install pymysql openai
python classification/build_classification.py

# 옵션
python classification/build_classification.py --limit 20
python classification/build_classification.py --dry-run --limit 20

# OpenAI fallback 분류 활성화 (macOS/Linux bash)
export OPENAI_API_KEY="<YOUR_API_KEY>"
python classification/build_classification.py --use-openai --openai-model gpt-4o-mini

# OpenAI 반드시 사용되어야 할 때(초기화 실패 시 즉시 종료)
python classification/build_classification.py --use-openai --openai-model gpt-4o-mini --strict-openai

# OpenAI fallback 분류 활성화 (Windows PowerShell)
$env:OPENAI_API_KEY="<YOUR_API_KEY>"
python classification/build_classification.py --use-openai --openai-model gpt-4o-mini

# OpenAI fallback 분류 활성화 (Windows CMD)
set OPENAI_API_KEY=<YOUR_API_KEY>
python classification/build_classification.py --use-openai --openai-model gpt-4o-mini
```

### 4.3 OpenAI 오류 해결 (자주 발생)
`⚠️ OpenAI client init failed: No module named 'openai'` 오류는 OpenAI Python SDK가 설치되지 않았다는 의미다.

```bash
# 현재 실행 중인 파이썬에 설치 (권장)
python -m pip install openai

# 또는 환경에 따라
pip install openai

# Conda 환경이라면
conda install -c conda-forge openai
```

가상환경(venv/conda)을 사용 중이라면, `build_classification.py`를 실행하는 **동일한 인터프리터**에 설치해야 한다.
아래로 설치 위치를 점검할 수 있다.

```bash
python -m pip show openai
```

`--use-openai`를 줬는데도 OpenAI 초기화가 실패하면 기본 동작은 rule/fallback으로 계속 진행한다.
OpenAI 사용이 필수라면 `--strict-openai` 옵션을 같이 사용해 초기화 실패 시 즉시 종료하도록 설정한다.

`openai` 패키지는 설치되어 있는데도 `from openai import OpenAI` 오류가 나면 구버전(0.x)일 수 있다.
스크립트는 구버전 SDK도 자동 호환 시도하지만, 가능하면 최신 버전으로 업그레이드하는 것을 권장한다.

```bash
python -m pip install -U openai
```

`Error code: 429` + `insufficient_quota`가 나오면 API 키 문제라기보다 크레딧/요금제 한도 문제다.
- OpenAI Platform에서 Billing/Usage를 확인하고 결제수단/크레딧을 점검한다.
- 한도가 복구되기 전까지는 스크립트가 OpenAI를 자동 비활성화하고 rule/fallback으로 계속 진행한다.

### 4.4 결과 저장 테이블
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

## 8. 파일 구조

```
classification/
├─ build_classification.py   # 핵심 분류 엔진 (1,100+ 줄)
├─ auto_rule_builder.py      # Fallback 자동 규칙 생성기
├─ run_classification.py     # 환경변수 래퍼 (build_classification.py 호출)
├─ load_synonyms.py          # 동의어 사전 DB 로드 유틸
├─ rules.yaml                # 분류 규칙 정의 파일
├─ synonyms.yaml             # 동의어/번역 사전
└─ eval/
   ├─ accuracy_report.txt    # 최근 파이프라인 실행 통계
   ├─ evaluate.py            # ground_truth 기반 정확도 평가
   ├─ ground_truth.csv       # 수동 라벨 정답 데이터
   ├─ check_db.py            # DB 무결성 검사
   ├─ db_setup_kitchen.py    # 테스트 데이터 셋업
   ├─ label_update.py        # 수동 라벨 업데이트 유틸
   ├─ fix_labels.py          # 라벨 수정 스크립트
   ├─ refresh_auto.py        # 자동 분류 새로고침
   └─ rule_suggestions.txt   # auto_rule_builder 검토 목록 (자동 생성)
```

### `build_classification.py`
핵심 분류 엔진. DB에서 모든 `auction_item`을 읽어 분류 결과를 `item_classification`에, 검색 토큰을 `item_search_token`에 저장합니다.

주요 함수:
- `normalize_text(s)` — 대문자화, 공백 정리
- `extract_raw_tokens(norm)` — A-Z0-9 기준 토큰 분리 (2자 이상)
- `build_rules(rules_path)` — rules.yaml 로드 (없으면 하드코딩 fallback)
- `CategoryResolver` — category 트리를 메모리에 적재, 경로↔ID 변환
- `classify_with_openai(name, resolver, model)` — OpenAI gpt-4o-mini 호출
- `main()` — 전체 파이프라인 실행

### `auto_rule_builder.py`
Fallback(기타/미분류) 물품을 자동으로 분석해 `rules.yaml`에 규칙을 추가합니다.  
`build_classification.py`의 `normalize_text`, `extract_raw_tokens`, `CategoryResolver`를 import하여 재사용합니다.

**5단계 처리:**

| 단계 | 내용 |
|------|------|
| Phase 1 | DB에서 fallback 물품 조회 (`category.name_ko = '기타'` 또는 미분류) |
| Phase 2 | 단일 토큰·2-gram 빈도 분석 → `--min-count` 이상 패턴 추출 |
| Phase 3 | OpenAI에 패턴별 카테고리 제안 요청 (배치) |
| Phase 4 | confidence ≥ threshold → `rules.yaml` 자동 추가 / 미달 → `eval/rule_suggestions.txt` 기록 |
| Phase 5 | 규칙 추가 시 `--rule-only-update` 재분류 실행 |

**안전 장치:**
- 쓰기 전 `rules.yaml.bak.{timestamp}` 백업 (최근 5개 유지)
- category_path DB 존재 확인
- 중복 rule ID 체크
- `--dry-run` — 파일/DB 미수정, 결과만 출력

```bash
# 파일 미수정, 제안만 출력
python classification/auto_rule_builder.py --dry-run --min-count 3

# 실제 적용 (기본 threshold=0.85)
python classification/auto_rule_builder.py --min-count 5 --confidence 0.85

# 재분류 생략
python classification/auto_rule_builder.py --no-rerun
```

### `rules.yaml`
Rule 기반 분류 규칙 파일. 각 규칙의 구조:

```yaml
rules:
  - id: alcohol_wine           # 고유 식별자
    priority: 10               # 낮을수록 먼저 평가
    keywords_any:              # 하나라도 포함되면 매칭 (OR)
      - WINE
      - WHISKY
    keywords_all: []           # 전부 포함되어야 매칭 (AND)
    category_path:             # DB category 트리 경로
      - 식품·음료
      - 음료
      - 주류
    confidence: 0.88
    rationale: "주류 키워드 직접 매칭"
```

규칙 추가 기준 (주석 참조):
- 5건 이상 fallback 물품이 동일 키워드 패턴 → 규칙 추가 검토
- OpenAI가 동일 카테고리를 3건 이상·confidence ≥ 0.85로 제안 → 규칙 승격
- 해당 카테고리에 6개월 이상 물품 0건 → 규칙 삭제 검토

### `synonyms.yaml`
영문 키워드 → 한글/동의어 매핑. DB의 `synonym_dictionary`와 동기화.  
`load_synonyms.py`로 DB에 적재합니다.

### `eval/evaluate.py`
`eval/ground_truth.csv`와 실제 DB 분류 결과를 비교해 정확도(accuracy) 지표를 계산합니다.

### `eval/rule_suggestions.txt`
`auto_rule_builder.py`가 자동 생성하는 검토 파일.  
threshold 미달 패턴을 YAML 블록 형식으로 출력하며, 내용을 확인 후 `rules.yaml`에 수동으로 붙여넣을 수 있습니다.
