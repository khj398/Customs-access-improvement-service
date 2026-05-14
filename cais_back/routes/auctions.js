/*
routes/auctions.js
공매(경매) 공고 라우트
- 전체 목록 조회 (필터/검색/페이징)
- 특정 공고 상세 조회
- 특정 공고에 속한 물품 목록 조회
*/

const express       = require('express');
const router        = express.Router();
const auctionController = require('../controllers/auctionController');
const optionalAuth  = require('../middleware/optionalAuth');

// 공매 목록 조회 (검색, 카테고리, 세관, 페이징)
router.get('/',            optionalAuth, auctionController.getAuctions);

// 홈 화면용 - 이번 주 신규 공매
router.get('/new',         optionalAuth, auctionController.getNewAuctions);

// 내 위치 기반 근처 공매 (세관코드 기준)
router.get('/nearby',      optionalAuth, auctionController.getNearbyAuctions);

// 공매 상세
router.get('/:pbacNo',     optionalAuth, auctionController.getAuctionDetail);

// 공매에 속한 물품 목록
router.get('/:pbacNo/items', optionalAuth, auctionController.getAuctionItems);

module.exports = router;
