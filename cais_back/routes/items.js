/*
routes/items.js
공매 물품(auctionitem) 라우트
- 물품 상세 조회
- 검색 (itemsearchtoken 기반)
*/

const express      = require('express');
const router       = express.Router();
const itemController = require('../controllers/itemController');
const optionalAuth = require('../middleware/optionalAuth');

// 물품 검색
router.get('/search', optionalAuth, itemController.searchItems);

// 자동완성
router.get('/autocomplete', itemController.autocomplete);

// 카테고리별 물품 건수 (반드시 /:pbacNo/... 앞에 위치)
router.get('/category-stats', itemController.getCategoryStats);

// 세관별 활성 물품 건수
router.get('/customs-stats', itemController.getCustomsStats);

// 달력용 — 특정 연월에 마감되는 물품 목록 (반드시 /:pbacNo/... 앞에 위치)
router.get('/calendar', optionalAuth, itemController.getCalendarItems);

// 같은 공매번호(pbacNo)에 속한 모든 물품 (번들 구성 확인용)
router.get('/:pbacNo/bundle', itemController.getBundledItems);

// 물품 상세 조회 (PK: pbacNo, pbacSrno, cmdtLnNo)
router.get('/:pbacNo/:pbacSrno/:cmdtLnNo', optionalAuth, itemController.getItemDetail);

module.exports = router;
