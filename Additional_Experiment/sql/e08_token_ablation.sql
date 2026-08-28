-- =========================================================
-- E08. 토큰 유형별 기여도  [권장]  -> 논문 4.3절 본문
-- 실험계획서 6장 E8 의 SQL 원문 (수동 실행용, 질의 '와인' 예시)
-- 자동 실행(질의 20개 전체): python Additional_Experiment/scripts/e08_token_ablation.py
-- =========================================================

-- RAW만
SELECT COUNT(DISTINCT pbac_no, pbac_srno, cmdt_ln_no) FROM item_search_token
WHERE token LIKE '%와인%' AND token_type = 'RAW';

-- RAW + SYN
SELECT COUNT(DISTINCT pbac_no, pbac_srno, cmdt_ln_no) FROM item_search_token
WHERE token LIKE '%와인%' AND token_type IN ('RAW','SYN');

-- RAW + SYN + CATEGORY
SELECT COUNT(DISTINCT pbac_no, pbac_srno, cmdt_ln_no) FROM item_search_token
WHERE token LIKE '%와인%' AND token_type IN ('RAW','SYN','CATEGORY');

-- 참고: 스키마상 토큰 유형은 RAW / KO / SYN / CATEGORY 네 가지다.
--       자동 스크립트는 KO 를 포함한 4단계 누적으로 집계한다.
SELECT token_type, COUNT(*) AS 토큰수,
       COUNT(DISTINCT pbac_no, pbac_srno, cmdt_ln_no) AS 보유물품수
FROM item_search_token GROUP BY token_type;
