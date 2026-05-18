/*
models/itemModel.js
공매 물품(auction_item) DB 모델
*/

const pool = require('../config/db');

// 물품 검색 (item_search_token 활용)
exports.search = async ({ keyword, categoryId, cstmSgn, page = 1, limit = 20, userId = null }) => {
  const offset = (page - 1) * limit;

  const likesJoin = userId
    ? `LEFT JOIN user_watchlist_target l
         ON l.user_id = ? AND l.target_level = 'ITEM'
        AND l.pbac_no = ai.pbac_no AND l.pbac_srno = ai.pbac_srno AND l.cmdt_ln_no = ai.cmdt_ln_no`
    : '';
  const isFavoriteCol = userId
    ? `CASE WHEN l.watch_target_id IS NOT NULL THEN 1 ELSE 0 END AS isFavorite`
    : `0 AS isFavorite`;
  const joinParams = userId ? [userId] : [];

  // ── WHERE 조건 ───────────────────────────────────────────────
  let where = 'WHERE 1=1';
  const whereParams = [];

  if (keyword) {
    where += ` AND EXISTS (
      SELECT 1 FROM item_search_token ist
      WHERE ist.pbac_no = ai.pbac_no
        AND ist.pbac_srno = ai.pbac_srno
        AND ist.cmdt_ln_no = ai.cmdt_ln_no
        AND ist.token LIKE ?
    )`;
    whereParams.push(`%${keyword.toUpperCase()}%`);
  }

  if (categoryId) {
    // 선택 카테고리 + 직접 하위(L2) + 손자 하위(L3) 모두 포함
    const [catRows] = await pool.query(`
      SELECT category_id FROM category
      WHERE category_id = ?
         OR parent_id = ?
         OR parent_id IN (SELECT category_id FROM category WHERE parent_id = ?)
    `, [categoryId, categoryId, categoryId]);

    const catIds = catRows.map(r => r.category_id);

    if (catIds.length > 0) {
      where += ` AND EXISTS (
        SELECT 1 FROM item_classification ic2
        WHERE ic2.pbac_no = ai.pbac_no
          AND ic2.pbac_srno = ai.pbac_srno
          AND ic2.cmdt_ln_no = ai.cmdt_ln_no
          AND ic2.category_id IN (${catIds.map(() => '?').join(',')})
      )`;
      whereParams.push(...catIds);
    }
  }

  if (cstmSgn) {
    where += ' AND a.cstm_sgn = ?';
    whereParams.push(cstmSgn);
  }

  const allParams = [...joinParams, ...whereParams, limit, offset];

  const [rows] = await pool.query(`
    SELECT
      ai.pbac_no AS pbacNo, ai.pbac_srno AS pbacSrno, ai.cmdt_ln_no AS cmdtLnNo,
      ai.cmdt_nm AS cmdtNm, ai.cmdt_qty AS cmdtQty, ai.cmdt_qty_ut_cd AS cmdtQtyUtCd,
      ai.cmdt_wght AS cmdtWght, ai.cmdt_wght_ut_cd AS cmdtWghtUtCd,
      ai.pbac_prng_prc AS pbacPrngPrc, ai.atnt_cmdt AS atntCmdt, ai.atnt_cmdt_nm AS atntCmdtNm,
      ai.pbac_cond_cn AS pbacCondCn,
      a.pbac_strt_dttm AS pbacStrtDttm, a.pbac_end_dttm AS pbacEndDttm,
      a.cstm_sgn AS cstmSgn, co.cstm_name AS cstmName,
      ic.category_id AS categoryId, c.name_ko AS categoryName,
      ${isFavoriteCol},
      (
        SELECT GROUP_CONCAT(aii.image_url ORDER BY aii.image_seq SEPARATOR '|')
        FROM auction_item_image aii
        WHERE aii.pbac_no = ai.pbac_no AND aii.pbac_srno = ai.pbac_srno AND aii.cmdt_ln_no = ai.cmdt_ln_no
      ) AS imageUrls
    FROM auction_item ai
    JOIN auction a ON ai.pbac_no = a.pbac_no
    LEFT JOIN customs_office co ON a.cstm_sgn = co.cstm_sgn
    LEFT JOIN item_classification ic ON ic.pbac_no = ai.pbac_no AND ic.pbac_srno = ai.pbac_srno AND ic.cmdt_ln_no = ai.cmdt_ln_no
    LEFT JOIN category c ON ic.category_id = c.category_id
    ${likesJoin}
    ${where}
    ORDER BY a.pbac_strt_dttm DESC
    LIMIT ? OFFSET ?
  `, allParams);
  return rows;
};

