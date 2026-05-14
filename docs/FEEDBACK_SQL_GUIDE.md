# feedback.sql 체크 가이드

> **파일 위치**: `db/feedback.sql`  
> **실행 시점**: ETL 실행 직후 / `build_classification.py` 실행 직후 / 스키마 패치 적용 직후

---

## 전체 구성 한눈에 보기

| 섹션 | 제목 | 실행 시점 |
|------|------|----------|
| 0 | 전체 상태 요약 | 분류 파이프라인 실행 후 항상 |
| 0-1 | 특정 토큰 검색 토큰 존재 여부 | 검색 기능 테스트 전 |
| 1 | fallback(미분류) 분석 | 분류 품질 점검 시 |
| 1-1 | fallback 토큰 TOP 20 | Rule/사전 보강 계획 수립 시 |
| 1-2 | 특정 토큰이 포함된 fallback 항목 | Rule 디버깅 시 |
| 2 | synonym_dictionary 확인 | 사전 품질 점검 시 |
| 3 | 전체 물품 확인 | 데이터 전체 흐름 점검 시 |
| 4 | 검토용 VIEW | 반복 조회 시 |
| sanity | 빠른 최종 확인 3종 | 파이프라인 완료 직후 항상 |
| 5 | 스키마 v3 패치 후 정합성 확인 | schema_patch_v3.sql 적용 직후 |

---

## 섹션 0 — 전체 상태 요약

### 쿼리 1: classification_rows / token_rows 건수

```sql
SELECT COUNT(*) AS classification_rows FROM item_classification;
SELECT COUNT(*) AS token_rows FROM item_search_token;
```

**왜 체크하는가**

ETL과 분류 스크립트가 예외 없이 종료했더라도 실제로 DB에 데이터가 들어갔는지는 별도로 확인해야 한다. 다음 상황에서 스크립트가 정상 종료하면서도 0건이 적재된다.

- 입력 JSON 파일이 비어있거나 경로가 잘못됨
- `auction_item`에 데이터가 없어 분류 대상 자체가 없음
- 트랜잭션 rollback이 발생했으나 오류 메시지를 놓침

| 결과 | 의미 |
|------|------|
| `classification_rows = 0` | 분류 미실행 또는 `auction_item` 비어있음 |
| `token_rows = 0` | 검색 토큰 미생성 → 검색 기능 전체 불능 |

---

### 쿼리 2: 토큰 타입별 생성 현황

```sql
SELECT token_type, COUNT(*) AS cnt
FROM item_search_token
GROUP BY token_type
ORDER BY cnt DESC;
```

**왜 체크하는가**

`build_classification.py`는 물품 1건당 세 종류 토큰을 생성한다.

- **RAW**: 원문 영문 토큰 (예: `WINE`, `BATTERY`)
- **SYN**: 동의어·번역 토큰 (예: `와인`, `배터리`)
- **CATEGORY**: 분류 카테고리 토큰 (예: `주류`, `식품·음료 > 음료 > 주류`)

| 상태 | 의미 | 조치 |
|------|------|------|
| RAW만 존재, SYN·CATEGORY = 0 | 동의어 사전 비어있거나 카테고리 seed 없음 | `seed_synonym.sql` / `seed_category.sql` 재실행 |
| SYN은 있지만 CATEGORY = 0 | 분류는 됐으나 카테고리 트리 조회 실패 | `category` 테이블 seed 누락 확인 |
| 세 타입 모두 존재 | 정상 |  |

---

### 쿼리 3: 카테고리별 분류 건수 (상위 20)

```sql
SELECT c.category_id, c.name_ko AS category, COUNT(*) AS cnt
FROM item_classification ic
JOIN category c ON c.category_id = ic.category_id
GROUP BY c.category_id, c.name_ko
ORDER BY cnt DESC
LIMIT 20;
```

**왜 체크하는가**

분류 결과가 특정 카테고리에 과도하게 몰려 있으면 Rule/사전 커버리지가 편중된 것이다.

> **GROUP BY를 `category_id`로 하는 이유**  
> 서로 다른 레벨에 동일한 `name_ko`('기타' 등)가 존재한다. `name_ko`만으로 그루핑하면 별개 카테고리가 합산되어 수치가 왜곡된다. `category_id`로 그루핑해야 각 카테고리를 정확히 구분할 수 있다.

