/*
controllers/itemController.js
공매 물품 컨트롤러
*/

const itemModel  = require('../models/itemModel');
const meiliModel = require('../models/meiliModel');
const likeModel  = require('../models/likeModel');
const bidModel   = require('../models/bidModel');

exports.searchItems = async (req, res) => {
  try {
    const { keyword, categoryId, cstmSgn, page = 1, limit = 20 } = req.query;
    const userId = req.user?.userId ?? null;

    // keyword·카테고리·세관 필터가 있으면 Meilisearch, 없으면 MySQL (최신순)
    if (keyword || categoryId || cstmSgn) {
      const hits = await meiliModel.search({
        keyword, categoryId, cstmSgn,
        page: parseInt(page),
        limit: parseInt(limit),
      });

      // Meilisearch 결과로 MySQL에서 상세 정보(찜·이미지 등) 보완
      if (!hits.length) return res.json({ items: [] });

      const pool = require('../config/db');
      const isFavoriteCol = userId
        ? `CASE WHEN l.watch_target_id IS NOT NULL THEN 1 ELSE 0 END AS isFavorite`
        : `0 AS isFavorite`;
      const likesJoin = userId
        ? `LEFT JOIN user_watchlist_target l
             ON l.user_id = ? AND l.target_level = 'ITEM'
            AND l.pbac_no = ai.pbac_no AND l.pbac_srno = ai.pbac_srno AND l.cmdt_ln_no = ai.cmdt_ln_no`
        : '';

      // Meilisearch hit 키를 중첩 배열로 전달 → mysql2가 tuple IN 형태로 파라미터화
      // (외부 검색 인덱스 값을 직접 SQL에 보간하지 않음)
      const keyTuples = hits.map(h => [String(h.pbacNo), String(h.pbacSrno), String(h.cmdtLnNo)]);
      const queryParams = userId ? [userId, keyTuples] : [keyTuples];

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
        WHERE (ai.pbac_no, ai.pbac_srno, ai.cmdt_ln_no) IN (?)
      `, queryParams);

      // Meilisearch 관련도 순서 유지
      const map = new Map(rows.map(r => [`${r.pbacNo}_${r.pbacSrno}_${r.cmdtLnNo}`, r]));
      const items = hits.map(h => map.get(`${h.pbacNo}_${h.pbacSrno}_${h.cmdtLnNo}`)).filter(Boolean);
      return res.json({ items });
    }

    // 필터 없음 → 기존 MySQL 최신순
    const items = await itemModel.search({
      keyword, categoryId, cstmSgn,
      page: parseInt(page),
      limit: parseInt(limit),
      userId,
    });
    res.json({ items });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

exports.autocomplete = async (req, res) => {
  try {
    const { q } = req.query;
    const suggestions = await meiliModel.autocomplete(q);
    res.json({ suggestions });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

exports.getCategoryStats = async (req, res) => {
  try {
    const stats = await itemModel.getCategoryStats();
    res.json({ stats });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

exports.getCustomsStats = async (req, res) => {
  try {
    const customs = await itemModel.getCustomsStats();
    res.json({ customs });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

exports.getCalendarItems = async (req, res) => {
  try {
    const year  = parseInt(req.query.year  || new Date().getFullYear());
    const month = parseInt(req.query.month || new Date().getMonth() + 1);
    const userId = req.user?.userId ?? null;
    const items = await itemModel.findByMonth(year, month, userId);
    res.json({ items });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

exports.getBundledItems = async (req, res) => {
  try {
    const { pbacNo } = req.params;
    const items = await itemModel.findByPbacNo(pbacNo);
    res.json({ items });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

exports.getItemDetail = async (req, res) => {
  try {
    const { pbacNo, pbacSrno, cmdtLnNo } = req.params;
    const item = await itemModel.findOne(pbacNo, pbacSrno, cmdtLnNo);
    if (!item) return res.status(404).json({ error: '물품을 찾을 수 없습니다' });

    const topBid = await bidModel.getTopBid(pbacNo, pbacSrno, cmdtLnNo);
    const likeCount = await likeModel.count(pbacNo, pbacSrno, cmdtLnNo);

    let isLiked = false;
    let myBid   = null;
    if (req.user) {
      const likeRow = await likeModel.exists(req.user.userId, pbacNo, pbacSrno, cmdtLnNo);
      isLiked = !!likeRow;
      myBid   = await bidModel.findUserBid(req.user.userId, pbacNo, pbacSrno, cmdtLnNo);
    }

    res.json({ item, topBid, likeCount, isLiked, myBid });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};
