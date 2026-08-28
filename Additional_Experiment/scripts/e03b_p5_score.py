"""
E03-b. P@5 판정 집계  [E03 후속]
=================================
e03_search_baseline.py 가 만든 results/E03/p5_judgement.csv 를
2인이 독립 판정(judge1_OX / judge2_OX)한 뒤 집계한다.

산출
    - 질의별 P@5 (두 판정자 합의 기준)
    - 평균 P@5 (설계서 목표 0.80 과 비교)
    - 판정자 간 일치도(%) 및 Cohen's kappa
    - 불일치 건 목록 -> 협의 대상

논문 대응  4.3절 표 5 / 4.3 본문 한 문장
실험계획서  6장 E3 "판정 시 유의"

실행:
    python Additional_Experiment/scripts/e03b_p5_score.py
    python Additional_Experiment/scripts/e03b_p5_score.py --resolve judge1   # 협의 전 잠정 집계
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))

import exp_common as C  # noqa: E402

TARGET_P5 = 0.80


def norm_ox(v: str) -> str:
    v = (v or "").strip().upper()
    if v in ("O", "0", "Y", "YES", "T", "TRUE", "1"):
        return "O"
    if v in ("X", "N", "NO", "F", "FALSE"):
        return "X"
    return ""


def main() -> int:
    ap = argparse.ArgumentParser(description="E03-b P@5 판정 집계")
    ap.add_argument("--file", default=str(C.RESULTS_DIR / "E03" / "p5_judgement.csv"),
                    help="판정지 CSV 경로")
    ap.add_argument("--resolve", choices=["strict", "judge1", "judge2", "lenient"], default="strict",
                    help="불일치 처리: strict=불일치는 부적합(기본), lenient=불일치는 적합, "
                         "judge1/judge2=해당 판정자 값 사용")
    args = ap.parse_args()

    path = Path(args.file)
    if not path.exists():
        C.die(f"판정지가 없습니다: {path}\n   먼저 e03_search_baseline.py 를 실행하세요.")

    rows = C.read_csv(path)
    if not rows:
        C.die("판정지가 비어 있습니다.")

    rep = C.Report("E03b", "P@5 판정 집계", paper_ref="4.3절 표 5", plan_ref="6장 E3")

    # ── 판정 상태 확인 ─────────────────────────────────
    unjudged = [r for r in rows
                if r.get("cmdt_nm") != "(결과 없음)"
                and (not norm_ox(r.get("judge1_OX", "")) or not norm_ox(r.get("judge2_OX", "")))]
    rep.section("판정 상태")
    rep.table(["항목", "값"],
              [["전체 판정 행", len(rows)],
               ["미판정 행", len(unjudged)],
               ["불일치 처리 방식", args.resolve]])
    if unjudged:
        rep.note(f"미판정 {len(unjudged)}행이 있다. 집계는 진행하되 논문 인용 전에 모두 채울 것.")

    # ── 일치도 ────────────────────────────────────────
    both = [(norm_ox(r["judge1_OX"]), norm_ox(r["judge2_OX"])) for r in rows
            if norm_ox(r.get("judge1_OX", "")) and norm_ox(r.get("judge2_OX", ""))]
    agree = sum(1 for a, b in both if a == b)
    n = len(both)
    po = agree / n if n else 0.0
    # Cohen's kappa
    p1o = sum(1 for a, _ in both if a == "O") / n if n else 0
    p2o = sum(1 for _, b in both if b == "O") / n if n else 0
    pe = p1o * p2o + (1 - p1o) * (1 - p2o)
    kappa = (po - pe) / (1 - pe) if n and pe < 1 else 0.0

    rep.section("판정자 간 일치도")
    rep.table(["지표", "값"],
              [["공통 판정 행 수", n],
               ["단순 일치율", f"{po * 100:.1f}%"],
               ["Cohen's kappa", f"{kappa:.3f}"]])
    rep.data["agreement"] = {"n": n, "percent_agreement": round(po * 100, 1), "kappa": round(kappa, 3)}

    disagree = [r for r in rows
                if norm_ox(r.get("judge1_OX", "")) and norm_ox(r.get("judge2_OX", ""))
                and norm_ox(r["judge1_OX"]) != norm_ox(r["judge2_OX"])]
    if disagree:
        rep.section("불일치 건 (협의 대상)")
        rep.table(["#", "질의", "순위", "물품명", "judge1", "judge2"],
                  [[r["no"], r["query"], r["rank"], r["cmdt_nm"][:45],
                    norm_ox(r["judge1_OX"]), norm_ox(r["judge2_OX"])] for r in disagree])
        rep.csv("p5_disagreement.csv",
                ["no", "query", "rank", "cmdt_nm", "judge1_OX", "judge2_OX", "note"],
                [[r["no"], r["query"], r["rank"], r["cmdt_nm"],
                  norm_ox(r["judge1_OX"]), norm_ox(r["judge2_OX"]), r.get("note", "")]
                 for r in disagree])

    # ── 질의별 P@5 ─────────────────────────────────────
    def verdict(r) -> bool:
        j1, j2 = norm_ox(r.get("judge1_OX", "")), norm_ox(r.get("judge2_OX", ""))
        if args.resolve == "judge1":
            return j1 == "O"
        if args.resolve == "judge2":
            return j2 == "O"
        if args.resolve == "lenient":
            return "O" in (j1, j2)
        return j1 == "O" and j2 == "O"  # strict

    per_query: dict = {}
    for r in rows:
        key = (int(r["no"]), r["query"])
        d = per_query.setdefault(key, {"hits": 0, "slots": 0, "empty": 0})
        d["slots"] += 1
        if r.get("cmdt_nm") == "(결과 없음)":
            d["empty"] += 1
            continue
        if verdict(r):
            d["hits"] += 1

    rep.section("질의별 P@5")
    table_rows = []
    p5_values = []
    for (no, q), d in sorted(per_query.items()):
        p5 = d["hits"] / d["slots"] if d["slots"] else 0.0
        p5_values.append(p5)
        table_rows.append([no, q, d["hits"], d["slots"], f"{p5:.2f}",
                           "결과 없음" if d["empty"] == d["slots"] else ""])
    rep.table(["#", "질의", "적합 건수", "판정 슬롯", "P@5", "비고"], table_rows)

    avg_p5 = C.mean(p5_values)
    rep.section("요약")
    rep.table(["지표", "값", "목표", "판정"],
              [["평균 P@5", f"{avg_p5:.3f}", f"{TARGET_P5:.2f}",
                "달성" if avg_p5 >= TARGET_P5 else "미달"]])
    rep.data.update({
        "avg_p5": round(avg_p5, 3),
        "target_p5": TARGET_P5,
        "target_met": avg_p5 >= TARGET_P5,
        "per_query": [{"no": no, "query": q, "p5": round(d["hits"] / d["slots"], 3) if d["slots"] else 0}
                      for (no, q), d in sorted(per_query.items())],
        "unjudged_rows": len(unjudged),
        "resolve_mode": args.resolve,
    })

    rep.note("논문 4.3절에는 평균 P@5 와 함께 \"2인 독립 판정, 일치율 "
             f"{po * 100:.1f}%(kappa {kappa:.2f}), 불일치 {len(disagree)}건은 협의로 확정\"을 한 문장으로 기재한다.")
    if avg_p5 < TARGET_P5:
        rep.note("목표 미달 시에도 수치를 그대로 쓰고, 원인(동의어 사전 커버리지 등)을 5장 향후 과제로 넘긴다.")

    rep.save()
    return 0


if __name__ == "__main__":
    sys.exit(main())
