# Backend (FastAPI) — ⚠️ 레거시

> **현재 프로젝트는 `cais_back/` (Node.js/Express) 를 공식 백엔드로 사용합니다.**  
> 이 디렉터리는 초기 MVP 검증용으로 작성된 FastAPI 서버이며, 더 이상 유지보수되지 않습니다.  
> 신규 기능 추가나 배포에는 [`cais_back/README.md`](../cais_back/README.md)를 참조하세요.

---

## 개요

DB 구축 단계에서 ETL/분류 결과를 빠르게 API로 검증하기 위해 작성된 최소 FastAPI 서버입니다.

## 실행 (레거시)

```bash
cd backend
python -m venv .venv
source .venv/bin/activate    # Windows: .venv\Scripts\activate
pip install -r requirements.txt
uvicorn app:app --reload --host 0.0.0.0 --port 8000
```

## 환경변수

| 변수 | 기본값 |
|------|--------|
| `DB_HOST` | `127.0.0.1` |
| `DB_PORT` | `3306` |
| `DB_USER` | `root` |
| `DB_PASSWORD` | `password` |
| `DB_NAME` | `customs_auction` |

## 엔드포인트 (레거시)

| 경로 | 설명 |
|------|------|
| `GET /health` | 서버 상태 확인 |
| `GET /db/health` | DB 연결 확인 |
| `GET /items?q=&limit=` | 물품 목록 조회 (단순 검색) |
| `GET /items/{pbac_no}/{pbac_srno}/{cmdt_ln_no}/images` | 물품 이미지 URL 목록 |
