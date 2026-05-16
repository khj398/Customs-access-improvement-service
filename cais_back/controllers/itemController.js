/*
controllers/itemController.js
공매 물품 컨트롤러
*/

const itemModel = require('../models/itemModel');
const likeModel = require('../models/likeModel');
const bidModel  = require('../models/bidModel');

exports.searchItems = async (req, res) => {
  try {
    const { keyword, categoryId, cstmSgn, page = 1, limit = 20 } = req.query;
    const userId = req.user?.userId ?? null; // optionalAuth 미들웨어에서 설정
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

exports.getCategoryStats = async (req, res) => {
  try {
    const stats = await itemModel.getCategoryStats();
    res.json({ stats });
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
