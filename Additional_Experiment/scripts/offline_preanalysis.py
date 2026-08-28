"""
오프라인 사전 분석 (DB·백엔드 없이 수행 가능한 실험)
=====================================================
MySQL / Meilisearch / cais_back 이 준비되지 않은 환경에서도, 저장소에 있는
수집 원본 JSON 과 분류 규칙·동의어 사전만으로 계산할 수 있는 수치를 산출한다.

포함 (실측 — 실제 파이프라인과 동일한 코드·데이터를 사용)
    O-1  데이터셋 기초 통계            → E01 과 동일 지표
    O-2  (A) LIKE 베이스라인 0건 질의   → E03 의 (A) 열 (MySQL LIKE 와 동일한 부분문자열 매칭)
    O-3  룰 단독 분류 커버리지          → E07 의 (1)  (build_classification.match_rule 재사용)
    O-4  토큰 유형별 검색 가능 건수     → E08 (RAW / +SYN / +CATEGORY 오프라인 재현)

제외 (서비스가 있어야만 가능)
    E03 (B) 제안 방식 실제 응답 · E04 오타 보정 · E10 응답시간
    → Meilisearch 랭킹·오타 허용은 오프라인으로 재현할 수 없다.
    E05 라벨링 · E06 사용성 → 사람이 수행해야 한다.

★ 이 결과는 "예비 수치"다. 논문에 인용할 최종 수치는 DB·검색엔진을 기동한 뒤
  e01~e13 스크립트로 다시 산출한다. 두 값이 다르면 후자가 정본이다.

실행:
    python Additional_Experiment/scripts/offline_preanalysis.py
"""

from __future__ import annotations

import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))

import exp_common as C  # noqa: E402

sys.path.insert(0, str(C.REPO_ROOT / "classification"))

SOURCES = [
    ("unipass_all_2b.json", "BUSINESS"),
    ("unipass_all_2c.json", "PERSONAL"),
]
SYN_SEEDS = ["db/seed_synonym.sql", "db/seed_synonym_extend.sql"]
SYN_YAML = "classification/synonyms.yaml"

HANGUL = re.compile(r"[가-힣]")
SYN_ROW = re.compile(
    r"\(\s*'([^']*)'\s*,\s*'([^']*)'\s*,\s*'([^']*)'\s*,\s*'([^']*)'\s*,\s*([0-9.]+)\s*\)"
)


# ──────────────────────────────────────────────
# 입력 로딩
# ──────────────────────────────────────────────
def load_items() -> tuple[list[dict], dict]:
    """수집 JSON → ETL 이 적재할 물품 목록(복합 PK 기준 중복 제거)."""
    items: dict[tuple, dict] = {}
    raw_rows = 0
    dup = 0
    for fname, source in SOURCES:
        path = C.REPO_ROOT / fname
        if not path.exists():
            print(f"  [건너뜀] {fname} 없음")
            continue
        rows = json.loads(path.read_text(encoding="utf-8"))
        raw_rows += len(rows)
        for r in rows:
            key = (r.get("pbacNo"), r.get("pbacSrno"), r.get("cmdtLnNo"))
            if key in items:
                dup += 1
            items[key] = {
                "pbac_no": r.get("pbacNo"),
                "pbac_srno": r.get("pbacSrno"),
                "cmdt_ln_no": r.get("cmdtLnNo"),
                "cmdt_nm": (r.get("cmdtNm") or "").strip(),
                "price": r.get("pbacPrngPrc"),
                "cstm_sgn": r.get("pbacCstmSgn"),
                "cstm_nm": r.get("pbacCstmSgnNm"),
                "cargo_type": r.get("pbacTrgtCargTpNm"),
                "start": r.get("pbacStrtDttm"),
                "end": r.get("pbacEndDttm"),
                "source": source,
            }
    return list(items.values()), {"raw_rows": raw_rows, "duplicates": dup}


