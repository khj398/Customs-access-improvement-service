/* =========================================================
   app_user v1 schema
   - docs/DB_REDESIGN_DISCUSSION.md 기준
   - 로컬+소셜 로그인, LOT/ITEM 관심대상, APP_PUSH 알림
   ========================================================= */

CREATE DATABASE IF NOT EXISTS app_user
DEFAULT CHARACTER SET utf8mb4
COLLATE utf8mb4_general_ci;

USE app_user;

CREATE TABLE IF NOT EXISTS app_user (
  user_id BIGINT NOT NULL AUTO_INCREMENT,
  email VARCHAR(255) NOT NULL,
  password_hash VARCHAR(255) NULL,
  status ENUM('ACTIVE','SUSPENDED','DELETED') NOT NULL DEFAULT 'ACTIVE',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  last_login_at TIMESTAMP NULL,
  PRIMARY KEY (user_id),
  UNIQUE KEY uq_app_user_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='앱 사용자';

CREATE TABLE IF NOT EXISTS user_auth_provider (
  auth_provider_id BIGINT NOT NULL AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  provider ENUM('LOCAL','KAKAO','GOOGLE','APPLE') NOT NULL,
  provider_user_key VARCHAR(255) NOT NULL,
  connected_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (auth_provider_id),
  UNIQUE KEY uq_provider_key (provider, provider_user_key),
  INDEX idx_uap_user (user_id),
  CONSTRAINT fk_uap_user
    FOREIGN KEY (user_id) REFERENCES app_user(user_id)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='소셜/로컬 로그인 연동';

CREATE TABLE IF NOT EXISTS user_profile (
  user_id BIGINT NOT NULL,
  nickname VARCHAR(50) NULL,
  locale VARCHAR(20) NULL,
  timezone VARCHAR(40) NULL,
  marketing_opt_in TINYINT NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id),
  CONSTRAINT fk_user_profile_user
    FOREIGN KEY (user_id) REFERENCES app_user(user_id)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='사용자 프로필';

CREATE TABLE IF NOT EXISTS user_watchlist_target (
  watch_target_id BIGINT NOT NULL AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  target_level ENUM('LOT','ITEM') NOT NULL,
  pbac_no VARCHAR(20) NOT NULL,
  pbac_srno VARCHAR(20) NULL,
  cmdt_ln_no VARCHAR(10) NULL,
  notify_enabled TINYINT NOT NULL DEFAULT 1,
  memo VARCHAR(255) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (watch_target_id),
  UNIQUE KEY uq_watch_lot (user_id, target_level, pbac_no),
  UNIQUE KEY uq_watch_item (user_id, target_level, pbac_no, pbac_srno, cmdt_ln_no),
  INDEX idx_watch_user (user_id),
  CONSTRAINT fk_watch_user
    FOREIGN KEY (user_id) REFERENCES app_user(user_id)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='관심대상(LOT/ITEM)';

CREATE TABLE IF NOT EXISTS user_notification_rule (
  notification_rule_id BIGINT NOT NULL AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  watch_target_id BIGINT NULL,
  channel ENUM('APP_PUSH') NOT NULL DEFAULT 'APP_PUSH',
  event_type ENUM('PRICE_CHANGED','STATUS_CHANGED','NEW_ITEM','REMOVED_ITEM') NOT NULL,
  enabled TINYINT NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (notification_rule_id),
  INDEX idx_rule_user (user_id),
  INDEX idx_rule_target (watch_target_id),
  CONSTRAINT fk_rule_user
    FOREIGN KEY (user_id) REFERENCES app_user(user_id)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_rule_watch
    FOREIGN KEY (watch_target_id) REFERENCES user_watchlist_target(watch_target_id)
    ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='알림 규칙(APP_PUSH 1차)';

CREATE TABLE IF NOT EXISTS user_notification_event (
  notification_event_id BIGINT NOT NULL AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  notification_rule_id BIGINT NULL,
  watch_target_id BIGINT NULL,
  channel ENUM('APP_PUSH') NOT NULL DEFAULT 'APP_PUSH',
  status ENUM('PENDING','SENT','FAILED') NOT NULL DEFAULT 'PENDING',
  message_title VARCHAR(200) NULL,
  message_body TEXT NULL,
  sent_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (notification_event_id),
  INDEX idx_noti_event_user_created (user_id, created_at),
  CONSTRAINT fk_noti_event_user
    FOREIGN KEY (user_id) REFERENCES app_user(user_id)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_noti_event_rule
    FOREIGN KEY (notification_rule_id) REFERENCES user_notification_rule(notification_rule_id)
    ON UPDATE CASCADE ON DELETE SET NULL,
  CONSTRAINT fk_noti_event_watch
    FOREIGN KEY (watch_target_id) REFERENCES user_watchlist_target(watch_target_id)
    ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='알림 발송 이력';
