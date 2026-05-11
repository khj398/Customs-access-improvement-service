# 분류 로직 설계서 (Classification Logic Design)

## 1. 배경 및 목적

### 문제 (평가 피드백)
- "핵심 로직에 대한 설계가 없음"
- "로직 기반 분류방법 제시 필요"
- "OpenAI API로 분류 방법 재시필요 · 라벨을 추가하는 기준이 모호함"

### 목적
- 분류 5단계 흐름을 명문화하여 누구나 이해·재현 가능하게 함
- Rule 추가/폐기 기준을 수치로 명확히 정의
- OpenAI 프롬프트를 구조화하여 분류 근거가 항상 남도록 함

---

## 2. 분류 5단계 흐름

```
┌─────────────────────────────────────────────────────────┐
│  입력: cmdt_nm (영문 물품명)                              │
│  예)  "LITHIUM BATTERY 18650 3.7V 2600MAH"              │
└────────────────────┬────────────────────────────────────┘
                     │
          ┌──────────▼──────────┐
          │   STEP A: 전처리     │
          │  대문자 통일         │
          │  특수문자 → 공백     │
          │  토큰화             │
          │  결과: {LITHIUM,    │
          │   BATTERY,18650,..} │
          └──────────┬──────────┘
                     │
          ┌──────────▼──────────────────────────┐
          │   STEP B: Rule-based 분류            │
          │  rules.yaml 순서(priority)대로 매칭   │
          │  keywords_all (AND) 먼저 검사         │
          │  keywords_any (OR) 후 검사            │
          │                                      │
          │  매칭 시 → confidence = base_conf    │
          │           + 0.02×(매칭 키워드 수-1)  │
          │  source = "rule"                     │
          └──────────┬──────────────────────────┘
                     │
            매칭? ───┤
           Yes       │ No
            │        │
            │   ┌────▼──────────────────────────────┐
            │   │   STEP C: OpenAI 분류              │
            │   │  gpt-4o-mini 호출                  │
            │   │  입력: cmdt_nm + 카테고리 목록      │
            │   │  출력: category_path +             │
            │   │        confidence + reason         │
            │   │  source = "openai"                 │
            │   │                                    │
            │   │  실패/쿼터 초과 → fallback          │
            │   └────┬──────────────────────────────┘
            │        │
            └────────┤
                     │
          ┌──────────▼──────────────────────────┐
          │   STEP D: 저장                       │
          │  item_classification UPSERT          │
          │  category_id / model_name /          │
          │  confidence / rationale              │
          └──────────┬──────────────────────────┘
                     │
          ┌──────────▼──────────────────────────┐
          │   STEP E: 검색 토큰 생성              │
          │  RAW  : 원문 영문 토큰 (weight=1.0)  │
          │  SYN  : 동의어/번역 사전 기반         │
          │  CATEGORY: 분류 카테고리명            │
          │  → item_search_token UPSERT          │
          └─────────────────────────────────────┘
```

---

## 3. Rule 설계 원칙

### 3-1. Rule 파일 위치
```
classification/rules.yaml
```

### 3-2. Rule 구조

```yaml
- id: battery_lithium        # 고유 식별자 (snake_case)
  priority: 20               # 낮을수록 먼저 적용
  keywords_all: [LITHIUM, BATTERY]  # AND 조건 (둘 다 있어야)
  keywords_any: []           # OR 조건 (하나라도)
  category_path: [부품·소모품, 배터리·전지, 리튬배터리]
  confidence: 0.90           # 기본 신뢰도
  rationale: "리튬 계열 + BATTERY 동시 포함"
```

### 3-3. 우선순위(priority) 배치 원칙

