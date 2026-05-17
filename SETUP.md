# 세관 경매 서비스 (CAIS) — 팀원 실행 가이드

## 사전 준비 (설치가 필요한 것들)

| 도구 | 버전 | 다운로드 |
|------|------|----------|
| Node.js | 18 이상 | https://nodejs.org |
| Flutter | 3.10 이상 | https://flutter.dev/docs/get-started/install |
| MySQL | 8.0 이상 | https://dev.mysql.com/downloads/ |
| Docker | 최신 | https://www.docker.com/products/docker-desktop (Meilisearch 실행용) |

---

## Step 1 — 코드 받기

```bash
git clone https://github.com/khj398/Customs-access-improvement-service.git
cd Customs-access-improvement-service
```

---

## Step 2 — MySQL DB 세팅

MySQL에 접속한 뒤 아래 순서로 SQL 파일을 실행합니다.

```sql
-- MySQL 클라이언트(DBeaver, Workbench, CLI 등)에서 실행
SOURCE db/schema_create.sql;
SOURCE db/schema_app_user_unified_v1.sql;
SOURCE db/schema_patch_v2.sql;
SOURCE db/schema_patch_v3.sql;
SOURCE db/seed_category.sql;
SOURCE db/seed_category_extend.sql;
SOURCE db/seed_synonym.sql;
SOURCE db/seed_synonym_extend.sql;
```

> 실제 공매 데이터는 ETL 파이프라인으로 적재합니다 (팀장에게 문의).

---

## Step 3 — 백엔드 환경변수 설정

`cais_back/` 폴더 안에 `.env` 파일을 만들어 아래 내용을 채웁니다.

```env
# MySQL
DB_HOST=localhost
DB_PORT=3306
DB_USER=root
DB_PASSWORD=여기에_MySQL_비밀번호
DB_NAME=customs_auction

# Meilisearch
MEILI_HOST=http://localhost:7700
MEILI_MASTER_KEY=cais-search-key

# JWT
JWT_SECRET=여기에_임의의_긴_문자열

# 서버 포트 (기본값 3000)
PORT=3000
```

---

## Step 4 — 백엔드 실행

```bash
cd cais_back
npm install
npm run dev      # nodemon으로 자동 재시작 (개발용)
# 또는
npm start        # 일반 실행
```

터미널에 `CAIS API 서버 실행: http://localhost:3000` 이 뜨면 성공입니다.

---

## Step 5 — Meilisearch 실행 (Docker)

Docker Desktop이 실행 중인 상태에서 아래 명령어를 입력합니다.

```bash
docker run -d --name meilisearch -p 7700:7700 -e MEILI_MASTER_KEY=cais-search-key -e MEILI_ENV=development getmeili/meilisearch:v1.8
```

브라우저에서 `http://localhost:7700` 에 접속했을 때 API key 입력창이 뜨면 성공입니다.  
입력창에 `cais-search-key` 를 입력하면 대시보드로 들어갈 수 있습니다.

> **이미 컨테이너가 있는 경우 (두 번째 실행부터)**  
> ```bash
> docker start meilisearch
> ```

> **컨테이너 상태 확인**  
> ```bash
> docker ps | grep meilisearch
> ```

---

## Step 6 — Meilisearch 인덱스 동기화

MySQL 데이터를 검색 인덱스에 넣는 작업입니다. **백엔드와 Meilisearch가 모두 실행 중인 상태**에서 실행합니다.

```bash
# cais_back 폴더에서 실행
cd cais_back
node scripts/sync_meili.js
```

완료 메시지가 나오면 검색 기능이 활성화됩니다.

---

## Step 7 — Flutter 앱 실행

```bash
cd cais_front
flutter pub get
flutter run -d chrome    # 웹 브라우저
# 또는
flutter run              # 연결된 기기 / 에뮬레이터
```

> **API 주소 변경이 필요한 경우**  
> `cais_front/lib/services/api_config.dart` 파일에서 `baseUrl`을 수정합니다.  
> 기본값: `http://localhost:3000`

---

## 실행 순서 요약

```
[터미널 1] docker start meilisearch          ← 최초엔 docker run ... (Step 5 참고)
[터미널 2] cd cais_back && npm run dev
[터미널 3] node scripts/sync_meili.js        ← 최초 1회 또는 데이터 변경 시
[터미널 4] cd cais_front && flutter run -d chrome
```

---

## 자주 발생하는 문제

| 증상 | 원인 | 해결 |
|------|------|------|
| `ECONNREFUSED 3000` | 백엔드 미실행 | Step 4 확인 |
| 검색 결과 없음 | Meilisearch 미동기화 | Step 6 재실행 |
| `Access denied for user` | DB 비밀번호 오류 | `.env` 파일 확인 |
| Flutter 빌드 오류 | 패키지 미설치 | `flutter pub get` 재실행 |
| Meilisearch 인증 오류 | master-key 불일치 | `.env`의 `MEILI_MASTER_KEY`와 실행 옵션 일치 여부 확인 |
