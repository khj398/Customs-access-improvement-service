-- =========================================================
-- E01. 데이터셋 기초 통계  [필수]  -> 논문 4.1절 표 3
-- 실험계획서 6장 E1 의 SQL 원문 (수동 실행용)
-- 자동 실행: python Additional_Experiment/scripts/e01_dataset_stats.py
-- =========================================================

-- (1) 전체 규모
SELECT (SELECT COUNT(*) FROM auction)             AS 공매수,
       (SELECT COUNT(*) FROM auction_item)        AS 물품수,
       (SELECT COUNT(*) FROM customs_office)      AS 세관수,
       (SELECT COUNT(*) FROM auction_item_image)  AS 이미지수;

-- (2) 물품명 언어 구성  <- 서론의 핵심 근거
SELECT SUM(cmdt_nm REGEXP '[가-힣]')      AS 한글포함,
       SUM(NOT (cmdt_nm REGEXP '[가-힣]')) AS 영문전용,
       ROUND(AVG(CHAR_LENGTH(cmdt_nm)),1)  AS 평균길이,
       MAX(CHAR_LENGTH(cmdt_nm))           AS 최대길이
FROM auction_item;

-- (2b) 수집 출처별 한글 포함 비율  <- E1 판정 기준
SELECT COALESCE(a.collector_source,'(미상)')   AS 수집출처,
       COUNT(*)                                AS 물품수,
       SUM(ai.cmdt_nm REGEXP '[가-힣]')        AS 한글포함,
       ROUND(SUM(ai.cmdt_nm REGEXP '[가-힣]') / COUNT(*) * 100, 1) AS 한글포함률
FROM auction a
JOIN auction_item ai ON ai.pbac_no = a.pbac_no
GROUP BY a.collector_source;

-- (3) 수집 출처별 분포 (수입화물 vs 휴대품)
SELECT a.collector_source, COUNT(ai.cmdt_ln_no) AS 물품수
FROM auction a JOIN auction_item ai ON a.pbac_no = ai.pbac_no
GROUP BY a.collector_source;

-- (4) 공매당 물품 라인 수 (복합 PK 설계의 근거)
SELECT ROUND(AVG(cnt),2) AS 평균라인수, MAX(cnt) AS 최대라인수
FROM (SELECT pbac_no, COUNT(*) cnt FROM auction_item GROUP BY pbac_no) t;

-- (5) 예정가 분포
SELECT MIN(pbac_prng_prc), MAX(pbac_prng_prc), ROUND(AVG(pbac_prng_prc)) FROM auction_item;

-- (6) 수집 기준일 (논문 4.1절에 명시)
SELECT MIN(pbac_strt_dttm) AS 최초공매시작,
       MAX(pbac_end_dttm)  AS 최종공매종료,
       MAX(updated_at)     AS DB최종갱신
FROM auction;
