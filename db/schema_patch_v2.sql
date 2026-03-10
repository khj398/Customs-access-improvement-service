/* =========================================================
   customs_auction v2 patch
   - collector 출처(BUSINESS/PERSONAL/IMAGE) 반영
   - ingestion/raw payload/change event 테이블 추가
   - 큐 테이블(재수집/분류/알림) 추가
   ========================================================= */

USE customs_auction;

-- 1) auction: 수집 출처 구분 컬럼 추가
SET @col_exists := (
  SELECT COUNT(1)
  FROM information_schema.columns
  WHERE table_schema = DATABASE()
    AND table_name = 'auction'
    AND column_name = 'collector_source'
);
SET @col_sql := IF(@col_exists = 0,
  "ALTER TABLE auction ADD COLUMN collector_source VARCHAR(20) NULL COMMENT '수집 출처(BUSINESS/PERSONAL/IMAGE)' AFTER cargo_tpcd",
  'SELECT 1');
PREPARE stmt FROM @col_sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @idx_exists := (
  SELECT COUNT(1)
  FROM information_schema.statistics
  WHERE table_schema = DATABASE()
    AND table_name = 'auction'
    AND index_name = 'idx_auction_collector_source'
);
SET @idx_sql := IF(@idx_exists = 0,
  'CREATE INDEX idx_auction_collector_source ON auction (collector_source)',
  'SELECT 1');
PREPARE stmt FROM @idx_sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 2) ingestion 실행 이력
CREATE TABLE IF NOT EXISTS ingestion_run (
  ingestion_run_id BIGINT NOT NULL AUTO_INCREMENT,
  source_name VARCHAR(50) NOT NULL COMMENT '수집기 이름(unipass_list_business 등)',
  collector_source VARCHAR(20) NOT NULL DEFAULT 'BUSINESS' COMMENT 'BUSINESS/PERSONAL/IMAGE',
  started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  finished_at TIMESTAMP NULL,
  status ENUM('RUNNING','SUCCESS','FAILED','PARTIAL') NOT NULL DEFAULT 'RUNNING',
  raw_item_count INT NOT NULL DEFAULT 0,
  upsert_count INT NOT NULL DEFAULT 0,
  error_count INT NOT NULL DEFAULT 0,
  error_message VARCHAR(1000) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (ingestion_run_id),
  INDEX idx_ingestion_run_started (started_at),
  INDEX idx_ingestion_run_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='수집 실행 이력';


-- 3) 원문 payload 보관
CREATE TABLE IF NOT EXISTS raw_auction_payload (
  payload_id BIGINT NOT NULL AUTO_INCREMENT,
  ingestion_run_id BIGINT NOT NULL,
  source_name VARCHAR(50) NOT NULL,
  source_key VARCHAR(80) NOT NULL COMMENT 'pbacNo|pbacSrno|cmdtLnNo',
  payload_json JSON NOT NULL,
  payload_hash CHAR(64) NOT NULL,
  collected_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (payload_id),
  UNIQUE KEY uq_raw_payload_source_hash (source_name, source_key, payload_hash),
  INDEX idx_raw_payload_run (ingestion_run_id),
  INDEX idx_raw_payload_collected (collected_at),
  CONSTRAINT fk_raw_payload_run
    FOREIGN KEY (ingestion_run_id) REFERENCES ingestion_run(ingestion_run_id)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='원문 JSON payload 보관';


-- 4) 변경 이벤트
CREATE TABLE IF NOT EXISTS auction_item_change_event (
  event_id BIGINT NOT NULL AUTO_INCREMENT,
  pbac_no VARCHAR(20) NOT NULL,
  pbac_srno VARCHAR(20) NOT NULL,
  cmdt_ln_no VARCHAR(10) NOT NULL,
  event_type ENUM('PRICE_CHANGED','STATUS_CHANGED','NEW_ITEM','REMOVED_ITEM') NOT NULL,
  before_value_json JSON NULL,
  after_value_json JSON NULL,
  detected_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ingestion_run_id BIGINT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (event_id),
  INDEX idx_change_event_item_time (pbac_no, pbac_srno, cmdt_ln_no, detected_at),
  INDEX idx_change_event_type_time (event_type, detected_at),
  INDEX idx_change_event_run (ingestion_run_id),
  CONSTRAINT fk_change_event_item
    FOREIGN KEY (pbac_no, pbac_srno, cmdt_ln_no)
    REFERENCES auction_item(pbac_no, pbac_srno, cmdt_ln_no)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_change_event_run
    FOREIGN KEY (ingestion_run_id)
    REFERENCES ingestion_run(ingestion_run_id)
    ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='물품 변경 이벤트';


-- 5) 큐 테이블 3종 (공통 최소 컬럼 반영)
CREATE TABLE IF NOT EXISTS recollect_job_queue (
  job_id BIGINT NOT NULL AUTO_INCREMENT,
  pbac_no VARCHAR(20) NULL,
  status ENUM('PENDING','RUNNING','FAILED','DONE') NOT NULL DEFAULT 'PENDING',
  retry_count INT NOT NULL DEFAULT 0,
  next_retry_at DATETIME NULL,
  last_error VARCHAR(1000) NULL,
  payload_json JSON NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (job_id),
  INDEX idx_recollect_status_retry (status, next_retry_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='재수집 작업 큐';

CREATE TABLE IF NOT EXISTS classification_job_queue (
  job_id BIGINT NOT NULL AUTO_INCREMENT,
  pbac_no VARCHAR(20) NOT NULL,
  pbac_srno VARCHAR(20) NOT NULL,
  cmdt_ln_no VARCHAR(10) NOT NULL,
  status ENUM('PENDING','RUNNING','FAILED','DONE') NOT NULL DEFAULT 'PENDING',
  retry_count INT NOT NULL DEFAULT 0,
  next_retry_at DATETIME NULL,
  last_error VARCHAR(1000) NULL,
  payload_json JSON NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (job_id),
  INDEX idx_cls_queue_status_retry (status, next_retry_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='분류 작업 큐';

CREATE TABLE IF NOT EXISTS notification_job_queue (
  job_id BIGINT NOT NULL AUTO_INCREMENT,
  user_id BIGINT NULL,
  watch_target_id BIGINT NULL,
  event_id BIGINT NULL,
  status ENUM('PENDING','RUNNING','FAILED','DONE') NOT NULL DEFAULT 'PENDING',
  retry_count INT NOT NULL DEFAULT 0,
  next_retry_at DATETIME NULL,
  last_error VARCHAR(1000) NULL,
  payload_json JSON NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (job_id),
  INDEX idx_noti_queue_status_retry (status, next_retry_at),
  INDEX idx_noti_queue_event (event_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='알림 작업 큐';

-- 6) 이미지 source_type 표준화 예시(선택)
-- UPDATE auction_item_image
-- SET source_type = CASE
--   WHEN source_type IN ('LIST_API', 'LIST_GENERAL') THEN 'LIST_BUSINESS'
--   WHEN source_type IN ('LIST_BUSINESS') THEN 'LIST_BUSINESS'
--   WHEN source_type IN ('LIST_PERSONAL') THEN 'LIST_PERSONAL'
--   ELSE source_type
-- END;
