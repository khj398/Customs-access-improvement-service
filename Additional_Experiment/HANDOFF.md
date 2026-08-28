# 인수인계 설명서 — 남은 실험 실행

S108 「세관 공매 접근성 향상 서비스」 졸업논문 평가 실험(E1~E13)의 실행 인수인계 문서.
실행 환경(MySQL·Meilisearch·Node.js)이 준비된 담당자에게 넘긴다.

---

## 0. 이 문서를 받은 AI 에이전트에게

당신은 이 저장소에서 **논문 평가 실험을 실행하고 수치를 산출**하는 역할이다.
스크립트·기록지·문서는 전부 준비되어 있다. 당신이 할 일은 환경을 갖추고 순서대로 실행한 뒤,
결과 파일을 정리해 사용자에게 돌려주는 것이다.

**절대 규칙 세 가지 — 어기면 졸업논문이 무효가 된다.**

1. **수치를 지어내지 않는다.** 실행하지 못한 실험은 "미수행"으로 보고한다.
   그럴듯한 값을 채우거나 예시 값을 결과로 제시하면 논문 데이터 위조다.
   특히 아래 3건은 **사람이 직접 수행해야만 데이터가 생긴다**(6장 참조).
   E03 P@5 판정 · E05 블라인드 라벨링 · E06 사용성 실험.
2. **DB를 파괴하는 명령을 실행하지 않는다.** 특히 `python classification/build_classification.py`를
   `--dry-run` 없이 전체 실행하면 기존 OpenAI 분류 결과가 「기타 > 미분류」로 덮어써진다(7장).
3. **원본 데이터·문서를 수정하지 않는다.** 수집 JSON(`unipass_all_2*.json`),
   `classification/eval/ground_truth.csv`, `docs/` 문서는 읽기만 한다.
   모든 산출물은 `Additional_Experiment/results/` 아래에만 쓴다.

**시작할 때 이 순서로 하라.**

```bash
python Additional_Experiment/scripts/e00_preflight.py
```

이 명령이 무엇이 준비되고 무엇이 빠졌는지 표로 알려준다. FAIL 항목을 3장 순서대로 해결한 뒤
다시 실행해 전부 통과시키고 나서 실험을 시작한다. 그 전에 다른 실험 스크립트를 돌리지 마라.

그다음 읽을 문서는 이 순서다.
`Additional_Experiment/README.md`(실행 가이드) → `CHECKLIST.md`(주의사항) →
`docs/EXPERIMENT_REPORT.md`(직전 사전 분석 결과와 발견 사항).

---

## 1. 배경 30초

- 논문 4장(평가)에 넣을 정량 수치가 없어서, 실험계획서 v1.0이 실험 13건을 정의했다.
- `Additional_Experiment/` 폴더에 그 13건을 실행하는 스크립트가 전부 구현되어 있다.
- 직전 작업자는 **MySQL·Meilisearch·Node.js가 없는 PC**에서 작업해, 서비스가 필요 없는
  오프라인 분석만 수행했다. 그 결과는 `docs/EXPERIMENT_REPORT.md`에 있다.
- 남은 일: 환경을 갖추고 나머지 실험을 실행하는 것 + 사람이 해야 하는 3건.

---

## 2. 현재 상태

| ID | 실험 | 논문 위치 | 상태 | 남은 일 |
|---|---|---|---|---|
| E01 | 데이터셋 기초 통계 | 4.1 표 3 | 예비 수치만 | DB 기동 후 재실행 |
| E02 | 자동 분류 커버리지 | 4.2 표 4 상단 | 미수행 | DB + 분류 실행 |
| E03 | 한글 검색 비교 ★최우선 | 4.3 표 5 | (A)만 계산됨 | 서비스 기동 + **2인 판정** |
| E04 | 오타 허용 검증 | 4.3 표 5 하단 | 미수행 | Meilisearch 필요 |
| E05 | 분류 정확도 블라인드 | 4.2 표 4 하단 | 미수행 | DB + **3인 라벨링** |
| E06 | 사용성 과업 비교 | 4.4 표 6 | 미수행 | **참가자 8~10명** |
| E07 | 하이브리드 기여도 | 4.2 표 4 병합 | 룰 단독만 계산됨 | DB 필요 |
| E08 | 토큰 유형별 기여도 | 4.3 본문 | 예비 수치만 | DB 필요 |
| E09 | 신뢰도 구간별 정확도 | 4.2 본문 | 미수행 | E05 결과 필요 |
| E10 | 검색 응답시간 | 4.3 표 5 병합 | 미수행 | 서비스 기동 |
| E11 | 파이프라인 멱등성 | 3.2 본문 | 미수행 | DB + ETL |
| E12 | 오분류 정성 분석 | 5장 본문 | 미수행 | E05 결과 필요 |
| E13 | LLM 분류 깊이 비교 | 3.3.3 근거 | 미수행 | OPENAI_API_KEY |

