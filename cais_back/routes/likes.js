/*
routes/likes.js
찜(좋아요) 라우트
*/

const express     = require('express');
const router      = express.Router();
const likeController = require('../controllers/likeController');
const auth        = require('../middleware/auth');

// 찜 키 목록 조회 (JOIN 없이 user_watchlist_target 직접 조회)
router.get('/keys', auth, likeController.getMyLikeKeys);

// 찜 목록 조회
router.get('/my',   auth, likeController.getMyLikes);

// 찜 토글 (찜 추가/취소)
router.post('/toggle', auth, likeController.toggleLike);

module.exports = router;