| 패턴 | 의미 |
|------|------|
| '기타 > 미분류 > 기타'가 압도적으로 많음 | Rule 45개로 분류 가능한 품목이 적음 → Rule/사전 보강 필요 |
| 특정 카테고리 1~2개에 집중 | 해당 카테고리 Rule만 작동 중 |
| 고르게 분산 | 커버리지 양호 |

---

### 쿼리 4: 분류 결과 샘플 (최근 30건)

**왜 체크하는가**

숫자만으로는 분류 품질을 파악하기 어렵다. 실제 물품명과 카테고리를 눈으로 대조해 "이 물품이 이 카테고리에 맞는가"를 직관적으로 검토한다.

| 컬럼 | 확인 포인트 |
|------|------------|
| `model_name` | `rule`인지 `openai`인지 — OpenAI 미사용 시 `openai` 행 없어야 함 |
| `confidence` | 0.55 근처가 많으면 fallback이거나 매칭 키워드가 적음 |
| `rationale` | 왜 이 카테고리로 분류됐는지 근거 텍스트 — 이상한 근거 발견 시 Rule 점검 |

---

## 섹션 0-1 — 특정 토큰 검색 가능 여부

```sql
WHERE t.token IN ('와인','술','주류','WINE')
```

**왜 체크하는가**

동의어 사전과 분류 파이프라인이 정상 동작한다면 영문 원문 토큰 `WINE`을 기반으로 한국어 동의어(`와인`, `술`, `주류`)와 카테고리 토큰이 함께 생성되어야 한다.

이 쿼리는 **"WINE이 들어간 물품을 '와인'으로 검색했을 때 결과가 나오는가"를 사전에 보장**하는 용도다.

| 결과 | 의미 |
|------|------|
| 0건 | 동의어 사전 seed 누락 또는 분류 파이프라인 미실행 |
| SYN/CATEGORY 토큰 없이 RAW만 | 사전에 등록은 됐지만 분류 파이프라인에서 사전이 로드되지 않음 |
| 모든 타입 존재 | 정상, 해당 키워드로 검색 가능 |

> `IN` 절의 토큰을 바꿔가며 다른 품목도 동일하게 검증한다.

---

## 섹션 1 — fallback(미분류) 분석

### 쿼리: fallback 목록

**왜 체크하는가**

`build_classification.py`는 Rule 매칭 실패 + OpenAI 없거나 실패 시 `기타 > 미분류 > 기타`로 분류한다(fallback). 이 항목들은:

1. 검색에서 카테고리 필터로 걸러지지 않아 관련 없는 결과에 섞여 노출됨
2. 카테고리 토큰 품질이 낮아 검색 정확도가 떨어짐

fallback 건수와 내용을 확인해 Rule 또는 동의어 사전 보강의 우선순위를 결정한다.

---

### 섹션 1-1: fallback 항목의 RAW 토큰 TOP 20

**왜 체크하는가**

fallback으로 떨어진 물품명에서 자주 등장하는 영문 토큰이 Rule이나 동의어 사전에 없기 때문에 분류에 실패한 것이다.

이 목록은 **"어떤 키워드를 `rules.yaml` 또는 `synonym_dictionary`에 추가하면 fallback을 가장 많이 줄일 수 있는가"의 직접적인 우선순위 가이드**다. 상위 토큰부터 처리하는 것이 효율적이다.

---

### 섹션 1-2: 특정 토큰이 포함된 fallback 항목

```sql
AND t.token='GAUGE'
```

**왜 체크하는가**

`GAUGE`가 `rules.yaml`에 등록되어 있는데도 fallback인 물품이 있다면 Rule 조건이 잘못 작성된 것이다. 예를 들어:

- `keywords_all` 조건이 너무 엄격해 다른 필수 키워드도 있어야 매칭됨
- 토큰 전처리 과정에서 원문이 다르게 변환됨 (예: 특수문자 포함)

1-1에서 발견한 키워드를 이 쿼리에 하나씩 입력해 실제 물품명을 확인하고 Rule 수정 여부를 판단한다.

---

## 섹션 2 — synonym_dictionary 확인

### 쿼리 1: term_type별 건수

**왜 체크하는가**

동의어 사전은 영문 물품명을 한국어로 검색 가능하게 만드는 핵심 구성요소다.

| term_type | 역할 | 없을 때 문제 |
|-----------|------|-------------|
| `TRANSLATION` | 영문 → 한국어 번역 (WINE → 와인) | 한국어 검색 자체가 불가 |
| `SYN` | 동의어 확장 (와인 → 술, 포도주) | 유사 표현으로 검색 불가 |
| `CATEGORY_HINT` | 카테고리 경로 힌트 | 카테고리 기반 확장 검색 미동작 |

