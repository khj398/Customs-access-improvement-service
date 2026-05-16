/*
models/likeModel.js
찜(likes) DB 모델 — customs_auction.user_watchlist_target 테이블 사용
  target_level = 'ITEM' 인 행만 찜으로 취급한다.
*/

const pool = require('../config/db');

exports.findMyLikes = async (userId) => {
  const [rows] = await pool.query(`
    SELECT
      wt.watch_target_id AS likeId,
      wt.pbac_no    AS pbacNo,
      wt.pbac_srno  AS pbacSrno,
      wt.cmdt_ln_no AS cmdtLnNo,
      wt.created_at AS createdAt,
      ai.cmdt_nm         AS cmdtNm,
      ai.pbac_prng_prc   AS pbacPrngPrc,
      ai.atnt_cmdt_nm    AS atntCmdtNm,
      a.pbac_strt_dttm   AS pbacStrtDttm,
      a.pbac_end_dttm    AS pbacEndDttm,
      co.cstm_name       AS cstmName,
      ic.category_id     AS categoryId,
      c.name_ko          AS categoryName
    FROM user_watchlist_target wt
    JOIN auction_item ai
      ON wt.pbac_no = ai.pbac_no AND wt.pbac_srno = ai.pbac_srno AND wt.cmdt_ln_no = ai.cmdt_ln_no
    JOIN auction a ON wt.pbac_no = a.pbac_no
    LEFT JOIN customs_office co ON a.cstm_sgn = co.cstm_sgn
    LEFT JOIN item_classification ic
      ON ic.pbac_no = wt.pbac_no AND ic.pbac_srno = wt.pbac_srno AND ic.cmdt_ln_no = wt.cmdt_ln_no
    LEFT JOIN category c ON ic.category_id = c.category_id
    WHERE wt.user_id = ? AND wt.target_level = 'ITEM'
    ORDER BY wt.created_at DESC
  `, [userId]);
  return rows;
};

exports.findMyLikeKeys = async (userId) => {
  const [rows] = await pool.query(`
    SELECT pbac_no AS pbacNo, pbac_srno AS pbacSrno, cmdt_ln_no AS cmdtLnNo
    FROM user_watchlist_target
    WHERE user_id = ? AND target_level = 'ITEM'
  `, [userId]);
  return rows;
};

exports.exists = async (userId, pbacNo, pbacSrno, cmdtLnNo) => {
  const [rows] = await pool.query(`
    SELECT watch_target_id AS likeId
    FROM user_watchlist_target
    WHERE user_id = ? AND target_level = 'ITEM'
      AND pbac_no = ? AND pbac_srno = ? AND cmdt_ln_no = ?
  `, [userId, pbacNo, pbacSrno, cmdtLnNo]);
  return rows[0];
};

exports.add = async (userId, pbacNo, pbacSrno, cmdtLnNo) => {
  const [result] = await pool.query(`
    INSERT INTO user_watchlist_target
      (user_id, target_level, pbac_no, pbac_srno, cmdt_ln_no)
    VALUES (?, 'ITEM', ?, ?, ?)
  `, [userId, pbacNo, pbacSrno, cmdtLnNo]);
  return result.insertId;
};

exports.remove = async (userId, pbacNo, pbacSrno, cmdtLnNo) => {
  await pool.query(`
    DELETE FROM user_watchlist_target
    WHERE user_id = ? AND target_level = 'ITEM'
      AND pbac_no = ? AND pbac_srno = ? AND cmdt_ln_no = ?
  `, [userId, pbacNo, pbacSrno, cmdtLnNo]);
};

exports.count = async (pbacNo, pbacSrno, cmdtLnNo) => {
  const [rows] = await pool.query(`
    SELECT COUNT(*) AS cnt
    FROM user_watchlist_target
    WHERE target_level = 'ITEM'
      AND pbac_no = ? AND pbac_srno = ? AND cmdt_ln_no = ?
  `, [pbacNo, pbacSrno, cmdtLnNo]);
  return rows[0].cnt;
};
