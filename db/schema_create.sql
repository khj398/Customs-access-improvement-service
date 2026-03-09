/* =========================================================
   Customs Auction DB - Reset & Recreate Schema
   ---------------------------------------------------------
   목적:
   - 테이블 전체 삭제 후, 정규화된 구조로 다시 생성
   - 공매(상위) / 공매물품(하위) 구조 명확화
   - 코드/기관/보관처 마스터 테이블 분리
   - (pbacNo, pbacSrno)만으로 유일하지 않은 케이스 대응:
     -> 물품 라인까지 포함해 (pbacNo, pbacSrno, cmdtLnNo)를 유일키로 설정
   ========================================================= */

-- 0) (선택) DB 이름
--    너희 DB명이 이미 정해져 있으면 아래 이름만 맞춰서 사용하면 됨.
SET@DB_NAME='customs_auction';

-- 1) FK 체크 잠시 끄기 (드롭 순서 문제 방지)
SET FOREIGN_KEY_CHECKS=0;

-- 2) 기존 테이블 삭제 (있으면)
DROPTABLE IFEXISTS auction_item;
DROPTABLE IFEXISTS auction;

DROPTABLE IFEXISTS unit_code;
DROPTABLE IFEXISTS cargo_type;
DROPTABLE IFEXISTS bonded_warehouse;
DROPTABLE IFEXISTS customs_office;

SET FOREIGN_KEY_CHECKS=1;

-- 3) DB 생성/선택
CREATE DATABASE IFNOTEXISTS customs_auction
DEFAULTCHARACTER SET utf8mb4
COLLATE utf8mb4_general_ci;

USE customs_auction;

-- =========================================================
-- A. 마스터 테이블 (반복되는 코드/기관/보관처를 분리)
-- =========================================================

/* ---------------------------------------------------------
   customs_office
   - 세관 기관 마스터
   - pbacCstmSgn(세관부호)로 식별
   - 세관명은 변경 가능성이 있어 PK로 두지 않고 UNIQUE로 관리 가능
   --------------------------------------------------------- */
CREATE TABLE IFNOTEXISTS customs_office (
  cstm_sgnVARCHAR(10)NOT NULL COMMENT'세관부호(pbacCstmSgn)',
  cstm_nameVARCHAR(100)NOT NULL COMMENT'세관명(pbacCstmSgnNm)',

  created_atTIMESTAMPNOT NULLDEFAULTCURRENT_TIMESTAMP COMMENT'생성 시각',
  updated_atTIMESTAMPNOT NULLDEFAULTCURRENT_TIMESTAMPONUPDATECURRENT_TIMESTAMP COMMENT'갱신 시각',

PRIMARY KEY (cstm_sgn),
UNIQUE KEY uq_customs_name (cstm_name)
) ENGINE=InnoDBDEFAULT CHARSET=utf8mb4 COMMENT='세관 기관 마스터';


/* ---------------------------------------------------------
   bonded_warehouse
   - 보세창고/장치장 마스터
   - snarSgn(창고부호)로 식별
   - 관할 세관은 선택적 연결(없을 수도 있으니 NULL 허용)
   --------------------------------------------------------- */
CREATE TABLE IFNOTEXISTS bonded_warehouse (
  snar_sgnVARCHAR(20)NOT NULL COMMENT'창고부호(snarSgn)',
  snar_nameVARCHAR(150)NOT NULL COMMENT'창고명(snarSgnNm)',
  cstm_sgnVARCHAR(10)NULL COMMENT'관할 세관부호(있으면 연결)',

  created_atTIMESTAMPNOT NULLDEFAULTCURRENT_TIMESTAMP COMMENT'생성 시각',
  updated_atTIMESTAMPNOT NULLDEFAULTCURRENT_TIMESTAMPONUPDATECURRENT_TIMESTAMP COMMENT'갱신 시각',

PRIMARY KEY (snar_sgn),
  INDEX idx_wh_customs (cstm_sgn),

CONSTRAINT fk_wh_customs
FOREIGN KEY (cstm_sgn)REFERENCES customs_office(cstm_sgn)
ONUPDATE CASCADEONDELETESETNULL
) ENGINE=InnoDBDEFAULT CHARSET=utf8mb4 COMMENT='보세창고 마스터';


