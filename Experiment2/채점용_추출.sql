-- ============================================================
-- 표본 100건에 대한 자동 분류 결과 추출 (채점 입력 생성)
-- 실행 환경: customs_auction DB (동료 PC 또는 본인 로컬)
-- 결과를 classification/eval/ground_truth_v2.csv 로 저장한 뒤 evaluate.py 실행
-- ============================================================

-- [1] 임시 테이블 생성
DROP TABLE IF EXISTS eval_label;
CREATE TABLE eval_label (
  no             INT,
  pbac_no        VARCHAR(20),
  pbac_srno      VARCHAR(20),
  cmdt_ln_no     VARCHAR(10),
  true_category_path VARCHAR(200),
  label_depth    INT,
  note           VARCHAR(500),
  PRIMARY KEY (pbac_no, pbac_srno, cmdt_ln_no)
) CHARACTER SET utf8mb4;

-- [2] label_sample_100_FINAL.csv 를 eval_label 로 적재
--     (MySQL Workbench의 Table Data Import Wizard 또는 아래 LOAD DATA)
--     ※ pbac_no 는 반드시 문자열로 적재할 것. 엑셀에서 열면 지수표기로 깨짐.
-- LOAD DATA LOCAL INFILE 'label_sample_100_FINAL.csv'
-- INTO TABLE eval_label
-- CHARACTER SET utf8mb4
-- FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
-- LINES TERMINATED BY '\n' IGNORE 1 LINES
-- (no, pbac_no, pbac_srno, cmdt_ln_no, @cargo, @nm, true_category_path, label_depth, note);

-- [3] 적재 검증 — 100 이 나와야 하고, 미매칭 0 이어야 함
SELECT COUNT(*) AS 적재건수 FROM eval_label;
SELECT COUNT(*) AS DB미존재
FROM eval_label l
LEFT JOIN auction_item ai USING (pbac_no, pbac_srno, cmdt_ln_no)
WHERE ai.pbac_no IS NULL;

-- [4] 채점 입력 추출  ★ 이 결과를 CSV로 저장 → ground_truth_v2.csv
SELECT l.no,
       l.pbac_no, l.pbac_srno, l.cmdt_ln_no,
       ai.cmdt_nm,
       CONCAT_WS(' > ', cg.name_ko, cp.name_ko, cl.name_ko) AS auto_category_path,
       ic.confidence  AS auto_confidence,
       ic.model_name  AS auto_model,
       l.true_category_path,
       l.label_depth,
       'PJY' AS labeler,
       l.note
FROM eval_label l
JOIN auction_item ai USING (pbac_no, pbac_srno, cmdt_ln_no)
LEFT JOIN item_classification ic USING (pbac_no, pbac_srno, cmdt_ln_no)
LEFT JOIN category cl ON cl.category_id = ic.category_id
LEFT JOIN category cp ON cp.category_id = cl.parent_id
LEFT JOIN category cg ON cg.category_id = cp.parent_id
ORDER BY l.no;

-- ============================================================
-- 채점 규칙 (논문 4.2절에 명시할 것)
--  라벨 깊이(label_depth)가 3 미만인 행은 그 깊이까지만 비교한다(접두 일치).
--   - depth 1 (전자·전기 / 산업·장비) : 3건 — 대분류만 비교
--   - depth 2 (가전 > 생활가전 등)    : 6건 — 중분류까지 비교
--   - depth 3                        : 91건 — 전체 경로 비교
-- ============================================================
