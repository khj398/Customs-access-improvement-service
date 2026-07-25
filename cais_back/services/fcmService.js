/*
services/fcmService.js
Firebase Admin SDK를 이용한 FCM 푸시 발송
서비스 계정 키 파일이 없으면(설정 전) 발송을 건너뛰고 경고만 남긴다.
*/

const fs   = require('fs');
const path = require('path');

const SERVICE_ACCOUNT_PATH = process.env.FIREBASE_SERVICE_ACCOUNT_PATH
  || path.join(__dirname, '..', 'config', 'firebase-service-account.json');

let messaging = null;

if (fs.existsSync(SERVICE_ACCOUNT_PATH)) {
  // firebase-admin v12+ : 네임스페이스(admin.apps/admin.messaging()) API가 제거되고
  // 모듈형 API(firebase-admin/app, firebase-admin/messaging)로 대체됨
  const { initializeApp, getApps, cert } = require('firebase-admin/app');
  const { getMessaging } = require('firebase-admin/messaging');
  const serviceAccount = require(SERVICE_ACCOUNT_PATH);

  const app = getApps().length ? getApps()[0] : initializeApp({ credential: cert(serviceAccount) });
  messaging = getMessaging(app);
} else {
  console.warn(`[fcmService] 서비스 계정 키(${SERVICE_ACCOUNT_PATH})가 없어 FCM 발송이 비활성화됩니다.`);
}

// tokens: string[], 반환: { successCount, failureCount, invalidTokens }
exports.sendToTokens = async (tokens, title, body, data = {}) => {
  if (!messaging || tokens.length === 0) {
    return { successCount: 0, failureCount: tokens.length, invalidTokens: [] };
  }

  const res = await messaging.sendEachForMulticast({
    tokens,
    notification: { title, body },
    data,
  });

  const invalidTokens = [];
  res.responses.forEach((r, i) => {
    if (!r.success) {
      const code = r.error && r.error.code;
      if (code === 'messaging/registration-token-not-registered'
        || code === 'messaging/invalid-registration-token') {
        invalidTokens.push(tokens[i]);
      }
    }
  });

  return {
    successCount: res.successCount,
    failureCount: res.failureCount,
    invalidTokens,
  };
};

exports.isEnabled = () => messaging !== null;
