# Additional_Experiment — 졸업논문 성능 평가 및 추가 실험

S108 「세관 공매 접근성 향상 서비스」 졸업논문 실험계획서 v1.0 에 정의된
**필수 6건 · 권장 3건 · 선택 4건, 총 13건**의 실험을 실행·기록하기 위한 작업 폴더다.

> 원본 계획서(`S108_졸업논문_실험계획서_v1.0.docx`)는 읽기 전용 참고 자료다.
> 이 폴더의 어떤 스크립트도 원본 문서를 읽거나 쓰지 않는다.

---

## 0. 30초 요약

```bash
# 1) 스냅샷 고정 (실험 시작 전 1회, 반드시 먼저)
powershell -ExecutionPolicy Bypass -File Additional_Experiment\snapshot\make_snapshot.ps1

# 2) 환경 점검
python Additional_Experiment/scripts/e00_preflight.py

# 3) 자동 실험 일괄 실행 (필수 항목)
python Additional_Experiment/scripts/run_all.py

# 4) 논문 표 초안 생성
python Additional_Experiment/scripts/collect_results.py
```

사람이 직접 해야 하는 것은 네 가지뿐이다: **E03 P@5 판정 · E05 블라인드 라벨링 ·
E06 사용성 실험 · E13 판정**. 나머지는 스크립트가 수치를 뽑는다.

---

## 1. 폴더 구조

```text
Additional_Experiment/
├─ README.md                  # 이 문서 (실행 가이드)
├─ HANDOFF.md                # 인수인계 설명서 (다른 담당자/AI가 이어받을 때 먼저 읽는 문서)
├─ CHECKLIST.md               # 실험 전 체크리스트 + 절대 주의사항
├─ requirements.txt           # Python 의존성
├─ config/
│  ├─ .env.example            # DB·API·Meili·OpenAI 설정 예시 (복사해서 .env 로 사용)
│  └─ queryset.json           # 부록 A 질의셋 (한글 20개 + 오타쌍 5개)
├─ common/
│  └─ exp_common.py           # 공통 유틸 (DB·API·리포트 저장)
├─ scripts/                   # 실험 스크립트 (E00~E13)
├─ sql/                       # 계획서 원문 SQL (수동 실행용)
├─ snapshot/                  # 데이터 스냅샷 고정 도구 + 스냅샷 보관
├─ templates/                 # 기록지 템플릿 (부록 B) + E06 진행 스크립트
├─ docs/
│  └─ EXPERIMENT_MATRIX.md    # 논문 표·그림 ↔ 실험 대응표, 역할·일정, 금지 표현
└─ results/                   # 실험 결과 (스크립트가 자동 생성)
   ├─ RUN_LOG.md              # 실행 이력
   ├─ PAPER_TABLES.md         # 논문 표 3~6 초안 (collect_results.py 생성)
   └─ E01/, E02/ ...          # 실험별 report.md · data.json · CSV
```

---

## 2. 사전 준비

### 2.1 Python 의존성

```bash
python -m pip install -r Additional_Experiment/requirements.txt
```

`openai` 는 E07(선택 모드) · E13 에서만 필요하다.

### 2.2 설정 파일

```bash
cp Additional_Experiment/config/.env.example Additional_Experiment/config/.env
```

`.env` 에 DB 비밀번호 · Meilisearch 마스터키 · OpenAI 키를 채운다.
**이 파일은 커밋하지 않는다** (계획서 5.4 경고 3).

### 2.3 서비스 기동

| 대상 | 기동 방법 | 확인 |
|---|---|---|
| MySQL 8 | `customs_auction` 스키마 + patch v2~v5 + seed 4종 적용 | `e00_preflight.py` |
| Meilisearch | `docker run -p 7700:7700 -e MEILI_MASTER_KEY=... getmeili/meilisearch` | `http://localhost:7700/health` |
| cais_back | `cd cais_back && npm start` (포트 3000) | `/api/items/search?keyword=와인` |

### 2.4 데이터 스냅샷 고정 — 반드시 먼저

GitHub Actions 가 매일 02:00 KST 에 `unipass_all_2b.json` / `2c.json` 을 갱신·커밋한다.
실험 도중 표본이 바뀌면 E1~E13 의 수치가 서로 어긋난다.

```bash
powershell -ExecutionPolicy Bypass -File Additional_Experiment\snapshot\make_snapshot.ps1
```

