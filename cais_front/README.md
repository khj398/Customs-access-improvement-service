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
| 마이페이지 | 내 정보, 내 입찰 내역, 위치 설정, 알림 on/off, 관심 검색어 관리 |
| 위치 기반 세관 추천 | GPS 또는 주소 입력으로 내 위치 저장 → 홈 화면 세관 현황이 거리순 정렬, 마이페이지에 지도 미리보기 |
| 푸시 알림(FCM) | 찜한 상품 경매 임박 알림, 관심 검색어 신규 물품 알림. 마이페이지에서 on/off 토글 |
| 관심 검색어 구독 | 검색 탭에서 검색어별로 신규 물품 알림 구독/해제 (당근마켓 스타일) |
| Curated For You | 홈 화면 추천 물품 — 구독한 관심 검색어 기준으로 매칭 키워드 많은 순 정렬(한 줄 통합), 구독 키워드가 없으면 진행 중 물품 전체로 fallback |

---

## 기술 스택

| 항목 | 내용 |
|------|------|
| 프레임워크 | Flutter (Dart) |
| 상태 관리 | GetX (`app_controller.dart`) |
| HTTP | package:http |
| 로컬 저장소 | get_storage (JWT 토큰, 알림 on/off 설정) |
| 푸시 알림 | firebase_core, firebase_messaging (FCM), flutter_local_notifications (foreground 시 실제 알림창 표시) |
| 위치 | geolocator (GPS 좌표 조회, 위치 권한 요청) |
| 지도 | flutter_map + latlong2 (OpenStreetMap 타일, API 키 불필요) |
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
├─ main.dart                        # 앱 진입점 (Firebase.initializeApp() 포함)
├─ models/
│   └─ item.dart                    # AuctionItem 모델 (imageUrls 파싱 포함)
├─ services/
│   ├─ api_config.dart              # baseUrl(kIsWeb/Platform.isAndroid 분기), timeout 상수
│   ├─ api_service.dart             # HTTP 호출 모음
│   │   ├─ fetchItems()             # 물품 검색
│   │   ├─ fetchAutocomplete()      # 자동완성 제안
│   │   ├─ fetchCategories()        # 카테고리 목록
│   │   ├─ fetchCalendarItems()     # 달력용 월별 물품
│   │   ├─ toggleLike()             # 찜 토글
│   │   ├─ fetchCustomsStats()      # 세관 현황 (lat/lng 지정 또는 로그인 사용자 저장 위치 있으면 거리순 + distanceKm 포함)
│   │   ├─ fetch/updateBaseLocation*() # 내 위치 조회/설정(GPS·주소)
│   │   ├─ registerDeviceToken() / removeDeviceToken() # FCM 토큰 등록/삭제
│   │   ├─ fetch/add/remove/toggleSearchSubscription() # 관심 검색어 구독 CRUD
│   │   └─ ...
│   └─ local_notification_service.dart # foreground에서 수신한 FCM 메시지를 실제 시스템 알림으로 표시 (flutter_local_notifications)
├─ controllers/
│   └─ app_controller.dart          # GetxController
│       ├─ searchItems()            # 검색 (300ms 디바운스)
│       ├─ fetchSuggestions()       # 자동완성 (200ms 디바운스)
│       ├─ selectL1/L2/L3Category() # 카테고리 드릴다운
│       ├─ toggleWish()             # 찜 (낙관적 업데이트)
│       ├─ setLocationFromGps() / setLocationFromAddress() # 위치 설정
│       ├─ registerPushToken() / toggleNotifications()     # FCM 토큰 등록, 알림 on/off
│       ├─ subscribeToSearch() / removeSearchSubscription() / toggleSearchSubscription() # 관심 검색어
│       ├─ loadCuratedItems()      # Curated For You — 구독 키워드 매칭 물품 추천(매칭 수 순), 키워드 없으면 진행 중 전체 fallback
│       └─ FirebaseMessaging.onMessage 리스너 (foreground 푸시를 LocalNotificationService로 실제 알림창에 표시)
├─ screens/
│   ├─ main_screen.dart             # BottomNavigationBar (홈/검색/달력/찜/마이페이지)
│   ├─ home_tab.dart                # 홈 (추천 물품, 세관별 섹션(거리 km/m 배지), Pull-to-refresh)
│   ├─ search_tab.dart              # 검색 (자동완성 드롭다운, 카테고리 칩, 관심 검색어 구독 배너, Pull-to-refresh)
│   ├─ detail_screen.dart           # 물품 상세
│   ├─ wishlist_tab.dart            # 찜 목록
│   ├─ mypage_tab.dart              # 마이페이지 (위치 설정+지도, 알림 on/off, 관심 검색어 관리)
│   └─ login_screen.dart            # 로그인/회원가입 (성공 시 위치/구독 로드 + FCM 토큰 등록)
├─ widgets/
│   └─ item_card.dart               # 물품 카드 (이미지 · 가격 · 찜 버튼)
└─ utils/
    └─ format.dart                  # 숫자/날짜 포맷 유틸
