/*
routes/bids.js
입찰 라우트
- 입찰 신청
- 내 입찰 목록 조회 (탭: 입찰중 / 낙찰 / 종료)
- 입찰 취소
*/

const express     = require('express');
const router      = express.Router();
const bidController = require('../controllers/bidController');
const auth        = require('../middleware/auth');

// 내 입찰 전체 목록 (status 쿼리로 필터: bidding / won / expired)
router.get('/my',               auth, bidController.getMyBids);

// 특정 물품 최고 입찰가 조회
router.get('/:pbacNo/:pbacSrno/:cmdtLnNo', auth, bidController.getTopBid);

// 입찰 신청
router.post('/',                auth, bidController.createBid);

// 입찰 취소
router.delete('/:bidId',        auth, bidController.cancelBid);

module.exports = router;