// 물품 상세
exports.findOne = async (pbacNo, pbacSrno, cmdtLnNo) => {
  const [rows] = await pool.query(`
    SELECT
      ai.pbac_no AS pbacNo, ai.pbac_srno AS pbacSrno, ai.cmdt_ln_no AS cmdtLnNo,
      ai.cmdt_nm AS cmdtNm, ai.cmdt_qty AS cmdtQty, ai.cmdt_qty_ut_cd AS cmdtQtyUtCd,
      ai.cmdt_wght AS cmdtWght, ai.cmdt_wght_ut_cd AS cmdtWghtUtCd,
      ai.pbac_prng_prc AS pbacPrngPrc, ai.atnt_cmdt AS atntCmdt, ai.atnt_cmdt_nm AS atntCmdtNm,
      ai.pbac_cond_cn AS pbacCondCn, ai.created_at AS createdAt, ai.updated_at AS updatedAt,
      a.pbac_strt_dttm AS pbacStrtDttm, a.pbac_end_dttm AS pbacEndDttm,
      a.bid_rstc_yn AS bidRstcYn, a.elct_bid_eon AS elctBidEon,
      a.cstm_sgn AS cstmSgn, co.cstm_name AS cstmName,
      a.snar_sgn AS snarSgn, bw.snar_name AS snarName,
      ic.category_id AS categoryId, c.name_ko AS categoryName,
      (
        SELECT GROUP_CONCAT(aii.image_url ORDER BY aii.image_seq SEPARATOR '|')
        FROM auction_item_image aii
        WHERE aii.pbac_no = ai.pbac_no AND aii.pbac_srno = ai.pbac_srno AND aii.cmdt_ln_no = ai.cmdt_ln_no
      ) AS imageUrls
    FROM auction_item ai
    JOIN auction a ON ai.pbac_no = a.pbac_no
    LEFT JOIN customs_office co ON a.cstm_sgn = co.cstm_sgn
    LEFT JOIN bonded_warehouse bw ON a.snar_sgn = bw.snar_sgn
    LEFT JOIN item_classification ic
      ON ic.pbac_no = ai.pbac_no AND ic.pbac_srno = ai.pbac_srno AND ic.cmdt_ln_no = ai.cmdt_ln_no
    LEFT JOIN category c ON ic.category_id = c.category_id
    WHERE ai.pbac_no = ? AND ai.pbac_srno = ? AND ai.cmdt_ln_no = ?
  `, [pbacNo, pbacSrno, cmdtLnNo]);
  return rows[0];
};

// 달력용 — 특정 연월에 공매가 마감되는 물품 전체 (최대 500건)
// isFavorite: 로그인 사용자의 찜 여부 (미로그인 시 0)
exports.findByMonth = async (year, month, userId = null) => {
  const likeJoin = userId
    ? `LEFT JOIN app_user.user_watchlist_target wt
         ON wt.user_id = ? AND wt.target_level = 'ITEM'
        AND wt.pbac_no = ai.pbac_no AND wt.pbac_srno = ai.pbac_srno AND wt.cmdt_ln_no = ai.cmdt_ln_no`
    : '';
  const isFavoriteCol = userId
    ? `CASE WHEN wt.watch_target_id IS NOT NULL THEN 1 ELSE 0 END AS isFavorite`
    : `0 AS isFavorite`;
  const params = userId ? [userId, year, month] : [year, month];

  const [rows] = await pool.query(`
    SELECT
      DATE_FORMAT(a.pbac_end_dttm, '%Y-%m-%d') AS date,
      ai.pbac_no    AS pbacNo,
      ai.pbac_srno  AS pbacSrno,
      ai.cmdt_ln_no AS cmdtLnNo,
      ai.cmdt_nm    AS cmdtNm,
      ai.pbac_prng_prc AS pbacPrngPrc,
      a.pbac_end_dttm  AS pbacEndDttm,
      a.cstm_sgn       AS cstmSgn,
      co.cstm_name     AS cstmName,
      ic.category_id   AS categoryId,
      c.name_ko        AS categoryName,
      ${isFavoriteCol},
      (
        SELECT GROUP_CONCAT(aii.image_url ORDER BY aii.image_seq SEPARATOR '|')
        FROM auction_item_image aii
        WHERE aii.pbac_no = ai.pbac_no AND aii.pbac_srno = ai.pbac_srno AND aii.cmdt_ln_no = ai.cmdt_ln_no
      ) AS imageUrls
    FROM auction_item ai
    JOIN auction a ON ai.pbac_no = a.pbac_no
    LEFT JOIN customs_office co ON a.cstm_sgn = co.cstm_sgn
    LEFT JOIN item_classification ic
      ON ic.pbac_no = ai.pbac_no AND ic.pbac_srno = ai.pbac_srno AND ic.cmdt_ln_no = ai.cmdt_ln_no
    LEFT JOIN category c ON ic.category_id = c.category_id
    ${likeJoin}
    WHERE YEAR(a.pbac_end_dttm) = ? AND MONTH(a.pbac_end_dttm) = ?
    ORDER BY a.pbac_end_dttm, ai.pbac_no
    LIMIT 500
  `, params);
  return rows;
};

