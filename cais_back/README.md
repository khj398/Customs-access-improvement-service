# CAIS Backend (cais_back)

Node.js (Express) 기반 REST API 서버입니다.  
공매 물품 조회·검색·입찰·찜·알림 등 CAIS 앱의 모든 백엔드 기능을 담당합니다.

---

## 기술 스택

| 항목 | 내용 |
|------|------|
| 런타임 | Node.js (Express 4) |
| DB | MySQL 8 (mysql2/promise) |
| 검색 | Meilisearch v1 (관련도 검색 · 한글 · 오타 허용 · 자동완성) |
| 인증 | JWT (jsonwebtoken + bcryptjs) |
| 포트 | 3000 |

---

## 실행 방법

### 1) 의존성 설치

```bash
cd cais_back
npm install
```

### 2) 환경변수 설정

`.env` 파일 또는 셸에서 아래 변수를 설정합니다.

```
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=root
DB_PASSWORD=<MySQL 비밀번호>
DB_NAME=customs_auction
JWT_SECRET=<임의 문자열>
MEILI_HOST=http://localhost:7700
MEILI_MASTER_KEY=cais-search-key

# 위치 기반 세관 추천 (주소 → 좌표 변환)
KAKAO_REST_API_KEY=<카카오 개발자 콘솔에서 발급>

# FCM 푸시 알림 (선택 — 없으면 서버는 정상 동작하고 발송만 비활성화됨)
# 기본값: cais_back/config/firebase-service-account.json
FIREBASE_SERVICE_ACCOUNT_PATH=<서비스 계정 키 JSON 경로>
```

### 3) 서버 실행

```bash
node server.js        # 일반 실행 (포트 3000)
npx nodemon server.js # 개발용 (파일 변경 시 자동 재시작)
```

### 4) Meilisearch 동기화

Meilisearch Docker 컨테이너가 실행 중인 상태에서:

```bash
node scripts/sync_meili.js
```

물품 데이터가 추가·수정될 때마다 재실행해야 검색 인덱스가 최신으로 유지됩니다.

---

## API 엔드포인트

### 인증 (`/api/auth`)
| 메서드 | 경로 | 설명 |
|--------|------|------|
| POST | `/api/auth/register` | 회원가입 |
| POST | `/api/auth/login` | 로그인 (JWT 반환) |

### 물품 (`/api/items`)
| 메서드 | 경로 | 설명 |
|--------|------|------|
| GET | `/api/items/search` | 물품 검색 (keyword·categoryId·cstmSgn·page·limit) |
| GET | `/api/items/autocomplete` | 자동완성 제안 (q 파라미터) |
| GET | `/api/items/category-stats` | 카테고리별 물품 건수 |
| GET | `/api/items/customs-stats` | 세관별 활성 물품 건수. `lat`·`lng` 쿼리를 주거나 로그인 사용자가 기본 위치를 저장해뒀으면 **거리순**, 아니면 물품 수 내림차순 |
| GET | `/api/items/calendar` | 달력용 월별 마감 물품 목록 (year·month) |
| GET | `/api/items/:pbacNo/:pbacSrno/:cmdtLnNo` | 물품 상세 조회 |

> **검색 동작**: `keyword`, `categoryId`, `cstmSgn` 중 하나라도 있으면 Meilisearch(관련도 순)를 사용합니다.  
> 아무 필터도 없으면 MySQL 최신순 fallback이 적용됩니다.

### 공매 (`/api/auctions`)
| 메서드 | 경로 | 설명 |
|--------|------|------|
| GET | `/api/auctions` | 공매 목록 |
| GET | `/api/auctions/:pbacNo` | 공매 상세 + 포함 물품 목록 |

### 찜 (`/api/likes`)
| 메서드 | 경로 | 설명 |
|--------|------|------|
| POST | `/api/likes/toggle` | 찜 추가/해제 토글 |
| GET | `/api/likes` | 내 찜 목록 |
| GET | `/api/likes/keys` | 내 찜 키 목록 (Flutter 동기화용) |

### 입찰 (`/api/bids`)
| 메서드 | 경로 | 설명 |
|--------|------|------|
| POST | `/api/bids` | 입찰 등록 |
| GET | `/api/bids/my` | 내 입찰 목록 |

### 카테고리 (`/api/categories`)
| 메서드 | 경로 | 설명 |
|--------|------|------|
| GET | `/api/categories` | 최상위 카테고리 목록 |
| GET | `/api/categories/:id/children` | 하위 카테고리 목록 |

