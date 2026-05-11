"""서버 실행 스크립트 - 환경변수 직접 주입"""
import os
os.environ["DB_HOST"] = "localhost"
os.environ["DB_USER"] = "root"
os.environ["DB_PASSWORD"] = "1234"
os.environ["DB_NAME"] = "customs_auction"

import uvicorn
uvicorn.run("app:app", host="0.0.0.0", port=8000, reload=False)