/* ---------------------------------------------------------
   cargo_type
   - 화물 유형 마스터
   - pbacTrgtCargTpcd / pbacTrgtCargTpNm
   --------------------------------------------------------- */
CREATE TABLE IFNOTEXISTS cargo_type (
  cargo_tpcdVARCHAR(10)NOT NULL COMMENT'화물유형코드(pbacTrgtCargTpcd)',
  cargo_nameVARCHAR(50)NOT NULL COMMENT'화물유형명(pbacTrgtCargTpNm)',

  created_atTIMESTAMPNOT NULLDEFAULTCURRENT_TIMESTAMP COMMENT'생성 시각',
  updated_atTIMESTAMPNOT NULLDEFAULTCURRENT_TIMESTAMPONUPDATECURRENT_TIMESTAMP COMMENT'갱신 시각',

PRIMARY KEY (cargo_tpcd),
UNIQUE KEY uq_cargo_name (cargo_name)
) ENGINE=InnoDBDEFAULT CHARSET=utf8mb4 COMMENT='화물 유형 마스터';


/* ---------------------------------------------------------
   unit_code
   - 단위 코드 마스터 (KG, GT 등)
   - unit_kind는 수량/중량 구분용 (서비스/필터링에 도움)
   --------------------------------------------------------- */
CREATE TABLE IFNOTEXISTS unit_code (
  unit_cdVARCHAR(10)NOT NULL COMMENT'단위코드(KG, GT 등)',
  unit_nameVARCHAR(50)NULL COMMENT'단위명(선택)',
  unit_kind    ENUM('QTY','WEIGHT','OTHER')NOT NULLDEFAULT'OTHER' COMMENT'단위 종류',

  created_atTIMESTAMPNOT NULLDEFAULTCURRENT_TIMESTAMP COMMENT'생성 시각',
  updated_atTIMESTAMPNOT NULLDEFAULTCURRENT_TIMESTAMPONUPDATECURRENT_TIMESTAMP COMMENT'갱신 시각',

PRIMARY KEY (unit_cd)
) ENGINE=InnoDBDEFAULT CHARSET=utf8mb4 COMMENT='단위 코드 마스터';


-- =========================================================
-- B. 트랜잭션 테이블 (실제 공매 데이터)
-- =========================================================

/* ---------------------------------------------------------
   auction (상위 공매)
   - 공매번호(pbacNo) 단위의 "공매 이벤트"를 표현
   - 기간/기관/보관처/화물유형 등 공매 단위 메타데이터
   - auction_item(하위)들이 pbac_no로 연결됨
   --------------------------------------------------------- */
