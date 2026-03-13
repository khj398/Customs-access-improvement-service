/* =========================================================
   feedback.sql
   - 자동 분류/검색 토큰 생성 결과 확인용 쿼리 모음
   - 목적: 동작 여부 확인 + fallback(미분류) 개선 포인트 찾기
   ========================================================= */

USE customs_auction;

-- =========================================================
-- 0) 실행 후 전체 상태 요약
-- =========================================================
SELECT COUNT(*) AS classification_rows FROM item_classification;
SELECT COUNT(*) AS token_rows FROM item_search_token;

-- 토큰 타입별 생성 현황 (RAW/SYN/CATEGORY)
SELECT token_type, COUNT(*) AS cnt
FROM item_search_token
GROUP BY token_type
ORDER BY cnt DESC;

-- 카테고리별 분류 건수 (상위 20)
SELECT c.name_ko AS category, COUNT(*) AS cnt
FROM item_classification ic
JOIN category c ON c.category_id = ic.category_id
GROUP BY c.name_ko
ORDER BY cnt DESC
LIMIT 20;

-- 분류 결과 샘플 (최근 갱신 30건)
SELECT
  ai.cmdt_nm,
  ic.model_name,
  ic.model_ver,
  ic.confidence,
  c.name_ko AS category_leaf,
  ic.rationale,
  ic.updated_at
FROM item_classification ic
JOIN auction_item ai
  ON ai.pbac_no=ic.pbac_no AND ai.pbac_srno=ic.pbac_srno AND ai.cmdt_ln_no=ic.cmdt_ln_no
JOIN category c ON c.category_id = ic.category_id
ORDER BY ic.updated_at DESC
LIMIT 30;

-- =========================================================
-- 0-1) 특정 토큰(예: 와인/술/주류/WINE) 검색 토큰 존재 여부
--      보기 좋게 정렬: cmdt_nm -> token_type(RAW,SYN,CATEGORY) -> token
-- =========================================================
SELECT ai.cmdt_nm, t.token, t.token_type
FROM item_search_token t
JOIN auction_item ai
  ON ai.pbac_no=t.pbac_no AND ai.pbac_srno=t.pbac_srno AND ai.cmdt_ln_no=t.cmdt_ln_no
WHERE t.token IN ('와인','술','주류','WINE')
ORDER BY ai.cmdt_nm, FIELD(t.token_type,'RAW','SYN','CATEGORY'), t.token;

-- =========================================================
-- 1) fallback(미분류) 분석
--    - 정확히: 기타 > 미분류 > 기타 로 떨어진 항목만 추출
-- =========================================================
SELECT
  ai.cmdt_nm,
  ic.confidence,
  ic.rationale,
  ic.updated_at
FROM item_classification ic
JOIN auction_item ai
  ON ai.pbac_no=ic.pbac_no AND ai.pbac_srno=ic.pbac_srno AND ai.cmdt_ln_no=ic.cmdt_ln_no
JOIN category c3 ON c3.category_id = ic.category_id          -- leaf
JOIN category c2 ON c2.category_id = c3.parent_id
JOIN category c1 ON c1.category_id = c2.parent_id
WHERE c1.name_ko='기타' AND c2.name_ko='미분류' AND c3.name_ko='기타'
ORDER BY ai.cmdt_nm;

-- =========================================================
-- 1-1) fallback 항목에서 자주 등장하는 RAW 토큰 TOP 20
--      -> 룰/사전(synonym_dictionary) 확장 우선순위로 사용
-- =========================================================
SELECT t.token, COUNT(*) AS cnt
FROM item_classification ic
JOIN item_search_token t
  ON t.pbac_no=ic.pbac_no AND t.pbac_srno=ic.pbac_srno AND t.cmdt_ln_no=ic.cmdt_ln_no
JOIN category c3 ON c3.category_id = ic.category_id
JOIN category c2 ON c2.category_id = c3.parent_id
JOIN category c1 ON c1.category_id = c2.parent_id
WHERE c1.name_ko='기타' AND c2.name_ko='미분류' AND c3.name_ko='기타'
  AND t.token_type='RAW'
GROUP BY t.token
ORDER BY cnt DESC
LIMIT 20;

