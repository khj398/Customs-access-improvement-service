/* =========================================================
   customs_auction v4 patch
   - 위치 기반 세관 추천 + 알림(FCM 푸시) 기능 확장
   1) customs_office: 위경도 컬럼 추가 + 실제 데이터 좌표 시딩
   2) user_notification_rule.event_type: AUCTION_STARTING_SOON 추가
   3) user_device_token: FCM 기기 토큰 저장 (신규)
   4) user_search_subscription: 관심 검색어 구독 (신규)
   ========================================================= */

USE customs_auction;


-- 1) customs_office: 위경도 컬럼 추가 (멱등성 보장)
SET @col_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE table_schema = DATABASE()
    AND table_name = 'customs_office'
    AND column_name = 'latitude'
);
SET @sql = IF(@col_exists = 0,
  'ALTER TABLE customs_office
     ADD COLUMN latitude DECIMAL(10,7) NULL COMMENT ''세관 위도'',
     ADD COLUMN longitude DECIMAL(10,7) NULL COMMENT ''세관 경도''',
  'SELECT ''customs_office.latitude already exists, skipping'' AS info'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 1-1) 현재 DB에 존재하는 세관 5곳 좌표 시딩
--      (SELECT cstm_sgn, cstm_name FROM customs_office; 결과 기준으로 매칭)
--      좌표는 각 세관의 공식 위치(항만/공항) 기준 근사치 — 필요 시 보정 가능
UPDATE customs_office SET latitude = 36.9755000, longitude = 126.8254000 WHERE cstm_sgn = '016'; -- 평택세관 (평택항)
UPDATE customs_office SET latitude = 37.4707000, longitude = 126.6180000 WHERE cstm_sgn = '020'; -- 인천세관 (인천항)
UPDATE customs_office SET latitude = 35.1035000, longitude = 129.0355000 WHERE cstm_sgn = '030'; -- 부산세관 (부산항)
UPDATE customs_office SET latitude = 37.4602000, longitude = 126.4407000 WHERE cstm_sgn = '040'; -- 인천공항세관
UPDATE customs_office SET latitude = 37.5583000 , longitude = 126.7906000 WHERE cstm_sgn = '041'; -- 김포공항세관

-- 확인용: 시딩 후 좌표 없는(NULL) 세관이 있는지 점검
-- SELECT cstm_sgn, cstm_name, latitude, longitude FROM customs_office WHERE latitude IS NULL;


-- 2) user_notification_rule.event_type: AUCTION_STARTING_SOON 추가
--    기존 값(PRICE_CHANGED/STATUS_CHANGED/NEW_ITEM/REMOVED_ITEM)은 그대로 유지
ALTER TABLE user_notification_rule
  MODIFY COLUMN event_type
    ENUM('PRICE_CHANGED','STATUS_CHANGED','NEW_ITEM','REMOVED_ITEM','AUCTION_STARTING_SOON')
    NOT NULL COMMENT '알림 이벤트 종류 (AUCTION_STARTING_SOON: 경매 시작 임박)';


-- 3) user_device_token (신규) — FCM 푸시 발송 대상 기기 토큰
CREATE TABLE IF NOT EXISTS user_device_token (
  device_token_id BIGINT NOT NULL AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  fcm_token VARCHAR(255) NOT NULL,
  platform ENUM('ANDROID','IOS','WEB') NOT NULL DEFAULT 'ANDROID',
  last_used_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (device_token_id),
  UNIQUE KEY uq_device_token (fcm_token),
  INDEX idx_device_token_user (user_id),
  CONSTRAINT fk_device_token_user
    FOREIGN KEY (user_id) REFERENCES app_user(user_id)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='FCM 기기 토큰';


-- 4) user_search_subscription (신규) — 관심 검색어 구독(당근마켓 스타일)
--    user_recent_search(단순 이력)과 분리: 신규 물품 매칭 알림 대상만 관리
CREATE TABLE IF NOT EXISTS user_search_subscription (
  subscription_id BIGINT NOT NULL AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  keyword VARCHAR(200) NOT NULL,
  keyword_normalized VARCHAR(200) NOT NULL,
  notify_enabled TINYINT NOT NULL DEFAULT 1,
  last_notified_at DATETIME NULL COMMENT '마지막으로 신규 물품 알림을 보낸 시각(중복 발송 방지 기준)',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (subscription_id),
  UNIQUE KEY uq_subscription_user_keyword (user_id, keyword_normalized),
  INDEX idx_subscription_user (user_id),
  INDEX idx_subscription_keyword_norm (keyword_normalized),
  CONSTRAINT fk_subscription_user
    FOREIGN KEY (user_id) REFERENCES app_user(user_id)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='관심 검색어 구독(신규 물품 알림용)';