`snapshot/eval_snapshot_<날짜>/` 에 입력 JSON · 커밋 해시 · DB 백업 · `SNAPSHOT_INFO.md` 가 생성된다.
`mysqldump` 가 PATH 에 없으면 자동으로 Python CSV 백업(`snapshot_db.py`)으로 대체된다.

---

## 3. 실험 목록과 실행 명령

| ID | 구분 | 실험 | 논문 위치 | 실행 |
|---|---|---|---|---|
| E00 | 사전 | 환경 점검 | — | `python Additional_Experiment/scripts/e00_preflight.py` |
| OFF | 사전 | 오프라인 사전 분석 (DB 없이 수행) | E01/E03(A)/E07/E08 예비 | `offline_preanalysis.py` |
| E01 | 필수 | 데이터셋 기초 통계 | 4.1 표 3 | `e01_dataset_stats.py` |
| E02 | 필수 | 자동 분류 커버리지 | 4.2 표 4 상단 | `e02_classification_coverage.py` |
| E03 | 필수 | 한글 검색 베이스라인 비교 ★ | 4.3 표 5 | `e03_search_baseline.py` → 2인 판정 → `e03b_p5_score.py` |
| E04 | 필수 | 오타 허용 검증 | 4.3 표 5 하단 | `e04_typo_tolerance.py` |
| E05 | 필수 | 분류 정확도 블라인드 재평가 | 4.2 표 4 하단 | `e05a_sample_blind.py` → 3인 라벨링 → `e05b_merge_and_evaluate.py` |
| E06 | 필수 | 사용성 과업 비교 | 4.4 표 6 | `e06_usability_analyze.py --init` → 실험 → `e06_usability_analyze.py` |
| E07 | 권장 | 하이브리드 기여도 (ablation) | 4.2 표 4 병합 | `e07_hybrid_ablation.py` |
| E08 | 권장 | 토큰 유형별 기여도 | 4.3 본문 | `e08_token_ablation.py` |
| E09 | 권장 | 신뢰도 구간별 정확도 | 4.2 본문 | `e09_confidence_bins.py` (E05 결과 재활용) |
| E10 | 선택 | 검색 응답시간 p50/p95 | 4.3 표 5 병합 | `e10_latency.py` |
| E11 | 선택 | 파이프라인 멱등성 | 3.2 본문 | `e11_idempotency.py --run-etl` |
| E12 | 선택 | 오분류 정성 분석 | 5장 본문 | `e12_error_analysis.py` (E05 결과 재활용) |
| E13 | 선택 | LLM 분류 깊이 비교 | 3.3.3 근거 | `e13_llm_depth.py --run` → 판정 → `--score` |

일괄 실행:

```bash
python Additional_Experiment/scripts/run_all.py --set required     # 필수 자동 실험
python Additional_Experiment/scripts/run_all.py --set all          # 권장·선택까지
```

---

## 4. 사람이 개입하는 3.5개 단계

### 4.1 E03 — P@5 판정 (2인 독립)

1. `e03_search_baseline.py` 실행 → `results/E03/p5_judgement.csv` 생성 (질의 20개 × 상위 5건)
2. 두 사람이 **서로 보지 않고** `judge1_OX` / `judge2_OX` 열에 `O`/`X` 기입
3. `e03b_p5_score.py` 실행 → 질의별 P@5, 평균 P@5, 일치율·kappa, 불일치 목록 산출
4. 불일치 건만 협의해 확정하고 재실행

혼자 판정하면 "내가 만든 검색이라 맞다고 본다"는 지적을 받는다. 반드시 2인으로 한다.

### 4.2 E05 — 블라인드 라벨링 (3인, 표본 100건)

```bash
python Additional_Experiment/scripts/e05a_sample_blind.py
```

- `results/E05/eval_label_blank.csv` (전체 표본) + `results/E05/labels/label_<코드>.csv` (배포용)
- 배포 파일에는 **자동 분류 결과가 들어 있지 않다**. 이것이 블라인드의 핵심이다.
- 기본 배분: 공통 문항 20건(전원 동일) + 나머지 80건을 3인이 분할 → 1인당 약 47건.
  계획서의 "각 40건" 배분을 그대로 쓰려면 `--common 20 --n 80` 으로 조정한다.
- **애매한 건도 비워두지 않는다.** 「기타 > 미분류 > 기타」로 명시한다.

라벨링이 끝나면:

