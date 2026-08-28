"""
exp_common.py - Additional_Experiment 공통 유틸
================================================
S108 졸업논문 실험계획서 v1.0 의 E1~E13 실험 스크립트가 공유하는 기능.

제공 기능
    - .env 로딩 (Additional_Experiment/config/.env -> 저장소 루트 .env -> cais_back/.env)
    - MySQL 연결 (pymysql)
    - cais_back REST API / Meilisearch 호출 래퍼
    - 부록 A 질의셋 로딩
    - 콘솔 출력(UTF-8 강제) + Markdown/JSON/CSV 결과 저장
"""

from __future__ import annotations

import csv
import io
import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence

# ──────────────────────────────────────────────
# 경로
# ──────────────────────────────────────────────
EXP_ROOT = Path(__file__).resolve().parents[1]          # Additional_Experiment/
REPO_ROOT = EXP_ROOT.parent                             # 저장소 루트
CONFIG_DIR = EXP_ROOT / "config"
RESULTS_DIR = EXP_ROOT / "results"
TEMPLATES_DIR = EXP_ROOT / "templates"
SNAPSHOT_DIR = EXP_ROOT / "snapshot"


# ──────────────────────────────────────────────
# 콘솔 UTF-8 (Windows cp949 대응)
# ──────────────────────────────────────────────
def fix_console() -> None:
    enc = (sys.stdout.encoding or "").lower()
    if enc not in ("utf-8", "utf8"):
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
        sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")


fix_console()


# ──────────────────────────────────────────────
# .env 로딩
# ──────────────────────────────────────────────
ENV_FILES = [
    CONFIG_DIR / ".env",
    REPO_ROOT / ".env",
    REPO_ROOT / "cais_back" / ".env",
]


def load_env(verbose: bool = False) -> None:
    """이미 설정된 환경변수는 덮어쓰지 않는다(셸 지정값 우선)."""
    for path in ENV_FILES:
        if not path.exists():
            continue
        for line in path.read_text(encoding="utf-8-sig").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = value
        if verbose:
            print(f"[env] loaded: {path}")


load_env()


def env(key: str, default: str = "") -> str:
    return os.getenv(key, default)


# ──────────────────────────────────────────────
# MySQL
# ──────────────────────────────────────────────
def db_config() -> Dict[str, Any]:
    return {
        "host": env("DB_HOST", "127.0.0.1"),
        "port": int(env("DB_PORT", "3306")),
        "user": env("DB_USER", "root"),
        "password": env("DB_PASSWORD", ""),
        "database": env("DB_NAME", "customs_auction"),
        "charset": "utf8mb4",
    }


def db_conn():
    """pymysql 연결 반환. 실패 시 원인과 조치를 함께 출력하고 종료."""
    try:
        import pymysql
        from pymysql.cursors import DictCursor
    except ModuleNotFoundError:
        die(
            "pymysql 이 설치되어 있지 않습니다.\n"
            f"   설치: {sys.executable} -m pip install -r Additional_Experiment/requirements.txt"
        )

    cfg = db_config()
    try:
        return pymysql.connect(cursorclass=DictCursor, **cfg)
    except Exception as e:  # noqa: BLE001
        die(
            f"MySQL 연결 실패: {e}\n"
            f"   현재 설정: user={cfg['user']} host={cfg['host']}:{cfg['port']} db={cfg['database']}\n"
            "   Additional_Experiment/config/.env 를 확인하세요 (config/.env.example 참고)."
        )


def fetch_all(conn, sql: str, params: Sequence = ()) -> List[Dict]:
    with conn.cursor() as cur:
        cur.execute(sql, params)
        return list(cur.fetchall())


def fetch_one(conn, sql: str, params: Sequence = ()) -> Optional[Dict]:
    rows = fetch_all(conn, sql, params)
    return rows[0] if rows else None


