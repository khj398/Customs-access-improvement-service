"""
E05-b. 블라인드 라벨 병합 · 일치도 · 정확도 산출  [필수 · E05의 2단계]
=======================================================================
입력  results/E05/labels/label_*.csv  (라벨러가 true_category_path 를 채운 파일)

수행
    1. 라벨 유효성 검사 (카테고리 트리에 존재하는 경로인가)
    2. 공통 문항의 라벨러 간 일치도 계산 (전원 일치율 / 쌍별 일치율 / Fleiss' kappa)
    3. 다수결로 정답 확정 (동점은 협의 대상으로 표시)
    4. DB의 자동 분류 결과를 join 하여 ground_truth_v2.csv 생성
    5. classification/eval/evaluate.py 를 실행해 정확도 산출

산출
    results/E05/ground_truth_v2.csv     evaluate.py 입력 형식
    results/E05/accuracy_report.txt     evaluate.py 출력 원문
    results/E05b/report.md              일치도·정확도 요약

논문 대응  4.2절 표 4 (하단) + 4.2절 라벨링 절차 문단
실험계획서  6장 E5

실행:
    python Additional_Experiment/scripts/e05b_merge_and_evaluate.py
    python Additional_Experiment/scripts/e05b_merge_and_evaluate.py --no-evaluate
    python Additional_Experiment/scripts/e05b_merge_and_evaluate.py --copy-to-repo
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from collections import Counter, defaultdict
from itertools import combinations
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))

import exp_common as C  # noqa: E402

GT_HEADERS = ["pbac_no", "pbac_srno", "cmdt_ln_no", "cmdt_nm",
              "auto_category_path", "auto_confidence", "auto_model",
              "true_category_path", "labeler", "note"]


def norm_path(p: str) -> str:
    return " > ".join(s.strip() for s in (p or "").split(">") if s.strip())


def main() -> int:
    ap = argparse.ArgumentParser(description="E05-b 라벨 병합 및 정확도 산출")
    ap.add_argument("--labels-dir", default=str(C.RESULTS_DIR / "E05" / "labels"))
    ap.add_argument("--out", default=str(C.RESULTS_DIR / "E05" / "ground_truth_v2.csv"))
    ap.add_argument("--no-evaluate", action="store_true", help="evaluate.py 실행 생략")
    ap.add_argument("--copy-to-repo", action="store_true",
                    help="classification/eval/ground_truth_v2.csv 로도 복사")
    args = ap.parse_args()

    labels_dir = Path(args.labels_dir)
    files = sorted(labels_dir.glob("label_*.csv"))
    if not files:
        C.die(f"라벨 파일이 없습니다: {labels_dir}\n   먼저 e05a_sample_blind.py 를 실행하고 라벨링을 완료하세요.")

    rep = C.Report("E05b", "블라인드 라벨 병합 · 정확도 산출",
                   paper_ref="4.2절 표 4 (하단)", plan_ref="6장 E5")
    conn = C.db_conn()

    # ── 유효 카테고리 경로 집합 ───────────────────────
    valid_paths = set()
    for r in C.fetch_all(conn, """
        SELECT c1.name_ko AS lv1, c2.name_ko AS lv2, c3.name_ko AS lv3
        FROM category c3
        JOIN category c2 ON c2.category_id = c3.parent_id
        JOIN category c1 ON c1.category_id = c2.parent_id
        WHERE c3.level = 3
    """):
        valid_paths.add(norm_path(f"{r['lv1']} > {r['lv2']} > {r['lv3']}"))
    for r in C.fetch_all(conn, """
        SELECT c1.name_ko AS lv1, c2.name_ko AS lv2
        FROM category c2 JOIN category c1 ON c1.category_id = c2.parent_id
        WHERE c2.level = 2
    """):
        valid_paths.add(norm_path(f"{r['lv1']} > {r['lv2']}"))
    for r in C.fetch_all(conn, "SELECT name_ko FROM category WHERE level = 1"):
        valid_paths.add(norm_path(r["name_ko"]))

    # ── 라벨 로딩 ─────────────────────────────────────
    labels: dict[tuple, dict[str, str]] = defaultdict(dict)   # key -> {labeler: path}
    names: dict[tuple, str] = {}
    notes: dict[tuple, list[str]] = defaultdict(list)
    invalid, empty = [], []

    rep.section("라벨 파일")
    file_rows = []
    for f in files:
        rows = C.read_csv(f)
        labeler = f.stem.replace("label_", "")
        filled = 0
        for r in rows:
            key = (r["pbac_no"], r["pbac_srno"], r["cmdt_ln_no"])
            names[key] = r.get("cmdt_nm", "")
            lab = (r.get("labeler") or labeler).strip() or labeler
            path = norm_path(r.get("true_category_path", ""))
            if not path:
                empty.append([lab, key, r.get("cmdt_nm", "")[:40]])
                continue
            filled += 1
            if path not in valid_paths:
                invalid.append([lab, r.get("cmdt_nm", "")[:40], path])
            labels[key][lab] = path
            if r.get("note"):
                notes[key].append(f"{lab}: {r['note']}")
        file_rows.append([labeler, f.name, len(rows), filled, len(rows) - filled])
    rep.table(["라벨러", "파일", "행 수", "라벨 완료", "미라벨"], file_rows)

    if empty:
        rep.note(f"미라벨 {len(empty)}건 — 실험계획서 규칙상 '판단 유보'는 허용되지 않는다. "
                 "애매한 건은 「기타 > 미분류 > 기타」로 명시하고 다시 실행할 것.")
        rep.csv("unlabeled.csv", ["labeler", "key", "cmdt_nm"],
                [[e[0], "/".join(e[1]), e[2]] for e in empty])
    if invalid:
        rep.section("카테고리 트리에 없는 경로 (오타 의심)")
        rep.table(["라벨러", "물품명", "입력 경로"], invalid[:30])
        rep.note(f"총 {len(invalid)}건. category_reference.csv 의 경로를 그대로 복사해 수정한 뒤 재실행할 것. "
                 "경로가 다르면 evaluate.py 에서 전부 오분류로 계산된다.")

    # ── 일치도 (공통 문항) ────────────────────────────
    rep.section("라벨러 간 일치도 (공통 문항)")
    common_keys = [k for k, v in labels.items() if len(v) >= 2]
    all_labelers = sorted({lab for v in labels.values() for lab in v})

    unanimous = sum(1 for k in common_keys if len(set(labels[k].values())) == 1)
    pair_stats = []
    for a, b in combinations(all_labelers, 2):
        both = [k for k in common_keys if a in labels[k] and b in labels[k]]
        if not both:
            continue
        agree = sum(1 for k in both if labels[k][a] == labels[k][b])
        pair_stats.append([f"{a} vs {b}", len(both), agree,
                           f"{agree / len(both) * 100:.1f}%"])

    # Fleiss' kappa (공통 문항, 라벨러 수가 동일한 항목만)
    fleiss = None
    if common_keys:
        n_raters = min(len(labels[k]) for k in common_keys)
        if n_raters >= 2:
            cats = sorted({p for k in common_keys for p in labels[k].values()})
            cat_idx = {c: i for i, c in enumerate(cats)}
            N, k_cat = len(common_keys), len(cats)
            table = [[0] * k_cat for _ in range(N)]
            for i, key in enumerate(common_keys):
                for p in list(labels[key].values())[:n_raters]:
                    table[i][cat_idx[p]] += 1
            p_j = [sum(table[i][j] for i in range(N)) / (N * n_raters) for j in range(k_cat)]
            P_i = [(sum(c * c for c in table[i]) - n_raters) / (n_raters * (n_raters - 1))
                   for i in range(N)] if n_raters > 1 else [0] * N
            P_bar = sum(P_i) / N if N else 0
            Pe = sum(p * p for p in p_j)
            fleiss = (P_bar - Pe) / (1 - Pe) if Pe < 1 else 0.0

    rep.table(["지표", "값"],
              [["공통 문항 수", len(common_keys)],
               ["전원 일치 건수", unanimous],
               ["전원 일치율", f"{unanimous / len(common_keys) * 100:.1f}%" if common_keys else "-"],
               ["Fleiss' kappa", f"{fleiss:.3f}" if fleiss is not None else "-"]])
    if pair_stats:
        rep.table(["라벨러 쌍", "공통 건수", "일치", "일치율"], pair_stats)

    rep.data["agreement"] = {
        "common_items": len(common_keys),
        "unanimous": unanimous,
        "unanimous_rate": round(unanimous / len(common_keys) * 100, 1) if common_keys else None,
        "fleiss_kappa": round(fleiss, 3) if fleiss is not None else None,
        "pairwise": [{"pair": p[0], "n": p[1], "agree": p[2], "rate": p[3]} for p in pair_stats],
    }

    # ── 다수결로 정답 확정 ────────────────────────────
    resolved: dict[tuple, tuple[str, str, str]] = {}   # key -> (path, labeler, note)
    ties = []
    for key, per_lab in labels.items():
        cnt = Counter(per_lab.values())
        top, n_top = cnt.most_common(1)[0]
        tied = [p for p, c in cnt.items() if c == n_top]
        labeler_str = "/".join(sorted(per_lab.keys()))
        note = "; ".join(notes.get(key, []))
        if len(tied) > 1:
            ties.append([names.get(key, ""), " | ".join(tied), labeler_str])
            note = ("협의 필요(동점): " + " | ".join(tied) + ("; " + note if note else ""))
        resolved[key] = (top, labeler_str, note)

    if ties:
        rep.section("동점 발생 문항 (협의 대상)")
        rep.table(["물품명", "동점 경로", "라벨러"], ties[:20])
        rep.csv("label_ties.csv", ["cmdt_nm", "tied_paths", "labelers"], ties)
        rep.note(f"동점 {len(ties)}건은 3인 협의로 확정한 뒤 라벨 파일을 수정하고 재실행한다. "
                 "현재 집계에는 최빈값 중 첫 번째 경로가 임시로 들어가 있다.")

    # ── 자동 분류 결과 join ───────────────────────────
    rep.section("자동 분류 결과 병합")
    gt_rows = []
    missing_auto = 0
    for key, (true_path, labeler, note) in sorted(resolved.items()):
        r = C.fetch_one(conn, """
            SELECT ai.cmdt_nm,
                   CONCAT_WS(' > ', cg.name_ko, cp.name_ko, cl.name_ko) AS auto_category_path,
                   ic.confidence AS auto_confidence,
                   ic.model_name AS auto_model
            FROM auction_item ai
            LEFT JOIN item_classification ic USING (pbac_no, pbac_srno, cmdt_ln_no)
            LEFT JOIN category cl ON cl.category_id = ic.category_id
            LEFT JOIN category cp ON cp.category_id = cl.parent_id
            LEFT JOIN category cg ON cg.category_id = cp.parent_id
            WHERE ai.pbac_no = %s AND ai.pbac_srno = %s AND ai.cmdt_ln_no = %s
        """, key)
        if not r:
            missing_auto += 1
            continue
        if not r["auto_category_path"]:
            missing_auto += 1
        gt_rows.append([
            key[0], key[1], key[2], r["cmdt_nm"],
            norm_path(r["auto_category_path"] or ""),
            r["auto_confidence"] if r["auto_confidence"] is not None else "",
            r["auto_model"] or "none",
            true_path, labeler, note,
        ])

    out_path = Path(args.out)
    C.write_csv(out_path, GT_HEADERS, gt_rows)
    rep.table(["항목", "값"],
              [["병합 행 수", len(gt_rows)],
               ["자동 분류 결과 없음", missing_auto],
               ["출력", C.rel(out_path)]])
    rep.data["ground_truth_rows"] = len(gt_rows)
    rep.data["ground_truth_path"] = C.rel(out_path)

    if args.copy_to_repo:
        repo_gt = C.REPO_ROOT / "classification" / "eval" / "ground_truth_v2.csv"
        C.write_csv(repo_gt, GT_HEADERS, gt_rows)
        rep.note(f"저장소에도 복사: {C.rel(repo_gt)}")

    # ── evaluate.py 실행 ──────────────────────────────
    if not args.no_evaluate:
        rep.section("정확도 산출 (classification/eval/evaluate.py)")
        script = C.REPO_ROOT / "classification" / "eval" / "evaluate.py"
        proc = subprocess.run(
            [sys.executable, str(script), "--gt", str(out_path)],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            cwd=str(C.REPO_ROOT),
        )
        output = (proc.stdout or "") + (("\n[stderr]\n" + proc.stderr) if proc.stderr else "")
        report_txt = C.RESULTS_DIR / "E05" / "accuracy_report.txt"
        report_txt.parent.mkdir(parents=True, exist_ok=True)
        report_txt.write_text(output, encoding="utf-8")
        print(output)
        rep.lines.append("```text")
        rep.lines.append(output.strip())
        rep.lines.append("```")
        rep.data["evaluate_exit_code"] = proc.returncode
        rep.data["accuracy_report_path"] = C.rel(report_txt)

        # 요약 수치 파싱
        for line in output.splitlines():
            if "전체 정확도" in line:
                rep.data["accuracy_line"] = line.strip()
            if "대분류 정확도" in line:
                rep.data["top1_line"] = line.strip()
        rep.note("evaluate.py 는 --save 를 주면 classification/eval/accuracy_report.txt 를 "
                 "덮어쓴다. 여기서는 저장소 파일을 건드리지 않고 results/E05/accuracy_report.txt "
                 "에만 기록한다.")

    rep.note("결과 해석 지침: 80%대가 나와도 그대로 쓴다. 100%보다 훨씬 강한 결과다. "
             "라벨링 절차(블라인드·3인·유보 없음·라벨러 간 일치도)를 4.2절에 한 문단으로 기술하면 "
             "그 자체가 방법론적 기여가 된다.")

    rep.save()
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
