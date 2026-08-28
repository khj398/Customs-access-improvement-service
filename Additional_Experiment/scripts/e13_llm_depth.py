"""
E13. LLM 분류 깊이 비교 (중분류 vs 소분류)  [선택 · 1시간]  ★ 신규
===================================================================
목적  설계서(CLASSIFICATION_LOGIC_DESIGN.md)는 중분류(level-2) 타깃을 권장하지만,
      build_classification.py 의 --openai-target-level 기본값은 3(소분류)이다.
      문서와 코드가 어긋나 있으므로 어느 쪽을 논문에 쓸지 실측으로 정한다.

방법  룰 미매칭 물품 30건을 고정 표본(RAND 시드 고정)으로 잡고,
      OpenAIClassifier 를 target_level=2 / 3 으로 각각 호출해 결과를 비교한다.
      DB 에는 아무것도 쓰지 않는다(dry-run 성격).

자동 산출 지표
    - 카테고리 트리 해석 성공률: LLM 이 반환한 경로가 실제 트리에 존재하는 비율
    - 평균 confidence
    - 두 설정의 대분류 일치율
사람 판정
    - results/E13/depth_compare.csv 의 judge_level2 / judge_level3 열에 O/X 를 채운 뒤
      --score 로 재실행하면 정확도가 집계된다.

★ 비용 주의  실제 OpenAI API 를 호출한다(표본 30건 x 2회 = 60콜).
             기본은 표본만 뽑는 미리보기이고, --run 을 줘야 호출한다.

논문 대응  3.3.3절 서술 근거 / 팀 내 설정 확정
실험계획서  6장 E13

실행:
    python Additional_Experiment/scripts/e13_llm_depth.py            # 표본 미리보기
    python Additional_Experiment/scripts/e13_llm_depth.py --run      # 실제 비교 실행
    python Additional_Experiment/scripts/e13_llm_depth.py --score    # 사람 판정 집계
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))

import exp_common as C  # noqa: E402

sys.path.insert(0, str(C.REPO_ROOT / "classification"))

CSV_NAME = "depth_compare.csv"
CSV_HEADERS = ["no", "pbac_no", "pbac_srno", "cmdt_ln_no", "cmdt_nm",
               "level2_path", "level2_conf", "level2_resolved",
               "level3_path", "level3_conf", "level3_resolved",
               "judge_level2", "judge_level3", "note"]


def ox(v: str) -> bool:
    return (v or "").strip().upper() in ("O", "Y", "1", "TRUE")


def score_mode(rep: C.Report) -> int:
    path = rep.out_dir / CSV_NAME
    if not path.exists():
        C.die(f"비교 결과가 없습니다: {path}\n   먼저 --run 으로 실행하세요.")
    rows = C.read_csv(path)
    judged2 = [r for r in rows if (r.get("judge_level2") or "").strip()]
    judged3 = [r for r in rows if (r.get("judge_level3") or "").strip()]
    acc2 = sum(1 for r in judged2 if ox(r["judge_level2"])) / len(judged2) if judged2 else 0
    acc3 = sum(1 for r in judged3 if ox(r["judge_level3"])) / len(judged3) if judged3 else 0

    rep.section("사람 판정 집계")
    rep.table(["설정", "판정 건수", "정답", "정확도"],
              [["target-level 2 (중분류)", len(judged2),
                sum(1 for r in judged2 if ox(r["judge_level2"])), f"{acc2 * 100:.1f}%"],
               ["target-level 3 (소분류)", len(judged3),
                sum(1 for r in judged3 if ox(r["judge_level3"])),
                f"{acc3 * 100:.1f}%"]])
    rep.data.update({"judged_level2": len(judged2), "judged_level3": len(judged3),
                     "accuracy_level2": round(acc2 * 100, 1),
                     "accuracy_level3": round(acc3 * 100, 1)})
    diff = (acc2 - acc3) * 100
    rep.section("논문 문장 초안")
    rep.text(f"LLM 분류 깊이를 중분류로 제한했을 때 정확도는 {acc2 * 100:.1f}%였고, "
             f"소분류까지 요구한 경우 {acc3 * 100:.1f}%로 {abs(diff):.1f}%p "
             f"{'낮았다' if diff > 0 else '높았다'}. "
             "이에 따라 본 시스템은 LLM 분류 깊이를 "
             f"{'중분류' if diff > 0 else '소분류'}로 설정하였다.")
    rep.note("이 결과로 --openai-target-level 기본값(코드 3 / 설계서 2)의 불일치를 팀 합의로 확정하고, "
             "논문과 코드·문서를 같은 값으로 맞춘다.")
    rep.save()
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="E13 LLM 분류 깊이 비교")
    ap.add_argument("--n", type=int, default=30, help="표본 크기 (기본 30)")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--model", default=C.env("OPENAI_MODEL", "gpt-4o-mini"))
    ap.add_argument("--run", action="store_true", help="실제 OpenAI 호출 수행")
    ap.add_argument("--score", action="store_true", help="사람 판정 결과 집계")
    args = ap.parse_args()

    rep = C.Report("E13", "LLM 분류 깊이 비교 (중분류 vs 소분류)",
                   paper_ref="3.3.3절 서술 근거", plan_ref="6장 E13")
    if args.score:
        return score_mode(rep)

    try:
        import build_classification as B
    except Exception as e:  # noqa: BLE001
        C.die(f"build_classification 모듈을 불러올 수 없습니다: {e}")

    conn = C.db_conn()

    # ── 룰 미매칭 표본 ────────────────────────────────
    rules = B.build_rules(None)
    items = C.fetch_all(conn, """
        SELECT pbac_no, pbac_srno, cmdt_ln_no, cmdt_nm
        FROM auction_item
        ORDER BY RAND(%s)
    """, (args.seed,))

    sample = []
    for it in items:
        nm = it["cmdt_nm"] or ""
        tokens = B.extract_raw_tokens(B.normalize_text(nm))
        if B.match_rule(tokens, rules, ko_text=nm) is None:
            sample.append((it, tokens))
        if len(sample) >= args.n:
            break

    rep.section("표본")
    rep.table(["항목", "값"],
              [["표본 크기", len(sample)],
               ["추출 기준", f"룰 미매칭 물품, RAND({args.seed}) 순"],
               ["모델", args.model]])
    rep.table(["#", "물품명"],
              [[i + 1, it["cmdt_nm"][:60]] for i, (it, _) in enumerate(sample)])

    if not args.run:
        rep.note(f"미리보기 모드입니다. 실제 비교를 수행하려면 --run 을 붙이세요 "
                 f"(OpenAI 호출 {len(sample)}건 x 2설정 = {len(sample) * 2}콜 발생).")
        rep.save()
        conn.close()
        return 0

    if not C.env("OPENAI_API_KEY"):
        C.die("OPENAI_API_KEY 가 설정되어 있지 않습니다. Additional_Experiment/config/.env 를 확인하세요.")

    # ── 분류기 준비 ───────────────────────────────────
    cat_rows = C.fetch_all(conn, B.SQL_FETCH_CATEGORIES)
    nodes = {}
    for r in cat_rows:
        nodes[int(r["category_id"])] = B.CategoryNode(
            category_id=int(r["category_id"]),
            parent_id=int(r["parent_id"]) if r["parent_id"] is not None else None,
            level=int(r["level"]),
            name_ko=r["name_ko"],
        )
    resolver = B.CategoryResolver(nodes)

    clf2 = B.OpenAIClassifier(args.model, resolver, target_level=2)
    clf3 = B.OpenAIClassifier(args.model, resolver, target_level=3)
    if not (clf2.enabled and clf3.enabled):
        C.die(f"OpenAI 클라이언트 초기화 실패: {clf2.init_error or clf3.init_error}")

    # ── 비교 실행 ─────────────────────────────────────
    rep.section("비교 실행")
    out_rows = []
    resolved2 = resolved3 = 0
    conf2, conf3 = [], []
    top1_same = 0

    for i, (it, tokens) in enumerate(sample, 1):
        nm = it["cmdt_nm"] or ""
        r2 = clf2.classify(nm, tokens)
        r3 = clf3.classify(nm, tokens)
        p2 = " > ".join(r2.category_path) if r2 else ""
        p3 = " > ".join(r3.category_path) if r3 else ""
        ok2 = bool(r2) and resolver.resolve_path(r2.category_path) is not None
        ok3 = bool(r3) and resolver.resolve_path(r3.category_path) is not None
        resolved2 += int(ok2)
        resolved3 += int(ok3)
        if r2:
            conf2.append(float(r2.confidence))
        if r3:
            conf3.append(float(r3.confidence))
        if p2 and p3 and p2.split(">")[0].strip() == p3.split(">")[0].strip():
            top1_same += 1
        out_rows.append([i, it["pbac_no"], it["pbac_srno"], it["cmdt_ln_no"], nm,
                         p2, f"{r2.confidence:.2f}" if r2 else "", "O" if ok2 else "X",
                         p3, f"{r3.confidence:.2f}" if r3 else "", "O" if ok3 else "X",
                         "", "", ""])
        print(f"  [{i}/{len(sample)}] {nm[:40]:<40} L2={p2[:28]:<28} L3={p3[:28]}")

    rep.csv(CSV_NAME, CSV_HEADERS, out_rows)

    n = len(sample)
    rep.section("자동 산출 지표")
    rep.table(
        ["지표", "target-level 2", "target-level 3"],
        [
            ["트리 해석 성공", f"{resolved2}/{n} ({resolved2 / n * 100:.1f}%)" if n else "-",
             f"{resolved3}/{n} ({resolved3 / n * 100:.1f}%)" if n else "-"],
            ["평균 confidence", f"{C.mean(conf2):.2f}", f"{C.mean(conf3):.2f}"],
            ["응답 실패", n - len(conf2), n - len(conf3)],
        ],
    )
    rep.table(["항목", "값"],
              [["두 설정의 대분류 일치", f"{top1_same}/{n} ({top1_same / n * 100:.1f}%)" if n else "-"]])
    rep.data.update({
        "sample_size": n, "model": args.model,
        "resolved_level2": resolved2, "resolved_level3": resolved3,
        "avg_conf_level2": round(C.mean(conf2), 3), "avg_conf_level3": round(C.mean(conf3), 3),
        "top1_agreement": round(top1_same / n * 100, 1) if n else 0,
    })

    rep.note(f"다음 단계: results/E13/{CSV_NAME} 의 judge_level2 / judge_level3 열에 "
             "사람이 O(정답) / X(오답)를 채운 뒤 "
             "`python Additional_Experiment/scripts/e13_llm_depth.py --score` 로 집계한다.")

    rep.save()
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