def load_synonyms() -> list:
    """seed_synonym*.sql + synonyms.yaml → SynEntry 목록 (DB 적재분과 동일 구성)."""
    import build_classification as B

    entries: dict[tuple, object] = {}
    counts = {"sql": 0, "yaml": 0}

    for rel in SYN_SEEDS:
        path = C.REPO_ROOT / rel
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        for src, norm, _lang, ttype, weight in SYN_ROW.findall(text):
            if not src or not norm:
                continue
            entries[(src.upper(), norm)] = B.SynEntry(
                src_term=src.strip(), norm_term=norm.strip(),
                term_type=ttype.strip(), weight=float(weight))
            counts["sql"] += 1

    yml = C.REPO_ROOT / SYN_YAML
    if yml.exists():
        import yaml as _yaml

        data = _yaml.safe_load(yml.read_text(encoding="utf-8")) or {}
        for row in data.get("synonyms", []):
            src = (row.get("src") or "").strip()
            for t in row.get("terms", []):
                norm = (t.get("text") or "").strip()
                if not src or not norm:
                    continue
                entries[(src.upper(), norm)] = B.SynEntry(
                    src_term=src, norm_term=norm,
                    term_type=t.get("type", "SYN"), weight=float(t.get("weight", 1.0)))
                counts["yaml"] += 1

    return list(entries.values()), counts