직전 오프라인 분석에서 확인된 수치(참고용, 커밋 `73cde03` 기준 물품 497건):
영문 전용 물품명 19.7% · 룰 단독 커버리지 52.1% · LIKE 0건 질의 12/20 · 동의어 오탐 10.9%.

> 데이터는 GitHub Actions가 매일 02:00 KST에 갱신한다. 지금 clone한 데이터는 위 수치와 다를 수 있다.
> 정상이다. 실험은 **당신이 고정한 스냅샷 기준**으로 수행하고, 그 수치를 논문에 쓴다.

---

## 3. 환경 준비

### 3.1 저장소와 Python

```bash
git clone https://github.com/khj398/Customs-access-improvement-service.git
```

`Additional_Experiment/` 폴더가 저장소 루트 안에 있어야 한다. 별도로 압축 파일을 받았다면
저장소 루트에 풀어라. 스크립트가 `classification/`, `etl/`, `db/`, `cais_back/` 을 상대경로로
참조하므로 **폴더만 따로 떼어내면 동작하지 않는다.**

```bash
python -m pip install -r Additional_Experiment/requirements.txt
```

### 3.2 MySQL 8

스키마를 이 순서로 적용한다. 순서를 바꾸면 FK 오류가 난다.

```bash
mysql -u root -p -e "CREATE DATABASE IF NOT EXISTS customs_auction DEFAULT CHARSET utf8mb4;"
```

그다음 `db/` 의 파일을 순서대로 적용한다:
`schema_create.sql` → `schema_patch_v2.sql` → `v3` → `v4` → `v5` →
`schema_app_user_unified_v1.sql` → `seed_category.sql` → `seed_category_extend.sql` →
`seed_synonym.sql` → `seed_synonym_extend.sql`

```bash
for f in schema_create schema_patch_v2 schema_patch_v3 schema_patch_v4 schema_patch_v5 schema_app_user_unified_v1 seed_category seed_category_extend seed_synonym seed_synonym_extend; do mysql -u root -p customs_auction < db/$f.sql; done
```

### 3.3 Meilisearch

```bash
docker run -d -p 7700:7700 -e MEILI_MASTER_KEY=cais-search-key getmeili/meilisearch:latest
```

Docker가 없으면 Meilisearch 단독 실행 바이너리를 받아 같은 포트·같은 마스터키로 띄운다.

### 3.4 백엔드 (cais_back)

```bash
cd cais_back && npm install && npm start
```

`cais_back/.env` 에 `DB_HOST` `DB_PORT` `DB_USER` `DB_PASSWORD` `DB_NAME` `JWT_SECRET`
`MEILI_HOST` `MEILI_MASTER_KEY` 를 설정한다. 포트는 3000이다.

### 3.5 실험용 설정 파일

```bash
cp Additional_Experiment/config/.env.example Additional_Experiment/config/.env
```

`.env` 에 DB 비밀번호·Meili 마스터키를 채운다. **이 파일은 커밋하지 않는다**(`.gitignore`에 등록되어 있다).
OpenAI 키는 E13을 할 때만 필요하다.

### 3.6 검증

```bash
python Additional_Experiment/scripts/e00_preflight.py
```

모든 항목이 PASS 여야 다음 단계로 간다. WARN은 해당 실험만 제한된다.

---

## 4. 실험 전에 사람이 결정해야 할 것 3건

직전 분석에서 발견된 문제다. **실험을 돌린 뒤에 고치면 그 실험을 다시 해야 하므로,
반드시 먼저 처리한다.** 근거와 상세는 `docs/EXPERIMENT_REPORT.md` 4장에 있다.

### 4.1 [코드 수정] 동의어 사전 오탐 — F-3

