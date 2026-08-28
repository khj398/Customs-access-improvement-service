"""
E06. 사용성 과업 비교 실험 — 집계  [필수 · 반나절]  ★ 신규
============================================================
목적  논문 제목의 "접근성 향상"을 뒷받침하는 유일한 근거.
      동일 과업을 유니패스와 제안 서비스에서 수행하게 하여 완료 시간·성공률을 비교한다.

입력 (실험 진행 후 사람이 채운 파일)
    results/E06/usability_record.csv     과업 기록지  (템플릿: templates/E6_usability_record.csv)
    results/E06/satisfaction.csv         만족도 기록지(템플릿: templates/E6_satisfaction.csv)

규칙
    - 180초 초과 시 중단하고 실패로 처리하되 시간은 180으로 기록한다.
    - 순서 효과 제거: 절반은 유니패스 먼저(U->C), 절반은 제안 서비스 먼저(C->U).
    - T4(관심 물품 저장)는 유니패스에서 수행 불가 -> 실패로 기록.

논문 대응  4.4절 표 6
실험계획서  6장 E6

실행:
    python Additional_Experiment/scripts/e06_usability_analyze.py
    python Additional_Experiment/scripts/e06_usability_analyze.py --init   # 기록지 생성
"""

from __future__ import annotations

import argparse
import shutil
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))

import exp_common as C  # noqa: E402

TIME_CAP = 180
TASKS = {
    "T1": "\"와인\" 관련 공매 물품을 찾아 예정가를 확인한다",
    "T2": "주방 식기류에 해당하는 물품 3건을 찾는다",
    "T3": "특정 세관에서 진행 중인 공매 물품을 찾는다",
    "T4": "관심 물품을 저장하고 마감 일정을 확인한다",
}


def ox(v: str) -> bool:
    return (v or "").strip().upper() in ("O", "Y", "YES", "1", "TRUE", "성공")


def num(v: str, default: float | None = None) -> float | None:
    try:
        return float(str(v).strip())
    except (TypeError, ValueError):
        return default


def init_files(rep_dir: Path) -> None:
    rep_dir.mkdir(parents=True, exist_ok=True)
    for src_name, dst_name in [("E6_usability_record.csv", "usability_record.csv"),
                               ("E6_satisfaction.csv", "satisfaction.csv")]:
        src = C.TEMPLATES_DIR / src_name
        dst = rep_dir / dst_name
        if dst.exists():
            print(f"[skip] 이미 존재: {dst}")
            continue
        shutil.copy(src, dst)
        print(f"[created] {dst}")