def scalar(conn, sql: str, params: Sequence = ()) -> Any:
    row = fetch_one(conn, sql, params)
    if not row:
        return None
    return list(row.values())[0]


def table_exists(conn, name: str) -> bool:
    return bool(
        scalar(
            conn,
            "SELECT COUNT(*) FROM information_schema.tables "
            "WHERE table_schema = %s AND table_name = %s",
            (db_config()["database"], name),
        )
    )


# ──────────────────────────────────────────────
# cais_back API / Meilisearch
# ──────────────────────────────────────────────
def api_base() -> str:
    return env("API_BASE", "http://localhost:3000").rstrip("/")


def meili_host() -> str:
    return env("MEILI_HOST", "http://localhost:7700").rstrip("/")


def meili_headers() -> Dict[str, str]:
    key = env("MEILI_MASTER_KEY", "")
    return {"Authorization": f"Bearer {key}"} if key else {}


def _requests():
    try:
        import requests

        return requests
    except ModuleNotFoundError:
        die(
            "requests 가 설치되어 있지 않습니다.\n"
            f"   설치: {sys.executable} -m pip install -r Additional_Experiment/requirements.txt"
        )


def api_search(keyword: str, limit: int = 20, timeout: float = 15.0) -> Dict[str, Any]:
    """
    cais_back /api/items/search 호출.
    반환: {"ok": bool, "items": [...], "elapsed_ms": float, "error": str|None}
    """
    requests = _requests()
    url = f"{api_base()}/api/items/search"
    t0 = time.perf_counter()
    try:
        r = requests.get(url, params={"keyword": keyword, "limit": limit}, timeout=timeout)
        elapsed = (time.perf_counter() - t0) * 1000
        if r.status_code != 200:
            return {"ok": False, "items": [], "elapsed_ms": elapsed, "error": f"HTTP {r.status_code}"}
        items = r.json().get("items", []) or []
        return {"ok": True, "items": items, "elapsed_ms": elapsed, "error": None}
    except Exception as e:  # noqa: BLE001
        return {
            "ok": False,
            "items": [],
            "elapsed_ms": (time.perf_counter() - t0) * 1000,
            "error": str(e),
        }


def api_autocomplete(q: str, timeout: float = 15.0) -> Dict[str, Any]:
    requests = _requests()
    url = f"{api_base()}/api/items/autocomplete"
    t0 = time.perf_counter()
    try:
        r = requests.get(url, params={"q": q}, timeout=timeout)
        elapsed = (time.perf_counter() - t0) * 1000
        if r.status_code != 200:
            return {"ok": False, "suggestions": [], "elapsed_ms": elapsed, "error": f"HTTP {r.status_code}"}
        return {
            "ok": True,
            "suggestions": r.json().get("suggestions", []) or [],
            "elapsed_ms": elapsed,
            "error": None,
        }
    except Exception as e:  # noqa: BLE001
        return {
            "ok": False,
            "suggestions": [],
            "elapsed_ms": (time.perf_counter() - t0) * 1000,
            "error": str(e),
        }


def meili_search(keyword: str, limit: int = 20, timeout: float = 15.0) -> Dict[str, Any]:
    """Meilisearch 직접 조회 (estimatedTotalHits 확보용)."""
    requests = _requests()
    url = f"{meili_host()}/indexes/auction_items/search"
    t0 = time.perf_counter()
    try:
        r = requests.post(
            url,
            json={"q": keyword, "limit": limit},
            headers={**meili_headers(), "Content-Type": "application/json"},
            timeout=timeout,
        )
        elapsed = (time.perf_counter() - t0) * 1000
        if r.status_code != 200:
            return {"ok": False, "hits": [], "total": 0, "elapsed_ms": elapsed, "error": f"HTTP {r.status_code}"}
        data = r.json()
        return {
            "ok": True,
            "hits": data.get("hits", []),
            "total": data.get("estimatedTotalHits", len(data.get("hits", []))),
            "elapsed_ms": elapsed,
            "error": None,
        }
    except Exception as e:  # noqa: BLE001
        return {
            "ok": False,
            "hits": [],
            "total": 0,
            "elapsed_ms": (time.perf_counter() - t0) * 1000,
            "error": str(e),
        }