`AR → 증강현실` 같은 2자 항목이 `SKIN CARE`, `HEART` 처럼 알파벳 조각만 겹치는
물품명에 매칭되어, 직전 데이터 기준 **전체 물품의 10.9%가 잘못된 검색 토큰**을 갖고 있었다.
E03의 P@5를 직접 떨어뜨린다.

수정 위치: `classification/build_classification.py` 의 `synonym_tokens_from_text()`

```python
    for e in dict_entries:
        src = e.src_term.upper()
        if not src:
            continue
        # 2자 이하 src_term은 부분문자열 매칭을 금지하고 토큰 정확 일치만 허용
        if len(src) < 3:
            if src not in raw_tokens:
                continue
        elif src not in raw_tokens and src not in norm_text:
            continue
        out.append((e.norm_term, "SYN", float(e.weight)))
```

**이 수정은 팀 공용 코드 변경이므로 사용자(팀) 승인을 받고 적용한다.**
적용했다면 분류를 다시 돌려 토큰을 재생성해야 한다(5장 3단계에 포함되어 있다).
적용하지 않기로 했다면 그 사실을 논문 5장 한계로 적는다. 어느 쪽이든 결정을 기록에 남긴다.

### 4.2 [설계 결정] 질의셋 재선정 — F-2

부록 A의 20개 질의 중 와인·배터리·냉장고·타이어·러닝머신 등은 **데이터에 존재하지 않는다.**
계획서 부록 A 자체가 "양쪽 모두 0건인 질의가 5개를 넘으면 재선정"이라고 규정했고,
직전 데이터에서 11개가 해당했다.

- 후보 목록: `Additional_Experiment/results/OFFLINE/query_candidates.csv`
  (LIKE로는 0건인데 토큰으로는 검색되는 후보가 이미 뽑혀 있다)
- 재선정한다면 `Additional_Experiment/config/queryset.json` 의 `korean_queries` 를 교체한다.
  구조는 그대로 두고 값만 바꾼다.
- **주의**: 잘 나오는 질의만 고르면 체리피킹이다. 선정 기준(예: 12개 대분류 균등 분포 +
  데이터 내 해당 물품 3건 이상)을 정하고 논문 4.3절에 명시한다. 기존 부록 A 질의의 0건 결과도
  함께 보고하는 편이 안전하다.
- 이 결정은 AI가 단독으로 하지 말고 팀에 선택지를 제시하고 승인을 받아라.

### 4.3 [집필 사항] 서론 범위 한정 — F-1

직전 데이터의 80.3%가 이미 한글 물품명이었다(휴대품 비중이 높기 때문). 논문 1장의
"물품명이 영문 위주" 전제를 **"수입화물 공매 물품에 한해"** 로 좁혀야 한다.
실행 담당자가 할 일은 아니고, 집필 담당자에게 전달만 하면 된다.

---

## 5. 실행 순서

각 단계마다 "성공 판정"을 확인하고 다음으로 넘어간다. 실패하면 8장을 본다.

### 1단계 — 데이터 스냅샷 고정 (가장 먼저, 한 번만)

```bash
powershell -ExecutionPolicy Bypass -File Additional_Experiment\snapshot\make_snapshot.ps1
```

- 하는 일: 수집 JSON 사본 + 커밋 해시 + DB 백업을 `snapshot/eval_snapshot_<날짜>/` 에 고정
- **성공 판정**: 폴더 안에 `COMMIT.txt`, `SNAPSHOT_INFO.md`, `db_before.sql`(또는 `db_before_csv/`) 생성
- 이후 실험 기간 중에는 `git pull` 로 데이터를 갱신하지 않는다. 표본이 바뀌면 실험 간 수치가 어긋난다.

### 2단계 — 파이프라인 1회 실행 (DB·색인 정렬)

```bash
python etl/load_unipass_to_mysql.py
```
```bash
python classification/build_classification.py --use-openai --openai-target-level 2
```
```bash
node cais_back/scripts/sync_meili.js
```

- OpenAI 키가 없으면 두 번째 명령에서 `--use-openai --openai-target-level 2` 를 빼고 실행한다.
  단, **이미 OpenAI 분류 결과가 들어 있는 DB라면 빼고 실행하면 안 된다**(7장 참조).
  키가 없고 기존 결과도 없는 새 DB라면 룰 단독으로 진행하고, E07·E13은 미수행으로 보고한다.