---

### 쿼리 2: 특정 원본어의 사전 등록 내용

**왜 체크하는가**

집계만으로는 실제로 어떤 한국어 표현이 연결되어 있는지 알 수 없다. 검색 테스트 전에 대표 키워드의 `norm_term`, `term_type`, `weight`를 직접 확인해 "이 키워드로 검색하면 어떤 토큰이 매칭되는가"를 파악한다.

> `weight`가 낮으면 검색 결과 순위가 뒤로 밀린다. 중요한 동의어는 weight를 높게 설정해야 한다.

---

## 섹션 3 — 전체 물품 확인

### 전체 물품 한 번에 보기 (메인 쿼리)

**왜 체크하는가**

물품명, 수량, 중량, 가격, 세관, 창고, 분류 결과, 카테고리 경로 토큰, 동의어 토큰을 한 행으로 조회해 데이터 전체 흐름을 한눈에 검토한다.

| 컬럼 | NULL이면 의미하는 것 |
|------|-------------------|
| `customs_office` | ETL 당시 세관 정보 없음 (원천 데이터 품질 문제) |
| `bonded_warehouse` | ETL 당시 창고 정보 없음 |
| `category_leaf` | 분류 미실행 또는 item_classification에 해당 행 없음 |
| `category_path_token` | CATEGORY 토큰 미생성 (분류는 됐지만 카테고리 트리 조회 실패) |
| `syn_tokens_sample` | 동의어 사전에 해당 물품 키워드 없음 → 한국어 검색 불가 |

---

### pbac_no당 pbac_srno 개수 확인

**왜 체크하는가**

공매번호(`pbac_no`) 하나에 여러 일련번호(`pbac_srno`)가 붙는지 실제 데이터로 확인한다.

| 결과 | 의미 |
|------|------|
| `srno_cnt > 1`인 공매 다수 | `(pbac_no, pbac_srno)`가 실제 중간 그룹핑 단위로 사용 중 |
| 항상 `srno_cnt = 1` | `pbac_no`만으로 공매 특정 가능 → 현재 `auction` PK 설계 적합 확인 |

---

### (A) 공매 요약 / (B) 전체 라인 상세

- **(A)**는 어느 세관·창고에서 얼마나 많은 물품이 나오는지 집계 수준으로 확인한다. `line_cnt`가 많은 공매번호는 분류 파이프라인 실행 시간에 영향을 주므로 사전에 인지한다.
- **(B)**는 (A)에서 이상이 발견된 공매번호를 라인 단위로 드릴다운해 분류·검색 파이프라인이 각 라인에서 정상 동작했는지 본다.

---

## 섹션 4 — 검토용 VIEW

**왜 체크하는가**

섹션 3의 쿼리는 길고 JOIN이 많아 반복 실행이 번거롭다. `vw_item_classification_review`를 한 번 생성해두면 이후 `SELECT * FROM vw_...` 한 줄로 같은 내용을 조회할 수 있다.

| 예시 | 용도 |
|------|------|
| `ORDER BY updated_at DESC` | 파이프라인 실행 직후 최신 분류 결과 빠른 확인 |
| `WHERE category_lv1='기타'...` | fallback 건만 추려서 Rule/사전 보강 우선순위 파악 |
| `WHERE model_name='openai'` | LLM 분류 품질만 집중 점검 |

---

## sanity check 3종

**왜 체크하는가**

파이프라인 완료 직후 가장 기본적인 이상 유무를 수치로 빠르게 확인한다. **세 쿼리 모두 0이 나와야 정상**이다.

| 쿼리 | 0이 아닐 때 의미 | 조치 |
|------|----------------|------|
| `missing_class` | 분류가 누락된 물품 존재 → 카테고리 필터 검색에서 제외됨 | `build_classification.py` 재실행, 로그에서 에러 확인 |
| `missing_tokens` | 토큰 없는 물품 존재 → 해당 물품은 키워드 검색에서 아예 안 나옴 | 분류는 됐지만 토큰 생성 단계 에러 → 파이프라인 재실행 |
| `bad_category_tokens` | `'기타'`/`'미분류'` CATEGORY 토큰 존재 → 관련 없는 물품이 함께 검색됨 | `CATEGORY_STOPWORDS` 필터 동작 확인, 토큰 재생성 |

