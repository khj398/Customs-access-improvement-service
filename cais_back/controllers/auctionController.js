/*
controllers/auctionController.js
공매 공고 컨트롤러
*/

const auctionModel = require('../models/auctionModel');
const itemModel    = require('../models/itemModel');

exports.getAuctions = async (req, res) => {
  try {
    const { cstmSgn, keyword, page = 1, limit = 20 } = req.query;
    const auctions = await auctionModel.findAll({
      cstmSgn, keyword,
      page: parseInt(page),
      limit: parseInt(limit),
    });
    res.json({ auctions });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

exports.getNewAuctions = async (req, res) => {
  try {
    const auctions = await auctionModel.findNew(10);
    res.json({ auctions });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

exports.getNearbyAuctions = async (req, res) => {
  try {
    const { cstmSgn } = req.query;
    if (!cstmSgn) return res.status(400).json({ error: 'cstmSgn 파라미터가 필요합니다' });
    const auctions = await auctionModel.findNearby(cstmSgn, 10);
    res.json({ auctions });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

exports.getAuctionDetail = async (req, res) => {
  try {
    const { pbacNo } = req.params;
    const auction = await auctionModel.findByPbacNo(pbacNo);
    if (!auction) return res.status(404).json({ error: '공매를 찾을 수 없습니다' });
    res.json({ auction });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

exports.getAuctionItems = async (req, res) => {
  try {
    const { pbacNo } = req.params;
    const items = await itemModel.findByPbacNo(pbacNo);
    res.json({ items });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};