CREATE TABLE IFNOTEXISTS auction (
  pbac_noVARCHAR(20)NOT NULL COMMENT'공매번호(pbacNo) - 공매 이벤트 단위 PK',

  pbac_yyVARCHAR(4)NULL COMMENT'공매연도(pbacYy)',
  pbac_dgcntVARCHAR(10)NULL COMMENT'차수(pbacDgcnt)',
  pbac_tncntVARCHAR(10)NULL COMMENT'회차(pbacTncnt)',

  cstm_sgnVARCHAR(10)NULL COMMENT'세관부호(pbacCstmSgn)',
  snar_sgnVARCHAR(20)NULL COMMENT'창고부호(snarSgn)',
  cargo_tpcdVARCHAR(10)NULL COMMENT'화물유형코드(pbacTrgtCargTpcd)',

  pbac_strt_dttm       DATETIMENULL COMMENT'공매 시작일시(pbacStrtDttm)',
  pbac_end_dttm        DATETIMENULL COMMENT'공매 종료일시(pbacEndDttm)',

  bid_rstc_ynCHAR(1)NULL COMMENT'입찰 제한 여부(bidRstcYn) Y/N',
  elct_bid_eonCHAR(1)NULL COMMENT'전자입찰 여부(elctBidEon) Y/N',

  created_atTIMESTAMPNOT NULLDEFAULTCURRENT_TIMESTAMP COMMENT'생성 시각',
  updated_atTIMESTAMPNOT NULLDEFAULTCURRENT_TIMESTAMPONUPDATECURRENT_TIMESTAMP COMMENT'갱신 시각',

PRIMARY KEY (pbac_no),

  INDEX idx_auction_period (pbac_strt_dttm, pbac_end_dttm),
  INDEX idx_auction_customs (cstm_sgn),
  INDEX idx_auction_wh (snar_sgn),
  INDEX idx_auction_cargo (cargo_tpcd),

CONSTRAINT fk_auction_customs
FOREIGN KEY (cstm_sgn)REFERENCES customs_office(cstm_sgn)
ONUPDATE CASCADEONDELETESETNULL,

CONSTRAINT fk_auction_warehouse
FOREIGN KEY (snar_sgn)REFERENCES bonded_warehouse(snar_sgn)
ONUPDATE CASCADEONDELETESETNULL,

CONSTRAINT fk_auction_cargo
FOREIGN KEY (cargo_tpcd)REFERENCES cargo_type(cargo_tpcd)
ONUPDATE CASCADEONDELETESETNULL
) ENGINE=InnoDBDEFAULT CHARSET=utf8mb4 COMMENT='공매(상위)';


/* ---------------------------------------------------------
   auction_item (하위 물품)
   - 실제 "물품 1건"은 (pbacNo, pbacSrno)만으로 유일하지 않을 수 있음
     -> cmdtLnNo(라인번호)까지 포함해야 물품을 정확히 구분 가능
   - 따라서 PK를 (pbac_no, pbac_srno, cmdt_ln_no)로 설정
   - 수량/중량 단위 코드는 unit_code로 FK 연결
   --------------------------------------------------------- */
CREATE TABLE IFNOTEXISTS auction_item (
  pbac_noVARCHAR(20)NOT NULL COMMENT'공매번호(FK -> auction)',
  pbac_srnoVARCHAR(20)NOT NULL COMMENT'공매일련번호(pbacSrno)',
  cmdt_ln_noVARCHAR(10)NOT NULL COMMENT'물품라인번호(cmdtLnNo) - 유일키 구성요소',

  cmdt_nmVARCHAR(255)NOT NULL COMMENT'물품명(cmdtNm)',
  cmdt_qtyINTNULL COMMENT'수량(cmdtQty)',
  cmdt_qty_ut_cdVARCHAR(10)NULL COMMENT'수량단위코드(cmdtQtyUtCd)',
  cmdt_wghtDECIMAL(12,3)NULL COMMENT'중량(cmdtWght)',
  cmdt_wght_ut_cdVARCHAR(10)NULL COMMENT'중량단위코드(cmdtWghtUtCd)',

  pbac_prng_prcBIGINTNULL COMMENT'예정가격/최저입찰가(pbacPrngPrc)',

  atnt_cmdtCHAR(1)NULL COMMENT'주의물품 여부(atntCmdt) Y/N',
  atnt_cmdt_nmVARCHAR(50)NULL COMMENT'주의물품 표기(atntCmdtNm)',
  pbac_cond_cn         TEXTNULL COMMENT'공매조건(pbacCondCn)',

  created_atTIMESTAMPNOT NULLDEFAULTCURRENT_TIMESTAMP COMMENT'생성 시각',
  updated_atTIMESTAMPNOT NULLDEFAULTCURRENT_TIMESTAMPONUPDATECURRENT_TIMESTAMP COMMENT'갱신 시각',

PRIMARY KEY (pbac_no, pbac_srno, cmdt_ln_no),

  INDEX idx_item_name (cmdt_nm),
  INDEX idx_item_qty_unit (cmdt_qty_ut_cd),
  INDEX idx_item_wght_unit (cmdt_wght_ut_cd),

CONSTRAINT fk_item_auction
FOREIGN KEY (pbac_no)REFERENCES auction(pbac_no)
ONUPDATE CASCADEONDELETE CASCADE,

CONSTRAINT fk_item_qty_unit
FOREIGN KEY (cmdt_qty_ut_cd)REFERENCES unit_code(unit_cd)
ONUPDATE CASCADEONDELETESETNULL,

CONSTRAINT fk_item_wght_unit
FOREIGN KEY (cmdt_wght_ut_cd)REFERENCES unit_code(unit_cd)
ONUPDATE CASCADEONDELETESETNULL
) ENGINE=InnoDBDEFAULT CHARSET=utf8mb4 COMMENT='공매 물품(하위)';