```bash
python Additional_Experiment/scripts/e05b_merge_and_evaluate.py
```

- 카테고리 경로 오타 검사 → 라벨러 간 일치도(전원 일치율 / 쌍별 / Fleiss' kappa)
- 다수결 정답 확정(동점은 협의 대상으로 표시) → `ground_truth_v2.csv` 생성
- `classification/eval/evaluate.py` 를 실행해 정확도 산출
  (저장소의 `accuracy_report.txt` 는 건드리지 않고 `results/E05/` 에만 기록)

### 4.3 E06 — 사용성 실험 (참가자 8~10명)

진행 스크립트: [`templates/E6_protocol.md`](templates/E6_protocol.md) — 안내문·과업 지시문·금지사항 포함.

```bash
python Additional_Experiment/scripts/e06_usability_analyze.py --init   # 기록지 생성
# ... 실험 진행 후 기록지 작성 ...
python Additional_Experiment/scripts/e06_usability_analyze.py          # 집계 → 표 6
```

### 4.4 E13 — LLM 깊이 판정 (선택)

`e13_llm_depth.py --run` 으로 level 2 / level 3 결과를 뽑고, CSV 의 `judge_level2` /
`judge_level3` 열을 채운 뒤 `--score` 로 집계한다.

---

## 5. 결과물

모든 스크립트는 세 가지를 남긴다.

| 파일 | 용도 |
|---|---|
| `results/<ID>/report.md` | 사람이 읽는 리포트 (표 + 판정 + 논문 문장 초안) |
| `results/<ID>/data.json` | 기계가 읽는 수치 (`collect_results.py` 가 취합) |
| `results/<ID>/*.csv` | 원자료 (판정지, 오분류 목록 등) |

취합:

```bash
python Additional_Experiment/scripts/collect_results.py
```

→ `results/PAPER_TABLES.md` 에 **표 3~6 초안 + 실험 진행 현황 + 집필 전 확인표**가 생성된다.
미수행 실험은 "미수행"으로 표시되므로 진행 현황판으로도 쓸 수 있다.

---

## 6. 안전장치 (계획서 5.4 대응)

| 위험 | 이 폴더의 대응 |
|---|---|
| `build_classification.py` 를 `--use-openai` 없이 전체 실행 → 기존 OpenAI 분류가 「기타 > 미분류」로 덮어써짐 | E07 은 기본적으로 CLI 를 실행하지 않고 룰 매칭 함수만 in-process 로 호출한다(DB 쓰기 0회). `--via-cli` 사용 시에도 `--dry-run` 을 **강제**로 붙인다 |
| 실험 중 데이터 갱신으로 표본이 어긋남 | `make_snapshot.ps1` 로 입력 JSON·커밋 해시·DB 를 고정하고, `e00_preflight.py` 가 스냅샷 유무를 점검한다 |
| DB 쓰기 실험 | 쓰기가 발생하는 실험은 E11 뿐이며, `--run-etl` + 확인 프롬프트가 없으면 조회만 한다 |
| 저장소 파일 오염 | 모든 산출물은 `Additional_Experiment/results/` 에만 쓴다. `classification/eval/ground_truth_v2.csv` 복사는 `--copy-to-repo` 를 명시해야 수행된다 |
| 자격 정보 노출 | 설정은 `config/.env`(비커밋)에서만 읽는다. 리포트에는 호스트·계정만 남고 비밀번호·키는 기록하지 않는다 |

---

## 7. 참고 문서

- [`HANDOFF.md`](HANDOFF.md) — **인수인계 설명서** (실행 담당자·AI 에이전트용 단계별 지침)
- [`docs/EXPERIMENT_REPORT.md`](docs/EXPERIMENT_REPORT.md) — **추가 실험 보고서** (사전 분석 실측 결과·발견 사항·잔여 절차)
- [`CHECKLIST.md`](CHECKLIST.md) — 실험 전 체크리스트, 절대 주의사항
- [`docs/EXPERIMENT_MATRIX.md`](docs/EXPERIMENT_MATRIX.md) — 논문 표·그림 ↔ 실험 대응, 역할 분담, 일정, 금지 표현
- [`templates/E6_protocol.md`](templates/E6_protocol.md) — 사용성 실험 진행 스크립트
- 저장소 문서: `docs/SEARCH_ENGINE_DESIGN.md`, `docs/CLASSIFICATION_LOGIC_DESIGN.md`, `classification/README.md`
