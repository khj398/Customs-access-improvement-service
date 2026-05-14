/*
routes/likes.js
찜(좋아요) 라우트
*/

const express     = require('express');
const router      = express.Router();
const likeController = require('../controllers/likeController');
const auth        = require('../middleware/auth');

// 찜 목록 조회
router.get('/my',   auth, likeController.getMyLikes);

// 찜 토글 (찜 추가/취소)
router.post('/toggle', auth, likeController.toggleLike);

module.exports = router;
