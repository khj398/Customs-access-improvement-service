"""
E07. 하이브리드 기여도 분석 (ablation)  [권장 · 1시간]  ★ 신규
==============================================================
목적  "왜 규칙만 쓰지 않고 LLM을 붙였는가"에 대한 정량적 답.
      룰 단독 커버리지 vs 룰+LLM 커버리지를 비교해 하이브리드 설계를 정당화한다.

★ 안전 설계 (실험계획서 5.4 경고 1 대응)
    build_classification.py 를 --use-openai 없이 "실제 실행"하면 기존 OpenAI 분류 결과가
    「기타 > 미분류」로 덮어써진다. 그래서 이 스크립트의 기본 모드는 CLI를 아예 실행하지 않고,
    build_classification 모듈의 룰 매칭 함수만 in-process 로 재사용해 커버리지를 계산한다.
      -> DB 쓰기 0회, OpenAI 호출 0회, 비용 0원.

    --via-cli 를 주면 CLI를 호출하되 --dry-run 을 강제로 붙인다(제거 불가).

측정
    (1) 룰 단독 커버리지 : 룰 매칭 성공 건수 / 전체
    (2) 룰+LLM 커버리지  : 룰 매칭 + (룰 미매칭 중 DB에 openai 로 분류된 건수)
    (3) 미분류 감소폭    : (1) -> (2) 로 줄어든 %p

논문 대응  4.2절 표 4 (병합) / 3.3절 서술 근거
실험계획서  6장 E7

실행:
    python Additional_Experiment/scripts/e07_hybrid_ablation.py
    python Additional_Experiment/scripts/e07_hybrid_ablation.py --via-cli
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))

import exp_common as C  # noqa: E402

sys.path.insert(0, str(C.REPO_ROOT / "classification"))


def run_cli_dry_run(extra: list[str]) -> str:
    """build_classification.py 를 --dry-run 강제로 실행하고 출력을 반환."""
    cmd = [sys.executable, str(C.REPO_ROOT / "classification" / "build_classification.py"), "--dry-run"]
    cmd += [a for a in extra if a != "--dry-run"]
    print(f"$ {' '.join(cmd)}")
    proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                          errors="replace", cwd=str(C.REPO_ROOT))
    return (proc.stdout or "") + (("\n[stderr]\n" + proc.stderr) if proc.stderr else "")


def parse_cli_stats(output: str) -> dict:
    stats = {}
    for line in output.splitlines():
        line = line.strip()
        for key, label in [("processed", "- processed items:"),
                           ("rule", "- classified by rule:"),
                           ("openai", "- classified by openai:"),
                           ("fallback", "- fallback:"),
                           ("tokens", "- tokens upserted:")]:
            if line.startswith(label):
                try:
                    stats[key] = int(line.split(":")[1].strip())
                except (IndexError, ValueError):
                    pass
    return stats


def main() -> int:
    ap = argparse.ArgumentParser(description="E07 하이브리드 기여도 분석")
    ap.add_argument("--via-cli", action="store_true",
                    help="build_classification.py 를 --dry-run 강제로 호출해 교차 검증")
    ap.add_argument("--cli-use-openai", action="store_true",
                    help="--via-cli 와 함께 쓸 때 2차 실행에 --use-openai 를 붙인다(API 비용 발생)")
    args = ap.parse_args()

    rep = C.Report("E07", "하이브리드 기여도 분석 (ablation)",
                   paper_ref="4.2절 표 4 (병합)", plan_ref="6장 E7")

    try:
        import build_classification as B
    except Exception as e:  # noqa: BLE001
        C.die(f"build_classification 모듈을 불러올 수 없습니다: {e}")

    conn = C.db_conn()

    # ── 룰 단독 커버리지 (in-process, DB 쓰기 없음) ────
    rep.section("(1) 룰 단독 커버리지 — in-process 계산 (DB 쓰기 없음)")
    rules = B.build_rules(None)
    items = C.fetch_all(conn, B.SQL_FETCH_ITEMS)

    rule_matched = []
    rule_unmatched = []
    rule_hits = Counter()
    for it in items:
        nm = it["cmdt_nm"] or ""
        tokens = B.extract_raw_tokens(B.normalize_text(nm))
        m = B.match_rule(tokens, rules, ko_text=nm)
        if m:
            rule_matched.append(it)
            rule_hits[m[0].name] += 1
        else:
            rule_unmatched.append(it)

    total = len(items)
    n_rule = len(rule_matched)
    rep.table(["항목", "값"],
              [["로드된 룰 수", len(rules)],
               ["전체 물품", f"{total:,}"],
               ["룰 매칭", f"{n_rule:,}"],
               ["룰 미매칭", f"{total - n_rule:,}"],
               ["룰 단독 커버리지", f"{n_rule / total * 100:.1f}%" if total else "-"]])

    # ── 룰 + LLM 커버리지 (현재 DB 상태 기준) ──────────
    rep.section("(2) 룰 + LLM 보완 커버리지 — 현재 DB의 분류 결과 기준")
    cls = {(r["pbac_no"], r["pbac_srno"], r["cmdt_ln_no"]): r for r in C.fetch_all(conn, """
        SELECT ic.pbac_no, ic.pbac_srno, ic.cmdt_ln_no, ic.model_name, ic.confidence,
               c.name_ko AS category_name
        FROM item_classification ic
        LEFT JOIN category c ON c.category_id = ic.category_id
    """)}

    def is_misc(row) -> bool:
        return (row or {}).get("category_name") in ("미분류", "기타")

    llm_rescued = 0
    still_unclassified = 0
    unmatched_rows = []
    for it in rule_unmatched:
        key = (it["pbac_no"], it["pbac_srno"], it["cmdt_ln_no"])
        row = cls.get(key)
        rescued = bool(row) and row.get("model_name") == "openai" and not is_misc(row)
        if rescued:
            llm_rescued += 1
        else:
            still_unclassified += 1
        unmatched_rows.append([it["pbac_no"], it["pbac_srno"], it["cmdt_ln_no"],
                               it["cmdt_nm"], (row or {}).get("model_name", "none"),
                               (row or {}).get("category_name", ""),
                               "LLM 보완" if rescued else "미분류"])

    hybrid = n_rule + llm_rescued
    rep.table(
        ["구분", "건수", "커버리지"],
        [
            ["룰 단독", f"{n_rule:,}", f"{n_rule / total * 100:.1f}%" if total else "-"],
            ["LLM 보완분", f"{llm_rescued:,}", f"{llm_rescued / total * 100:.1f}%p" if total else "-"],
            ["하이브리드 합계", f"{hybrid:,}", f"{hybrid / total * 100:.1f}%" if total else "-"],
            ["여전히 미분류", f"{still_unclassified:,}",
             f"{still_unclassified / total * 100:.1f}%" if total else "-"],
        ],
    )
    rep.csv("rule_unmatched_items.csv",
            ["pbac_no", "pbac_srno", "cmdt_ln_no", "cmdt_nm", "model_name", "category", "판정"],
            unmatched_rows)

    # ── 룰별 기여 ─────────────────────────────────────
    rep.section("룰별 매칭 건수 상위 15개")
    rep.table(["룰 이름", "매칭 건수"],
              [[name, f"{cnt:,}"] for name, cnt in rule_hits.most_common(15)])
    rep.csv("rule_hits.csv", ["rule_name", "matched_items"], rule_hits.most_common())

    rep.data.update({
        "total_items": total,
        "rules_loaded": len(rules),
        "rule_only_coverage": round(n_rule / total * 100, 1) if total else 0,
        "rule_matched": n_rule,
        "llm_rescued": llm_rescued,
        "hybrid_coverage": round(hybrid / total * 100, 1) if total else 0,
        "still_unclassified": still_unclassified,
        "misc_reduction_pp": round(llm_rescued / total * 100, 1) if total else 0,
    })

    # ── CLI 교차 검증 (선택) ──────────────────────────
    if args.via_cli:
        rep.section("(3) CLI 교차 검증 — --dry-run 강제")
        out1 = run_cli_dry_run([])
        s1 = parse_cli_stats(out1)
        rep.table(["항목", "룰 단독 (--dry-run)"],
                  [[k, v] for k, v in s1.items()] or [["파싱 실패", "-"]])
        (rep.out_dir / "cli_rule_only.log").write_text(out1, encoding="utf-8")
        rep.data["cli_rule_only"] = s1

        if args.cli_use_openai:
            out2 = run_cli_dry_run(["--use-openai", "--openai-target-level", "2"])
            s2 = parse_cli_stats(out2)
            rep.table(["항목", "룰+LLM (--dry-run --use-openai)"],
                      [[k, v] for k, v in s2.items()] or [["파싱 실패", "-"]])
            (rep.out_dir / "cli_rule_llm.log").write_text(out2, encoding="utf-8")
            rep.data["cli_rule_llm"] = s2
        else:
            rep.note("--cli-use-openai 를 주지 않아 LLM 호출 실행은 생략했다(API 비용 절약). "
                     "in-process 계산 결과 (1)(2)로 충분히 표를 채울 수 있다.")

    # ── 논문 문장 ─────────────────────────────────────
    rep.section("논문에 넣을 문장 초안")
    if total:
        rep.text(f"규칙 기반 분류만 적용했을 때 커버리지는 {n_rule / total * 100:.1f}%였으며, "
                 f"LLM 보완을 결합한 하이브리드 구성에서는 {hybrid / total * 100:.1f}%로 상승하여 "
                 f"미분류 비율이 {llm_rescued / total * 100:.1f}%p 감소하였다.")

    rep.note("경고: build_classification.py 를 --dry-run 없이 --use-openai 도 없이 전체 실행하면 "
             "기존 OpenAI 분류가 「기타 > 미분류」로 덮어써진다. 부분 갱신이 필요하면 "
             "--rule-only-update 를 사용한다.")

    rep.save()
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
