/*
models/bidModel.js
입찰(bid) DB 모델
*/

const pool = require('../config/db');

// 내 입찰 목록 조회
exports.findMyBids = async (userId, status) => {
  let statusWhere = '';
  if (status === 'bidding')  statusWhere = "AND b.status = 'BIDDING'";
  else if (status === 'won') statusWhere = "AND b.status = 'WON'";
  else if (status === 'expired') statusWhere = "AND b.status IN ('EXPIRED', 'LOST')";

  const [rows] = await pool.query(`
    SELECT
      b.bidId, b.pbacNo, b.pbacSrno, b.cmdtLnNo,
      b.bidAmount, b.status, b.createdAt,
      ai.cmdt_nm AS cmdtNm, ai.pbac_prng_prc AS pbacPrngPrc,
      a.pbac_strt_dttm AS pbacStrtDttm, a.pbac_end_dttm AS pbacEndDttm,
      co.cstm_name AS cstmName,
      (SELECT MAX(bidAmount) FROM bid WHERE pbacNo = b.pbacNo AND pbacSrno = b.pbacSrno AND cmdtLnNo = b.cmdtLnNo) AS currentTopBid
    FROM bid b
    JOIN auction_item ai ON b.pbacNo = ai.pbac_no AND b.pbacSrno = ai.pbac_srno AND b.cmdtLnNo = ai.cmdt_ln_no
    JOIN auction a ON b.pbacNo = a.pbac_no
    LEFT JOIN customs_office co ON a.cstm_sgn = co.cstm_sgn
    WHERE b.userId = ? ${statusWhere}
    ORDER BY b.createdAt DESC
  `, [userId]);
  return rows;
};

// 특정 물품 최고 입찰가
exports.getTopBid = async (pbacNo, pbacSrno, cmdtLnNo) => {
  const [rows] = await pool.query(`
    SELECT MAX(bidAmount) AS topBid, COUNT(*) AS bidCount
    FROM bid
    WHERE pbacNo = ? AND pbacSrno = ? AND cmdtLnNo = ?
  `, [pbacNo, pbacSrno, cmdtLnNo]);
  return rows[0];
};

// 입찰 생성
exports.create = async (userId, pbacNo, pbacSrno, cmdtLnNo, bidAmount) => {
  const [result] = await pool.query(`
    INSERT INTO bid (userId, pbacNo, pbacSrno, cmdtLnNo, bidAmount, status)
    VALUES (?, ?, ?, ?, ?, 'BIDDING')
  `, [userId, pbacNo, pbacSrno, cmdtLnNo, bidAmount]);
  return result.insertId;
};

// 기존 입찰 조회 (중복 방지)
exports.findUserBid = async (userId, pbacNo, pbacSrno, cmdtLnNo) => {
  const [rows] = await pool.query(`
    SELECT * FROM bid
    WHERE userId = ? AND pbacNo = ? AND pbacSrno = ? AND cmdtLnNo = ?
    ORDER BY createdAt DESC LIMIT 1
  `, [userId, pbacNo, pbacSrno, cmdtLnNo]);
  return rows[0];
};

// 입찰 취소
exports.cancel = async (bidId, userId) => {
  const [result] = await pool.query(`
    UPDATE bid SET status = 'CANCELLED'
    WHERE bidId = ? AND userId = ? AND status = 'BIDDING'
  `, [bidId, userId]);
  return result.affectedRows > 0;
};

// 달력용 - 날짜별 입찰 현황
exports.findCalendarData = async (userId, year, month) => {
  const [rows] = await pool.query(`
    SELECT
      DATE_FORMAT(b.createdAt, '%Y-%m-%d') AS date,
      b.status,
      COUNT(*) AS cnt
    FROM bid b
    WHERE b.userId = ?
      AND YEAR(b.createdAt) = ?
      AND MONTH(b.createdAt) = ?
    GROUP BY date, b.status
    ORDER BY date
  `, [userId, year, month]);
  return rows;
};
