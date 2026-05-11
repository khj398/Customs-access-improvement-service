"""분류 실행 래퍼 — 환경변수 자동 주입
사용법:
  python classification/run_classification.py                  # Rule만
  python classification/run_classification.py --use-openai     # Rule + OpenAI fallback (중분류)
  python classification/run_classification.py --rule-only-update  # Rule 매칭 물품만 업데이트
"""
import os, sys
from pathlib import Path

os.environ["DB_HOST"]     = "localhost"
os.environ["DB_USER"]     = "root"
os.environ["DB_PASSWORD"] = "1234"
os.environ["DB_NAME"]     = "customs_auction"

# OPENAI_API_KEY: 이미 환경변수에 설정돼 있으면 그대로 사용.
# 없으면 아래 주석을 해제하고 실제 키를 입력하세요.
# os.environ["OPENAI_API_KEY"] = "sk-..."

sys.path.insert(0, str(Path(__file__).parent))
from build_classification import main
main()