def main() -> int:
    ap = argparse.ArgumentParser(description="E06 사용성 실험 집계")
    ap.add_argument("--record", default=str(C.RESULTS_DIR / "E06" / "usability_record.csv"))
    ap.add_argument("--satisfaction", default=str(C.RESULTS_DIR / "E06" / "satisfaction.csv"))
    ap.add_argument("--init", action="store_true", help="템플릿을 results/E06/ 으로 복사")
    args = ap.parse_args()

    if args.init:
        init_files(C.RESULTS_DIR / "E06")
        print("\n기록지를 채운 뒤 --init 없이 다시 실행하세요.")
        return 0

    record_path = Path(args.record)
    if not record_path.exists():
        C.die(f"기록지가 없습니다: {record_path}\n"
              "   먼저 `python Additional_Experiment/scripts/e06_usability_analyze.py --init` 로 "
              "기록지를 만들고 실험을 진행하세요.")

    rep = C.Report("E06", "사용성 과업 비교 실험", paper_ref="4.4절 표 6", plan_ref="6장 E6")
    rows = [r for r in C.read_csv(record_path) if (r.get("participant") or "").strip()]
    if not rows:
        C.die("기록지에 데이터가 없습니다.")

    participants = sorted({r["participant"].strip() for r in rows})
    orders = defaultdict(int)
    for r in rows:
        orders[(r.get("order") or "").strip()] += 1

    rep.section("실험 개요")
    rep.table(["항목", "값"],
              [["참가자 수", len(participants)],
               ["기록 행 수", len(rows)],
               ["과업 수", len({r['task'].strip() for r in rows})],
               ["시간 상한", f"{TIME_CAP}초 (초과 시 실패 처리, 시간은 {TIME_CAP}으로 기록)"]])
    rep.table(["수행 순서", "행 수"], [[k or "(미기재)", v] for k, v in sorted(orders.items())])

    # ── 과업별 집계 ───────────────────────────────────
    per_task: dict[str, dict] = defaultdict(lambda: {
        "uni_times": [], "uni_success": 0, "uni_n": 0,
        "pro_times": [], "pro_success": 0, "pro_n": 0,
    })
    for r in rows:
        t = (r.get("task") or "").strip().upper()
        d = per_task[t]
        ut = num(r.get("unipass_time_sec"))
        pt = num(r.get("proposed_time_sec"))
        if ut is not None:
            d["uni_times"].append(min(ut, TIME_CAP))
            d["uni_n"] += 1
            if ox(r.get("unipass_success")):
                d["uni_success"] += 1
        if pt is not None:
            d["pro_times"].append(min(pt, TIME_CAP))
            d["pro_n"] += 1
            if ox(r.get("proposed_success")):
                d["pro_success"] += 1

    rep.section("과업별 결과 (논문 표 6 초안)")
    table_rows = []
    for t in sorted(per_task):
        d = per_task[t]
        u_mean = C.mean(d["uni_times"])
        p_mean = C.mean(d["pro_times"])
        u_sr = d["uni_success"] / d["uni_n"] * 100 if d["uni_n"] else 0
        p_sr = d["pro_success"] / d["pro_n"] * 100 if d["pro_n"] else 0
        improve = (u_mean - p_mean) / u_mean * 100 if u_mean else 0
        table_rows.append([
            t, TASKS.get(t, "")[:28],
            f"{u_mean:.1f}", f"{u_sr:.0f}%",
            f"{p_mean:.1f}", f"{p_sr:.0f}%",
            f"{improve:+.1f}%",
        ])
    rep.table(["과업", "내용", "유니패스 평균(초)", "유니패스 성공률",
               "제안 평균(초)", "제안 성공률", "시간 단축률"], table_rows)

    # ── 전체 집계 ─────────────────────────────────────
    all_u_times = [t for d in per_task.values() for t in d["uni_times"]]
    all_p_times = [t for d in per_task.values() for t in d["pro_times"]]
    u_succ = sum(d["uni_success"] for d in per_task.values())
    u_n = sum(d["uni_n"] for d in per_task.values())
    p_succ = sum(d["pro_success"] for d in per_task.values())
    p_n = sum(d["pro_n"] for d in per_task.values())

    rep.section("전체 집계")
    rep.table(
        ["지표", "유니패스", "제안 서비스"],
        [
            ["평균 완료 시간(초)", f"{C.mean(all_u_times):.1f}", f"{C.mean(all_p_times):.1f}"],
            ["중앙값(초)", f"{C.percentile(all_u_times, 50):.1f}", f"{C.percentile(all_p_times, 50):.1f}"],
            ["성공률", f"{u_succ / u_n * 100:.1f}% ({u_succ}/{u_n})" if u_n else "-",
             f"{p_succ / p_n * 100:.1f}% ({p_succ}/{p_n})" if p_n else "-"],
            ["시간 상한 도달 건수", sum(1 for t in all_u_times if t >= TIME_CAP),
             sum(1 for t in all_p_times if t >= TIME_CAP)],
        ],
    )

    # 참가자별 방향성 (몇 명이 제안 서비스에서 더 빨랐는가)
    per_part: dict[str, dict] = defaultdict(lambda: {"u": [], "p": []})
    for r in rows:
        pid = r["participant"].strip()
        ut, pt = num(r.get("unipass_time_sec")), num(r.get("proposed_time_sec"))
        if ut is not None:
            per_part[pid]["u"].append(min(ut, TIME_CAP))
        if pt is not None:
            per_part[pid]["p"].append(min(pt, TIME_CAP))
    faster = sum(1 for d in per_part.values()
                 if d["u"] and d["p"] and C.mean(d["p"]) < C.mean(d["u"]))
    rep.table(["항목", "값"],
              [["제안 서비스가 더 빨랐던 참가자", f"{faster} / {len(per_part)}"]])

    # ── 순서 효과 ─────────────────────────────────────
    rep.section("순서 효과 점검")
    order_rows = []
    for order_key in sorted({(r.get("order") or "").strip() for r in rows}):
        sub = [r for r in rows if (r.get("order") or "").strip() == order_key]
        ut = [min(num(r.get("unipass_time_sec"), 0) or 0, TIME_CAP) for r in sub
              if num(r.get("unipass_time_sec")) is not None]
        pt = [min(num(r.get("proposed_time_sec"), 0) or 0, TIME_CAP) for r in sub
              if num(r.get("proposed_time_sec")) is not None]
        order_rows.append([order_key or "(미기재)", len(sub),
                           f"{C.mean(ut):.1f}", f"{C.mean(pt):.1f}"])
    rep.table(["수행 순서", "행 수", "유니패스 평균(초)", "제안 평균(초)"], order_rows)
    rep.note("두 순서 그룹의 경향이 크게 다르면 순서 효과가 남아 있다는 뜻이므로 4.4절에 함께 밝힌다.")

    # ── 만족도 ────────────────────────────────────────
    sat_path = Path(args.satisfaction)
    sat_summary = None
    if sat_path.exists():
        sat_rows = [r for r in C.read_csv(sat_path) if (r.get("participant") or "").strip()]
        u_scores = [num(r.get("unipass_score")) for r in sat_rows if num(r.get("unipass_score")) is not None]
        p_scores = [num(r.get("proposed_score")) for r in sat_rows if num(r.get("proposed_score")) is not None]
        if u_scores or p_scores:
            rep.section("주관 만족도 (5점 척도)")
            rep.table(["대상", "응답 수", "평균"],
                      [["유니패스", len(u_scores), f"{C.mean(u_scores):.2f}"],
                       ["제안 서비스", len(p_scores), f"{C.mean(p_scores):.2f}"]])
            sat_summary = {"unipass_mean": round(C.mean(u_scores), 2),
                           "proposed_mean": round(C.mean(p_scores), 2),
                           "n": len(sat_rows)}
    else:
        rep.note(f"만족도 기록지가 없습니다: {sat_path.name} (선택 항목)")

    rep.data.update({
        "participants": len(participants),
        "tasks": {t: {
            "unipass_mean_sec": round(C.mean(d["uni_times"]), 1),
            "unipass_success_rate": round(d["uni_success"] / d["uni_n"] * 100, 1) if d["uni_n"] else None,
            "proposed_mean_sec": round(C.mean(d["pro_times"]), 1),
            "proposed_success_rate": round(d["pro_success"] / d["pro_n"] * 100, 1) if d["pro_n"] else None,
        } for t, d in per_task.items()},
        "overall": {
            "unipass_mean_sec": round(C.mean(all_u_times), 1),
            "proposed_mean_sec": round(C.mean(all_p_times), 1),
            "unipass_success_rate": round(u_succ / u_n * 100, 1) if u_n else None,
            "proposed_success_rate": round(p_succ / p_n * 100, 1) if p_n else None,
        },
        "satisfaction": sat_summary,
    })

    rep.note("T4는 유니패스에서 수행 불가이므로 '수행 불가'가 그대로 결과가 된다. "
             "표 6에서 성공률 0%로 표기하고 각주로 사유를 밝힌다.")
    rep.note("참가자 정보는 익명 번호(P1~P10)만 사용하며 개인정보는 수집·기록하지 않는다.")

    rep.save()
    return 0


if __name__ == "__main__":
    sys.exit(main())
