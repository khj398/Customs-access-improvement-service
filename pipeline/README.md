# pipeline — 파이프라인 오케스트레이터 & 스케줄러

ETL → 분류 → (선택) 자동 규칙 생성을 순차 실행하고, 이를 매일 자동으로 반복합니다.

---

## 파일 구조

```
pipeline/
├─ run_pipeline.py    # 1회 실행 오케스트레이터
└─ scheduler.py       # 일별 스케줄 반복 실행기
```

---

## 각 파일 설명

### `run_pipeline.py`

ETL → 분류 → (선택) 자동 규칙 생성을 순서대로 실행하는 진입점입니다.  
각 단계를 subprocess로 호출하고 성공/실패를 출력합니다.  
완료 후 `classification/eval/accuracy_report.txt`에 통계 리포트를 저장합니다.

**실행 방법**

```bash
# ETL + Rule 분류
python pipeline/run_pipeline.py

# ETL + Rule + OpenAI fallback 분류
python pipeline/run_pipeline.py --use-openai

# ETL + OpenAI + 자동 규칙 생성
python pipeline/run_pipeline.py --use-openai --auto-rules

# 분류만 (ETL 생략)
python pipeline/run_pipeline.py --mode classify-only

# ETL만 (분류 생략)
python pipeline/run_pipeline.py --mode etl-only

# Rule 매칭 물품만 갱신 (OpenAI 결과 보존)
python pipeline/run_pipeline.py --rule-only-update
```

**옵션 전체**

| 옵션 | 기본값 | 설명 |
|------|--------|------|
| `--mode` | `full` | `full` / `etl-only` / `classify-only` |
| `--use-openai` | false | OpenAI fallback 분류 활성화 |
| `--openai-model` | `gpt-4o-mini` | 사용할 OpenAI 모델 |
| `--rule-only-update` | false | Rule 매칭 물품만 갱신 |
| `--auto-rules` | false | 분류 완료 후 auto_rule_builder 실행 |
| `--auto-rules-min-count` | 5 | 자동 규칙 추가 최소 물품 수 |
| `--auto-rules-confidence` | 0.85 | 자동 규칙 추가 최소 confidence |

**실행 단계**

```
STEP 1  ETL     : etl/load_unipass_to_mysql.py
STEP 2  분류    : classification/build_classification.py
STEP 3  자동규칙: classification/auto_rule_builder.py  (--auto-rules 시)
```

**출력 예시**

```
🚀 CAIS 파이프라인 시작  [2026-05-15 02:00:01]
   모드: full + OpenAI fallback
============================================================
▶  ETL — 유니패스 JSON → MySQL
   cmd: python etl/load_unipass_to_mysql.py
============================================================
✅ 성공  [12.3s]
...
  단계별 결과:
    ✅  ETL
    ✅  분류
    ✅  자동규칙
📄 리포트 저장 완료: classification/eval/accuracy_report.txt
```

---

### `scheduler.py`

`run_pipeline.py`를 매일 지정된 시각에 자동 실행합니다.  
`schedule` 라이브러리를 사용하며, 월별 로그 파일(`logs/scheduler_YYYYMM.log`)을 생성합니다.

**실행 방법**

```bash
pip install schedule

# 기본: 매일 02:00 실행
python pipeline/scheduler.py

# 시각 지정
python pipeline/scheduler.py --time 03:30

# OpenAI + 자동 규칙 포함
python pipeline/scheduler.py --use-openai --auto-rules

# 즉시 1회 실행 후 스케줄 유지 (테스트용)
python pipeline/scheduler.py --run-now --use-openai --auto-rules
```

**옵션 전체**

| 옵션 | 기본값 | 설명 |
|------|--------|------|
| `--time` | `02:00` | 매일 실행 시각 (KST, HH:MM) |
| `--use-openai` | false | OpenAI fallback 활성화 |
| `--openai-model` | `gpt-4o-mini` | 사용할 OpenAI 모델 |
| `--run-now` | false | 즉시 1회 실행 후 스케줄 대기 |
| `--auto-rules` | false | 파이프라인 완료 후 auto_rule_builder 실행 |
| `--auto-rules-min-count` | 5 | 자동 규칙 추가 최소 물품 수 |
| `--auto-rules-confidence` | 0.85 | 자동 규칙 추가 최소 confidence |

> **주의**: `--auto-rules`는 `OPENAI_API_KEY` 환경변수가 설정된 경우에만 실행됩니다.  
> 키가 없으면 해당 단계를 자동으로 건너뜁니다.

**환경변수 설정 (Windows PowerShell)**

```powershell
$env:DB_HOST="127.0.0.1"
$env:DB_USER="root"
$env:DB_PASSWORD="<비밀번호>"
$env:DB_NAME="customs_auction"
$env:OPENAI_API_KEY="<OpenAI API 키>"

python pipeline/scheduler.py --use-openai --auto-rules
```

---

## 전체 자동화 흐름

```
[매일 02:00]
scheduler.py
    │
    ├─ run_pipeline.py --mode full --use-openai
    │       │
    │       ├─ etl/load_unipass_to_mysql.py
    │       │       유니패스 JSON → MySQL auction_item UPSERT
    │       │
    │       └─ classification/build_classification.py --use-openai
    │               Rule 분류 → OpenAI fallback → DB 저장
    │               item_classification + item_search_token
    │
    └─ (--auto-rules 시) classification/auto_rule_builder.py
            fallback 물품 패턴 분석 → OpenAI 카테고리 제안
            → 조건 충족 시 rules.yaml 자동 추가
            → classification/eval/rule_suggestions.txt 출력
            → --rule-only-update 재분류 실행
```

## 로그

로그 파일 위치: `logs/scheduler_YYYYMM.log` (월별 롤링)

```
2026-05-15 02:00:01  INFO      파이프라인 시작 ─────────────────────────────
2026-05-15 02:00:14  INFO      파이프라인 완료 ✅  (13.2s)
2026-05-15 02:00:14  INFO      auto_rule_builder 시작 ─────────────────────────────
2026-05-15 02:00:21  INFO      auto_rule_builder 완료 ✅  (7.1s)
```

## GitHub Actions 연동

`.github/workflows/daily_pipeline.yml`에 GitHub Actions로도 실행 가능합니다.  
`classification_ci.yml`은 `classification/` 변경 시 `rules.yaml` 문법 검증을 수행합니다.
