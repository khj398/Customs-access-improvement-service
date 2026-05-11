# 검색 엔진 설계서 (Search Engine Design)

## 1. 배경 및 목표

### 문제
- 기존 `/items` API는 `cmdt_nm LIKE %q%` 단순 패턴 매칭
- 물품명이 영문 위주(예: `LITHIUM BATTERY 18650`) → 한글 검색 불가
- 랭킹 없음 → 관련도 낮은 결과가 상단에 노출

### 목표
| 항목 | 내용 |
|------|------|
| 한글 검색 | "와인", "배터리" 등 한글 키워드로 영문 물품 검색 |
| 동의어 확장 | "술" → WINE/WHISKY/VODKA 물품까지 검색 |
| 랭킹 | 토큰 가중치(weight) 합산 → score 정렬 |
| 필터 | 카테고리 / 가격 범위 / 세관 / 진행상태 |
| 자동완성 | 입력 중 한글/영문 후보어 실시간 제안 |

---

## 2. 레퍼런스 분석 (쿠팡 / G마켓 / 네이버쇼핑)

| 기능 | 쿠팡 | G마켓 | 네이버쇼핑 | CAIS 적용 |
|------|------|-------|-----------|---------|
| 형태소 분석 | ✅ | ✅ | ✅ (은전한닢) | 토큰 사전 기반 유사 효과 |
| 동의어 확장 | ✅ | ✅ | ✅ | `synonym_dictionary` 활용 |
| 오타 보정 | ✅ | 부분 | ✅ | 향후 편집 거리 구현 예정 |
| 자동완성 | ✅ | ✅ | ✅ | `/search/autocomplete` |
| 카테고리 필터 | ✅ | ✅ | ✅ | `category_id` 파라미터 |
| 가격 필터 | ✅ | ✅ | ✅ | `price_min` / `price_max` |
| 랭킹 | 구매수+평점+관련도 | 판매량+관련도 | 인기도+관련도 | 토큰 weight 합산 |
| 결과 없음 처리 | 연관 검색어 제안 | 대체 카테고리 | 포함어 재검색 | 향후 구현 |

---

## 3. 아키텍처

```
┌─────────────────────────────────────────┐
│           사용자 입력                     │
│   예) "와인 50만원 이하"                  │
└────────────────┬────────────────────────┘
                 │
         ┌───────▼──────┐
         │   파싱 레이어   │  split_keywords() / parse_price()
         │  키워드 분리    │  → ["와인"] + price_max=500000
         └───────┬───────┘
                 │
    ┌────────────▼─────────────────────────┐
    │        토큰 매칭 레이어                │
    │  item_search_token.token LIKE '%와인%' │
    │  → WINE, 와인, 주류, 술 등 모두 매칭   │
    └────────────┬─────────────────────────┘
                 │
    ┌────────────▼──────────────────────┐
    │        가중치 집계                  │
    │  SUM(weight) → score               │
    │  SYN 토큰 > RAW 토큰 weight 높음    │
    └────────────┬──────────────────────┘
                 │
    ┌────────────▼──────────────────────┐
    │        필터 적용                    │
    │  price_max / category_id / status  │
    └────────────┬──────────────────────┘
                 │
    ┌────────────▼──────────────────────┐
    │        정렬 + 페이징                │
    │  score DESC → pbac_end_dttm DESC   │
    │  limit / offset                    │
    └───────────────────────────────────┘
```

---

## 4. 토큰 구조 (item_search_token)

물품 1건 → 복수의 토큰으로 분해하여 저장

| token_type | 예시 | weight | 설명 |
|-----------|------|--------|------|
| RAW | WINE, LITHIUM | 1.0 | 원문 영문 토큰 |
| SYN | 와인, 배터리, 주류 | 1.4~2.0 | 동의어/번역 사전 기반 |
| CATEGORY | 식품·음료, 주류 | 1.2~2.0 | 분류 카테고리명 토큰 |

**검색 흐름 예시 — "와인" 검색**

```
사용자: "와인"
  ↓
item_search_token WHERE token LIKE '%와인%'
  → 물품 A: token=와인(SYN,w=2.0) + token=주류(SYN,w=1.6) → score=3.6
  → 물품 B: token=와인(SYN,w=2.0) → score=2.0
  ↓
score DESC → 물품 A 상단 노출
```