| priority 범위 | 설명 | 예시 |
|-------------|------|------|
| 1 ~ 9 | 초정밀 (3개 이상 키워드 AND) | `CHEONG + JU` |
| 10 ~ 29 | 식품/음료 (주류 등) | `WINE`, `SAKE` |
| 20 ~ 39 | 부품/소모품 (배터리, 화학) | `LITHIUM + BATTERY` |
| 30 ~ 49 | 산업장비 (계측, 유체) | `GAUGE`, `PUMP` |
| 50 ~ 59 | 전자/전기 | `PCB`, `RELAY` |
| 60 ~ 69 | 컴퓨터/모바일 | `SERVER`, `IPHONE` |
| 70 ~ 79 | 자동차/공구 | `TIRE`, `DRILL` |
| 80 ~ 99 | 스포츠/레저/가전 | `GUITAR`, `BEVERAGE` |

> 더 구체적인 Rule(AND 조건 많은 것)을 더 낮은 priority에 배치

---

## 4. 라벨 추가/폐기 기준 (명확한 수치 기준)

### 4-1. 신규 Rule 추가 기준

| 조건 | 기준 |
|------|------|
| **미분류 누적** | 동일 키워드 패턴이 fallback(기타/미분류) 5건 이상 발생 |
| **OpenAI 제안 일치** | 동일 category_path 제안이 3건 이상 & confidence ≥ 0.85 |
| **수동 확인** | 담당자가 정답 라벨 확인 후 Rule 직접 추가 |

**추가 절차:**
```
1. feedback.sql 또는 평가 스크립트로 미분류 물품 확인
2. rules.yaml에 새 Rule 작성 (priority, keywords, category_path)
3. --dry-run으로 영향 범위 확인
4. 운영 DB에 적용 (build_classification.py 재실행)
5. 정확도 스크립트(eval/evaluate.py)로 수치 변화 확인
```

### 4-2. 기존 Rule 수정 기준

| 조건 | 조치 |
|------|------|
| confidence < 0.70인 Rule 매칭 건수 > 전체의 20% | keywords_any/all 조건 강화 |
| 동일 키워드가 다른 카테고리 Rule과 충돌 | priority 재조정, keywords_all 추가 |
| 오분류율 > 10% (평가셋 기준) | Rule 분리 또는 삭제 후 OpenAI 위임 |

### 4-3. Rule 폐기 기준

| 조건 | 조치 |
|------|------|
| 최근 6개월 해당 카테고리 물품 수집 0건 | `is_active: false` 처리 (삭제 아님) |
| 오분류율 > 30% | 즉시 폐기 후 OpenAI 재분류 |

---

## 5. OpenAI API 프롬프트 설계

### 5-1. 개선 전 문제점

| 항목 | 기존 | 개선 |
|------|------|------|
| 카테고리 목록 전달 | 전체 leaf 경로를 한 번에 | 관련도 높은 경로 우선 노출 |
| 출력 형식 강제 | JSON 스키마만 명시 | 예시 포함, 오류시 재시도 로직 |
| 근거 요구 | 짧은 근거 | 매칭 키워드 반드시 포함 |
| 확신 없을 때 | confidence 범위만 지정 | alternative 필드로 차선 카테고리 반환 |

### 5-2. 개선된 시스템 프롬프트

```
당신은 세관 공매 물품 자동 분류 전문가입니다.
주어진 영문 물품명을 분석하여 제공된 카테고리 목록 중 정확히 하나로 분류하세요.

분류 절차:
1. 물품명의 핵심 명사/형용사 키워드를 추출하세요
2. 추출한 키워드와 카테고리명을 비교하여 가장 적합한 경로를 선택하세요
3. 확신도(confidence)를 0~1 사이로 평가하세요:
   - 0.85 이상: 키워드가 카테고리와 명확히 일치
   - 0.70~0.84: 맥락상 합리적이나 다른 해석 가능
   - 0.70 미만: 불확실, alternative에 차선 경로 기재

반드시 아래 JSON 형식으로만 응답하세요. 다른 텍스트 금지.
```

### 5-3. 개선된 사용자 프롬프트