- **성공 판정**: `e00_preflight.py` 재실행 시 `item_classification` 행 수 > 0,
  Meilisearch 색인 문서 수 > 0

### 3단계 — 자동 실험 일괄 실행

```bash
python Additional_Experiment/scripts/run_all.py --set all
```

- 실행되는 것: E00 · E01 · E02 · E03(A/B 수집) · E04 · E07 · E08 · E10 · E11(조회 모드)
- **성공 판정**: 실행 요약표에 "실패"가 없고, `Additional_Experiment/results/` 아래
  실험별 폴더에 `report.md` 와 `data.json` 이 생성됨
- 개별 재실행이 필요하면 `python Additional_Experiment/scripts/e03_search_baseline.py` 처럼
  스크립트를 직접 부른다. 모든 스크립트는 `--help` 를 지원한다.

### 4단계 — 사람 단계 (6장)

E03 판정 · E05 라벨링 · E06 실험. 여기서 AI는 **입력 파일을 만들고, 채워진 파일을 집계**한다.
값을 채우는 것은 사람이다.

### 5단계 — 후속 실험 (E05 결과가 있어야 가능)

```bash
python Additional_Experiment/scripts/e09_confidence_bins.py
```
```bash
python Additional_Experiment/scripts/e12_error_analysis.py
```

### 6단계 — 결과 취합

```bash
python Additional_Experiment/scripts/collect_results.py
```

- 산출: `Additional_Experiment/results/PAPER_TABLES.md` — 논문 표 3~6 초안 + 진행 현황 + 집필 전 확인표
- **성공 판정**: 진행 현황표에서 필수 실험 6건이 "완료"

---

## 6. 사람이 해야 하는 3건 — AI는 대신할 수 없다

### 6.1 E03 P@5 판정 (2인, 각 30분)

```bash
python Additional_Experiment/scripts/e03_search_baseline.py
```

→ `results/E03/p5_judgement.csv` 생성 (질의 20개 × 상위 5건).
두 사람이 **서로 보지 않고** `judge1_OX` / `judge2_OX` 열에 `O`(질의에 부합) / `X` 를 채운다.
혼자 판정하면 "자기 검색이라 맞다고 본다"는 지적을 받는다.

```bash
python Additional_Experiment/scripts/e03b_p5_score.py
```

→ 질의별 P@5, 평균 P@5, 판정자 간 일치율·Cohen's kappa, 불일치 목록.
불일치 건만 협의로 확정하고 파일을 고쳐 재실행한다.

### 6.2 E05 블라인드 라벨링 (3인, 각 1.5시간)

```bash
python Additional_Experiment/scripts/e05a_sample_blind.py
```

→ `results/E05/labels/label_<코드>.csv` 3개 배포.
**자동 분류 결과가 일부러 빠져 있다. 이것이 블라인드의 핵심이다.**
라벨러는 물품명만 보고 `true_category_path` 를 채운다. 참고표는 같은 폴더의
`category_reference.csv` 이고, 경로를 그대로 복사해 넣어야 한다(오타 시 전부 오분류로 계산된다).
**애매한 건도 비워두지 않는다. 「기타 > 미분류 > 기타」로 명시한다.**

```bash
python Additional_Experiment/scripts/e05b_merge_and_evaluate.py
```

