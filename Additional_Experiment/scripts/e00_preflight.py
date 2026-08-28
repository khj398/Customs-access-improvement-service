"""
E00. 사전 점검 (Preflight)
==========================
실험계획서 5.1 환경 체크리스트 / 5.2 스냅샷 고정 상태를 자동 점검한다.
어떤 실험도 이 스크립트가 통과한 뒤에 시작한다.

실행:
    python Additional_Experiment/scripts/e00_preflight.py

점검 항목
    1. Python 의존성 (pymysql / requests / yaml / openai)
    2. MySQL 연결 및 필수 테이블 존재 / 적재 건수
    3. Meilisearch 상태 및 색인 문서 수
    4. cais_back REST API (/api/items/search) 응답
    5. OPENAI_API_KEY 설정 여부 (E7 / E13용)
    6. 데이터 스냅샷 고정 여부 (5.2)
"""

from __future__ import annotations

import importlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))

import exp_common as C  # noqa: E402

REQUIRED_TABLES = [
    "auction",
    "auction_item",
    "auction_item_image",
    "customs_office",
    "category",
    "item_classification",
    "item_search_token",
    "synonym_dictionary",
]
OPTIONAL_TABLES = ["ingestion_run", "user_watchlist_target"]

PASS, WARN, FAIL = "PASS", "WARN", "FAIL"