-- 끝

/* =========================================================
   [추가 스키마] 자동 분류 + 다국어/동의어 검색 지원
   ---------------------------------------------------------
   목표:
   1) auction_item 원본을 보존한 채, 분류 결과를 별도 테이블로 관리
   2) 카테고리 트리(대/중/소/세)로 정교한 분류/필터 지원
   3) 영문 물품명 기반이라도 한글/동의어 검색 가능하도록 토큰 기반 검색 지원
   ========================================================= */

-- FK 드롭/생성 안전을 위해 (선택) 실행 전 FK 체크 끄고 켜도 됨
-- SET FOREIGN_KEY_CHECKS = 0;
-- SET FOREIGN_KEY_CHECKS = 1;


-- ---------------------------------------------------------
-- 1) category: 카테고리 트리 (대/중/소/세)
--    - parent_id로 트리 구조 표현
--    - level: 1(대)~4(세) 권장
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS category (
  category_id BIGINT NOT NULL AUTO_INCREMENT COMMENT '카테고리 ID',
  parent_id   BIGINT NULL COMMENT '상위 카테고리 ID (NULL이면 최상위)',
  level       TINYINT NOT NULL COMMENT '카테고리 레벨(1:대,2:중,3:소,4:세)',
  name_ko     VARCHAR(100) NOT NULL COMMENT '카테고리 한글명',
  name_en     VARCHAR(100) NULL COMMENT '카테고리 영문명(선택)',
  is_active   TINYINT NOT NULL DEFAULT 1 COMMENT '사용 여부(1:사용,0:비활성)',

  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '생성 시각',
  updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '갱신 시각',

  PRIMARY KEY (category_id),

  -- 같은 부모 아래에서 동일 한글명 중복 방지
  UNIQUE KEY uq_category_parent_ko (parent_id, name_ko),

  INDEX idx_category_parent (parent_id),
  INDEX idx_category_level (level),

  CONSTRAINT fk_category_parent
    FOREIGN KEY (parent_id) REFERENCES category(category_id)
    ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='자동분류용 카테고리 트리(대/중/소/세)';


-- ---------------------------------------------------------
-- 2) item_classification: 물품별 분류 결과
--    - auction_item의 원본 키(3컬럼)와 1:1 (최신/대표 분류 1개)
--    - 모델을 바꿔도 재분류 가능(원본 보존)
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS item_classification (
  pbac_no     VARCHAR(20) NOT NULL COMMENT '공매번호',
  pbac_srno   VARCHAR(20) NOT NULL COMMENT '공매일련번호',
  cmdt_ln_no  VARCHAR(10) NOT NULL COMMENT '물품라인번호',

  category_id BIGINT NOT NULL COMMENT '분류된 카테고리 ID',
  model_name  VARCHAR(50) NOT NULL COMMENT '분류 모델명(rule/bert/llm/hybrid 등)',
  model_ver   VARCHAR(30) NULL COMMENT '모델 버전(선택)',
  confidence  DECIMAL(5,4) NULL COMMENT '신뢰도(0~1)',
  rationale   TEXT NULL COMMENT '분류 근거(키워드/설명/로그)',

  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '생성 시각',
  updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '갱신 시각',

  PRIMARY KEY (pbac_no, pbac_srno, cmdt_ln_no),

  INDEX idx_cls_category (category_id),
  INDEX idx_cls_model (model_name),

  CONSTRAINT fk_cls_item
    FOREIGN KEY (pbac_no, pbac_srno, cmdt_ln_no)
    REFERENCES auction_item(pbac_no, pbac_srno, cmdt_ln_no)
    ON UPDATE CASCADE ON DELETE CASCADE,

  CONSTRAINT fk_cls_category
    FOREIGN KEY (category_id) REFERENCES category(category_id)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='물품별 자동분류 결과(대표 1개)';


-- ---------------------------------------------------------
-- 3) synonym_dictionary: 동의어/번역 사전(관리용)
--    - 예: WINE -> 와인/술/주류, BATTERY -> 배터리/전지
--    - 검색 토큰 생성 또는 분류 근거로 활용
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS synonym_dictionary (
  dict_id      BIGINT NOT NULL AUTO_INCREMENT COMMENT '사전 ID',
  src_term     VARCHAR(100) NOT NULL COMMENT '원본 용어(영문/한글/숫자 포함 가능)',
  norm_term    VARCHAR(100) NOT NULL COMMENT '정규화 용어(검색에 쓰는 대표어)',
  lang         ENUM('EN','KO','MIX') NOT NULL DEFAULT 'MIX' COMMENT '용어 언어',
  term_type    ENUM('SYN','TRANSLATION','BRAND','MODEL','CATEGORY_HINT') NOT NULL DEFAULT 'SYN'
               COMMENT '동의어/번역/브랜드/모델/카테고리 힌트',
  weight       DECIMAL(5,2) NOT NULL DEFAULT 1.00 COMMENT '가중치(중요도)',
  is_active    TINYINT NOT NULL DEFAULT 1 COMMENT '사용 여부',

  created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '생성 시각',
  updated_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '갱신 시각',

  PRIMARY KEY (dict_id),

  -- 같은 src_term이 여러 norm_term으로 매핑될 수 있으므로 복합 유니크
  UNIQUE KEY uq_dict_pair (src_term, norm_term),

  INDEX idx_dict_src (src_term),
  INDEX idx_dict_norm (norm_term),
  INDEX idx_dict_type (term_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='동의어/번역 사전(검색/분류 보조)';


-- ---------------------------------------------------------
-- 4) item_search_token: 물품 검색 토큰 (검색 최적화)
--    - 토큰은 여러 개일 수 있으므로 (item + token) 복합 PK
--    - token_type: RAW(원문 토큰), KO(한글화), SYN(사전 기반 동의어), CATEGORY(카테고리 토큰)
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS item_search_token (
  pbac_no     VARCHAR(20) NOT NULL COMMENT '공매번호',
  pbac_srno   VARCHAR(20) NOT NULL COMMENT '공매일련번호',
  cmdt_ln_no  VARCHAR(10) NOT NULL COMMENT '물품라인번호',

  token       VARCHAR(100) NOT NULL COMMENT '검색 토큰(예: WINE, 와인, 술, 주류 등)',
  token_type  ENUM('RAW','KO','SYN','CATEGORY') NOT NULL COMMENT '토큰 유형',
  weight      DECIMAL(5,2) NOT NULL DEFAULT 1.00 COMMENT '가중치(랭킹용)',
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '생성 시각',

  PRIMARY KEY (pbac_no, pbac_srno, cmdt_ln_no, token),

  INDEX idx_token (token),
  INDEX idx_token_type (token_type),
  INDEX idx_token_weight (weight),

  CONSTRAINT fk_token_item
    FOREIGN KEY (pbac_no, pbac_srno, cmdt_ln_no)
    REFERENCES auction_item(pbac_no, pbac_srno, cmdt_ln_no)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='물품 검색 토큰(다국어/동의어 검색 지원)';

/* ---------------------------------------------------------
   7) auction_item_image: 물품별 이미지 URL 메타
   - 수집 원본(JSON)의 image_urls 또는 추후 상세 크롤링 결과를 저장
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS auction_item_image (
  pbac_no      VARCHAR(20) NOT NULL COMMENT '공매번호',
  pbac_srno    VARCHAR(20) NOT NULL COMMENT '공매일련번호',
  cmdt_ln_no   VARCHAR(10) NOT NULL COMMENT '물품라인번호',
  image_seq    INT NOT NULL DEFAULT 1 COMMENT '이미지 순번(1부터)',
  image_url    TEXT NOT NULL COMMENT '이미지 URL',
  source_type  VARCHAR(20) NOT NULL DEFAULT 'LIST_API' COMMENT '수집 출처(LIST_API/DETAIL_PAGE 등)',
  created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '생성 시각',
  updated_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '갱신 시각',

  PRIMARY KEY (pbac_no, pbac_srno, cmdt_ln_no, image_seq),
  INDEX idx_item_image_key (pbac_no, pbac_srno, cmdt_ln_no),

  CONSTRAINT fk_item_image_item
    FOREIGN KEY (pbac_no, pbac_srno, cmdt_ln_no)
    REFERENCES auction_item(pbac_no, pbac_srno, cmdt_ln_no)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='물품별 이미지 URL 메타';

/* ---------------------------------------------------------
   8) classification_job_queue: LLM 분류 재처리 큐
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS classification_job_queue (
  job_id         BIGINT NOT NULL AUTO_INCREMENT COMMENT '큐 작업 ID',
  pbac_no        VARCHAR(20) NOT NULL COMMENT '공매번호',
  pbac_srno      VARCHAR(20) NOT NULL COMMENT '공매일련번호',
  cmdt_ln_no     VARCHAR(10) NOT NULL COMMENT '물품라인번호',

  status         ENUM('PENDING','RUNNING','DONE','FAILED') NOT NULL DEFAULT 'PENDING' COMMENT '작업 상태',
  priority       INT NOT NULL DEFAULT 100 COMMENT '작업 우선순위(낮을수록 우선)',
  retries        INT NOT NULL DEFAULT 0 COMMENT '재시도 횟수',
  max_retries    INT NOT NULL DEFAULT 3 COMMENT '최대 재시도 횟수',
  last_error     TEXT NULL COMMENT '마지막 오류 메시지',

  lock_owner     VARCHAR(100) NULL COMMENT '워커 식별자',
  locked_at      DATETIME NULL COMMENT '작업 잠금 시각',
  processed_at   DATETIME NULL COMMENT '완료 시각',

  created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '생성 시각',
  updated_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '갱신 시각',

  PRIMARY KEY (job_id),
  UNIQUE KEY uq_cls_queue_item (pbac_no, pbac_srno, cmdt_ln_no),
  INDEX idx_cls_queue_status_priority (status, priority, created_at),

  CONSTRAINT fk_cls_queue_item
    FOREIGN KEY (pbac_no, pbac_srno, cmdt_ln_no)
    REFERENCES auction_item(pbac_no, pbac_srno, cmdt_ln_no)
    ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='LLM 분류 재처리 큐';

/* ---------------------------------------------------------
   9) llm_classification_cache: 동일 물품명 캐시
   --------------------------------------------------------- */
CREATE TABLE IF NOT EXISTS llm_classification_cache (
  cache_key      CHAR(64) NOT NULL COMMENT '정규화 물품명의 SHA256',
  cmdt_nm_norm   VARCHAR(500) NOT NULL COMMENT '정규화 물품명',
  category_id    BIGINT NOT NULL COMMENT '분류 카테고리 ID',
  category_path  VARCHAR(300) NOT NULL COMMENT '카테고리 경로(>)',
  confidence     DECIMAL(5,4) NULL COMMENT '모델 신뢰도',
  rationale      TEXT NULL COMMENT '모델 분류 근거',
  model_name     VARCHAR(50) NOT NULL COMMENT '모델명',
  model_ver      VARCHAR(30) NULL COMMENT '모델 버전',
  created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '생성 시각',
  updated_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '갱신 시각',

  PRIMARY KEY (cache_key),
  INDEX idx_llm_cache_category (category_id),

  CONSTRAINT fk_llm_cache_category
    FOREIGN KEY (category_id) REFERENCES category(category_id)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='LLM 분류 캐시';
