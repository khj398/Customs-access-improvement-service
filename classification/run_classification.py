"""분류 실행 래퍼 — 환경변수 자동 주입"""
import os, sys
from pathlib import Path

os.environ["DB_HOST"] = "localhost"
os.environ["DB_USER"] = "root"
os.environ["DB_PASSWORD"] = "1234"
os.environ["DB_NAME"] = "customs_auction"

# build_classification.py 위치를 sys.path에 추가
sys.path.insert(0, str(Path(__file__).parent))
from build_classification import main
main()