---

## 섹션 5 — 스키마 v3 패치 후 데이터 정합성 확인

> `schema_patch_v3.sql` 적용 직후 반드시 실행한다.

---

### 쿼리 1: `atnt_cmdt` ENUM 값 분포

```sql
SELECT atnt_cmdt, COUNT(*) AS cnt
FROM auction_item
GROUP BY atnt_cmdt;
```

**왜 체크하는가**

`atnt_cmdt`를 `CHAR(1)`에서 `ENUM('Y','N')`으로 변경했다. ENUM 마이그레이션 시 기존 데이터 중 `'Y'`/`'N'`/`NULL` 이외의 값이 있었다면 MySQL이 해당 행을 빈 문자열(`''`)로 강제 변환하거나 INSERT를 거부했을 수 있다.

| 결과 | 의미 | 조치 |
|------|------|------|
| `Y`, `N`, `NULL`만 있음 | 정상 | 없음 |
| `''`(빈 문자열) 또는 다른 값 존재 | 원천 데이터에 비정상 값이 있었음 | 해당 행 확인 후 `UPDATE`로 보정 |

---

### 쿼리 2: `cmdt_qty` 소수 수량 존재 여부

```sql
WHERE cmdt_qty IS NOT NULL
  AND cmdt_qty != FLOOR(cmdt_qty)
```

**왜 체크하는가**

`cmdt_qty`를 `INT`에서 `DECIMAL(12,2)`로 변경한 이유는 소수점 수량(예: 0.5 KG, 2.75개)이 실제 데이터에 존재할 수 있기 때문이다.

| 결과 | 의미 |
|------|------|
| 0건 | 현재 데이터에는 소수 수량 없음. INT 시절 데이터 손실 없었음을 확인. 마이그레이션 안전 완료 |
| 건수 있음 | 기존에 INT로 잘렸던 값들이 DECIMAL로 올바르게 저장됨. ETL 재실행 시 정확한 소수 수량 반영 |

---

### 쿼리 3: `synonym_dictionary` 중복 확인

```sql
SELECT src_term, norm_term, COUNT(*) AS cnt,
       GROUP_CONCAT(CONCAT(lang,'/',term_type) ORDER BY lang SEPARATOR ' | ') AS variants
FROM synonym_dictionary
GROUP BY src_term, norm_term
HAVING cnt > 1
ORDER BY cnt DESC;
```

**왜 체크하는가**

UNIQUE 제약을 `(src_term, norm_term)` 2컬럼에서 `(src_term, norm_term, lang, term_type)` 4컬럼으로 변경했다.

이제 동일한 `(src_term, norm_term)` 쌍이 `lang` 또는 `term_type`이 다르면 별개 레코드로 공존할 수 있다.

예)
```
WINE → 와인  (EN, TRANSLATION)  ← 서로 다른 레코드로 공존 가능
WINE → 와인  (KO, SYN)
```

| `variants` 컬럼 내용 | 의미 |
|---------------------|------|
| `EN/TRANSLATION \| KO/SYN` 등 서로 다른 조합 | 의도한 분리 → 정상 |
| 동일한 `lang/term_type`이 2개 이상 | seed 파일에 중복 오류 → `seed_synonym.sql` 점검 |

---

### 쿼리 4: `category` 고아 노드 확인

```sql
SELECT COUNT(*) AS orphan_categories
FROM category
WHERE parent_id IS NULL AND level > 1;
```

**왜 체크하는가**

`category` 테이블의 FK를 `ON DELETE SET NULL`에서 `ON DELETE RESTRICT`로 변경했다.

`ON DELETE SET NULL`이던 시절, 부모 카테고리가 삭제되면 자식의 `parent_id`가 `NULL`로 바뀌어 `level > 1`인 카테고리가 마치 최상위처럼 동작하는 **고아 노드**가 생겼을 수 있다. 이런 노드는 분류 경로 탐색(`resolver.resolve_path`) 시 최상위로 잘못 취급되어 카테고리 토큰이 올바르게 생성되지 않는다.

| 결과 | 의미 | 조치 |
|------|------|------|
| 0 | 정상. 모든 `level > 1` 카테고리는 부모가 있음 | 없음 |
| 0이 아님 | 고아 노드 존재. 분류 경로 탐색 오류 가능 | 해당 `category_id`를 조회해 올바른 `parent_id`로 `UPDATE` |