# ──────────────────────────────────────────────
# 질의셋 (실험계획서 부록 A)
# ──────────────────────────────────────────────
def load_queryset() -> Dict[str, Any]:
    path = CONFIG_DIR / "queryset.json"
    if not path.exists():
        die(f"질의셋 파일이 없습니다: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def korean_queries() -> List[Dict[str, Any]]:
    return load_queryset()["korean_queries"]


def typo_pairs() -> List[Dict[str, Any]]:
    return load_queryset()["typo_pairs"]


# ──────────────────────────────────────────────
# 통계 유틸
# ──────────────────────────────────────────────
def percentile(values: Sequence[float], pct: float) -> float:
    """nearest-rank 백분위수 (측정 표본을 그대로 보고하기 위해 보간하지 않음)."""
    if not values:
        return 0.0
    ordered = sorted(values)
    idx = int(-(-pct / 100.0 * len(ordered) // 1)) - 1  # ceil(p/100 * n) - 1
    return ordered[max(0, min(idx, len(ordered) - 1))]


def mean(values: Sequence[float]) -> float:
    return sum(values) / len(values) if values else 0.0


# ──────────────────────────────────────────────
# 출력 / 결과 저장
# ──────────────────────────────────────────────
def die(msg: str, code: int = 1):
    print(f"[FAIL] {msg}")
    sys.exit(code)


def md_table(headers: Sequence[str], rows: Iterable[Sequence[Any]]) -> str:
    out = [
        "| " + " | ".join(str(h) for h in headers) + " |",
        "|" + "|".join("---" for _ in headers) + "|",
    ]
    for r in rows:
        out.append("| " + " | ".join("" if c is None else str(c) for c in r) + " |")
    return "\n".join(out)


def _display_width(s: str) -> int:
    """한글(전각) 폭을 2로 계산."""
    width = 0
    for ch in s:
        code = ord(ch)
        width += 2 if (0x1100 <= code <= 0x115F or 0x2E80 <= code <= 0xA4CF
                       or 0xAC00 <= code <= 0xD7A3 or 0xF900 <= code <= 0xFAFF
                       or 0xFE30 <= code <= 0xFE6F or 0xFF00 <= code <= 0xFF60
                       or 0xFFE0 <= code <= 0xFFE6) else 1
    return width


def console_table(headers: Sequence[str], rows: Iterable[Sequence[Any]]) -> str:
    rows = [[("" if c is None else str(c)) for c in r] for r in rows]
    headers = [str(h) for h in headers]
    widths = [_display_width(h) for h in headers]
    for r in rows:
        for i, c in enumerate(r):
            if i < len(widths):
                widths[i] = max(widths[i], _display_width(c))

    def fmt(cells):
        return "  ".join(
            c + " " * max(0, widths[i] - _display_width(c)) for i, c in enumerate(cells)
        )

    lines = [fmt(headers), "  ".join("-" * w for w in widths)]
    lines += [fmt(r) for r in rows]
    return "\n".join(lines)


def rel(path: Path) -> str:
    """저장소 기준 상대경로. 저장소 밖 경로면 절대경로를 그대로 돌려준다."""
    path = Path(path)
    try:
        return path.resolve().relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return str(path)


def now_stamp() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def run_id() -> str:
    return env("EXP_RUN_ID", datetime.now().strftime("%Y%m%d"))


class Report:
    """
    실험 1건의 결과를 콘솔 출력 + Markdown + JSON 으로 남긴다.

        rep = Report("E01", "데이터셋 기초 통계", paper_ref="4.1절 표 3")
        rep.section("전체 규모")
        rep.table(["항목", "값"], rows)
        rep.note("판정: ...")
        rep.data["total_items"] = 512
        rep.save()
    """

    def __init__(self, exp_id: str, title: str, paper_ref: str = "", plan_ref: str = ""):
        self.exp_id = exp_id
        self.title = title
        self.paper_ref = paper_ref
        self.plan_ref = plan_ref
        self.lines: List[str] = []
        self.data: Dict[str, Any] = {
            "exp_id": exp_id,
            "title": title,
            "paper_ref": paper_ref,
            "executed_at": now_stamp(),
            "run_id": run_id(),
        }
        self.out_dir = RESULTS_DIR / exp_id
        self.out_dir.mkdir(parents=True, exist_ok=True)
        self.lines.append(f"# [{exp_id}] {title}")
        self.lines.append("")
        self.lines.append(f"- 실행 시각: {self.data['executed_at']}")
        if paper_ref:
            self.lines.append(f"- 논문 대응: {paper_ref}")
        if plan_ref:
            self.lines.append(f"- 실험계획서: {plan_ref}")
        self.lines.append("")
        print("=" * 72)
        print(f"  [{exp_id}] {title}" + (f"   -> {paper_ref}" if paper_ref else ""))
        print("=" * 72)

    def section(self, title: str):
        self.lines.append("")
        self.lines.append(f"## {title}")
        self.lines.append("")
        print(f"\n-- {title} " + "-" * max(0, 60 - _display_width(title)))

    def text(self, s: str = ""):
        self.lines.append(s)
        print(s)

    def note(self, s: str):
        self.lines.append("")
        self.lines.append(f"> {s}")
        self.lines.append("")
        print(f"  > {s}")

    def table(self, headers: Sequence[str], rows: Sequence[Sequence[Any]]):
        rows = [list(r) for r in rows]
        self.lines.append(md_table(headers, rows))
        self.lines.append("")
        print(console_table(headers, rows))

    def csv(self, filename: str, headers: Sequence[str], rows: Sequence[Sequence[Any]]) -> Path:
        path = self.out_dir / filename
        with open(path, "w", encoding="utf-8-sig", newline="") as f:
            w = csv.writer(f)
            w.writerow(headers)
            w.writerows(rows)
        self.lines.append(f"- 데이터 파일: `{rel(path)}`")
        print(f"  [saved] {rel(path)}")
        return path

    def save(self) -> Path:
        md_path = self.out_dir / "report.md"
        json_path = self.out_dir / "data.json"
        md_path.write_text("\n".join(self.lines) + "\n", encoding="utf-8")
        json_path.write_text(
            json.dumps(self.data, ensure_ascii=False, indent=2, default=str), encoding="utf-8"
        )
        self._append_run_log()
        print(f"\n[report] {rel(md_path)}")
        print(f"[data]   {rel(json_path)}")
        return md_path

    def _append_run_log(self):
        log = RESULTS_DIR / "RUN_LOG.md"
        if not log.exists():
            log.write_text(
                "# 실험 실행 로그\n\n| 실행 시각 | 실험 | 제목 | 결과 파일 |\n|---|---|---|---|\n",
                encoding="utf-8",
            )
        with open(log, "a", encoding="utf-8") as f:
            f.write(
                f"| {self.data['executed_at']} | {self.exp_id} | {self.title} | "
                f"`results/{self.exp_id}/report.md` |\n"
            )


def load_result(exp_id: str) -> Optional[Dict[str, Any]]:
    """다른 실험 결과(JSON)를 읽어온다 (collect_results.py 용)."""
    path = RESULTS_DIR / exp_id / "data.json"
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def read_csv(path: Path) -> List[Dict[str, str]]:
    with open(path, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def write_csv(path: Path, headers: Sequence[str], rows: Sequence[Sequence[Any]]) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(headers)
        w.writerows(rows)
    return path
