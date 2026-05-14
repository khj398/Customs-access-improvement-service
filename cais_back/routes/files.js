/*
routes/files.js
파일 업로드 라우트
*/

const express        = require('express');
const router         = express.Router();
const fileController = require('../controllers/fileController');
const auth           = require('../middleware/auth');
const { uploadImage } = require('../config/upload');

// 이미지 업로드
router.post('/', auth, uploadImage.single('file'), fileController.uploadImage);

// 이미지 조회 (S3 presigned URL or 직접 URL 반환)
router.get('/:id', fileController.getImage);

module.exports = router;
