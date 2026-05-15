# cais_front — Flutter 앱 소스 구조

GetX 상태관리 기반의 세관 공매 탐색 앱입니다.  
Node.js 백엔드(`cais_back`)의 `/api/items` 엔드포인트와 통신합니다.

---

## 실행

```bash
cd cais_front
flutter pub get

# Android 에뮬레이터 (백엔드는 10.0.2.2:3000으로 자동 연결)
flutter run

# 실기기 또는 IP 직접 지정
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:3000
```

---

## lib/ 파일 구조

```
lib/
├─ main.dart
├─ models/
│  └─ item.dart
├─ services/
│  ├─ api_config.dart
│  └─ api_service.dart
├─ controllers/
│  └─ app_controller.dart
├─ data/
│  └─ items_data.dart
├─ screens/
│  ├─ home_tab.dart
│  ├─ search_tab.dart
│  ├─ wishlist_tab.dart
│  ├─ calendar_tab.dart
│  ├─ mypage_tab.dart
│  └─ detail_screen.dart
├─ widgets/
│  └─ item_card.dart
└─ utils/
   └─ (유틸 함수)
```

---

## 각 파일 설명

### 진입점

#### `main.dart`
앱 진입점. `GetMaterialApp`을 설정하고 `AppController`를 `Get.put()`으로 등록합니다.  
하단 탭 네비게이션(홈·검색·캘린더·찜·마이페이지)을 구성합니다.

---

### models/

#### `models/item.dart`
공매 물품 데이터 모델 `AuctionItem`.

| 필드 | 타입 | 설명 |
|------|------|------|
| `id` | `int` | 공매번호(`pbacNo`) |
| `name` | `String` | 물품명(`cmdtNm`) |
| `cat` | `String` | 카테고리명(`categoryName`) |
| `price` | `int` | 예정가격(`pbacPrngPrc`) |
| `customs` | `String` | 세관명(`cstmName`) |
| `startDate` | `String` | 공매 시작일시 |
| `endDate` | `String` | 공매 종료일시 |
| `status` | `String` | `진행중` / `마감` (종료일시 기준 파생) |
| `qty` | `String` | 수량 + 단위 (예: `10 EA`) |
| `wght` | `String` | 중량 + 단위 (예: `5.2 KG`) |
| `warehouse` | `String` | 창고명(`snarName`) |
| `images` | `List<String>` | 이미지 URL 목록 (현재 미연동) |

`AuctionItem.fromJson(Map json)` — API 응답 JSON을 모델로 변환.  
`endDateTime` / `endDay` getter — 날짜 파싱 유틸.

---

### services/

#### `services/api_config.dart`
API 서버 기본 설정.

- `baseUrl` — `API_BASE_URL` 환경변수 우선, 없으면 플랫폼 감지:
  - Android: `http://10.0.2.2:3000`
  - iOS/기타: `http://localhost:3000`
- `timeoutSeconds` — 요청 타임아웃 (10초)
- `defaultPageSize` — 페이지당 물품 수 (20건)

#### `services/api_service.dart`
백엔드 HTTP 통신 클래스.

| 메서드 | 엔드포인트 | 설명 |
|--------|-----------|------|
| `fetchItems({keyword, categoryId, cstmSgn, page, limit})` | `GET /api/items/search` | 물품 목록 조회. 응답 `items` 배열을 `AuctionItem.fromJson`으로 파싱 |
| `fetchCalendarItems({year, month})` | `GET /api/items/calendar` | 월별 물품 조회 |

비-200 응답 또는 네트워크 오류 시 `ApiException` throw.

---

### controllers/

#### `controllers/app_controller.dart`
앱 전역 상태를 관리하는 GetX 컨트롤러.

**상태**

| 변수 | 타입 | 설명 |
|------|------|------|
| `allItems` | `RxList<AuctionItem>` | 현재 로드된 물품 전체 목록 |
| `isLoading` | `RxBool` | API 요청 중 여부 |
| `hasError` | `RxBool` | 마지막 요청 실패 여부 |
| `errorMessage` | `RxString` | 에러 메시지 |
| `currentPage` | `RxInt` | 현재 페이지 번호 |
| `hasMore` | `RxBool` | 추가 로드 가능 여부 |
| `wishlistIds` | `RxList<int>` | 찜한 물품 id 목록 |
| `activeCategory` | `RxString` | 선택된 카테고리 칩 |
| `searchQuery` | `RxString` | 현재 검색어 |
| `currentTab` | `RxInt` | 하단 탭 인덱스 |
| `newDropsMode` | `RxBool` | '새로 등록' 필터 모드 |

