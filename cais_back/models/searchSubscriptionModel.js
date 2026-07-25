/*
models/searchSubscriptionModel.js
관심 검색어 구독 DB 모델 — customs_auction.user_search_subscription 테이블 사용
(user_recent_search와 별개: "신규 물품 매칭 시 알림"을 원하는 키워드만 관리)
*/

const pool = require('../config/db');

const normalize = (keyword) => keyword.trim().toLowerCase();

exports.findMySubscriptions = async (userId) => {
  const [rows] = await pool.query(
    `SELECT
       subscription_id  AS subscriptionId,
       keyword,
       notify_enabled   AS notifyEnabled,
       last_notified_at AS lastNotifiedAt,
       created_at       AS createdAt
     FROM user_search_subscription
     WHERE user_id = ?
     ORDER BY created_at DESC`,
    [userId]
  );
  return rows;
};

exports.add = async (userId, keyword) => {
  const [result] = await pool.query(
    `INSERT INTO user_search_subscription (user_id, keyword, keyword_normalized)
     VALUES (?, ?, ?)
     ON DUPLICATE KEY UPDATE notify_enabled = 1`,
    [userId, keyword, normalize(keyword)]
  );
  return result.insertId;
};

exports.remove = async (userId, subscriptionId) => {
  await pool.query(
    `DELETE FROM user_search_subscription WHERE user_id = ? AND subscription_id = ?`,
    [userId, subscriptionId]
  );
};

exports.setNotifyEnabled = async (userId, subscriptionId, enabled) => {
  await pool.query(
    `UPDATE user_search_subscription SET notify_enabled = ? WHERE user_id = ? AND subscription_id = ?`,
    [enabled ? 1 : 0, userId, subscriptionId]
  );
};

// 알림 발송 대상 조회용 — 활성화된 구독 전체(유저 무관하게 cron이 순회)
exports.findAllActive = async () => {
  const [rows] = await pool.query(
    `SELECT
       subscription_id    AS subscriptionId,
       user_id            AS userId,
       keyword,
       keyword_normalized AS keywordNormalized,
       last_notified_at   AS lastNotifiedAt
     FROM user_search_subscription
     WHERE notify_enabled = 1`
  );
  return rows;
};

exports.markNotified = async (subscriptionId) => {
  await pool.query(
    `UPDATE user_search_subscription SET last_notified_at = NOW() WHERE subscription_id = ?`,
    [subscriptionId]
  );
};