def main() -> int:
    rep = C.Report("E00", "사전 점검 (Preflight)", plan_ref="5.1 환경 체크리스트 / 5.2 스냅샷 고정")
    checks: list[list[str]] = []

    def add(name: str, status: str, detail: str = ""):
        detail = " ".join(str(detail).split())
        if len(detail) > 96:
            detail = detail[:93] + "..."
        checks.append([name, status, detail])
        print(f"  [{status}] {name}" + (f" — {detail}" if detail else ""))

    # ── 1. Python 의존성 ────────────────────────────────
    rep.section("1. Python 의존성")
    for mod, need in [("pymysql", True), ("requests", True), ("yaml", True), ("openai", False)]:
        try:
            importlib.import_module(mod)
            add(f"모듈 {mod}", PASS, "설치됨")
        except ModuleNotFoundError:
            add(f"모듈 {mod}", FAIL if need else WARN,
                "미설치 - pip install -r Additional_Experiment/requirements.txt"
                + ("" if need else " (E7·E13에서만 필요)"))

    # ── 2. MySQL ───────────────────────────────────────
    rep.section("2. MySQL")
    conn = None
    counts: dict[str, int] = {}
    try:
        import pymysql  # noqa: F401
        from pymysql.cursors import DictCursor

        cfg = C.db_config()
        conn = pymysql.connect(cursorclass=DictCursor, **cfg)
        add("MySQL 연결", PASS, f"{cfg['user']}@{cfg['host']}:{cfg['port']}/{cfg['database']}")
    except Exception as e:  # noqa: BLE001
        add("MySQL 연결", FAIL, str(e)[:90])

    if conn:
        for t in REQUIRED_TABLES:
            if C.table_exists(conn, t):
                n = int(C.scalar(conn, f"SELECT COUNT(*) FROM `{t}`") or 0)
                counts[t] = n
                add(f"테이블 {t}", PASS if n > 0 else WARN, f"{n}행")
            else:
                add(f"테이블 {t}", FAIL, "없음 - db/schema_create.sql 및 patch 적용 필요")
        for t in OPTIONAL_TABLES:
            if C.table_exists(conn, t):
                n = int(C.scalar(conn, f"SELECT COUNT(*) FROM `{t}`") or 0)
                counts[t] = n
                add(f"테이블 {t} (선택)", PASS, f"{n}행")
            else:
                add(f"테이블 {t} (선택)", WARN, "없음 - E11 등 일부 실험 제한")

        # 분류 커버리지 간이 확인
        if counts.get("auction_item") and counts.get("item_classification") is not None:
            ai, ic = counts["auction_item"], counts["item_classification"]
            ratio = ic / ai * 100 if ai else 0
            add("분류 적재율", PASS if ratio >= 99 else WARN,
                f"{ic}/{ai} ({ratio:.1f}%) - 낮으면 build_classification.py 재실행 필요")

    # ── 3. Meilisearch ─────────────────────────────────
    rep.section("3. Meilisearch")
    try:
        import requests

        h = requests.get(f"{C.meili_host()}/health", timeout=5)
        add("Meilisearch health", PASS if h.status_code == 200 else FAIL, f"HTTP {h.status_code}")
        st = requests.get(
            f"{C.meili_host()}/indexes/auction_items/stats",
            headers=C.meili_headers(), timeout=5,
        )
        if st.status_code == 200:
            docs = st.json().get("numberOfDocuments", 0)
            add("색인 auction_items", PASS if docs > 0 else WARN,
                f"{docs}건 - 0이면 node cais_back/scripts/sync_meili.js 실행")
        else:
            add("색인 auction_items", FAIL, f"HTTP {st.status_code} (마스터키 확인)")
    except Exception as e:  # noqa: BLE001
        add("Meilisearch", FAIL, f"{C.meili_host()} 접속 불가: {str(e)[:70]}")

    # ── 4. 백엔드 API ──────────────────────────────────
    rep.section("4. cais_back REST API")
    r = C.api_search("와인", limit=5)
    if r["ok"]:
        add("GET /api/items/search", PASS, f"{len(r['items'])}건, {r['elapsed_ms']:.0f}ms")
    else:
        add("GET /api/items/search", FAIL, f"{C.api_base()} - {r['error']}")
    a = C.api_autocomplete("와")
    add("GET /api/items/autocomplete", PASS if a["ok"] else WARN,
        f"{len(a['suggestions'])}건" if a["ok"] else str(a["error"])[:70])

    # ── 5. OpenAI ──────────────────────────────────────
    rep.section("5. OpenAI (E7 · E13 전용)")
    key = C.env("OPENAI_API_KEY", "")
    add("OPENAI_API_KEY", PASS if key else WARN,
        f"설정됨 (끝 4자리 {key[-4:]})" if key
        else "미설정 - E13 수행 불가 / E07은 기본 모드(in-process)로 수행 가능")

    # ── 6. 스냅샷 고정 ─────────────────────────────────
    rep.section("6. 데이터 스냅샷 (실험계획서 5.2)")
    snaps = sorted(p for p in C.SNAPSHOT_DIR.glob("eval_snapshot_*") if p.is_dir())
    if snaps:
        latest = snaps[-1]
        commit = (latest / "COMMIT.txt")
        add("스냅샷 폴더", PASS, latest.name)
        add("커밋 해시 기록", PASS if commit.exists() else WARN,
            commit.read_text(encoding="utf-8").strip()[:60] if commit.exists() else "COMMIT.txt 없음")
        for f in ("unipass_all_2b.json", "unipass_all_2c.json"):
            add(f"스냅샷 {f}", PASS if (latest / f).exists() else WARN,
                "복사됨" if (latest / f).exists() else "없음")
        dump = list(latest.glob("db_before.*"))
        add("DB 백업", PASS if dump else WARN,
            dump[0].name if dump else "없음 - snapshot/make_snapshot.ps1 실행 권장")
    else:
        add("스냅샷 폴더", FAIL,
            "없음 - 실험 전에 snapshot/make_snapshot.ps1 을 먼저 실행할 것")

    # ── 결과 ───────────────────────────────────────────
    rep.section("점검 결과")
    rep.table(["점검 항목", "상태", "비고"], checks)

    n_fail = sum(1 for c in checks if c[1] == FAIL)
    n_warn = sum(1 for c in checks if c[1] == WARN)
    rep.data["checks"] = [{"name": c[0], "status": c[1], "detail": c[2]} for c in checks]
    rep.data["table_counts"] = counts
    rep.data["fail"] = n_fail
    rep.data["warn"] = n_warn

    if n_fail:
        rep.note(f"FAIL {n_fail}건 · WARN {n_warn}건 — FAIL 항목을 해결한 뒤 실험을 시작한다.")
    elif n_warn:
        rep.note(f"WARN {n_warn}건 — 해당 실험만 제한된다. 나머지는 진행 가능.")
    else:
        rep.note("모든 점검 통과 — E1부터 순서대로 진행 가능.")

    rep.save()
    if conn:
        conn.close()
    return 1 if n_fail else 0


if __name__ == "__main__":
    sys.exit(main())