-- =========================================================
-- 1-2) fallback인데 특정 RAW 토큰이 포함된 항목 찾기 (디버깅용)
--      예: GAUGE가 있는데도 fallback이면 룰 누락 가능성
-- =========================================================
-- 아래 토큰을 바꿔가며 확인해도 됨 (예: 'PUMP', 'VALVE', 'CABLE' 등)
SELECT ai.cmdt_nm
FROM item_classification ic
JOIN auction_item ai
  ON ai.pbac_no=ic.pbac_no AND ai.pbac_srno=ic.pbac_srno AND ai.cmdt_ln_no=ic.cmdt_ln_no
JOIN item_search_token t
  ON t.pbac_no=ic.pbac_no AND t.pbac_srno=ic.pbac_srno AND t.cmdt_ln_no=ic.cmdt_ln_no
JOIN category c3 ON c3.category_id = ic.category_id
JOIN category c2 ON c2.category_id = c3.parent_id
JOIN category c1 ON c1.category_id = c2.parent_id
WHERE c1.name_ko='기타' AND c2.name_ko='미분류' AND c3.name_ko='기타'
  AND t.token_type='RAW'
  AND t.token='GAUGE'
ORDER BY ai.cmdt_nm;

-- =========================================================
-- 2) synonym_dictionary(사전) 확인
-- =========================================================
SELECT term_type, COUNT(*) AS cnt
FROM synonym_dictionary
GROUP BY term_type
ORDER BY cnt DESC;

SELECT *
FROM synonym_dictionary
WHERE src_term IN ('WINE','GAUGE','BATTERY','PUMP','VALVE')
ORDER BY src_term, norm_term;

-- =========================================================
-- 3) 전체 물품 확인
-- =========================================================

-- =====================================================================================
-- [CHECK] 전체 물품(라인) 한 번에 보기 (현재 스키마 기준)
-- - auction에는 pbac_srno가 없으므로 pbac_no로만 JOIN
-- - 분류 + 카테고리 경로 토큰 + SYN 토큰 샘플까지 같이 확인
-- =====================================================================================

SELECT
  ai.pbac_no,
  ai.pbac_srno,
  ai.cmdt_ln_no,

  -- 공매 헤더(상위) : pbac_no 기준
  DATE_FORMAT(a.pbac_strt_dttm, '%Y-%m-%d %H:%i') AS pbac_start,
  DATE_FORMAT(a.pbac_end_dttm,  '%Y-%m-%d %H:%i') AS pbac_end,
  co.cstm_name AS customs_office,
  bw.snar_name AS bonded_warehouse,
  ct.cargo_name AS cargo_type,

  -- 물품(라인)
  ai.cmdt_nm,
  ai.cmdt_qty,
  ai.cmdt_qty_ut_cd,
  ai.cmdt_wght,
  ai.cmdt_wght_ut_cd,
  ai.pbac_prng_prc,

  -- 분류 결과
  c.name_ko AS category_leaf,
  ic.model_name,
  ic.confidence,
  ic.rationale,

  -- 카테고리 경로 토큰 (A안: token_type='CATEGORY' 이면서 ' > ' 포함)
  MAX(CASE
        WHEN t.token_type='CATEGORY' AND t.token LIKE '%>%' THEN t.token
      END) AS category_path_token,

  -- SYN 토큰 샘플(최대 15개만)
  SUBSTRING_INDEX(
    GROUP_CONCAT(DISTINCT CASE WHEN t.token_type='SYN' THEN t.token END
                 ORDER BY t.token SEPARATOR ', '),
    ', ',
    15
  ) AS syn_tokens_sample

FROM auction_item ai
JOIN auction a
  ON a.pbac_no = ai.pbac_no
LEFT JOIN customs_office co
  ON co.cstm_sgn = a.cstm_sgn
LEFT JOIN bonded_warehouse bw
  ON bw.snar_sgn = a.snar_sgn
LEFT JOIN cargo_type ct
  ON ct.cargo_tpcd = a.cargo_tpcd

LEFT JOIN item_classification ic
  ON ic.pbac_no=ai.pbac_no AND ic.pbac_srno=ai.pbac_srno AND ic.cmdt_ln_no=ai.cmdt_ln_no
LEFT JOIN category c
  ON c.category_id = ic.category_id
LEFT JOIN item_search_token t
  ON t.pbac_no=ai.pbac_no AND t.pbac_srno=ai.pbac_srno AND t.cmdt_ln_no=ai.cmdt_ln_no

GROUP BY
  ai.pbac_no, ai.pbac_srno, ai.cmdt_ln_no,
  a.pbac_strt_dttm, a.pbac_end_dttm,
  co.cstm_name, bw.snar_name, ct.cargo_name,
  ai.cmdt_nm, ai.cmdt_qty, ai.cmdt_qty_ut_cd, ai.cmdt_wght, ai.cmdt_wght_ut_cd, ai.pbac_prng_prc,
  c.name_ko, ic.model_name, ic.confidence, ic.rationale