→ 경로 오타 검사 → 라벨러 간 일치도(Fleiss' kappa) → 다수결 확정 →
`ground_truth_v2.csv` 생성 → `classification/eval/evaluate.py` 실행 → 정확도 산출.

정확도가 80%대로 나와도 그대로 쓴다. 기존 100%(자동 결과와 일치하는 50건만 라벨링한 편향값)보다
훨씬 강한 결과다.

### 6.3 E06 사용성 실험 (참가자 8~10명, 반나절)

진행 스크립트: `Additional_Experiment/templates/E6_protocol.md`
— 참가자 안내문, 과업 4종 지시문, 진행자 금지사항, 기록 규칙이 전부 들어 있다. 그대로 읽고 진행한다.

```bash
python Additional_Experiment/scripts/e06_usability_analyze.py --init
```

→ `results/E06/usability_record.csv` · `satisfaction.csv` 생성. 실험 후 값을 채운다.

```bash
python Additional_Experiment/scripts/e06_usability_analyze.py
```

→ 과업별 평균 완료 시간·성공률·순서 효과·만족도 집계(논문 표 6).

---

## 7. 절대 금지

| 금지 | 이유 |
|---|---|
| `python classification/build_classification.py` 를 `--dry-run` 도 `--use-openai` 도 없이 전체 실행 | 기존 OpenAI 분류가 전부 「기타 > 미분류」(confidence 0.55)로 덮어써진다. 부분 갱신이 필요하면 `--rule-only-update` 를 쓴다 |
| DB 백업 없이 `e11_idempotency.py --run-etl` 실행 | 이 실험만 DB 쓰기가 발생한다. 1단계 스냅샷을 먼저 끝낸다 |
| 실험 중 `git pull` 로 데이터 갱신 | GitHub Actions가 매일 JSON을 바꾼다. 표본이 바뀌면 E01~E13 수치가 서로 어긋난다 |
| 실험 중간에 재분류 후 일부 실험만 재실행 | E02 커버리지와 E05 정확도는 같은 DB 상태에서 나와야 한다. 재분류했다면 둘 다 다시 한다 |
| DB 비밀번호·Lambda Function URL·API 키를 결과 파일이나 스크린샷에 남기기 | 논문 본문·부록·스크린샷 어디에도 노출 금지 |
| `config/.env` 커밋 | 자격 정보 유출 |
| 미수행 실험을 추정값으로 채우기 | 논문 데이터 위조 |

---

## 8. 문제 해결

| 증상 | 원인·조치 |
|---|---|
| `pymysql 이 설치되어 있지 않습니다` | `python -m pip install -r Additional_Experiment/requirements.txt` |
| `MySQL 연결 실패 (1045)` | `config/.env` 의 계정·비밀번호 확인. `root@localhost` 만 있고 `root@127.0.0.1` 권한이 없으면 `DB_HOST=localhost` 로 변경 |
| E03에서 `(B) 호출 실패` | cais_back(3000)·Meilisearch(7700) 미기동. 기동 후 재실행. **실패 상태의 수치는 논문에 쓸 수 없다** |
| Meilisearch 색인 문서 0건 | `node cais_back/scripts/sync_meili.js` 실행 |
| 콘솔에 한글이 깨짐 | 스크립트는 UTF-8을 강제한다. 결과는 `results/**/report.md` 파일로 확인하면 정상이다 |
| E05에서 "카테고리 트리에 없는 경로" 경고 | 라벨러 오타. `category_reference.csv` 의 경로를 그대로 복사해 수정 후 재실행 |
| E09/E12가 "ground_truth_v2.csv 없음" | E05 라벨링이 끝나지 않았다. 정상이다 |
| E13에서 OpenAI 초기화 실패 | `OPENAI_API_KEY` 미설정 또는 크레딧 소진. E13은 선택 실험이므로 미수행 처리 가능 |
| 오프라인 분석 수치와 다름 | 데이터가 갱신되었기 때문. 당신의 스냅샷 기준 수치가 정본이다 |

DB·서비스 없이 먼저 감을 잡고 싶다면 이것만 따로 돌려도 된다(읽기 전용, 안전):

```bash
python Additional_Experiment/scripts/offline_preanalysis.py
```

---

## 9. 완료 후 회신물

실행이 끝나면 아래를 압축해 요청자에게 보낸다.

- `Additional_Experiment/results/` 폴더 전체 (실험별 `report.md` · `data.json` · CSV)
- `Additional_Experiment/results/PAPER_TABLES.md` (논문 표 3~6 초안)
- `snapshot/eval_snapshot_<날짜>/SNAPSHOT_INFO.md` (수집 기준일·커밋 해시 — 논문 4.1절에 필요)

함께 적어 보낼 것:

1. 수행한 실험과 **수행하지 못한 실험, 그 이유**
2. 4장의 결정 3건을 어떻게 처리했는지 (F-3 코드 수정 적용 여부, F-2 질의셋 교체 여부)
3. 실행 중 발견한 이상 징후 (0건 질의가 많다, 특정 룰이 과매칭된다 등)

**보내지 말 것**: `config/.env`, DB 덤프(`db_before.sql`), 참가자 개인정보.
E06 기록지는 익명 번호(P1~P10)만 있으므로 그대로 보내도 된다.
