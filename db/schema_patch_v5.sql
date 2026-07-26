/* =========================================================
   customs_auction v5 patch
   - 최신 ETL 수집으로 새로 등장한 세관 좌표 시딩
     (schema_patch_v4.sql 이후 신규 데이터에 포함된 세관들)
   ========================================================= */

USE customs_auction;

UPDATE customs_office SET latitude = 37.2636000, longitude = 127.0286000 WHERE cstm_sgn = '021'; -- 수원세관
UPDATE customs_office SET latitude = 35.3350000, longitude = 129.1378000 WHERE cstm_sgn = '033'; -- 양산세관 
UPDATE customs_office SET latitude = 37.3943000, longitude = 126.9568000 WHERE cstm_sgn = '131'; -- 안양세관 

-- 확인용: 좌표 없는(NULL) 세관이 남아있는지 점검
-- SELECT cstm_sgn, cstm_name, latitude, longitude FROM customs_office WHERE latitude IS NULL;