// 공매에 속한 물품 전체 목록
exports.findByPbacNo = async (pbacNo) => {
  const [rows] = await pool.query(`
    SELECT
      ai.pbac_no AS pbacNo, ai.pbac_srno AS pbacSrno, ai.cmdt_ln_no AS cmdtLnNo,
      ai.cmdt_nm AS cmdtNm, ai.cmdt_qty AS cmdtQty, ai.cmdt_qty_ut_cd AS cmdtQtyUtCd,
      ai.cmdt_wght AS cmdtWght, ai.cmdt_wght_ut_cd AS cmdtWghtUtCd,
      ai.pbac_prng_prc AS pbacPrngPrc,
      ai.atnt_cmdt AS atntCmdt, ai.atnt_cmdt_nm AS atntCmdtNm, ai.pbac_cond_cn AS pbacCondCn,
      a.pbac_strt_dttm AS pbacStrtDttm, a.pbac_end_dttm AS pbacEndDttm,
      a.cstm_sgn AS cstmSgn, co.cstm_name AS cstmName,
      ic.category_id AS categoryId, c.name_ko AS categoryName,
      (
        SELECT GROUP_CONCAT(aii.image_url ORDER BY aii.image_seq SEPARATOR '|')
        FROM auction_item_image aii
        WHERE aii.pbac_no = ai.pbac_no AND aii.pbac_srno = ai.pbac_srno AND aii.cmdt_ln_no = ai.cmdt_ln_no
      ) AS imageUrls
    FROM auction_item ai
    JOIN auction a ON ai.pbac_no = a.pbac_no
    LEFT JOIN customs_office co ON a.cstm_sgn = co.cstm_sgn
    LEFT JOIN item_classification ic
      ON ic.pbac_no = ai.pbac_no AND ic.pbac_srno = ai.pbac_srno AND ic.cmdt_ln_no = ai.cmdt_ln_no
    LEFT JOIN category c ON ic.category_id = c.category_id
    WHERE ai.pbac_no = ?
    ORDER BY ai.pbac_srno, ai.cmdt_ln_no
  `, [pbacNo]);
  return rows;
};

// 세관별 활성 물품 건수 (물품 수 내림차순)
exports.getCustomsStats = async () => {
  const [rows] = await pool.query(`
    SELECT a.cstm_sgn AS cstmSgn, co.cstm_name AS cstmName, COUNT(ai.cmdt_ln_no) AS itemCount
    FROM auction a
    LEFT JOIN customs_office co ON a.cstm_sgn = co.cstm_sgn
    LEFT JOIN auction_item ai ON a.pbac_no = ai.pbac_no
    WHERE a.pbac_end_dttm >= NOW()
    GROUP BY a.cstm_sgn
    HAVING itemCount > 0
    ORDER BY itemCount DESC
  `);
  return rows;
};

// 카테고리별 물품 건수 (L3→L2→L1 롤업)
exports.getCategoryStats = async () => {
  const [rows] = await pool.query(`
    SELECT ic.category_id AS categoryId, COUNT(*) AS cnt
    FROM item_classification ic
    GROUP BY ic.category_id
  `);

  const direct = {};
  for (const r of rows) direct[r.categoryId] = Number(r.cnt);

  const [cats] = await pool.query(`SELECT category_id, parent_id FROM category`);
  const parentOf = {};
  for (const c of cats) parentOf[c.category_id] = c.parent_id;

  const totals = { ...direct };
  for (const [id, cnt] of Object.entries(direct)) {
    let cur = parentOf[Number(id)];
    while (cur != null) {
      totals[cur] = (totals[cur] || 0) + cnt;
      cur = parentOf[cur];
    }
  }
  return totals;
};
