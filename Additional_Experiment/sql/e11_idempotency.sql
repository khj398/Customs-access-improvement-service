-- =========================================================
-- E11. 파이프라인 멱등성 · 처리시간 검증  [선택]  -> 논문 3.2절 본문
-- 실험계획서 6장 E11 의 SQL 원문 (수동 실행용)
-- 자동 실행: python Additional_Experiment/scripts/e11_idempotency.py --run-etl
-- =========================================================

-- (1) ETL 실행 전 건수
SELECT (SELECT COUNT(*) FROM auction)      AS 공매수,
       (SELECT COUNT(*) FROM auction_item) AS 물품수;

-- (2) ETL 을 연속 2회 실행
--     python etl/load_unipass_to_mysql.py && python etl/load_unipass_to_mysql.py

-- (3) 실행 후 건수가 동일한지 확인 (복합 PK + ON DUPLICATE KEY UPDATE 의 멱등성)
SELECT (SELECT COUNT(*) FROM auction)      AS 공매수,
       (SELECT COUNT(*) FROM auction_item) AS 물품수;

-- (4) ingestion_run 이력 비교
SELECT ingestion_run_id, source_name, status, raw_item_count, upsert_count,
       TIMESTAMPDIFF(SECOND, started_at, finished_at) AS 소요초
FROM ingestion_run ORDER BY ingestion_run_id DESC LIMIT 4;

-- 주의: 이 실험만 DB 쓰기가 발생한다. 스냅샷 고정(5.2)과 DB 백업을 마친 뒤 수행할 것.
