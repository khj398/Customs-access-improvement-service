-- 1) 공매 목록(기간 기준) 조회
SELECT
  a.pbac_no,
  a.pbac_strt_dttm,
  a.pbac_end_dttm,
  co.cstm_name,
  bw.snar_name,
  ct.cargo_name
FROM auction a
LEFT JOIN customs_office co ON a.cstm_sgn = co.cstm_sgn
LEFT JOIN bonded_warehouse bw ON a.snar_sgn = bw.snar_sgn
LEFT JOIN cargo_type ct ON a.cargo_tpcd = ct.cargo_tpcd
WHERE a.pbac_strt_dttm >= NOW()
ORDER BY a.pbac_strt_dttm ASC;
-- ======================================================================================

-- 2) 물품 검색(키워드)
--    ?는 백엔드에서 파라미터 바인딩
SELECT
  ai.pbac_no, ai.pbac_srno, ai.cmdt_ln_no,
  ai.cmdt_nm, ai.cmdt_wght, ai.cmdt_wght_ut_cd,
  ai.pbac_prng_prc,
  a.pbac_strt_dttm, a.pbac_end_dttm
FROM auction_item ai
JOIN auction a ON a.pbac_no = ai.pbac_no
WHERE ai.cmdt_nm LIKE CONCAT('%', ?, '%')
ORDER BY a.pbac_strt_dttm ASC;
-- ======================================================================================

-- 3) 가격 범위 필터
SELECT
  ai.pbac_no, ai.pbac_srno, ai.cmdt_ln_no,
  ai.cmdt_nm, ai.pbac_prng_prc
FROM auction_item ai
WHERE ai.pbac_prng_prc BETWEEN ? AND ?
ORDER BY ai.pbac_prng_prc ASC;
-- ======================================================================================

-- 4) 세관/창고별 필터
SELECT
  ai.pbac_no, ai.pbac_srno, ai.cmdt_ln_no,
  ai.cmdt_nm, co.cstm_name, bw.snar_name
FROM auction_item ai
JOIN auction a ON a.pbac_no = ai.pbac_no
LEFT JOIN customs_office co ON a.cstm_sgn = co.cstm_sgn
LEFT JOIN bonded_warehouse bw ON a.snar_sgn = bw.snar_sgn
WHERE co.cstm_name = ? OR bw.snar_name = ?
ORDER BY a.pbac_strt_dttm DESC;
-- ======================================================================================

-- 5) 공매 상세(공매번호로 물품 라인 전부)
SELECT
  ai.pbac_srno, ai.cmdt_ln_no,
  ai.cmdt_nm, ai.cmdt_qty, ai.cmdt_qty_ut_cd,
  ai.cmdt_wght, ai.cmdt_wght_ut_cd,
  ai.pbac_prng_prc, ai.atnt_cmdt
FROM auction_item ai
WHERE ai.pbac_no = ?
ORDER BY ai.pbac_srno ASC, ai.cmdt_ln_no ASC;
-- ======================================================================================

-- 6) “최근 갱신된 항목” (알림/동기화 핵심)
SELECT
  ai.pbac_no, ai.pbac_srno, ai.cmdt_ln_no,
  ai.cmdt_nm, ai.updated_at
FROM auction_item ai
WHERE ai.updated_at >= ?
ORDER BY ai.updated_at DESC;
-- ======================================================================================