```json
{
  "item_name": "LITHIUM BATTERY 18650 3.7V 2600MAH",
  "extracted_keywords": ["LITHIUM", "BATTERY", "18650"],
  "candidate_categories": [
    "부품·소모품 > 배터리·전지 > 리튬배터리",
    "부품·소모품 > 배터리·전지 > 일반 배터리",
    "전자·전기 > 전자부품 > PCB·모듈"
  ],
  "output_schema": {
    "category_path": ["대분류", "중분류", "소분류"],
    "confidence": "0.0~1.0 실수",
    "matched_keywords": ["분류 근거가 된 키워드 목록"],
    "reason": "한 줄 근거 (키워드 포함 필수)",
    "alternative": "확신도 낮을 때 차선 카테고리 경로 (없으면 null)"
  }
}
```

### 5-4. 예상 응답

```json
{
  "category_path": ["부품·소모품", "배터리·전지", "리튬배터리"],
  "confidence": 0.95,
  "matched_keywords": ["LITHIUM", "BATTERY"],
  "reason": "LITHIUM + BATTERY 키워드로 리튬배터리 확정",
  "alternative": null
}
```

---

## 6. 신뢰도(Confidence) 기준표

| 구간 | 의미 | 처리 방식 |
|------|------|---------|
| 0.90 이상 | 고확신 (Rule AND 매칭) | 검수 불필요 |
| 0.80 ~ 0.89 | 확신 (Rule OR 매칭) | 샘플 검수 (10% 추출) |
| 0.70 ~ 0.79 | 보통 (OpenAI 분류) | 전수 검수 권장 |
| 0.70 미만 | 불확실 | 수동 분류 or 재분류 대기열 추가 |
| 0.55 (fallback) | 미분류 | 기타/미분류 카테고리로 저장 |

---

## 7. 전체 분류 파이프라인 실행 방법

### 7-1. 기본 실행 (Rule only)

```bash
python classification/build_classification.py
```

### 7-2. OpenAI 보강 실행 (Rule 미매칭 물품에만 적용)

```bash
# 환경변수 설정
export OPENAI_API_KEY="sk-..."

# Rule 미매칭 물품에 OpenAI 적용
python classification/build_classification.py --use-openai

# 특정 rules.yaml 지정
python classification/build_classification.py --use-openai --rules-file classification/rules.yaml

# 테스트 (DB 기록 없이)
python classification/build_classification.py --use-openai --dry-run --limit 10
```

### 7-3. 재분류 (기존 분류 덮어쓰기)

```bash
# 전체 재분류 (UPSERT이므로 안전)
python classification/build_classification.py --use-openai --model-ver "rule-v2"
```

### 7-4. 정확도 평가

```bash
# 50건 평가셋 기준 정확도 측정
python classification/eval/evaluate.py
```

---

## 8. 분류 결과 조회 쿼리

### 8-1. 분류 현황 요약

```sql
SELECT
    ic.model_name,
    ROUND(AVG(ic.confidence), 3) AS avg_confidence,
    COUNT(*) AS total,
    SUM(CASE WHEN ic.confidence >= 0.90 THEN 1 ELSE 0 END) AS high,
    SUM(CASE WHEN ic.confidence BETWEEN 0.70 AND 0.89 THEN 1 ELSE 0 END) AS mid,
    SUM(CASE WHEN ic.confidence < 0.70 THEN 1 ELSE 0 END) AS low
FROM item_classification ic
GROUP BY ic.model_name;
```

### 8-2. 미분류(fallback) 물품 조회

```sql
SELECT ai.pbac_no, ai.cmdt_nm, ic.rationale
FROM item_classification ic
JOIN auction_item ai USING (pbac_no, pbac_srno, cmdt_ln_no)
JOIN category c ON c.category_id = ic.category_id
WHERE c.name_ko IN ('기타', '미분류')
ORDER BY ai.pbac_no;
```

### 8-3. 카테고리별 물품 분포

```sql
SELECT
    pc.name_ko AS 대분류,
    c.name_ko  AS 소분류,
    COUNT(*)   AS 물품수
FROM item_classification ic
JOIN category c  ON c.category_id = ic.category_id
JOIN category pc ON pc.category_id = c.parent_id
GROUP BY pc.name_ko, c.name_ko
ORDER BY 물품수 DESC;
```