ORDER BY
  ai.pbac_no, ai.pbac_srno, ai.cmdt_ln_no;
  
-- =====================================================================================

-- [CHECK] pbac_no당 pbac_srno 개수 (여러 srno가 붙는지 확인)
SELECT pbac_no, COUNT(DISTINCT pbac_srno) AS srno_cnt, COUNT(*) AS line_cnt
FROM auction_item
GROUP BY pbac_no
ORDER BY srno_cnt DESC, line_cnt DESC;

-- =====================================================================================

-- (A) pbac_no별 라인 수 / 시작~종료 / 기관까지 한 번에 보기(요약)
-- [CHECK] 공매(pbac_no) 요약: 라인수/기간/기관/보관처
SELECT
  a.pbac_no,
  COUNT(*) AS line_cnt,
  DATE_FORMAT(a.pbac_strt_dttm, '%Y-%m-%d %H:%i') AS pbac_start,
  DATE_FORMAT(a.pbac_end_dttm,  '%Y-%m-%d %H:%i') AS pbac_end,
  co.cstm_name AS customs_office,
  bw.snar_name AS bonded_warehouse,
  ct.cargo_name AS cargo_type
FROM auction a
JOIN auction_item ai
  ON ai.pbac_no=a.pbac_no
LEFT JOIN customs_office co ON co.cstm_sgn=a.cstm_sgn
LEFT JOIN bonded_warehouse bw ON bw.snar_sgn=a.snar_sgn
LEFT JOIN cargo_type ct ON ct.cargo_tpcd=a.cargo_tpcd
GROUP BY a.pbac_no, a.pbac_strt_dttm, a.pbac_end_dttm, co.cstm_name, bw.snar_name, ct.cargo_name
ORDER BY line_cnt DESC, a.pbac_no;

-- =====================================================================================

-- (B) 전체 라인 상세: 물품 + 분류 + 경로 토큰 + SYN 샘플(상세)
-- [CHECK] 전체 물품(라인) 상세: 물품 + 분류 + 경로토큰 + SYN 토큰 샘플
SELECT
  ai.pbac_no,
  ai.pbac_srno,
  ai.cmdt_ln_no,

  DATE_FORMAT(a.pbac_strt_dttm, '%Y-%m-%d %H:%i') AS pbac_start,
  DATE_FORMAT(a.pbac_end_dttm,  '%Y-%m-%d %H:%i') AS pbac_end,
  co.cstm_name AS customs_office,
  bw.snar_name AS bonded_warehouse,
  ct.cargo_name AS cargo_type,

  ai.cmdt_nm,
  ai.cmdt_qty,
  ai.cmdt_qty_ut_cd,
  ai.cmdt_wght,
  ai.cmdt_wght_ut_cd,
  ai.pbac_prng_prc,

  c.name_ko AS category_leaf,
  ic.model_name,
  ic.confidence,
  ic.rationale,

  -- A안: token_type='CATEGORY' 안에 경로 토큰이 섞여있고(' > ' 포함), 이걸 대표로 보여줌
  MAX(CASE
        WHEN t.token_type='CATEGORY' AND t.token LIKE '%>%' THEN t.token
      END) AS category_path_token,

  SUBSTRING_INDEX(
    GROUP_CONCAT(DISTINCT CASE WHEN t.token_type='SYN' THEN t.token END
                 ORDER BY t.token SEPARATOR ', '),
    ', ',
    15
  ) AS syn_tokens_sample

FROM auction_item ai
JOIN auction a
  ON a.pbac_no = ai.pbac_no
LEFT JOIN customs_office co
  ON co.cstm_sgn = a.cstm_sgn
LEFT JOIN bonded_warehouse bw
  ON bw.snar_sgn = a.snar_sgn
LEFT JOIN cargo_type ct
  ON ct.cargo_tpcd = a.cargo_tpcd
LEFT JOIN item_classification ic
  ON ic.pbac_no=ai.pbac_no AND ic.pbac_srno=ai.pbac_srno AND ic.cmdt_ln_no=ai.cmdt_ln_no
LEFT JOIN category c
  ON c.category_id = ic.category_id
LEFT JOIN item_search_token t
  ON t.pbac_no=ai.pbac_no AND t.pbac_srno=ai.pbac_srno AND t.cmdt_ln_no=ai.cmdt_ln_no

