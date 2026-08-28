"""
E04. 오타 허용 검증  [필수 · 10분]
==================================
목적  3차 데모 시나리오의 "오타가 입력되어도 관련 물품이 검색된다"를 수치로 고정한다.

절차  정상 질의와 오타 질의 쌍 5개(부록 A-2)에 대해 각각 검색하고,
      정상 질의의 상위 5건이 오타 질의에서도 나오는지 확인한다.

Meilisearch 설정: 4자 이상 1회, 8자 이상 2회 오타 허용
  -> 2~3자 한글 질의는 오타 보정이 되지 않는 것이 정상이며, 이 한계도 결과에 함께 적는다.

논문 대응  4.3절 표 5 (하단 병합)
실험계획서  6장 E4

실행:
    python Additional_Experiment/scripts/e04_typo_tolerance.py
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))

import exp_common as C  # noqa: E402


def key_of(item: dict) -> tuple:
    return (item.get("pbacNo"), item.get("pbacSrno"), item.get("cmdtLnNo"))


def main() -> int:
    ap = argparse.ArgumentParser(description="E04 오타 허용 검증")
    ap.add_argument("--topk", type=int, default=5)
    args = ap.parse_args()

    rep = C.Report("E04", "오타 허용 검증", paper_ref="4.3절 표 5 (하단)", plan_ref="6장 E4")
    qs = C.load_queryset()
    pairs = qs["typo_pairs"]
    setting = qs.get("typo_tolerance_setting", {})

    rep.section("실험 조건")
    rep.table(["항목", "값"],
              [["질의쌍 수", len(pairs)],
               ["검색 경로", f"{C.api_base()}/api/items/search"],
               ["오타 허용 설정", f"oneTypo>={setting.get('minWordSizeForTypos', {}).get('oneTypo', 4)}자, "
                                  f"twoTypos>={setting.get('minWordSizeForTypos', {}).get('twoTypos', 8)}자"],
               ["설정 출처", setting.get("source", "cais_back/scripts/sync_meili.js")]])

    rows = []
    detail_rows = []
    recovered = 0
    for p in pairs:
        normal, typo = p["normal"], p["typo"]
        r_norm = C.api_search(normal, limit=args.topk)
        r_typo = C.api_search(typo, limit=args.topk)

        if not (r_norm["ok"] and r_typo["ok"]):
            rows.append([p["no"], normal, typo, len(normal),
                         "ERR" if not r_norm["ok"] else len(r_norm["items"]),
                         "ERR" if not r_typo["ok"] else len(r_typo["items"]),
                         "-", "-", (r_norm["error"] or r_typo["error"] or "")[:40]])
            continue

        n_items, t_items = r_norm["items"], r_typo["items"]
        n_keys = [key_of(i) for i in n_items]
        t_keys = [key_of(i) for i in t_items]
        overlap = len(set(n_keys) & set(t_keys))
        match = "O" if overlap > 0 else "X"
        if overlap > 0:
            recovered += 1

        rows.append([p["no"], normal, typo, len(typo), len(n_items), len(t_items),
                     f"{overlap}/{len(n_keys) or args.topk}", match, p["note"]])

        for rank, it in enumerate(n_items, 1):
            detail_rows.append([p["no"], normal, "정상", rank, it.get("cmdtNm", "")])
        for rank, it in enumerate(t_items, 1):
            detail_rows.append([p["no"], typo, "오타", rank, it.get("cmdtNm", "")])

    rep.section("질의쌍별 결과")
    rep.table(["#", "정상 질의", "오타 질의", "질의 길이", "정상 결과수", "오타 결과수",
               "상위 5건 일치", "보정 여부", "비고"], rows)
    rep.csv("typo_results.csv",
            ["no", "normal", "typo", "typo_len", "normal_count", "typo_count",
             "top5_overlap", "recovered_OX", "note"], rows)
    if detail_rows:
        rep.csv("typo_top5_items.csv", ["no", "query", "type", "rank", "cmdt_nm"], detail_rows)

    # ── 요약 ──────────────────────────────────────────
    rep.section("요약")
    ge4 = [r for r in rows if isinstance(r[3], int) and r[3] >= 4]
    lt4 = [r for r in rows if isinstance(r[3], int) and r[3] < 4]
    ge4_ok = sum(1 for r in ge4 if r[7] == "O")
    lt4_ok = sum(1 for r in lt4 if r[7] == "O")
    rep.table(
        ["구간", "질의쌍 수", "보정 성공", "해석"],
        [
            ["4자 이상 (보정 기대 구간)", len(ge4), ge4_ok, "성공해야 정상"],
            ["3자 이하 (보정 미적용 구간)", len(lt4), lt4_ok, "실패가 설정상 정상 동작"],
        ],
    )
    rep.data.update({
        "pairs": len(pairs),
        "recovered": recovered,
        "ge4_pairs": len(ge4), "ge4_recovered": ge4_ok,
        "lt4_pairs": len(lt4), "lt4_recovered": lt4_ok,
        "rows": [{"no": r[0], "normal": r[1], "typo": r[2], "normal_count": r[4],
                  "typo_count": r[5], "recovered": r[7]} for r in rows],
    })
    rep.note("논문에는 \"4자 이상 질의에서는 오타가 보정되고, 3자 이하 질의는 Meilisearch "
             "오타 허용 설정(oneTypo>=4자)상 보정되지 않는다\"는 한계를 함께 기재한다. "
             "한계를 명시하는 편이 설정을 이해하고 있다는 근거가 된다.")

    rep.save()
    return 0


if __name__ == "__main__":
    sys.exit(main())
