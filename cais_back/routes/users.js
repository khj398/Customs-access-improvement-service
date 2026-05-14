/*
routes/users.js
사용자 관련 라우트
*/

const express        = require('express');
const router         = express.Router();
const userController = require('../controllers/userController');
const auth           = require('../middleware/auth');

// 내 프로필 조회
router.get('/me',    auth, userController.getMyProfile);

// 내 프로필 수정
router.put('/me',    auth, userController.updateProfile);

// 내 위치(관심 세관) 설정
router.put('/me/location', auth, userController.updateLocation);

// 입찰 달력 - 날짜별 입찰/낙찰 현황
router.get('/me/calendar', auth, userController.getBidCalendar);

module.exports = router;