```

---

## API 연결 설정

`lib/services/api_config.dart`에서 백엔드 주소를 플랫폼별로 자동 분기합니다.

```dart
static String get baseUrl {
  if (kIsWeb) return 'http://localhost:3000';
  if (Platform.isAndroid) return 'http://10.0.2.2:3000';
  return 'http://localhost:3000';
}
```

Flutter Web은 `localhost:3000`을 사용합니다.  
Android 에뮬레이터는 `10.0.2.2:3000`(호스트 PC를 가리키는 에뮬레이터 전용 주소)으로 자동 연결됩니다.  
실기기 사용 시에는 이 파일의 `baseUrl`을 실제 PC의 IP(`http://192.168.x.x:3000`)로 직접 바꿔야 합니다.

---

## 위치 기반 추천 / 푸시 알림 설정 (Android)

이 기능들을 쓰려면 아래 파일/권한이 필요합니다.

1. **Firebase**: `android/app/google-services.json` (Firebase 콘솔에서 발급, 앱 패키지명과 일치해야 함). `android/build.gradle.kts`에 `com.google.gms:google-services` classpath, `android/app/build.gradle.kts`에 `com.google.gms.google-services` 플러그인이 적용되어 있어야 함.
2. **위치 권한**: `AndroidManifest.xml`에 `ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION` 추가됨. 앱 실행 중 `geolocator`가 런타임 권한 팝업을 띄움.
3. **알림 권한 + desugaring**: `AndroidManifest.xml`에 `POST_NOTIFICATIONS`(Android 13+) 추가됨. `flutter_local_notifications`가 core library desugaring을 요구해서 `android/app/build.gradle.kts`의 `compileOptions.isCoreLibraryDesugaringEnabled = true` + `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:...")` 의존성이 필요함 (이미 설정됨).
4. **백엔드**: 카카오 지오코딩(`KAKAO_REST_API_KEY`)과 FCM 서비스 계정 키가 `cais_back` 쪽에 설정되어 있어야 실제로 동작함 — [`cais_back/README.md`](../cais_back/README.md) 참고.

동작 요약:
- 마이페이지 "내 위치 설정"에서 GPS 버튼(현재 위치) 또는 주소 직접 입력 중 하나로 위치 저장 → 좌표는 항상 저장되고, 라벨(주소 텍스트)은 백엔드가 자동으로 채워줌(GPS는 역지오코딩, 주소 입력은 입력값 그대로)
- 저장된 위치는 지도 미리보기로 표시되고, 홈 화면 "전국 세관 현황"이 거리순으로 재정렬되며 각 카드에 거리(km/m)가 표시됨
- "푸시 알림 받기" 스위치는 FCM 기기 토큰을 등록/삭제하는 방식으로 동작 (꺼도 앱 자체 알림 로직은 그대로, 발송 대상에서만 빠짐)
- 앱이 foreground(켜져 있는 상태)일 때도 `LocalNotificationService`가 실제 시스템 알림을 직접 띄워서, background/killed 상태와 동일하게 **알림창에 남아있다가 사용자가 확인/삭제할 때까지 유지**됨 (예전엔 잠깐 뜨고 사라지는 토스트였음)

에뮬레이터로 테스트할 때 실기기 GPS가 없다면, Android Studio 에뮬레이터 툴바의 **Extended Controls → Location**에서 좌표를 직접 주입해 "현재 위치로 설정"을 테스트할 수 있습니다.

---

## 참고

- 이미지 표시: `auction_item_image` 테이블의 URL을 `imageUrls` 필드로 수신. S3 저장 이미지는 CORS 설정이 필요합니다.
- 검색: Meilisearch가 실행 중이어야 키워드 검색이 동작합니다. Meilisearch가 없으면 필터 없는 최신순 목록만 표시됩니다. `cstmSgn`(세관) 필터도 Meilisearch를 거치므로, 세관 클릭 시 물품이 하나도 안 보이면 Meilisearch가 꺼져있는지(`curl http://localhost:7700/health`) 먼저 확인하세요.
- Windows에서 Docker Desktop이 "Starting..."에서 멈추거나 알 수 없는 오류로 죽으면, WSL2의 `docker-desktop` 배포판이 꼬인 경우가 많습니다. `wsl --shutdown` 후 Docker Desktop을 다시 실행하면 대부분 해결되고, PC 재시작도 확실한 방법입니다.
- 에뮬레이터 시스템 시간대가 GMT로 되어있으면 공매 달력의 "오늘" 표시가 하루 어긋날 수 있습니다 (한국 시간 기준 `Asia/Seoul`로 맞춰야 함).
