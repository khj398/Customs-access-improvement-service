# PPT 1장용 ERD 구성안

## A. 핵심 8개 테이블 축약본(상단 60%)

**목적:** 심사위원/청중이 30초 내 데이터 핵심 흐름 이해

- 마스터: `customs_office`, `bonded_warehouse`, `cargo_type`
- 트랜잭션: `auction`, `auction_item`, `auction_item_image`
- 검색/분류: `item_classification`, `item_search_token` *(+ `category`는 보조 박스로 작게)*

### 레이아웃(권장)
1. 좌측(기준정보): `customs_office`, `bonded_warehouse`, `cargo_type`
2. 중앙(핵심거래): `auction` → `auction_item` → `auction_item_image`
3. 우측(지능화): `item_classification`, `item_search_token`, `category`

### 한 줄 설명(슬라이드 하단)
- “공매(auction)와 물품(auction_item)을 중심으로, 기준정보를 정규화하고 분류/검색 레이어를 분리한 구조”

---

## B. 전체본(하단 40% 또는 백업 슬라이드)

**목적:** 기술 질의 대응(사용자 도메인 + 운영 확장 포함)

### 포함 범위
- 코어 DB: 마스터 + 공매 + 검색/분류
- 사용자: `app_user` 계열 8개
- 운영확장(v2): `ingestion_run`, `raw_auction_payload`, `auction_item_change_event`, queue 3종

### 발표용 강조 포인트 3개
1. **정규화 축:** 반복코드(세관/창고/화물/단위) 분리
2. **기능 축:** 거래데이터와 분류/검색을 느슨 결합
3. **운영 축:** 수집이력/변경이벤트/큐로 운영 안정성 확보

---

## C. 한 장에 넣는 실제 구성 템플릿

- 제목: `ERD Overview (Core + Full)`
- 좌상단 큰 다이어그램: **Core 8 ERD**
- 우상단 미니맵: **Full ERD(축소판)**
- 하단 좌측: 핵심 관계 5줄
  - `auction 1:N auction_item`
  - `auction_item 1:N auction_item_image`
  - `auction_item 1:0..1 item_classification`
  - `auction_item 1:N item_search_token`
  - `customs_office / warehouse / cargo_type -> auction`
- 하단 우측: 운영/사용자 확장 3줄

---

## D. 발표 대본(40초)

“ERD는 코어와 확장으로 분리해서 보시면 됩니다. 코어는 auction과 auction_item 중심의 거래 구조이며,
좌측 마스터 테이블로 기준정보를 정규화했고 우측에 분류/검색 레이어를 분리했습니다.
전체본에는 사용자 기능과 운영 확장 테이블을 추가해 실서비스에 필요한 알림/이력/재처리 흐름까지 포함했습니다.”
