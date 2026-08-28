"""
collect_results.py — 논문 표 초안 생성
======================================
results/<실험ID>/data.json 을 읽어 논문 4장에 들어갈 표 3~6 초안과
실험 진행 현황표를 results/PAPER_TABLES.md 로 만든다.

아직 수행하지 않은 실험은 "미수행"으로 표시되므로 진행 현황판으로도 쓸 수 있다.

실행:
    python Additional_Experiment/scripts/collect_results.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))

import exp_common as C  # noqa: E402

EXPERIMENTS = [
    ("E00", "사전 점검", "-", "사전"),
    ("E01", "데이터셋 기초 통계", "4.1 표 3", "필수"),
    ("E02", "자동 분류 커버리지", "4.2 표 4 상단", "필수"),
    ("E03", "한글 검색 베이스라인 비교", "4.3 표 5", "필수"),
    ("E03b", "P@5 판정 집계", "4.3 표 5", "필수"),
    ("E04", "오타 허용 검증", "4.3 표 5 하단", "필수"),
    ("E05", "블라인드 표본 추출", "4.2 표 4 하단", "필수"),
    ("E05b", "라벨 병합·정확도", "4.2 표 4 하단", "필수"),
    ("E06", "사용성 과업 비교", "4.4 표 6", "필수"),
    ("E07", "하이브리드 기여도", "4.2 표 4 병합", "권장"),
    ("E08", "토큰 유형별 기여도", "4.3 본문", "권장"),
    ("E09", "신뢰도 구간별 정확도", "4.2 본문", "권장"),
    ("E10", "검색 응답시간", "4.3 표 5 병합", "선택"),
    ("E11", "파이프라인 멱등성", "3.2 본문", "선택"),
    ("E12", "오분류 정성 분석", "5장 본문", "선택"),
    ("E13", "LLM 분류 깊이 비교", "3.3.3 근거", "선택"),
]


def main() -> int:
    out = []
    add = out.append

    add("# 논문 표 초안 (자동 생성)")
    add("")
    add(f"- 생성 시각: {C.now_stamp()}")
    add("- 출처: `Additional_Experiment/results/<실험ID>/data.json`")
    add("- 값이 비어 있으면 해당 실험이 아직 수행되지 않은 것이다.")
    add("")

    # ── 진행 현황 ─────────────────────────────────────
    add("## 실험 진행 현황")
    add("")
    rows = []
    done = 0
    for exp_id, title, paper, kind in EXPERIMENTS:
        d = C.load_result(exp_id)
        status = "완료" if d else "미수행"
        if d:
            done += 1
        rows.append([exp_id, title, kind, paper, status, d.get("executed_at", "") if d else ""])
    add(C.md_table(["ID", "실험", "구분", "논문 위치", "상태", "실행 시각"], rows))
    add("")
    add(f"완료 {done} / {len(EXPERIMENTS)}건")
    add("")

    # ── 표 3 ─────────────────────────────────────────
    e1 = C.load_result("E01")
    add("## 표 3. 데이터셋 기초 통계 (4.1절)")
    add("")
    if e1:
        s, lang, price = e1.get("scale", {}), e1.get("language", {}), e1.get("price", {})
        lines = e1.get("lines_per_auction", {})
        add(C.md_table(["항목", "값"], [
            ["공매 건수", f"{s.get('auctions', 0):,}건"],
            ["물품 건수", f"{s.get('items', 0):,}건"],
            ["대상 세관 수", f"{s.get('customs_offices', 0):,}개"],
            ["물품 이미지 수", f"{s.get('images', 0):,}건"],
            ["영문 전용 물품명 비율", f"{lang.get('en_only_ratio', 0)}%"],
            ["평균 물품명 길이", f"{lang.get('avg_len', 0)}자"],
            ["공매당 평균 물품 라인 수", lines.get("avg_lines", "-")],
            ["예정가 범위",
             f"{(price.get('min_price') or 0):,} ~ {(price.get('max_price') or 0):,}원"],
        ]))
    else:
        add("_E01 미수행_")
    add("")

    # ── 표 4 ─────────────────────────────────────────
    e2, e5b, e7 = C.load_result("E02"), C.load_result("E05b"), C.load_result("E07")
    add("## 표 4. 자동 분류 커버리지 및 정확도 (4.2절)")
    add("")
    if e2:
        total = e2.get("total_classified", 0) or 1
        rows = [[m.get("model_name", "-"), f"{m.get('cnt', 0):,}건",
                 f"{m.get('cnt', 0) / total * 100:.1f}%", m.get("avg_conf", "-")]
                for m in e2.get("by_model", [])]
        rows.append(["미분류(기타)", f"{e2.get('misc_total', 0):,}건",
                     f"{e2.get('misc_ratio', 0)}%", "-"])
        add("**커버리지**")
        add("")
        add(C.md_table(["분류 경로", "건수", "비율", "평균 신뢰도"], rows))
    else:
        add("_E02 미수행_")
    add("")
    if e7:
        add("**하이브리드 기여도 (E07)**")
        add("")
        add(C.md_table(["구분", "커버리지"], [
            ["룰 단독", f"{e7.get('rule_only_coverage', 0)}%"],
            ["룰 + LLM", f"{e7.get('hybrid_coverage', 0)}%"],
            ["미분류 감소", f"{e7.get('misc_reduction_pp', 0)}%p"],
        ]))
        add("")
    if e5b:
        add("**정확도 (E05 블라인드 재평가)**")
        add("")
        acc_rows = [["평가 건수", e5b.get("ground_truth_rows", "-")]]
        if e5b.get("accuracy_line"):
            acc_rows.append(["전체 정확도", e5b["accuracy_line"]])
        if e5b.get("top1_line"):
            acc_rows.append(["대분류 정확도", e5b["top1_line"]])
        ag = e5b.get("agreement", {})
        acc_rows.append(["라벨러 간 전원 일치율",
                         f"{ag.get('unanimous_rate', '-')}% (공통 {ag.get('common_items', '-')}건)"])
        acc_rows.append(["Fleiss' kappa", ag.get("fleiss_kappa", "-")])
        add(C.md_table(["항목", "값"], acc_rows))
        add("")
        add("> 상세 수치는 `results/E05/accuracy_report.txt` 참조.")
    else:
        add("_E05b 미수행 — 블라인드 라벨링이 끝나야 채워진다._")
    add("")

    # ── 표 5 ─────────────────────────────────────────
    e3, e3b, e4, e10 = (C.load_result("E03"), C.load_result("E03b"),
                        C.load_result("E04"), C.load_result("E10"))
    add("## 표 5. 한글 검색 성능 비교 (4.3절)")
    add("")
    if e3:
        rows = [
            ["질의 수", e3.get("queries", "-"), e3.get("queries", "-")],
            ["0건 반환 질의 수", e3.get("a_zero", "-"), e3.get("b_zero", "-")],
        ]
        if e3b:
            rows.append(["평균 P@5", "-", e3b.get("avg_p5", "-")])
        if e10:
            rows.append(["응답시간 p50 (ms)", e10.get("like", {}).get("p50", "-"),
                         e10.get("proposed", {}).get("p50", "-")])
            rows.append(["응답시간 p95 (ms)", e10.get("like", {}).get("p95", "-"),
                         e10.get("proposed", {}).get("p95", "-")])
        add(C.md_table(["지표", "(A) LIKE 베이스라인", "(B) 제안 방식"], rows))
        add("")
    else:
        add("_E03 미수행_")
        add("")
    if e4:
        add("**오타 허용 (E04)**")
        add("")
        add(C.md_table(["구간", "질의쌍", "보정 성공"], [
            ["4자 이상", e4.get("ge4_pairs", "-"), e4.get("ge4_recovered", "-")],
            ["3자 이하", e4.get("lt4_pairs", "-"), e4.get("lt4_recovered", "-")],
        ]))
        add("")

    # ── 표 6 ─────────────────────────────────────────
    e6 = C.load_result("E06")
    add("## 표 6. 사용성 과업 비교 (4.4절)")
    add("")
    if e6:
        rows = []
        for task, d in sorted(e6.get("tasks", {}).items()):
            rows.append([task,
                         d.get("unipass_mean_sec", "-"), f"{d.get('unipass_success_rate', '-')}%",
                         d.get("proposed_mean_sec", "-"), f"{d.get('proposed_success_rate', '-')}%"])
        ov = e6.get("overall", {})
        rows.append(["전체", ov.get("unipass_mean_sec", "-"), f"{ov.get('unipass_success_rate', '-')}%",
                     ov.get("proposed_mean_sec", "-"), f"{ov.get('proposed_success_rate', '-')}%"])
        add(C.md_table(["과업", "유니패스 평균(초)", "유니패스 성공률",
                        "제안 평균(초)", "제안 성공률"], rows))
        sat = e6.get("satisfaction")
        if sat:
            add("")
            add(C.md_table(["만족도(5점)", "유니패스", "제안 서비스"],
                           [["평균", sat.get("unipass_mean", "-"), sat.get("proposed_mean", "-")]]))
    else:
        add("_E06 미수행 — 사용성 실험을 진행해야 채워진다._")
    add("")

    # ── 본문 문장 재료 ────────────────────────────────
    add("## 본문에 넣을 수치 (문장 재료)")
    add("")
    e8, e9, e11, e12, e13 = (C.load_result("E08"), C.load_result("E09"), C.load_result("E11"),
                             C.load_result("E12"), C.load_result("E13"))
    rows = []
    if e8:
        stages = {s["stage"]: s for s in e8.get("stages", [])}
        for name, s in stages.items():
            rows.append([f"4.3 토큰 누적 {name}", f"0건 질의 {s['queries_zero']}개 / 검색가능 합계 {s['total_hits']}"])
    if e9:
        for b in e9.get("bins", []):
            rows.append([f"4.2 신뢰도 {b['bin']}",
                         f"{b['n']}건, 정확도 {b['accuracy']}%" if b["n"] else "표본 없음"])
        rows.append(["4.2 신뢰도 단조성", "성립" if e9.get("monotonic") else "미성립(향후 과제로 기술)"])
    if e11:
        rows.append(["3.2 멱등성", "확인" if e11.get("idempotent") else "미수행/미확인"])
    if e12:
        for t, n in (e12.get("type_counts") or {}).items():
            rows.append([f"5장 오분류 유형 {t}", f"{n}건"])
    if e13:
        rows.append(["3.3.3 LLM 깊이",
                     f"level2 정확도 {e13.get('accuracy_level2', '-')}% / "
                     f"level3 {e13.get('accuracy_level3', '-')}%"])
    add(C.md_table(["논문 위치", "수치"], rows) if rows else "_해당 실험 미수행_")
    add("")

    # ── 금지 표현 체크 ────────────────────────────────
    add("## 집필 전 확인 (실험계획서 8장)")
    add("")
    add(C.md_table(["확인 항목", "상태"], [
        ["\"분류 정확도 100%\" 삭제 · E05 결과로 교체",
         "가능" if e5b else "E05 미수행 — 교체 불가"],
        ["\"응답시간 300ms 달성\" 은 E10 측정치로만 기재",
         "측정 완료" if e10 else "미측정 — 향후 과제로 이동"],
        ["\"유니패스 공개 API 활용\" → \"웹 자동화 기반 수집\"", "집필 시 확인"],
        ["FAQ 챗봇 · 커뮤니티 게시판은 기능으로 기술 금지", "집필 시 확인"],
        ["Lambda Function URL · DB 비밀번호 노출 금지", "집필 시 확인"],
    ]))
    add("")

    path = C.RESULTS_DIR / "PAPER_TABLES.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(out) + "\n", encoding="utf-8")
    print("\n".join(out))
    print(f"\n[saved] {C.rel(path)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
