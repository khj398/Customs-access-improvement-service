/*
jobs/notificationJob.js
알림 발송 cron 작업
  1) 찜한 물품 중 경매 시작 임박(24시간 전 / 1시간 전, 2단계) → AUCTION_STARTING_SOON 푸시
  2) 관심 검색어(user_search_subscription)와 매칭되는 신규 물품 → 요약 푸시
*/

const cron = require('node-cron');
const pool = require('../config/db');
const deviceTokenModel = require('../models/deviceTokenModel');
const searchSubscriptionModel = require('../models/searchSubscriptionModel');
const fcmService = require('../services/fcmService');

const RUN_INTERVAL_CRON = '*/15 * * * *'; // 15분마다
const NEW_ITEM_WINDOW_MINUTES = 20;       // cron 주기보다 약간 여유를 둔 조회 창

// 경매 시작 임박 알림 단계 — windowHours 이내로 시작하는 건을 찾아 title로 중복 발송 방지
const STARTING_SOON_TIERS = [
  { windowHours: 24, title: '경매 시작 임박 (24시간 전)' },
  { windowHours: 1,  title: '경매 시작 임박 (1시간 전)' },
];

async function sendAndLog({ userId, watchTargetId = null, title, body, data = {} }) {
  const tokens = await deviceTokenModel.findTokensByUser(userId);
  if (tokens.length === 0) return;

  const result = await fcmService.sendToTokens(tokens, title, body, data);
  if (result.invalidTokens.length > 0) {
    await deviceTokenModel.removeTokens(result.invalidTokens);
  }

  const status = result.successCount > 0 ? 'SENT' : 'FAILED';
  await pool.query(
    `INSERT INTO user_notification_event
       (user_id, watch_target_id, channel, status, message_title, message_body, sent_at)
     VALUES (?, ?, 'APP_PUSH', ?, ?, ?, NOW())`,
    [userId, watchTargetId, status, title, body]
  );
}

// 1) 찜한 물품 경매 시작 임박 알림 — 단계별(24시간 전, 1시간 전)로 각각 한 번씩 발송
async function checkAuctionStartingSoon() {
  for (const tier of STARTING_SOON_TIERS) {
    const [rows] = await pool.query(`
      SELECT
        wt.watch_target_id AS watchTargetId,
        wt.user_id         AS userId,
        a.pbac_no          AS pbacNo,
        ai.cmdt_nm         AS cmdtNm,
        a.pbac_strt_dttm   AS pbacStrtDttm
      FROM user_watchlist_target wt
      JOIN auction a ON a.pbac_no = wt.pbac_no
      LEFT JOIN auction_item ai
        ON ai.pbac_no = wt.pbac_no AND ai.pbac_srno = wt.pbac_srno AND ai.cmdt_ln_no = wt.cmdt_ln_no
      WHERE wt.notify_enabled = 1
        AND a.pbac_strt_dttm BETWEEN NOW() AND DATE_ADD(NOW(), INTERVAL ? HOUR)
        AND NOT EXISTS (
          SELECT 1 FROM user_notification_event ne
          WHERE ne.watch_target_id = wt.watch_target_id
            AND ne.user_id = wt.user_id
            AND ne.status = 'SENT'
            AND ne.message_title = ?
        )
    `, [tier.windowHours, tier.title]);

    for (const row of rows) {
      await sendAndLog({
        userId: row.userId,
        watchTargetId: row.watchTargetId,
        title: tier.title,
        body: `찜하신 "${row.cmdtNm || row.pbacNo}" 공매가 곧 시작됩니다.`,
        data: { type: 'AUCTION_STARTING_SOON', pbacNo: row.pbacNo, windowHours: String(tier.windowHours) },
      });
    }
  }
}

// 2) 관심 검색어 매칭 신규 물품 알림
async function checkSearchSubscriptions() {
  const subscriptions = await searchSubscriptionModel.findAllActive();

  for (const sub of subscriptions) {
    const [rows] = await pool.query(`
      SELECT COUNT(*) AS cnt
      FROM auction_item ai
      WHERE ai.created_at > DATE_SUB(NOW(), INTERVAL ? MINUTE)
        AND ai.cmdt_nm LIKE ?
    `, [NEW_ITEM_WINDOW_MINUTES, `%${sub.keyword}%`]);

    const newCount = rows[0].cnt;
    if (newCount === 0) continue;

    await sendAndLog({
      userId: sub.userId,
      title: '관심 검색어 신규 물품',
      body: `"${sub.keyword}" 관련 신규 물품이 ${newCount}건 등록되었습니다.`,
      data: { type: 'NEW_ITEM', keyword: sub.keyword },
    });
    await searchSubscriptionModel.markNotified(sub.subscriptionId);
  }
}

async function runOnce() {
  try {
    await checkAuctionStartingSoon();
  } catch (err) {
    console.error('[notificationJob] checkAuctionStartingSoon 실패:', err);
  }
  try {
    await checkSearchSubscriptions();
  } catch (err) {
    console.error('[notificationJob] checkSearchSubscriptions 실패:', err);
  }
}

function start() {
  if (!fcmService.isEnabled()) {
    console.warn('[notificationJob] FCM 미설정 상태 — cron은 등록하되 발송은 스킵됩니다.');
  }
  cron.schedule(RUN_INTERVAL_CRON, runOnce);
  console.log(`[notificationJob] cron 등록 완료 (${RUN_INTERVAL_CRON})`);
}

module.exports = { start, runOnce };
