/*
models/deviceTokenModel.js
FCM 기기 토큰 DB 모델 — customs_auction.user_device_token 테이블 사용
*/

const pool = require('../config/db');

// 동일 토큰이 다른 유저 소유였다면 갱신(재로그인/기기변경 대응), 아니면 새로 추가
exports.upsert = async (userId, fcmToken, platform = 'ANDROID') => {
  await pool.query(
    `INSERT INTO user_device_token (user_id, fcm_token, platform, last_used_at)
     VALUES (?, ?, ?, NOW())
     ON DUPLICATE KEY UPDATE user_id = VALUES(user_id), platform = VALUES(platform), last_used_at = NOW()`,
    [userId, fcmToken, platform]
  );
};

exports.remove = async (fcmToken) => {
  await pool.query(`DELETE FROM user_device_token WHERE fcm_token = ?`, [fcmToken]);
};

exports.findTokensByUser = async (userId) => {
  const [rows] = await pool.query(
    `SELECT fcm_token AS fcmToken FROM user_device_token WHERE user_id = ?`,
    [userId]
  );
  return rows.map(r => r.fcmToken);
};

exports.removeTokens = async (tokens) => {
  if (tokens.length === 0) return;
  await pool.query(
    `DELETE FROM user_device_token WHERE fcm_token IN (${tokens.map(() => '?').join(',')})`,
    tokens
  );
};
