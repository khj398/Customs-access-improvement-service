# CAIS Frontend (cais_front)

CAIS(Customs Access Improvement Service)의 Flutter 기반 앱입니다.  
Web / Android / iOS 빌드를 모두 지원합니다.

---

## 주요 기능

| 기능 | 설명 |
|------|------|
| 물품 검색 | Meilisearch 기반 관련도 순 검색, 오타 허용, 부분 일치 |
| 자동완성 | 검색어 입력 시 실시간 제안 드롭다운 (200ms 디바운스) |
| 카테고리 필터 | 대/중/소 3단계 드릴다운 칩 필터 |
| 세관 필터 | 세관별 물품 필터링 |
| 물품 상세 | 이미지, 공매 정보, 최고 입찰가, 찜 수 표시 |
| 찜(관심) | 로그인 사용자 대상 물품 찜/해제, 찜 목록 탭 |
| 입찰 | 물품 상세에서 입찰가 제출 |
| 달력 뷰 | 월별 공매 마감 일정 시각화 |
| Pull-to-refresh | 홈/검색 탭에서 아래로 당겨 최신 데이터 갱신 |
| 로그인/회원가입 | JWT 기반 인증, GetStorage로 토큰 로컬 보관 |
| 마이페이지 | 내 정보, 내 입찰 내역 |

---

## 기술 스택

| 항목 | 내용 |
|------|------|
| 프레임워크 | Flutter (Dart) |
| 상태 관리 | GetX (`app_controller.dart`) |
| HTTP | package:http |
| 로컬 저장소 | get_storage (JWT 토큰) |
| 백엔드 | CAIS Node.js API (`cais_back/`, 포트 3000) |

---

## 빠른 시작

```bash
# 의존성 설치
flutter pub get

# 개발 실행 (Chrome Web 권장)
flutter run -d chrome

# Android 에뮬레이터 (백엔드를 10.0.2.2:3000으로 자동 연결)
flutter run -d emulator-5554

# 실기기 / 커스텀 API 주소
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:3000
```

---

## 빌드

```bash
flutter build web        # Web
flutter build apk        # Android
flutter build ios        # iOS (macOS 필요)
```

---

## 프로젝트 구조

```
lib/
├─ main.dart                        # 앱 진입점
├─ models/
│   └─ item.dart                    # AuctionItem 모델 (imageUrls 파싱 포함)
├─ services/
│   ├─ api_config.dart              # baseUrl, timeout 상수
│   └─ api_service.dart             # HTTP 호출 모음
│       ├─ fetchItems()             # 물품 검색
│       ├─ fetchAutocomplete()      # 자동완성 제안
│       ├─ fetchCategories()        # 카테고리 목록
│       ├─ fetchCalendarItems()     # 달력용 월별 물품
│       ├─ toggleLike()             # 찜 토글
│       └─ ...
├─ controllers/
│   └─ app_controller.dart          # GetxController
│       ├─ searchItems()            # 검색 (300ms 디바운스)
│       ├─ fetchSuggestions()       # 자동완성 (200ms 디바운스)
│       ├─ selectL1/L2/L3Category() # 카테고리 드릴다운
│       └─ toggleWish()             # 찜 (낙관적 업데이트)
├─ screens/
│   ├─ main_screen.dart             # BottomNavigationBar (홈/검색/달력/찜/마이페이지)
│   ├─ home_tab.dart                # 홈 (추천 물품, 세관별 섹션, Pull-to-refresh)
│   ├─ search_tab.dart              # 검색 (자동완성 드롭다운, 카테고리 칩, Pull-to-refresh)
│   ├─ detail_screen.dart           # 물품 상세
│   ├─ wishlist_tab.dart            # 찜 목록
│   ├─ mypage_tab.dart              # 마이페이지
│   └─ login_screen.dart            # 로그인/회원가입
├─ widgets/
│   └─ item_card.dart               # 물품 카드 (이미지 · 가격 · 찜 버튼)
└─ utils/
    └─ format.dart                  # 숫자/날짜 포맷 유틸
```

---

## API 연결 설정

`lib/services/api_config.dart`에서 백엔드 주소를 확인합니다.

```dart
static const String baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000',
);
```

Flutter Web은 `localhost:3000`을 기본으로 사용합니다.  
Android 에뮬레이터는 `10.0.2.2:3000`으로 설정되어 있습니다.

---

## 참고

- 이미지 표시: `auction_item_image` 테이블의 URL을 `imageUrls` 필드로 수신. S3 저장 이미지는 CORS 설정이 필요합니다.
- 검색: Meilisearch가 실행 중이어야 키워드 검색이 동작합니다. Meilisearch가 없으면 필터 없는 최신순 목록만 표시됩니다.