# ──────────────────────────────────────────────
# 메인
# ──────────────────────────────────────────────
def main() -> int:
    rep = C.Report("OFFLINE", "오프라인 사전 분석 (DB 미기동 환경)",
                   paper_ref="E01 / E03(A) / E07 / E08 예비 수치",
                   plan_ref="실험계획서 6장 E1·E3·E7·E8")

    import build_classification as B

    items, load_stat = load_items()
    if not items:
        C.die("수집 JSON 을 찾을 수 없습니다.")
    syn_entries, syn_counts = load_synonyms()
    rules = B.build_rules(None)

    rep.section("입력 데이터")
    rep.table(["항목", "값"],
              [["수집 JSON 원본 행 수", f"{load_stat['raw_rows']:,}"],
               ["복합 PK 중복 제거 후 물품 수", f"{len(items):,}"],
               ["중복 제거된 행", load_stat["duplicates"]],
               ["로드된 분류 룰", f"{len(rules)}개 (classification/rules.yaml)"],
               ["로드된 동의어 엔트리", f"{len(syn_entries)}개 "
                                        f"(SQL seed {syn_counts['sql']} + YAML {syn_counts['yaml']}, 중복 병합)"]])
    rep.data["input"] = {"raw_rows": load_stat["raw_rows"], "items": len(items),
                         "duplicates": load_stat["duplicates"], "rules": len(rules),
                         "synonym_entries": len(syn_entries)}

    # ── O-1. 데이터셋 기초 통계 ────────────────────────
    rep.section("O-1. 데이터셋 기초 통계  (→ E01 / 논문 표 3)")
    auctions = {i["pbac_no"] for i in items}
    customs = {i["cstm_sgn"] for i in items if i["cstm_sgn"]}
    ko_items = [i for i in items if HANGUL.search(i["cmdt_nm"])]
    en_items = [i for i in items if not HANGUL.search(i["cmdt_nm"])]
    lens = [len(i["cmdt_nm"]) for i in items]
    prices = [int(i["price"]) for i in items if i["price"] not in (None, "")]

    rep.table(["항목", "값"],
              [["공매 건수", f"{len(auctions):,}"],
               ["물품 건수", f"{len(items):,}"],
               ["대상 세관 수", f"{len(customs):,}"],
               ["한글 포함 물품명", f"{len(ko_items):,} ({len(ko_items)/len(items)*100:.1f}%)"],
               ["영문 전용 물품명", f"{len(en_items):,} ({len(en_items)/len(items)*100:.1f}%)"],
               ["평균 물품명 길이", f"{C.mean(lens):.1f}자"],
               ["최대 물품명 길이", f"{max(lens)}자"],
               ["예정가 범위", f"{min(prices):,} ~ {max(prices):,}원" if prices else "-"],
               ["평균 예정가", f"{C.mean(prices):,.0f}원" if prices else "-"]])

    rep.section("O-1b. 수집 출처별 언어 구성 (서론 핵심 근거)")
    src_rows = []
    by_source = defaultdict(list)
    for i in items:
        by_source[i["source"]].append(i)
    for src, sub in sorted(by_source.items()):
        ko = sum(1 for i in sub if HANGUL.search(i["cmdt_nm"]))
        src_rows.append([src,
                         "수입화물" if src == "BUSINESS" else "휴대품",
                         f"{len(sub):,}",
                         f"{ko:,}",
                         f"{ko/len(sub)*100:.1f}%",
                         f"{C.mean([len(i['cmdt_nm']) for i in sub]):.1f}"])
    rep.table(["collector_source", "구분", "물품 수", "한글 포함", "한글 포함률", "평균 길이"], src_rows)

    lines_per_auction = Counter(i["pbac_no"] for i in items)
    rep.table(["항목", "값"],
              [["공매당 평균 물품 라인 수", f"{C.mean(list(lines_per_auction.values())):.2f}"],
               ["공매당 최대 물품 라인 수", max(lines_per_auction.values())]])

    starts = sorted({i["start"] for i in items if i["start"]})
    ends = sorted({i["end"] for i in items if i["end"]})
    rep.table(["항목", "값"],
              [["최초 공매 시작일시", starts[0] if starts else "-"],
               ["최종 공매 종료일시", ends[-1] if ends else "-"]])

    rep.data["dataset"] = {
        "auctions": len(auctions), "items": len(items), "customs_offices": len(customs),
        "ko_included": len(ko_items), "en_only": len(en_items),
        "en_only_ratio": round(len(en_items) / len(items) * 100, 1),
        "avg_len": round(C.mean(lens), 1), "max_len": max(lens),
        "price_min": min(prices) if prices else None, "price_max": max(prices) if prices else None,
        "avg_lines_per_auction": round(C.mean(list(lines_per_auction.values())), 2),
        "by_source": {s: {"items": len(v),
                          "ko_included": sum(1 for i in v if HANGUL.search(i["cmdt_nm"]))}
                      for s, v in by_source.items()},
        "period": {"first_start": starts[0] if starts else None, "last_end": ends[-1] if ends else None},
    }

    # ── O-3. 룰 단독 커버리지 (E08 에서 재사용) ────────
    matched: dict[tuple, object] = {}
    rule_hits = Counter()
    for i in items:
        nm = i["cmdt_nm"]
        raw = B.extract_raw_tokens(B.normalize_text(nm))
        i["_raw_tokens"] = raw
        i["_norm"] = B.normalize_text(nm)
        m = B.match_rule(raw, rules, ko_text=nm)
        if m:
            matched[(i["pbac_no"], i["pbac_srno"], i["cmdt_ln_no"])] = m[0]
            i["_rule"] = m[0]
            rule_hits[m[0].name] += 1
        else:
            i["_rule"] = None

    n_matched = len(matched)
    rep.section("O-3. 룰 단독 분류 커버리지  (→ E07 (1))")
    rep.table(["항목", "값"],
              [["전체 물품", f"{len(items):,}"],
               ["룰 매칭", f"{n_matched:,}"],
               ["룰 미매칭 (LLM 보완 대상)", f"{len(items) - n_matched:,}"],
               ["룰 단독 커버리지", f"{n_matched / len(items) * 100:.1f}%"]])
    rep.table(["출처", "물품 수", "룰 매칭", "커버리지"],
              [[s, len(v), sum(1 for i in v if i["_rule"]),
                f"{sum(1 for i in v if i['_rule']) / len(v) * 100:.1f}%"]
               for s, v in sorted(by_source.items())])
    rep.table(["매칭 상위 룰", "건수"], rule_hits.most_common(12))
    rep.csv("rule_hits.csv", ["rule_name", "matched_items"], rule_hits.most_common())
    rep.csv("rule_unmatched.csv", ["pbac_no", "pbac_srno", "cmdt_ln_no", "source", "cmdt_nm"],
            [[i["pbac_no"], i["pbac_srno"], i["cmdt_ln_no"], i["source"], i["cmdt_nm"]]
             for i in items if not i["_rule"]])
    rep.data["rule_coverage"] = {
        "items": len(items), "matched": n_matched,
        "coverage_pct": round(n_matched / len(items) * 100, 1),
        "by_source": {s: {"items": len(v), "matched": sum(1 for i in v if i["_rule"])}
                      for s, v in by_source.items()},
    }

    # ── 토큰 재현 ──────────────────────────────────────
    def tokens_of(item) -> dict[str, set]:
        raw = {t.upper() for t in item["_raw_tokens"]}
        syn = {tok for tok, _tt, _w in
               B.synonym_tokens_from_text(item["_norm"], item["_raw_tokens"], syn_entries)}
        cat: set[str] = set()
        rule = item["_rule"]
        if rule:
            names = [n for n in rule.category_path if n not in B.CATEGORY_STOPWORDS]
            cat |= set(names)
            if names:
                cat.add(" > ".join(rule.category_path))
        return {"RAW": raw, "SYN": syn, "CATEGORY": cat}

    tok_index = {(*[i[k] for k in ("pbac_no", "pbac_srno", "cmdt_ln_no")],): tokens_of(i) for i in items}

    # ── O-2 + O-4. 질의별 비교 ─────────────────────────
    rep.section("O-2. (A) LIKE 베이스라인 vs O-4. 토큰 누적 검색 가능 건수")
    queries = C.korean_queries()
    rows = []
    a_zero = 0
    stage_zero = {"RAW": 0, "RAW+SYN": 0, "RAW+SYN+CATEGORY": 0}
    stage_total = {"RAW": 0, "RAW+SYN": 0, "RAW+SYN+CATEGORY": 0}

    for q in queries:
        kw = q["query"]
        kw_up = kw.upper()
        like_cnt = sum(1 for i in items if kw in i["cmdt_nm"])
        if like_cnt == 0:
            a_zero += 1

        counts = {}
        for stage, types in [("RAW", ("RAW",)),
                             ("RAW+SYN", ("RAW", "SYN")),
                             ("RAW+SYN+CATEGORY", ("RAW", "SYN", "CATEGORY"))]:
            n = 0
            for key, toks in tok_index.items():
                pool = set()
                for t in types:
                    pool |= toks[t]
                if any(kw in tok or kw_up in tok.upper() for tok in pool):
                    n += 1
            counts[stage] = n
            stage_total[stage] += n
            if n == 0:
                stage_zero[stage] += 1

        rows.append([q["no"], kw, q["expected_en"], f"{like_cnt:,}",
                     counts["RAW"], counts["RAW+SYN"], counts["RAW+SYN+CATEGORY"]])

    rep.table(["#", "질의", "기대 영문 토큰", "(A) LIKE", "RAW", "RAW+SYN", "RAW+SYN+CAT"], rows)
    rep.csv("query_analysis.csv",
            ["no", "query", "expected_en", "like_count", "raw", "raw_syn", "raw_syn_category"], rows)

    n_q = len(queries)
    rep.section("요약")
    rep.table(
        ["방식", "0건 질의 수", "검색 가능 합계", "비고"],
        [
            ["(A) LIKE 베이스라인 (유니패스 동등)", f"{a_zero} / {n_q}", "-",
             f"기준 15개 이상 → {'충족' if a_zero >= 15 else '미충족'}"],
            ["RAW 토큰만", f"{stage_zero['RAW']} / {n_q}", f"{stage_total['RAW']:,}", "영문 원문 토큰"],
            ["RAW + SYN", f"{stage_zero['RAW+SYN']} / {n_q}", f"{stage_total['RAW+SYN']:,}", "동의어 사전 결합"],
            ["RAW + SYN + CATEGORY", f"{stage_zero['RAW+SYN+CATEGORY']} / {n_q}",
             f"{stage_total['RAW+SYN+CATEGORY']:,}", "룰 매칭 물품의 카테고리 토큰까지"],
        ],
    )
    rep.data["query_analysis"] = {
        "queries": n_q, "like_zero": a_zero,
        "stage_zero": stage_zero, "stage_total": stage_total,
        "rows": [{"no": r[0], "query": r[1], "like": r[3],
                  "raw": r[4], "raw_syn": r[5], "raw_syn_cat": r[6]} for r in rows],
    }

    # ── O-5. 영문 전용 물품 부분집합 (논문 주장의 실제 대상) ──
    rep.section("O-5. 영문 전용 물품 부분집합 분석 (논문 1장 주장의 실제 대상)")
    en_keys = {(i["pbac_no"], i["pbac_srno"], i["cmdt_ln_no"])
               for i in items if not HANGUL.search(i["cmdt_nm"])}
    sub_rows = []
    sub_like_zero = sub_tok_zero = 0
    for q in queries:
        kw, kw_up = q["query"], q["query"].upper()
        like_cnt = sum(1 for i in items
                       if (i["pbac_no"], i["pbac_srno"], i["cmdt_ln_no"]) in en_keys
                       and kw in i["cmdt_nm"])
        tok_cnt = 0
        for key in en_keys:
            toks = tok_index[key]
            pool = toks["RAW"] | toks["SYN"] | toks["CATEGORY"]
            if any(kw in t or kw_up in t.upper() for t in pool):
                tok_cnt += 1
        if like_cnt == 0:
            sub_like_zero += 1
        if tok_cnt == 0:
            sub_tok_zero += 1
        sub_rows.append([q["no"], kw, like_cnt, tok_cnt,
                         "제안 방식만 검색됨" if (like_cnt == 0 and tok_cnt > 0) else ""])
    rep.table(["#", "질의", "(A) LIKE", "(B) 토큰(재현)", "비고"], sub_rows)
    rescued = sum(1 for r in sub_rows if r[4])
    rep.table(["지표", "값"],
              [["대상 (영문 전용 물품)", f"{len(en_keys):,}건"],
               ["(A) LIKE 0건 질의", f"{sub_like_zero} / {n_q}"],
               ["(B) 토큰 0건 질의", f"{sub_tok_zero} / {n_q}"],
               ["LIKE 0건 → 토큰으로 검색된 질의", rescued]])
    rep.data["english_only_subset"] = {
        "items": len(en_keys), "like_zero": sub_like_zero,
        "token_zero": sub_tok_zero, "rescued_queries": rescued,
    }
    rep.note("논문의 주장('영문 물품명은 한글로 검색할 수 없다')이 성립하는 모집단은 "
             "전체가 아니라 이 영문 전용 부분집합이다. 4.3절 표 5를 전체 코퍼스 기준으로 쓰면 "
             "휴대품(한글 물품명)이 베이스라인 점수를 끌어올려 대비가 흐려진다.")

    # ── O-6. 데이터 기반 질의셋 후보 ───────────────────
    rep.section("O-6. 실제 데이터 기반 질의셋 후보 (부록 A 재선정용)")
    syn_hits = Counter()
    for key, toks in tok_index.items():
        for t in toks["SYN"] | toks["CATEGORY"]:
            if HANGUL.search(t) and ">" not in t and len(t) >= 2:
                syn_hits[t] += 1
    cand_rows = []
    for term, n_tok in syn_hits.most_common(40):
        n_like = sum(1 for i in items if term in i["cmdt_nm"])
        gain = n_tok - n_like
        cand_rows.append([term, n_like, n_tok, f"{gain:+d}",
                          "★ 대비 큼" if n_like == 0 and n_tok > 0 else ""])
    cand_rows.sort(key=lambda r: (r[1] == 0 and r[2] > 0, r[2]), reverse=True)
    rep.table(["질의 후보", "(A) LIKE", "(B) 토큰(재현)", "차이", "비고"], cand_rows[:25])
    rep.csv("query_candidates.csv",
            ["candidate", "like_count", "token_count", "gain", "note"], cand_rows)
    strong = [r for r in cand_rows if r[1] == 0 and r[2] > 0]
    rep.data["query_candidates"] = {
        "evaluated": len(cand_rows),
        "like_zero_but_token_hit": len(strong),
        "top": [{"term": r[0], "like": r[1], "token": r[2]} for r in cand_rows[:20]],
    }
    rep.note(f"LIKE 0건이면서 토큰으로는 검색되는 후보가 {len(strong)}개 있다. "
             "부록 A 질의셋을 재선정할 경우 이 후보들을 우선 포함하면 표 5의 대비가 분명해진다. "
             "단, 질의셋을 결과가 잘 나오는 쪽으로만 고르면 체리피킹이 되므로, "
             "선정 기준(예: 카테고리 균등 + 데이터 내 출현 물품 3건 이상)을 4.3절에 명시해야 한다.")

    # ── O-7. 동의어 사전 오탐 점검 ─────────────────────
    rep.section("O-7. 동의어 사전 오탐(false positive) 점검")
    rep.text("synonym_tokens_from_text() 는 `src_term in norm_text` 부분문자열 매칭을 쓴다.")
    rep.text("따라서 짧은 src_term 은 무관한 물품명 안의 알파벳 조각에도 매칭된다.")
    rep.text("")

    short_entries = [e for e in syn_entries if len(e.src_term.strip()) <= 2]
    fp_counter = Counter()
    fp_examples: dict[str, list] = defaultdict(list)
    for i in items:
        norm, raw = i["_norm"], {t.upper() for t in i["_raw_tokens"]}
        for e in short_entries:
            src = e.src_term.upper()
            if not src:
                continue
            if src in raw:
                continue                      # 독립 토큰으로 등장 → 정상 매칭
            if src in norm:                   # 다른 단어 안의 조각으로만 등장 → 오탐
                fp_counter[f"{e.src_term} → {e.norm_term}"] += 1
                if len(fp_examples[e.src_term]) < 3:
                    fp_examples[e.src_term].append(i["cmdt_nm"][:52])

    affected = set()
    for i in items:
        norm, raw = i["_norm"], {t.upper() for t in i["_raw_tokens"]}
        for e in short_entries:
            src = e.src_term.upper()
            if src and src not in raw and src in norm:
                affected.add((i["pbac_no"], i["pbac_srno"], i["cmdt_ln_no"]))
                break

    rep.table(["항목", "값"],
              [["2자 이하 src_term 엔트리", len(short_entries)],
               ["오탐이 발생한 물품 수", f"{len(affected):,} / {len(items):,} "
                                          f"({len(affected)/len(items)*100:.1f}%)"]])
    if fp_counter:
        rep.table(["오탐 엔트리 (src → norm)", "오탐 건수", "예시 물품명"],
                  [[k, v, " / ".join(fp_examples[k.split(" → ")[0]])[:60]]
                   for k, v in fp_counter.most_common(10)])
        rep.csv("synonym_false_positives.csv", ["entry", "false_positive_items"],
                fp_counter.most_common())
    rep.data["synonym_false_positive"] = {
        "short_entries": len(short_entries),
        "affected_items": len(affected),
        "affected_ratio": round(len(affected) / len(items) * 100, 1),
        "top": [{"entry": k, "count": v} for k, v in fp_counter.most_common(10)],
    }
    rep.note("예: 'AR → 증강현실/스마트글라스' 엔트리가 SKIN CARE, HEART, PREPARATIONS 등 "
             "'AR' 문자열을 포함한 물품에 매칭된다. E03 의 P@5 를 직접 떨어뜨리므로 "
             "실험 전에 수정하는 편이 유리하다. 수정안: src_term 길이가 3 미만이면 "
             "raw_tokens 정확 일치만 허용(부분문자열 매칭 제외).")

    # ── 한계 명시 ─────────────────────────────────────
    rep.section("이 분석의 한계 (반드시 함께 읽을 것)")
    for line in [
        "1. CATEGORY 토큰은 **룰 매칭 물품에 한해** 재현했다. OpenAI 로 분류되는 물품의 카테고리 토큰은",
        "   API·DB 없이 재현할 수 없으므로, 실제 시스템의 CATEGORY 기여도는 여기 수치보다 크다.",
        "2. 위 토큰 집계는 부분문자열 포함 여부만 본다. Meilisearch 의 랭킹·오타 허용·",
        "   attributesToSearchOn 설정은 반영되지 않는다. 따라서 E03 의 (B) 열과 P@5, E04, E10 은",
        "   서비스를 기동한 뒤 반드시 다시 측정해야 한다.",
        "3. ETL 의 UPSERT·정규화 과정에서 일부 행이 제외될 수 있으므로 DB 적재 건수와 미세한 차이가",
        "   있을 수 있다. 논문 표 3 의 정본은 DB 기준 E01 결과다.",
        "4. 스키마의 토큰 유형 중 'KO' 는 build_classification.py 가 생성하지 않는다(코드 확인).",
        "   실제로 생성되는 유형은 RAW / SYN / CATEGORY 3종이며, 3.4절 서술도 이에 맞춰야 한다.",
    ]:
        rep.text(line)

    rep.save()
    return 0


if __name__ == "__main__":
    sys.exit(main())
