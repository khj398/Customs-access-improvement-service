/* =========================================================
   customs_auction v3 patch
   - auction_item.cmdt_qty: INT → DECIMAL(12,2) (소수 수량 허용)
   - synonym_dictionary UNIQUE: (src_term, norm_term) →
     (src_term, norm_term, lang, term_type) (동일 원본어의 언어/타입 구분 허용)
   ========================================================= */

USE customs_auction;

-- 1) auction_item.cmdt_qty: INT → DECIMAL(12,2)
ALTER TABLE auction_item
  MODIFY COLUMN cmdt_qty DECIMAL(12,2) NULL COMMENT '수량(cmdtQty)';


-- 2) synonym_dictionary UNIQUE 제약 교체
--    기존: (src_term, norm_term) → 변경: (src_term, norm_term, lang, term_type)
ALTER TABLE synonym_dictionary
  DROP INDEX uq_dict_pair,
  ADD UNIQUE KEY uq_dict_pair (src_term, norm_term, lang, term_type);


-- 3) auction_item.pbac_prng_prc 인덱스 추가
--    검색 API / queries.sql #3의 가격 범위 필터가 풀스캔 발생 → 인덱스로 해결
ALTER TABLE auction_item
  ADD INDEX idx_item_price (pbac_prng_prc);


-- 4) category FK: ON DELETE SET NULL → ON DELETE RESTRICT
--    부모 카테고리 삭제 시 자식의 parent_id=NULL이 되어 의도치 않은 루트 카테고리 생성 방지
ALTER TABLE category
  DROP FOREIGN KEY fk_category_parent,
  ADD CONSTRAINT fk_category_parent
    FOREIGN KEY (parent_id) REFERENCES category(category_id)
    ON UPDATE CASCADE ON DELETE RESTRICT;


-- 5) auction_item.atnt_cmdt: CHAR(1) → ENUM('Y','N')
--    'Y'/'N' 외 값 삽입 차단 (기존 데이터에 'Y'/'N'/NULL 외 값이 없을 때만 적용)
--    확인 쿼리: SELECT DISTINCT atnt_cmdt FROM auction_item;
ALTER TABLE auction_item
  MODIFY COLUMN atnt_cmdt ENUM('Y','N') NULL COMMENT '주의물품 여부(atntCmdt)';


-- [참고] 아래 항목들은 구조상 변경 불가 또는 불필요하여 적용하지 않음
--
-- cstm_sgn NOT NULL 불가:
--   FK(auction → customs_office)가 ON DELETE SET NULL 이므로
--   NOT NULL 제약과 공존 불가. ETL 소스 데이터에 세관부호 없는 경우도 있음.
--   → ETL에서 NULL 발생 시 경고 로그로 대응.
--
-- auction_item (pbac_no, pbac_srno) 복합 인덱스 불필요:
--   PK = (pbac_no, pbac_srno, cmdt_ln_no) 이므로
--   (pbac_no), (pbac_no, pbac_srno) 프리픽스 스캔이 이미 PK로 커버됨.
--   별도 인덱스 추가 시 중복 및 write 오버헤드만 증가.
--
-- auction_item.collector_source 컬럼 불필요:
--   모든 검색 쿼리가 auction JOIN을 이미 사용 중이며
--   collector_source는 auction 단위 메타데이터임 (정규화 유지가 올바름).
