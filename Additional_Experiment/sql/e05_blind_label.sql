-- =========================================================
-- E05. 분류 정확도 블라인드 재평가  [필수]  -> 논문 4.2절 표 4 하단
-- 실험계획서 6장 E5 의 SQL 원문 (수동 실행용)
-- 자동 실행: e05a_sample_blind.py -> 라벨링 -> e05b_merge_and_evaluate.py
-- =========================================================

-- (1) 표본 추출 (재현성을 위해 RAND(42) 로 시드 고정)
--     ★ 자동 분류 결과 컬럼을 넣지 않는 것이 핵심이다.
SELECT ai.pbac_no, ai.pbac_srno, ai.cmdt_ln_no, ai.cmdt_nm,
       '' AS true_category_path, '' AS labeler, '' AS note
FROM auction_item ai
ORDER BY RAND(42) LIMIT 100;
-- 결과를 eval_label_blank.csv 로 내보낸다.

-- (2) 라벨링 참고용 카테고리 경로 목록
SELECT c3.category_id,
       CONCAT_WS(' > ', c1.name_ko, c2.name_ko, c3.name_ko) AS category_path
FROM category c3
JOIN category c2 ON c2.category_id = c3.parent_id
JOIN category c1 ON c1.category_id = c2.parent_id
WHERE c3.level = 3 AND c3.is_active = 1
ORDER BY category_path;

-- (3) 라벨 완료 후 자동 분류 결과 병합
--     eval_label(pbac_no, pbac_srno, cmdt_ln_no, true_category_path, labeler) 임시 테이블 적재 후 실행
SELECT l.pbac_no, l.pbac_srno, l.cmdt_ln_no, ai.cmdt_nm,
       CONCAT_WS(' > ', cg.name_ko, cp.name_ko, cl.name_ko) AS auto_category_path,
       ic.confidence AS auto_confidence,
       ic.model_name AS auto_model,
       l.true_category_path, l.labeler, '' AS note
FROM eval_label l
JOIN auction_item ai USING (pbac_no, pbac_srno, cmdt_ln_no)
LEFT JOIN item_classification ic USING (pbac_no, pbac_srno, cmdt_ln_no)
LEFT JOIN category cl ON cl.category_id = ic.category_id
LEFT JOIN category cp ON cp.category_id = cl.parent_id
LEFT JOIN category cg ON cg.category_id = cp.parent_id;
-- 결과를 ground_truth_v2.csv 로 저장한 뒤:
--   python classification/eval/evaluate.py --gt <경로>

-- 라벨링 규칙 (반드시 지킬 것)
--  1. 자동 분류 결과를 보지 않은 상태에서 물품명만 보고 정답 카테고리를 부여한다.
--  2. 애매한 건은 비워두지 말고 반드시 「기타 > 미분류 > 기타」를 정답으로 명시한다.
--     -> 이것이 기존 평가(100%)의 선택 편향을 없애는 핵심 규칙이다.
--  3. 3인이 분담하되 일부 문항은 공통으로 라벨링해 라벨러 간 일치도를 계산한다.
