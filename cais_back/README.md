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

### 파일 (`/api/files`)
| 메서드 | 경로 | 설명 |
|--------|------|------|
| POST | `/api/files/upload` | 이미지 업로드 |

---

## 디렉터리 구조

```
cais_back/
├─ server.js              # 서버 진입점 (포트 바인딩)
├─ app.js                 # Express 앱 설정 및 라우팅 연결
├─ config/
│   ├─ db.js              # MySQL 커넥션 풀 싱글톤
│   └─ meili.js           # Meilisearch 클라이언트 싱글톤
├─ routes/                # 라우트 정의
├─ controllers/           # 요청 처리 로직
├─ models/                # DB 쿼리 / Meilisearch 검색 로직
│   └─ meiliModel.js      # Meilisearch 검색 + 자동완성
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
