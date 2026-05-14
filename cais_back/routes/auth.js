/*
routes/auth.js
인증 라우트 - 회원가입, 로그인
*/

const express = require('express');
const router  = express.Router();
const authController = require('../controllers/authController');

router.post('/register', authController.register);
router.post('/login',    authController.login);

module.exports = router;
