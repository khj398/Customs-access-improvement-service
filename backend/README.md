# Backend MVP (FastAPI)

DB 구축 단계부터 바로 사용할 수 있는 최소 API 서버입니다.

## 왜 지금 서버를 같이 두는가?
- ETL/분류 결과를 즉시 API로 검증 가능
- 프론트와 병렬 개발 가능
- DB 스키마 변경 영향도를 빠르게 확인 가능

## 실행
```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app:app --reload --host 0.0.0.0 --port 8000
```

## 환경변수
- `DB_HOST` (default: `127.0.0.1`)
- `DB_PORT` (default: `3306`)
- `DB_USER` (default: `root`)
- `DB_PASSWORD` (default: `password`)
- `DB_NAME` (default: `customs_auction`)

## 엔드포인트
- `GET /health`: 서버 상태
- `GET /db/health`: DB 연결 확인
- `GET /items?q=&limit=`: 물품 목록 조회(간단 검색)
- `GET /items/{pbac_no}/{pbac_srno}/{cmdt_ln_no}/images`: 물품 이미지 URL 목록 조회
