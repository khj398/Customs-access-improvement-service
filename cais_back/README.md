# cais_back — Node.js 백엔드 API 서버

Express.js 기반 REST API 서버입니다. Flutter 앱에 물품 검색·상세·입찰·찜·회원 기능을 제공합니다.

---

## 실행

```bash
cd cais_back
npm install
node server.js        # 기본 포트 3000
```

환경변수 (`.env` 또는 셸에서 설정):

```
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=root
DB_PASSWORD=<비밀번호>
DB_NAME=customs_auction
JWT_SECRET=<임의 문자열>
```

---

## 파일 구조

```
cais_back/
├─ server.js                   # 진입점
├─ app.js                      # Express 앱 설정
├─ package.json
├─ config/
│  ├─ db.js                    # MySQL 커넥션 풀
│  └─ upload.js                # multer 파일 업로드 설정
├─ routes/                     # URL → Controller 연결
│  ├─ items.js
│  ├─ auctions.js
│  ├─ bids.js
│  ├─ likes.js
│  ├─ users.js
│  ├─ auth.js
│  ├─ files.js
│  └─ categories.js
├─ controllers/                # 요청 처리 로직
│  ├─ itemController.js
│  ├─ auctionController.js
│  ├─ bidController.js
│  ├─ likeController.js
│  ├─ userController.js
│  ├─ authController.js
│  ├─ fileController.js
│  └─ categoryController.js
├─ models/                     # DB 쿼리 함수
│  ├─ itemModel.js
│  ├─ auctionModel.js
│  ├─ bidModel.js
│  ├─ likeModel.js
│  ├─ userModel.js
│  └─ categoryModel.js
└─ middleware/
   ├─ auth.js                  # JWT 필수 인증
   └─ optionalAuth.js          # JWT 선택 인증
```

---

## 각 파일 설명

### 진입점

| 파일 | 설명 |
|------|------|
| `server.js` | HTTP 서버 시작, 포트 바인딩 |
| `app.js` | CORS, JSON 파싱, 정적 파일 서빙, 라우터 등록 |

### config/

| 파일 | 설명 |
|------|------|
| `config/db.js` | `mysql2/promise` 커넥션 풀 생성. 환경변수 `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`으로 설정 |
| `config/upload.js` | multer 설정. 업로드 파일을 `uploads/` 하위에 날짜별 폴더로 저장 |

### routes/

각 파일은 URL prefix를 받아 Controller 함수와 연결합니다.

| 파일 | 접두사 | 주요 엔드포인트 |
|------|--------|----------------|
| `routes/items.js` | `/api/items` | `GET /search` — 물품 목록 검색·필터·페이지네이션<br>`GET /calendar` — 월별 물품 조회<br>`GET /:pbacNo/:pbacSrno/:cmdtLnNo` — 물품 상세 |
| `routes/auctions.js` | `/api/auctions` | 공매 목록·상세 |
| `routes/bids.js` | `/api/bids` | 입찰 등록·조회 |
| `routes/likes.js` | `/api/likes` | 찜 추가·제거·목록 |
| `routes/users.js` | `/api/users` | 회원 조회·수정 |
| `routes/auth.js` | `/api/auth` | 회원가입·로그인·토큰 갱신 |
| `routes/files.js` | `/api/files` | 이미지 업로드·다운로드 |
| `routes/categories.js` | `/api/categories` | 카테고리 트리 조회 |

### controllers/

라우터에서 받은 `req`/`res`를 처리하고 Model을 호출합니다.

| 파일 | 설명 |
|------|------|
| `controllers/itemController.js` | 물품 검색(`search`), 캘린더(`calendar`), 상세(`detail`) 처리. `item_search_token`과 `item_classification` JOIN |
| `controllers/auctionController.js` | 공매 헤더 데이터 처리 |
| `controllers/bidController.js` | 입찰 CRUD |
| `controllers/likeController.js` | `user_watchlist_target` 기반 찜 토글 |
| `controllers/userController.js` | 회원 정보 CRUD |
| `controllers/authController.js` | bcrypt 비밀번호 해시, JWT 발급 |
| `controllers/fileController.js` | multer로 파일 수신 후 경로 응답 |
| `controllers/categoryController.js` | `category` 테이블 트리 구조 응답 |

### models/

순수 SQL 쿼리 함수 모음. Controller에서 호출합니다.

| 파일 | 설명 |
|------|------|
| `models/itemModel.js` | `search()` — keyword·categoryId·cstmSgn·page·limit 파라미터로 물품 검색<br>결과에 `cstmName`, `categoryName`, `isFavorite` 포함 |
| `models/auctionModel.js` | `auction` 테이블 조회 |
| `models/bidModel.js` | 입찰 INSERT·SELECT |
| `models/likeModel.js` | 찜 INSERT/DELETE, 목록 SELECT |
| `models/userModel.js` | 회원 SELECT·UPDATE |
| `models/categoryModel.js` | 카테고리 트리 SELECT |

### middleware/

| 파일 | 설명 |
|------|------|
| `middleware/auth.js` | `Authorization: Bearer <token>` 헤더를 검증. 토큰이 없거나 만료되면 401 반환. `req.user`에 디코딩 결과 주입 |
| `middleware/optionalAuth.js` | 토큰이 있으면 검증 후 `req.user` 주입, 없어도 계속 진행. 찜 여부처럼 로그인/비로그인 모두 허용하는 엔드포인트에서 사용 |

---

## 주요 API 요약

### `GET /api/items/search`

| 파라미터 | 타입 | 설명 |
|----------|------|------|
| `keyword` | string | 검색어 (`item_search_token.token LIKE %keyword%`) |
| `categoryId` | number | 카테고리 ID (하위 카테고리 포함) |
| `cstmSgn` | string | 세관 부호 |
| `page` | number | 페이지 번호 (기본 1) |
| `limit` | number | 페이지당 건수 (기본 20) |

응답 예시:
```json
{
  "items": [
    {
      "pbacNo": 12345,
      "pbacSrno": 1,
      "cmdtLnNo": 1,
      "cmdtNm": "LITHIUM BATTERY PACK",
      "cmdtQty": 10,
      "cmdtQtyUtCd": "EA",
      "pbacPrngPrc": 500000,
      "pbacStrtDttm": "2026-05-01 09:00:00",
      "pbacEndDttm": "2026-05-31 18:00:00",
      "cstmName": "인천세관",
      "categoryName": "배터리·전지",
      "isFavorite": 0
    }
  ],
  "total": 142
}
```

### `GET /api/items/calendar`

`year`, `month` 파라미터로 해당 월의 공매 물품을 반환합니다.

### `GET /api/items/:pbacNo/:pbacSrno/:cmdtLnNo`

복합 키 기반 물품 상세. 창고명(`snarName`), 물품 상태 설명(`pbacCondCn`) 등 추가 필드 포함.