### 사용자 (`/api/users`)
| 메서드 | 경로 | 설명 |
|--------|------|------|
| GET | `/api/users/me` | 내 정보 조회 |
| PUT | `/api/users/me` | 내 정보 수정 |
| PUT | `/api/users/me/location` | 관심 세관(preferredCstmSgn) 설정 |
| GET | `/api/users/me/base-location` | 내 기본 위치(위경도) 조회 |
| PUT | `/api/users/me/base-location` | 내 기본 위치 설정 — `{ latitude, longitude, label? }`(GPS, `label` 생략 시 좌표→주소 역지오코딩으로 자동 채움) 또는 `{ address, label? }`(주소→좌표 지오코딩, `label` 생략 시 입력한 주소를 그대로 사용) |
| POST | `/api/users/me/device-token` | FCM 기기 토큰 등록/갱신 |
| DELETE | `/api/users/me/device-token` | FCM 기기 토큰 삭제 |
| GET | `/api/users/me/calendar` | 입찰/낙찰 달력 데이터 |

### 관심 검색어 구독 (`/api/search-subscriptions`)
당근마켓 스타일 — 등록해둔 키워드에 신규 물품이 매칭되면 푸시 알림 발송 (`jobs/notificationJob.js` 참고)

| 메서드 | 경로 | 설명 |
|--------|------|------|
| GET | `/api/search-subscriptions` | 내 구독 키워드 목록 |
| POST | `/api/search-subscriptions` | 키워드 구독 추가 (`{ keyword }`) |
| DELETE | `/api/search-subscriptions/:subscriptionId` | 구독 삭제 |
| PATCH | `/api/search-subscriptions/:subscriptionId` | 알림 on/off (`{ enabled }`) |

### 파일 (`/api/files`)
| 메서드 | 경로 | 설명 |
|--------|------|------|
| POST | `/api/files/upload` | 이미지 업로드 |

---

## 알림(FCM 푸시) — `jobs/notificationJob.js`

서버 기동 시 `node-cron`으로 **15분마다** 자동 실행됩니다.

1. **경매 시작 임박 알림**: 찜한 물품(`user_watchlist_target.notify_enabled=1`) 중 연결된 공매의 `pbac_strt_dttm`이 임박한 건을 찾아 발송. **24시간 전 / 1시간 전, 2단계**로 각각 한 번씩 보내며(`jobs/notificationJob.js`의 `STARTING_SOON_TIERS`), 같은 찜 항목·같은 단계 재알림은 발송 이력(`message_title` 기준)으로 영구 방지.
2. **관심 검색어 신규 매칭 알림**: 활성화된 `user_search_subscription` 키워드에 최근 20분 내 등록된 신규 물품이 매칭되면 요약 푸시 발송.

발송 이력은 `user_notification_event`(PENDING/SENT/FAILED)에 기록됩니다.
`cais_back/config/firebase-service-account.json`이 없으면 cron은 정상 등록되지만 발송 단계에서 스킵되고 경고 로그만 남습니다(서버는 정상 동작).

---

## 디렉터리 구조

```
cais_back/
├─ server.js              # 서버 진입점 (포트 바인딩 + 알림 cron 시작)
├─ app.js                 # Express 앱 설정 및 라우팅 연결
├─ config/
│   ├─ db.js              # MySQL 커넥션 풀 싱글톤
│   ├─ meili.js           # Meilisearch 클라이언트 싱글톤
│   └─ firebase-service-account.json  # FCM 서비스 계정 키 (gitignore, 직접 발급 필요)
├─ routes/                # 라우트 정의
├─ controllers/           # 요청 처리 로직
├─ models/                # DB 쿼리 / Meilisearch 검색 로직
│   └─ meiliModel.js      # Meilisearch 검색 + 자동완성
├─ services/
│   ├─ geocodeService.js  # 카카오 주소↔좌표 변환 (geocodeAddress: 주소→좌표, reverseGeocodeAddress: 좌표→주소)
│   └─ fcmService.js      # FCM 푸시 발송 (firebase-admin, 모듈형 API 사용)
├─ jobs/
│   └─ notificationJob.js # 알림 cron (경매 임박 / 관심 검색어 매칭)
├─ middleware/
│   └─ optionalAuth.js    # JWT 선택적 인증 미들웨어
├─ scripts/
│   └─ sync_meili.js      # MySQL → Meilisearch 동기화 스크립트
└─ uploads/               # 업로드 이미지 저장 경로
```

---

## Meilisearch 검색 인덱스 설계

인덱스 이름: `auction_items`

| 항목 | 필드 |
|------|------|
| 검색 가능 | `cmdtNm`, `categoryName`, `cstmName`, `tokens` |
| 필터 가능 | `categoryId`, `cstmSgn`, `status` |
| 정렬 가능 | `pbacEndDttm`, `pbacPrngPrc`, `pbacStrtDttm` |
| Typo tolerance | 4자 이상 → 1회 오타 허용, 8자 이상 → 2회 허용 |

`tokens` 필드에는 `item_search_token` 테이블의 형태소/동의어 토큰이 공백으로 연결되어 저장됩니다.  
한글 검색은 이 토큰을 통해 지원됩니다 (예: "와인" 검색 → `WINE` 토큰이 있는 물품 매칭).
