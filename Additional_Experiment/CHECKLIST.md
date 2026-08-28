# 실험 전 체크리스트 (실험계획서 5장)

실험을 시작하기 전에 이 문서를 위에서 아래로 한 번 훑는다.
자동 점검은 `python Additional_Experiment/scripts/e00_preflight.py` 가 대신 해준다.

---

## 5.1 환경 체크리스트

- [ ] MySQL 8 기동, 스키마 `customs_auction` 에 아래 순서로 적용 완료
      `db/schema_create.sql` → `schema_patch_v2~v5.sql` → `schema_app_user_unified_v1.sql` → seed 4종
      (`seed_category.sql`, `seed_category_extend.sql`, `seed_synonym.sql`, `seed_synonym_extend.sql`)
- [ ] Meilisearch 컨테이너 기동 (포트 7700, `MEILI_MASTER_KEY` 설정)
- [ ] cais_back 기동 (포트 3000), `.env` 에 `DB_*` / `JWT_SECRET` / `MEILI_*` 설정
- [ ] Python 의존성 설치: `python -m pip install -r Additional_Experiment/requirements.txt`
      (pymysql, requests, PyYAML / E7·E13 용 openai)
- [ ] `Additional_Experiment/config/.env` 작성 (`.env.example` 복사)
- [ ] `OPENAI_API_KEY` 유효 및 잔여 크레딧 확인 (E13 에서 필요)

---

## 5.2 데이터 스냅샷 고정 — 반드시 먼저

GitHub Actions 가 매일 02:00 KST 에 `unipass_all_2b.json` / `2c.json` 을 갱신·커밋한다.
실험 도중 ETL 을 다시 돌리면 표본이 바뀌어 E1~E13 의 수치가 서로 어긋난다.

- [ ] 스냅샷 생성

```bash
powershell -ExecutionPolicy Bypass -File Additional_Experiment\snapshot\make_snapshot.ps1
```

- [ ] `snapshot/eval_snapshot_<날짜>/COMMIT.txt` 에 커밋 해시 기록됨
- [ ] `db_before.sql`(또는 `db_before_csv/`) 백업 생성됨
- [ ] 실험 기간 중 ETL 재실행 금지 (E11 제외)
- [ ] 논문 4.1절에 기재할 "수집 기준일 / 물품 N건" 확보 → `SNAPSHOT_INFO.md` 참조

---

## 5.3 파이프라인 1회 재실행 (스냅샷 기준 정렬)

실험 시작 전에 DB 와 검색 인덱스를 한 번 정렬해 둔다.

```bash
python etl/load_unipass_to_mysql.py
python classification/build_classification.py --use-openai --openai-target-level 2
node cais_back/scripts/sync_meili.js
```

- [ ] 세 명령 모두 정상 종료
- [ ] `e00_preflight.py` 에서 Meilisearch 색인 문서 수 > 0 확인

---

## 5.4 절대 주의사항

### 경고 1 — 분류 스크립트 전체 실행 금지

`build_classification.py` 를 `--use-openai` 없이 전체 실행하면,
기존에 OpenAI 가 분류해 둔 항목이 **「기타 > 미분류」(confidence 0.55)로 덮어써진다.**

- 커버리지 비교(E07)는 반드시 `--dry-run` 으로 수행한다.
  → `e07_hybrid_ablation.py` 는 기본적으로 CLI 를 실행하지 않고, `--via-cli` 사용 시에도
    `--dry-run` 을 강제로 붙이도록 구현되어 있다.
- 부분 갱신이 필요하면 `--rule-only-update` 를 사용한다.

### 경고 2 — DB 백업

실험 전 반드시 DB 를 백업한다. E05 의 라벨링 결과와 E02 의 커버리지는 **같은 DB 상태**에서
나와야 하므로, 중간에 재분류를 돌렸다면 두 실험을 모두 다시 해야 한다.

### 경고 3 — 자격 정보 노출 금지

`post.py` 에 하드코딩된 AWS Lambda Function URL 과 각 스크립트의 기본 DB 비밀번호는
**논문 본문·부록·스크린샷 어디에도 노출하지 않는다.**
스크린샷을 찍을 때 터미널 프롬프트·환경변수·설정 파일이 화면에 들어가지 않는지 확인한다.

---

## 실험 순서 (권장)

| 순서 | 작업 | 선행 조건 |
|---|---|---|
| D-0 | 스냅샷 고정 + DB 백업 + 파이프라인 1회 재실행 | 5.1 체크리스트 완료 |
| D-0 | E01 · E02 | 재실행 완료 |
| D-1 | **E03 · E04** ← 최우선 | Meilisearch 색인 완료 |
| D-1 | E07 · E08 | E02 완료 |
| D-2 | E05 라벨링 100건 (3인 병렬) | 표본 CSV 배포 |
| D-3 | E05 집계 · E09 · E12 | 라벨 병합 |
| D-3 | E06 사용성 실험 (참가자 8~10명) | 앱 시연 환경 준비 |
| D-4 | E10 · E11 (여유 시) + 결과 정리 | — |
| D-5 | 논문 4장 초고 작성 | 전체 결과 취합 (`collect_results.py`) |

---

## 실험 종료 후

- [ ] `python Additional_Experiment/scripts/collect_results.py` 실행 → `results/PAPER_TABLES.md`
- [ ] `results/PAPER_TABLES.md` 의 "집필 전 확인" 표 점검
- [ ] 금지 표현 점검 (→ `docs/EXPERIMENT_MATRIX.md` 5장)
- [ ] 실험 기간·기준일·표본 수가 논문 4.1절 서술과 일치하는지 확인
