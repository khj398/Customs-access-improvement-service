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

// 내 기본 위치(위경도) 조회/설정 — GPS 좌표 또는 주소(카카오 지오코딩) 둘 다 지원
router.get('/me/base-location', auth, userController.getBaseLocation);
router.put('/me/base-location', auth, userController.updateBaseLocation);

// 좌표 → 주소 미리보기 (저장 안 함) — 지도 화면에서 드래그 중 주소 표시용
router.get('/me/base-location/reverse-geocode', auth, userController.previewReverseGeocode);

// FCM 기기 토큰 등록/삭제
router.post('/me/device-token',   auth, userController.registerDeviceToken);
router.delete('/me/device-token', auth, userController.removeDeviceToken);

// 입찰 달력 - 날짜별 입찰/낙찰 현황
router.get('/me/calendar', auth, userController.getBidCalendar);

module.exports = router;