---

## 5. API 명세

### 5-1. `GET /search` — 핵심 검색

**요청 파라미터**

| 파라미터 | 타입 | 필수 | 기본값 | 설명 |
|---------|------|------|-------|------|
| `q` | string | ✅ | — | 검색어 (한글/영문) |
| `category_id` | int | — | null | 카테고리 ID 필터 |
| `price_min` | int | — | null | 최저 가격(원) |
| `price_max` | int | — | null | 최고 가격(원) |
| `cstm_sgn` | string | — | null | 세관 부호 필터 |
| `status` | string | — | null | `active`(진행중) / `ended`(종료) |
| `sort` | string | — | `score` | `score` / `price_asc` / `price_desc` / `newest` |
| `limit` | int | — | 20 | 페이지 크기 (1~100) |
| `offset` | int | — | 0 | 페이지 오프셋 |

**응답 예시**

```json
{
  "total": 42,
  "limit": 20,
  "offset": 0,
  "keywords": ["와인"],
  "query": "와인",
  "items": [
    {
      "pbac_no": "20240001",
      "pbac_srno": "01",
      "cmdt_ln_no": "001",
      "cmdt_nm": "WINE RED 750ML",
      "pbac_prng_prc": 450000,
      "pbac_strt_dttm": "2024-01-01T09:00:00",
      "pbac_end_dttm": "2024-01-10T17:00:00",
      "cstm_sgn": "0101",
      "cstm_name": "서울세관",
      "category_name": "주류",
      "parent_category_name": "음료",
      "confidence": 0.88,
      "score": 3.6
    }
  ]
}
```

---

### 5-2. `GET /search/autocomplete` — 자동완성

**요청 파라미터**

| 파라미터 | 타입 | 필수 | 설명 |
|---------|------|------|------|
| `q` | string | ✅ | 입력 중인 텍스트 |
| `limit` | int | — | 최대 10개 |

**응답 예시**

```json
{
  "query": "와",
  "suggestions": [
    { "token": "와인",   "token_type": "SYN",      "item_count": 15 },
    { "token": "와인잔", "token_type": "SYN",      "item_count": 3  },
    { "token": "WINE",  "token_type": "RAW",      "item_count": 15 }
  ]
}
```

---

### 5-3. `GET /search/filters` — 필터 옵션

검색 UI의 필터 패널 구성에 사용 (세관 목록, 대분류 카테고리 목록 반환)

---

## 6. 인덱스 전략

```sql
-- item_search_token 핵심 인덱스 (이미 스키마에 존재)
INDEX idx_token (token)           -- LIKE '%q%' 검색
INDEX idx_token_type (token_type) -- SYN/CATEGORY 필터
INDEX idx_token_weight (weight)   -- 정렬 보조

-- 추가 권장 인덱스 (아직 미생성)
-- auction_item 가격 범위 필터용
ALTER TABLE auction_item ADD INDEX idx_price (pbac_prng_prc);

-- auction 공매 기간 필터용 (이미 존재: idx_auction_period)
```

> **Full-text 한계**: MySQL `LIKE '%q%`는 인덱스를 타지 않음.  
> 데이터 1만건 이상 시 **Elasticsearch(Nori 분석기)** 도입 권장.

---

## 7. 성능 목표

| 지표 | 목표 | 측정 방법 |
|------|------|---------|
| 검색 응답시간 (p95) | ≤ 300ms | `EXPLAIN ANALYZE` |
| 자동완성 응답시간 (p95) | ≤ 100ms | 부하 테스트 |
| 검색 결과 정밀도 | 상위 5건 내 정답 포함 ≥ 80% | 50건 평가셋 기준 |

---

## 8. 향후 개선 계획

| 단계 | 내용 | 우선순위 |
|------|------|---------|
| 단기 | 오타 보정 (편집거리 1 허용) | 중 |
| 단기 | "결과 없음" → 연관 검색어 제안 | 중 |
| 중기 | Elasticsearch 도입 (Nori 형태소 분석) | 높음 |
| 중기 | 개인화 검색 (최근 검색어 가중치) | 낮음 |
| 장기 | 벡터 검색 (semantic similarity) | 낮음 |
