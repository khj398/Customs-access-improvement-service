# results/ — 실험 결과 보관 폴더

스크립트가 자동으로 채우는 폴더다. 여기 있는 파일이 논문 4장의 원자료가 된다.

## 생성되는 구조

```text
results/
├─ RUN_LOG.md              # 모든 실험 실행 이력 (자동 누적)
├─ PAPER_TABLES.md         # 논문 표 3~6 초안 (collect_results.py 생성)
├─ E01/
│  ├─ report.md            # 사람이 읽는 리포트 (표 + 판정 + 문장 초안)
│  └─ data.json            # 기계가 읽는 수치 (collect_results.py 입력)
├─ E03/
│  ├─ report.md
│  ├─ data.json
│  ├─ e03_counts.csv       # 질의별 LIKE/제안 결과 건수
│  └─ p5_judgement.csv     # ★ 2인이 O/X 를 채우는 판정지
├─ E05/
│  ├─ eval_label_blank.csv     # 블라인드 표본 100건 (배포용 원본)
│  ├─ category_reference.csv   # 정답 카테고리 경로 목록
│  ├─ labels/label_*.csv       # ★ 라벨러가 채우는 파일
│  ├─ ground_truth_v2.csv      # 라벨 + 자동 분류 병합 결과
│  └─ accuracy_report.txt      # evaluate.py 출력 원문
├─ E06/
│  ├─ usability_record.csv     # ★ 사용성 실험 기록지 (--init 로 생성)
│  └─ satisfaction.csv         # ★ 만족도 기록지
└─ ...
```

★ 표시가 사람이 직접 채우는 파일이다.

## 주의

- 이 폴더의 파일은 **스냅샷 고정 이후**에 생성된 것만 유효하다.
  실험 도중 ETL 을 재실행했다면 관련 결과를 모두 다시 뽑아야 한다
  (E02 커버리지와 E05 정확도는 같은 DB 상태에서 나와야 한다).
- 결과 파일에는 DB 비밀번호·API 키가 기록되지 않는다. 그래도 스크린샷을 논문에 넣을 때는
  터미널 프롬프트·환경변수가 함께 찍히지 않았는지 확인한다.
- `RUN_LOG.md` 는 append 방식이라 재실행 이력이 그대로 남는다. 논문에는 최종 실행분만 인용한다.
