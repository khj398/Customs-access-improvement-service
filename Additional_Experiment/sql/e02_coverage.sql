-- =========================================================
-- E02. 자동 분류 커버리지  [필수]  -> 논문 4.2절 표 4 상단
-- 실험계획서 6장 E2 의 SQL 원문 (수동 실행용)
-- 자동 실행: python Additional_Experiment/scripts/e02_classification_coverage.py
-- 주의: 모두 SELECT 이며 DB를 변경하지 않는다.
-- =========================================================

-- (1) 모델별 분류 건수 및 평균 신뢰도
SELECT model_name, COUNT(*) AS 건수, ROUND(AVG(confidence),3) AS 평균신뢰도
FROM item_classification GROUP BY model_name;

-- (2) 신뢰도 구간 분포
SELECT CASE WHEN confidence >= 0.90 THEN '0.90 이상'
            WHEN confidence >= 0.70 THEN '0.70~0.89'
            ELSE '0.70 미만' END AS 구간,
       COUNT(*) AS 건수
FROM item_classification GROUP BY 구간 ORDER BY 구간 DESC;

-- (3) 미분류(기타) 목록  ※ python check_misc.py 로도 확인 가능
SELECT ai.cmdt_nm, ic.model_name, ic.confidence
FROM item_classification ic
JOIN auction_item ai USING (pbac_no, pbac_srno, cmdt_ln_no)
JOIN category c ON c.category_id = ic.category_id
WHERE c.name_ko IN ('미분류','기타')
ORDER BY ai.cmdt_nm;

-- (4) 대분류별 물품 분포 (12개 대분류 커버 여부)
SELECT c1.name_ko AS 대분류, COUNT(*) AS 물품수
FROM item_classification ic
JOIN category cl ON cl.category_id = ic.category_id
LEFT JOIN category cp ON cp.category_id = cl.parent_id
LEFT JOIN category cg ON cg.category_id = cp.parent_id
JOIN category c1 ON c1.category_id = COALESCE(cg.category_id, cp.category_id, cl.category_id)
GROUP BY c1.name_ko ORDER BY 물품수 DESC;
