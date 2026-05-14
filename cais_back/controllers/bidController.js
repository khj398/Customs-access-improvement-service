/*
controllers/bidController.js
입찰 컨트롤러
*/

const bidModel  = require('../models/bidModel');
const itemModel = require('../models/itemModel');
const pool      = require('../config/db');

exports.getMyBids = async (req, res) => {
  try {
    const { status } = req.query; // bidding | won | expired
    const bids = await bidModel.findMyBids(req.user.userId, status);
    res.json({ bids });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

exports.getTopBid = async (req, res) => {
  try {
    const { pbacNo, pbacSrno, cmdtLnNo } = req.params;
    const topBid = await bidModel.getTopBid(pbacNo, pbacSrno, cmdtLnNo);
    res.json({ topBid });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

exports.createBid = async (req, res) => {
  try {
    const { pbacNo, pbacSrno, cmdtLnNo, bidAmount } = req.body;
    if (!pbacNo || !pbacSrno || !cmdtLnNo || !bidAmount) {
      return res.status(400).json({ error: '필수 파라미터가 누락되었습니다' });
    }

    // 물품 유효성 확인
    const item = await itemModel.findOne(pbacNo, pbacSrno, cmdtLnNo);
    if (!item) return res.status(404).json({ error: '물품을 찾을 수 없습니다' });

    // 입찰가 > 시작가 검증
    if (bidAmount < item.pbacPrngPrc) {
      return res.status(400).json({ error: `입찰가는 시작가(${item.pbacPrngPrc}원) 이상이어야 합니다` });
    }

    // 현재 최고가보다 높아야 함
    const top = await bidModel.getTopBid(pbacNo, pbacSrno, cmdtLnNo);
    if (top.topBid && bidAmount <= top.topBid) {
      return res.status(400).json({ error: `현재 최고 입찰가(${top.topBid}원)보다 높게 입찰해야 합니다` });
    }

    const bidId = await bidModel.create(req.user.userId, pbacNo, pbacSrno, cmdtLnNo, bidAmount);
    res.status(201).json({ bidId, message: '입찰이 완료되었습니다' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

exports.cancelBid = async (req, res) => {
  try {
    const { bidId } = req.params;
    const success = await bidModel.cancel(bidId, req.user.userId);
    if (!success) return res.status(400).json({ error: '입찰을 취소할 수 없습니다' });
    res.json({ message: '입찰이 취소되었습니다' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};
