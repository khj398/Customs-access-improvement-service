/*
models/auctionModel.js
공매 공고(auction) DB 모델
*/

const pool = require('../config/db');

// 공매 목록 조회 (필터: 세관, 카테고리, 키워드, 페이징)
exports.findAll = async ({ cstmSgn, keyword, page = 1, limit = 20 }) => {
  const offset = (page - 1) * limit;
  let where = 'WHERE 1=1';
  const params = [];

  if (cstmSgn) {
    where += ' AND a.cstm_sgn = ?';
    params.push(cstmSgn);
  }
  if (keyword) {
    where += ' AND EXISTS (SELECT 1 FROM auction_item ai WHERE ai.pbac_no = a.pbac_no AND ai.cmdt_nm LIKE ?)';
    params.push(`%${keyword}%`);
  }

  params.push(limit, offset);

  const [rows] = await pool.query(`
    SELECT
      a.pbac_no AS pbacNo, a.pbac_yy AS pbacYy, a.cstm_sgn AS cstmSgn, co.cstm_name AS cstmName,
      a.snar_sgn AS snarSgn, bw.snar_name AS snarName,
      a.pbac_strt_dttm AS pbacStrtDttm, a.pbac_end_dttm AS pbacEndDttm,
      a.bid_rstc_yn AS bidRstcYn, a.elct_bid_eon AS elctBidEon,
      COUNT(ai.cmdt_ln_no) AS itemCount
    FROM auction a
    LEFT JOIN customs_office co ON a.cstm_sgn = co.cstm_sgn
    LEFT JOIN bonded_warehouse bw ON a.snar_sgn = bw.snar_sgn
    LEFT JOIN auction_item ai ON a.pbac_no = ai.pbac_no
    ${where}
    GROUP BY a.pbac_no
    ORDER BY a.pbac_strt_dttm DESC
    LIMIT ? OFFSET ?
  `, params);
  return rows;
};

// 이번 주 신규 공매
exports.findNew = async (limit = 10) => {
  const [rows] = await pool.query(`
    SELECT
      a.pbac_no AS pbacNo, a.cstm_sgn AS cstmSgn, co.cstm_name AS cstmName,
      a.pbac_strt_dttm AS pbacStrtDttm, a.pbac_end_dttm AS pbacEndDttm,
      COUNT(ai.cmdt_ln_no) AS itemCount
    FROM auction a
    LEFT JOIN customs_office co ON a.cstm_sgn = co.cstm_sgn
    LEFT JOIN auction_item ai ON a.pbac_no = ai.pbac_no
    WHERE a.pbac_strt_dttm >= DATE_SUB(NOW(), INTERVAL 7 DAY)
    GROUP BY a.pbac_no
    ORDER BY a.pbac_strt_dttm DESC
    LIMIT ?
  `, [limit]);
  return rows;
};

// 세관 코드 기반 근처 공매
exports.findNearby = async (cstmSgn, limit = 10) => {
  const [rows] = await pool.query(`
    SELECT
      a.pbac_no AS pbacNo, a.cstm_sgn AS cstmSgn, co.cstm_name AS cstmName,
      a.snar_sgn AS snarSgn, bw.snar_name AS snarName,
      a.pbac_strt_dttm AS pbacStrtDttm, a.pbac_end_dttm AS pbacEndDttm,
      COUNT(ai.cmdt_ln_no) AS itemCount
    FROM auction a
    LEFT JOIN customs_office co ON a.cstm_sgn = co.cstm_sgn
    LEFT JOIN bonded_warehouse bw ON a.snar_sgn = bw.snar_sgn
    LEFT JOIN auction_item ai ON a.pbac_no = ai.pbac_no
    WHERE a.cstm_sgn = ?
      AND a.pbac_end_dttm >= NOW()
    GROUP BY a.pbac_no
    ORDER BY a.pbac_strt_dttm DESC
    LIMIT ?
  `, [cstmSgn, limit]);
  return rows;
};

// 공매 상세
exports.findByPbacNo = async (pbacNo) => {
  const [rows] = await pool.query(`
    SELECT
      a.pbac_no AS pbacNo, a.pbac_yy AS pbacYy, a.pbac_dgcnt AS pbacDgcnt, a.pbac_tncnt AS pbacTncnt,
      a.cstm_sgn AS cstmSgn, a.snar_sgn AS snarSgn, a.cargo_tpcd AS cargoTpcd,
      a.pbac_strt_dttm AS pbacStrtDttm, a.pbac_end_dttm AS pbacEndDttm,
      a.bid_rstc_yn AS bidRstcYn, a.elct_bid_eon AS elctBidEon,
      a.created_at AS createdAt, a.updated_at AS updatedAt,
      co.cstm_name AS cstmName,
      bw.snar_name AS snarName,
      ct.cargo_name AS cargoName
    FROM auction a
    LEFT JOIN customs_office co ON a.cstm_sgn = co.cstm_sgn
    LEFT JOIN bonded_warehouse bw ON a.snar_sgn = bw.snar_sgn
    LEFT JOIN cargo_type ct ON a.cargo_tpcd = ct.cargo_tpcd
    WHERE a.pbac_no = ?
  `, [pbacNo]);
  return rows[0];
};