GROUP BY
  ai.pbac_no, ai.pbac_srno, ai.cmdt_ln_no,
  a.pbac_strt_dttm, a.pbac_end_dttm,
  co.cstm_name, bw.snar_name, ct.cargo_name,
  ai.cmdt_nm, ai.cmdt_qty, ai.cmdt_qty_ut_cd, ai.cmdt_wght, ai.cmdt_wght_ut_cd, ai.pbac_prng_prc,
  c.name_ko, ic.model_name, ic.confidence, ic.rationale

ORDER BY
  ai.pbac_no, ai.cmdt_ln_no;

-- =====================================================================================


-- =====================================================================================
-- 4) 검토용 VIEW (처음 1회 생성 후, SELECT만 반복)
--    - DB/ERD에 익숙하지 않아도 한 화면으로 보기 쉽게 구성
-- =====================================================================================
DROP VIEW IF EXISTS vw_item_classification_review;

CREATE VIEW vw_item_classification_review AS
SELECT
  ai.pbac_no,
  ai.pbac_srno,
  ai.cmdt_ln_no,
  ai.cmdt_nm,
  ic.model_name,
  ic.model_ver,
  ic.confidence,
  ic.rationale,
  c1.name_ko AS category_lv1,
  c2.name_ko AS category_lv2,
  c3.name_ko AS category_leaf,
  MAX(CASE WHEN t.token_type='CATEGORY' AND t.token LIKE '%>%' THEN t.token END) AS category_path_token,
  SUBSTRING_INDEX(
    GROUP_CONCAT(DISTINCT CASE WHEN t.token_type='SYN' THEN t.token END ORDER BY t.token SEPARATOR ', '),
    ', ',
    20
  ) AS syn_tokens_sample,
  ic.updated_at
FROM auction_item ai
LEFT JOIN item_classification ic
  ON ic.pbac_no=ai.pbac_no AND ic.pbac_srno=ai.pbac_srno AND ic.cmdt_ln_no=ai.cmdt_ln_no
LEFT JOIN category c3 ON c3.category_id = ic.category_id
LEFT JOIN category c2 ON c2.category_id = c3.parent_id
LEFT JOIN category c1 ON c1.category_id = c2.parent_id
LEFT JOIN item_search_token t
  ON t.pbac_no=ai.pbac_no AND t.pbac_srno=ai.pbac_srno AND t.cmdt_ln_no=ai.cmdt_ln_no
GROUP BY
  ai.pbac_no, ai.pbac_srno, ai.cmdt_ln_no, ai.cmdt_nm,
  ic.model_name, ic.model_ver, ic.confidence, ic.rationale,
  c1.name_ko, c2.name_ko, c3.name_ko, ic.updated_at;

-- VIEW 사용 예시 1) 전체를 최신순으로 검토
SELECT *
FROM vw_item_classification_review
ORDER BY updated_at DESC, pbac_no, pbac_srno, cmdt_ln_no;

-- VIEW 사용 예시 2) fallback만 보기
SELECT *
FROM vw_item_classification_review
WHERE category_lv1='기타' AND category_lv2='미분류' AND category_leaf='기타'
ORDER BY pbac_no, pbac_srno, cmdt_ln_no;

-- VIEW 사용 예시 3) OpenAI 분류만 보기
SELECT *
FROM vw_item_classification_review
WHERE model_name='openai'
ORDER BY updated_at DESC;

-- 추가로 “진짜 빠른 최종 sanity check” 3줄
-- 분류 누락(0이면 정상)
SELECT COUNT(*) AS missing_class
FROM auction_item ai
LEFT JOIN item_classification ic
  ON ic.pbac_no=ai.pbac_no AND ic.pbac_srno=ai.pbac_srno AND ic.cmdt_ln_no=ai.cmdt_ln_no
WHERE ic.pbac_no IS NULL;

-- 토큰 누락(0이면 정상)
SELECT COUNT(*) AS missing_tokens
FROM auction_item ai
LEFT JOIN item_search_token t
  ON t.pbac_no=ai.pbac_no AND t.pbac_srno=ai.pbac_srno AND t.cmdt_ln_no=ai.cmdt_ln_no
WHERE t.pbac_no IS NULL;

-- '기타/미분류' 개별 CATEGORY 토큰 남아있나(0이면 정상)
SELECT COUNT(*) AS bad_category_tokens
FROM item_search_token
WHERE token_type='CATEGORY' AND token IN ('기타','미분류');



