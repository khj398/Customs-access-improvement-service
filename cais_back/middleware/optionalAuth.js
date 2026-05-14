/*
middleware/optionalAuth.js
선택적 JWT 인증 미들웨어 (비로그인도 허용, 로그인이면 user 정보 추가)
*/

const jwt = require('jsonwebtoken');

const optionalAuth = (req, res, next) => {
  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    const token = authHeader.split(' ')[1];
    try {
      req.user = jwt.verify(token, process.env.JWT_SECRET);
    } catch (_) {}
  }
  next();
};

module.exports = optionalAuth;
