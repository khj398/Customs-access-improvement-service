/*
routes/searchSubscriptions.js
관심 검색어 구독 라우트 (당근마켓 스타일 신규 물품 알림)
*/

const express = require('express');
const router  = express.Router();
const controller = require('../controllers/searchSubscriptionController');
const auth    = require('../middleware/auth');

router.get('/',    auth, controller.getMySubscriptions);
router.post('/',   auth, controller.addSubscription);
router.delete('/:subscriptionId', auth, controller.removeSubscription);
router.patch('/:subscriptionId',  auth, controller.toggleSubscription);

module.exports = router;