**메서드**

| 메서드 | 설명 |
|--------|------|
| `loadItems()` | 1페이지부터 새로 로드. `allItems` 교체 |
| `loadMore()` | 다음 페이지 fetch 후 `allItems`에 append. 스크롤 페이지네이션에서 호출 |
| `searchItems(String q)` | 300ms debounce 후 API keyword 검색. `allItems` 교체 |
| `toggleWish(int id)` | 찜 토글 + 토스트 메시지 |
| `isWished(int id)` | 찜 여부 확인 |
| `filteredItems` | `allItems`를 카테고리/newDropsMode 기준으로 필터링한 목록 |
| `wishedItems` | 찜 목록 |
| `nearbyItems` | 세관별 진행중 물품 맵 |
| `getItemsForDay(DateTime)` | 날짜별 물품 (캘린더 탭용) |
| `goToSearch({newDrops})` | 검색 탭으로 이동 |

---

### data/

#### `data/items_data.dart`
초기 개발 시 사용한 하드코딩 물품 데이터 (33건) 및 카테고리 목록.  
현재 앱에서 직접 참조하지 않으며, 백업 및 개발 참고용으로 보존합니다.

---

### screens/

#### `screens/home_tab.dart`
홈 화면.

- 검색 바 (탭하면 검색 탭으로 이동)
- Hero 배너 (NEW DROP → 검색 탭의 newDrops 모드)
- **Curated For You**: `ctrl.allItems` 중 진행중 물품 최대 6개. 로딩 중 스피너, 에러 시 재시도 버튼 표시
- **Live Auctions Nearby**: 세관별 물품 카드 (펼치면 그리드 표시)

#### `screens/search_tab.dart`
검색·탐색 화면.

- 검색 바: 입력 시 `ctrl.searchItems()` 호출 (300ms debounce)
- 카테고리 칩: 탭 시 `ctrl.activeCategory` 변경
- 물품 그리드: `ctrl.filteredItems` 표시
- 스크롤 하단 200px 근접 시 `ctrl.loadMore()` 호출 (페이지네이션)
- 로딩/에러/빈 결과 상태별 UI 분기

#### `screens/wishlist_tab.dart`
찜 목록 화면. `ctrl.wishedItems`를 그리드로 표시.

#### `screens/calendar_tab.dart`
공매 캘린더 화면. `table_calendar` 패키지 사용. 날짜 선택 시 `ctrl.getItemsForDay()` 호출.

#### `screens/mypage_tab.dart`
마이페이지 화면. 사용자 정보·통계 표시.

#### `screens/detail_screen.dart`
물품 상세 화면. `AuctionItem`을 받아 이름·가격·세관·창고·수량·중량·상태를 표시.

---

### widgets/

#### `widgets/item_card.dart`
물품 카드 위젯. `small: true`이면 가로 스크롤용 작은 카드, 기본은 그리드 카드.  
물품명·가격·카테고리·상태 표시. 탭하면 `detail_screen`으로 이동.  
찜 버튼: `ctrl.toggleWish(item.id)`.

---

## 데이터 흐름

```
MySQL
  ↓
Node.js (cais_back) /api/items/search
  ↓ HTTP GET (api_service.dart)
AppController.allItems (RxList)
  ↓ Obx()
home_tab / search_tab / wishlist_tab / calendar_tab
```

## 환경별 URL 설정

| 환경 | 설정 방법 |
|------|----------|
| Android 에뮬레이터 | 자동 (10.0.2.2:3000) |
| iOS 시뮬레이터 | 자동 (localhost:3000) |
| 실기기 | `--dart-define=API_BASE_URL=http://192.168.x.x:3000` |
| 프로덕션 | `--dart-define=API_BASE_URL=https://api.example.com` |
