/* =========================================================
   feedback.sql
   - ETL / 분류 / 스키마 패치 이후 DB 상태를 점검하는 쿼리 모음
   - 실행 시점: ETL 또는 build_classification.py 실행 직후, 스키마 패치 적용 직후
   - 각 섹션 앞 주석에 "왜 체크하는지"를 상세히 기재함
   ========================================================= */

USE customs_auction;


/* =========================================================
   0) 전체 상태 요약
   ---------------------------------------------------------
   [왜 체크하는가]
   ETL과 분류 스크립트가 정상 종료해도 실제로 DB에 데이터가
   들어갔는지는 별도로 확인해야 한다. 두 스크립트가 예외 없이
   끝났더라도 트랜잭션 rollback, 빈 입력 파일, 환경변수 오설정
   등으로 0건이 적재될 수 있다.
   - classification_rows = 0 → 분류 스크립트가 실행되지 않았거나
     auction_item 자체가 비어있음
   - token_rows = 0         → 검색 토큰이 생성되지 않아 검색 불가
   ========================================================= */
SELECT COUNT(*) AS classification_rows FROM item_classification;
SELECT COUNT(*) AS token_rows FROM item_search_token;

/* ---------------------------------------------------------
   토큰 타입별 생성 현황
   [왜 체크하는가]
   build_classification.py는 물품 1건당 RAW / SYN / CATEGORY
   세 종류 토큰을 생성한다.
   - RAW만 있고 SYN·CATEGORY가 0 → 동의어 사전(synonym_dictionary)이
     비어있거나 카테고리 seed가 없는 상태
   - SYN은 있는데 CATEGORY가 0 → 분류는 됐으나 카테고리 트리 조회에
     실패한 것으로, category 테이블 seed 누락을 의심
   세 타입이 고르게 분포하는지 확인해 검색 품질을 사전에 파악한다.
   --------------------------------------------------------- */
SELECT token_type, COUNT(*) AS cnt
FROM item_search_token
GROUP BY token_type
ORDER BY cnt DESC;

/* ---------------------------------------------------------
   카테고리별 분류 건수 (상위 20)
   [왜 체크하는가]
   분류 결과가 특정 카테고리에 과도하게 몰려 있으면 Rule/사전
   커버리지가 편중된 것이다.
   예) '기타 > 미분류 > 기타'가 압도적으로 많다면 Rule 45개만으로
   분류 가능한 품목이 적다는 신호 → Rule 또는 동의어 사전 보강 필요.
   GROUP BY를 category_id로 하는 이유: 서로 다른 레벨에 동일한
   name_ko('기타' 등)가 존재하면 name_ko만으로 그루핑 시 별개
   카테고리가 합산되어 수치가 왜곡된다.
   --------------------------------------------------------- */
SELECT c.category_id, c.name_ko AS category, COUNT(*) AS cnt
FROM item_classification ic
JOIN category c ON c.category_id = ic.category_id
GROUP BY c.category_id, c.name_ko
ORDER BY cnt DESC
LIMIT 20;

/* ---------------------------------------------------------
   분류 결과 샘플 (최근 갱신 30건)
   [왜 체크하는가]
   숫자만으로는 분류 품질을 파악하기 어렵다. 실제 물품명(cmdt_nm)과
   분류된 카테고리를 눈으로 대조해 "이 물품이 이 카테고리에 들어가는
   게 맞는가"를 직관적으로 검토한다.
   - model_name: rule인지 openai인지 확인 (rule만 쓸 경우 openai 행 없어야 함)
   - confidence: 0.55 근처가 많으면 fallback이거나 매칭 키워드가 적은 것
   - rationale: 왜 이 카테고리로 분류됐는지 근거 텍스트
   --------------------------------------------------------- */
SELECT
  ai.cmdt_nm,
  ic.model_name,
  ic.model_ver,
  ic.confidence,
  c.name_ko AS category_leaf,
  ic.rationale,
  ic.updated_at
FROM item_classification ic
JOIN auction_item ai
  ON ai.pbac_no=ic.pbac_no AND ai.pbac_srno=ic.pbac_srno AND ai.cmdt_ln_no=ic.cmdt_ln_no
JOIN category c ON c.category_id = ic.category_id
ORDER BY ic.updated_at DESC
LIMIT 30;


/* =========================================================
   0-1) 특정 토큰 검색 토큰 존재 여부
   ---------------------------------------------------------
   [왜 체크하는가]
   동의어 사전(synonym_dictionary)과 분류 파이프라인이 정상 동작한다면
   영문 원문 토큰(WINE)을 기반으로 한국어 동의어(와인, 술, 주류)와
   카테고리 토큰이 함께 생성되어야 한다.
   이 쿼리는 특정 토큰이 실제로 item_search_token에 존재하는지 확인해
   "WINE이 들어간 물품을 '와인'으로 검색했을 때 결과가 나오는가"를
   사전에 보장한다.
   결과가 0건이면 동의어 사전 seed 누락 또는 분류 파이프라인 미실행.
   토큰을 바꿔가며 원하는 품목이 검색 가능한지 검증한다.
   ========================================================= */
SELECT ai.cmdt_nm, t.token, t.token_type
FROM item_search_token t
JOIN auction_item ai
  ON ai.pbac_no=t.pbac_no AND ai.pbac_srno=t.pbac_srno AND ai.cmdt_ln_no=t.cmdt_ln_no
WHERE t.token IN ('와인','술','주류','WINE')
ORDER BY ai.cmdt_nm, FIELD(t.token_type,'RAW','SYN','CATEGORY'), t.token;


/* =========================================================
   1) fallback(미분류) 분석
   ---------------------------------------------------------
   [왜 체크하는가]
   build_classification.py는 Rule 매칭에도 실패하고 OpenAI도 없거나
   실패한 경우 '기타 > 미분류 > 기타'로 분류한다(fallback).
   이 항목들은 검색에서 카테고리 필터로 걸러지지 않고, 카테고리 토큰
   품질도 낮아 검색 정확도에 직접 영향을 준다.
   fallback 건수와 내용을 확인해 Rule 또는 동의어 사전의 보강
   우선순위를 결정한다.
   ========================================================= */
SELECT
  ai.cmdt_nm,
  ic.confidence,
  ic.rationale,
  ic.updated_at
FROM item_classification ic
JOIN auction_item ai
  ON ai.pbac_no=ic.pbac_no AND ai.pbac_srno=ic.pbac_srno AND ai.cmdt_ln_no=ic.cmdt_ln_no
JOIN category c3 ON c3.category_id = ic.category_id          -- leaf
JOIN category c2 ON c2.category_id = c3.parent_id
JOIN category c1 ON c1.category_id = c2.parent_id
WHERE c1.name_ko='기타' AND c2.name_ko='미분류' AND c3.name_ko='기타'
ORDER BY ai.cmdt_nm;

/* ---------------------------------------------------------
   1-1) fallback 항목에서 자주 등장하는 RAW 토큰 TOP 20
   [왜 체크하는가]
   fallback으로 떨어진 물품명에서 자주 등장하는 영문 토큰이
   Rule이나 동의어 사전에 없기 때문에 분류에 실패한 것이다.
   이 목록은 "어떤 키워드를 rules.yaml 또는 synonym_dictionary에
   추가하면 fallback을 줄일 수 있는가"의 직접적인 우선순위 가이드다.
   상위 토큰부터 Rule을 추가하거나 동의어를 등록하면 분류율이 오른다.
   --------------------------------------------------------- */
SELECT t.token, COUNT(*) AS cnt
FROM item_classification ic
JOIN item_search_token t
  ON t.pbac_no=ic.pbac_no AND t.pbac_srno=ic.pbac_srno AND t.cmdt_ln_no=ic.cmdt_ln_no
JOIN category c3 ON c3.category_id = ic.category_id
JOIN category c2 ON c2.category_id = c3.parent_id
JOIN category c1 ON c1.category_id = c2.parent_id
WHERE c1.name_ko='기타' AND c2.name_ko='미분류' AND c3.name_ko='기타'
  AND t.token_type='RAW'
GROUP BY t.token
ORDER BY cnt DESC
LIMIT 20;

/* ---------------------------------------------------------
   1-2) fallback인데 특정 RAW 토큰이 포함된 항목 찾기 (디버깅용)
   [왜 체크하는가]
   예를 들어 'GAUGE'라는 키워드가 rules.yaml에 등록되어 있는데도
   fallback으로 떨어지는 물품이 있다면 Rule 조건이 잘못 작성되었거나
   (keywords_all 조건이 너무 엄격하거나) 토큰 전처리 중 변환이
   안 된 것이다.
   1-1에서 발견한 키워드를 하나씩 이 쿼리에 입력해 실제 물품명을
   확인하고 Rule 수정 여부를 판단한다.
   --------------------------------------------------------- */
-- 아래 'GAUGE' 자리를 바꿔가며 확인 (예: 'PUMP', 'VALVE', 'CABLE' 등)
SELECT ai.cmdt_nm
FROM item_classification ic
JOIN auction_item ai
  ON ai.pbac_no=ic.pbac_no AND ai.pbac_srno=ic.pbac_srno AND ai.cmdt_ln_no=ic.cmdt_ln_no
JOIN item_search_token t
  ON t.pbac_no=ic.pbac_no AND t.pbac_srno=ic.pbac_srno AND t.cmdt_ln_no=ic.cmdt_ln_no
JOIN category c3 ON c3.category_id = ic.category_id
JOIN category c2 ON c2.category_id = c3.parent_id
JOIN category c1 ON c1.category_id = c2.parent_id
WHERE c1.name_ko='기타' AND c2.name_ko='미분류' AND c3.name_ko='기타'
  AND t.token_type='RAW'
  AND t.token='GAUGE'
ORDER BY ai.cmdt_nm;


/* =========================================================
   2) synonym_dictionary(동의어 사전) 확인
   ---------------------------------------------------------
   [왜 체크하는가]
   동의어 사전은 영문 물품명을 한국어로 검색 가능하게 만드는 핵심
   구성요소다. term_type별 건수를 보면 사전이 고르게 구축되어 있는지
   파악된다.
   - TRANSLATION만 많고 SYN이 적으면: 번역은 되지만 동의어 확장이
     부족해 '포도주'로 검색해도 와인이 안 나올 수 있음
   - CATEGORY_HINT가 전혀 없으면: 카테고리 경로를 힌트로 쓰는
     확장 검색이 동작하지 않음
   특정 키워드(WINE, BATTERY 등)의 실제 등록 내용을 확인해
   원하는 한국어 토큰이 사전에 있는지 직접 검증한다.
   ========================================================= */
SELECT term_type, COUNT(*) AS cnt
FROM synonym_dictionary
GROUP BY term_type
ORDER BY cnt DESC;

/* ---------------------------------------------------------
   특정 원본어의 사전 등록 내용 전체 확인
   [왜 체크하는가]
   위 집계만으로는 실제로 어떤 한국어 표현이 연결되어 있는지 알 수 없다.
   검색 테스트 전에 대표 키워드(WINE, GAUGE 등)의 norm_term, term_type,
   weight를 직접 확인해 "이 키워드로 검색하면 어떤 토큰이 매칭되는가"를
   파악한다. weight가 낮으면 검색 결과 순위가 뒤로 밀린다.
   --------------------------------------------------------- */
SELECT *
FROM synonym_dictionary
WHERE src_term IN ('WINE','GAUGE','BATTERY','PUMP','VALVE')
ORDER BY src_term, norm_term;


/* =========================================================
   3) 전체 물품 확인
   ========================================================= */

/* ---------------------------------------------------------
   전체 물품(라인) 한 번에 보기
   [왜 체크하는가]
   물품명, 수량, 중량, 가격, 세관, 창고, 분류 결과, 카테고리 경로 토큰,
   동의어 토큰 샘플을 한 행으로 조회해 데이터 전체 흐름을 한눈에 검토한다.
   - category_path_token이 NULL이면: 분류가 안 됐거나 CATEGORY 토큰 미생성
   - syn_tokens_sample이 NULL이면: 동의어 사전에 해당 물품 키워드가 없음
   - customs_office / bonded_warehouse가 NULL이면: 세관/창고 마스터 적재 누락
   auction에는 pbac_srno가 없으므로 pbac_no로만 JOIN하고 srno는
   auction_item에서 가져온다.
   --------------------------------------------------------- */
SELECT
  ai.pbac_no,
  ai.pbac_srno,
  ai.cmdt_ln_no,

  DATE_FORMAT(a.pbac_strt_dttm, '%Y-%m-%d %H:%i') AS pbac_start,
  DATE_FORMAT(a.pbac_end_dttm,  '%Y-%m-%d %H:%i') AS pbac_end,
  co.cstm_name AS customs_office,
  bw.snar_name AS bonded_warehouse,
  ct.cargo_name AS cargo_type,

  ai.cmdt_nm,
  ai.cmdt_qty,
  ai.cmdt_qty_ut_cd,
  ai.cmdt_wght,
  ai.cmdt_wght_ut_cd,
  ai.pbac_prng_prc,

  c.name_ko AS category_leaf,
  ic.model_name,
  ic.confidence,
  ic.rationale,

  MAX(CASE
        WHEN t.token_type='CATEGORY' AND t.token LIKE '%>%' THEN t.token
      END) AS category_path_token,

  SUBSTRING_INDEX(
    GROUP_CONCAT(DISTINCT CASE WHEN t.token_type='SYN' THEN t.token END
                 ORDER BY t.token SEPARATOR ', '),
    ', ',
    15
  ) AS syn_tokens_sample

FROM auction_item ai
JOIN auction a
  ON a.pbac_no = ai.pbac_no
LEFT JOIN customs_office co
  ON co.cstm_sgn = a.cstm_sgn
LEFT JOIN bonded_warehouse bw
  ON bw.snar_sgn = a.snar_sgn
LEFT JOIN cargo_type ct
  ON ct.cargo_tpcd = a.cargo_tpcd
LEFT JOIN item_classification ic
  ON ic.pbac_no=ai.pbac_no AND ic.pbac_srno=ai.pbac_srno AND ic.cmdt_ln_no=ai.cmdt_ln_no
LEFT JOIN category c
  ON c.category_id = ic.category_id
LEFT JOIN item_search_token t
  ON t.pbac_no=ai.pbac_no AND t.pbac_srno=ai.pbac_srno AND t.cmdt_ln_no=ai.cmdt_ln_no

GROUP BY
  ai.pbac_no, ai.pbac_srno, ai.cmdt_ln_no,
  a.pbac_strt_dttm, a.pbac_end_dttm,
  co.cstm_name, bw.snar_name, ct.cargo_name,
  ai.cmdt_nm, ai.cmdt_qty, ai.cmdt_qty_ut_cd, ai.cmdt_wght, ai.cmdt_wght_ut_cd, ai.pbac_prng_prc,
  c.name_ko, ic.model_name, ic.confidence, ic.rationale

ORDER BY
  ai.pbac_no, ai.pbac_srno, ai.cmdt_ln_no;

/* ---------------------------------------------------------
   pbac_no당 pbac_srno 개수 확인
   [왜 체크하는가]
   공매번호(pbac_no) 하나에 여러 일련번호(pbac_srno)가 붙을 수 있는지
   실제 데이터로 확인한다.
   - srno_cnt > 1인 공매가 많다면 "(pbac_no, pbac_srno)"가 공매 내
     중간 그룹핑 단위로 실제 사용되고 있는 것
   - srno_cnt가 항상 1이면 pbac_no만으로 공매를 특정할 수 있어
     현재 auction 테이블 설계(PK=pbac_no)가 적합하다는 확인
   --------------------------------------------------------- */
SELECT pbac_no, COUNT(DISTINCT pbac_srno) AS srno_cnt, COUNT(*) AS line_cnt
FROM auction_item
GROUP BY pbac_no
ORDER BY srno_cnt DESC, line_cnt DESC;

/* ---------------------------------------------------------
   (A) 공매(pbac_no) 요약: 라인 수 / 기간 / 기관 / 보관처
   [왜 체크하는가]
   어느 세관·창고에서 얼마나 많은 물품이 나오는지 파악한다.
   line_cnt가 유독 많은 공매번호는 대량 경매로, 분류 파이프라인
   실행 시간에 영향을 주므로 사전에 인지해두는 것이 유용하다.
   customs_office / bonded_warehouse가 NULL로 나오면 ETL 당시
   해당 공매의 세관/창고 정보가 없었던 것 → 원천 데이터 품질 문제.
   --------------------------------------------------------- */
SELECT
  a.pbac_no,
  COUNT(*) AS line_cnt,
  DATE_FORMAT(a.pbac_strt_dttm, '%Y-%m-%d %H:%i') AS pbac_start,
  DATE_FORMAT(a.pbac_end_dttm,  '%Y-%m-%d %H:%i') AS pbac_end,
  co.cstm_name AS customs_office,
  bw.snar_name AS bonded_warehouse,
  ct.cargo_name AS cargo_type
FROM auction a
JOIN auction_item ai
  ON ai.pbac_no=a.pbac_no
LEFT JOIN customs_office co ON co.cstm_sgn=a.cstm_sgn
LEFT JOIN bonded_warehouse bw ON bw.snar_sgn=a.snar_sgn
LEFT JOIN cargo_type ct ON ct.cargo_tpcd=a.cargo_tpcd
GROUP BY a.pbac_no, a.pbac_strt_dttm, a.pbac_end_dttm, co.cstm_name, bw.snar_name, ct.cargo_name
ORDER BY line_cnt DESC, a.pbac_no;

/* ---------------------------------------------------------
   (B) 전체 물품(라인) 상세
   [왜 체크하는가]
   위 (A) 요약에서 이상이 발견된 공매번호의 실제 물품 내용을
   라인 단위로 확인한다. (A)가 집계 수준이라면 (B)는 원본 데이터
   수준의 드릴다운 뷰다. 카테고리 경로 토큰과 SYN 토큰 샘플을
   함께 확인해 분류·검색 파이프라인이 라인별로 정상 동작했는지 본다.
   --------------------------------------------------------- */
SELECT
  ai.pbac_no,
  ai.pbac_srno,
  ai.cmdt_ln_no,

  DATE_FORMAT(a.pbac_strt_dttm, '%Y-%m-%d %H:%i') AS pbac_start,
  DATE_FORMAT(a.pbac_end_dttm,  '%Y-%m-%d %H:%i') AS pbac_end,
  co.cstm_name AS customs_office,
  bw.snar_name AS bonded_warehouse,
  ct.cargo_name AS cargo_type,

  ai.cmdt_nm,
  ai.cmdt_qty,
  ai.cmdt_qty_ut_cd,
  ai.cmdt_wght,
  ai.cmdt_wght_ut_cd,
  ai.pbac_prng_prc,

  c.name_ko AS category_leaf,
  ic.model_name,
  ic.confidence,
  ic.rationale,

  MAX(CASE
        WHEN t.token_type='CATEGORY' AND t.token LIKE '%>%' THEN t.token
      END) AS category_path_token,

  SUBSTRING_INDEX(
    GROUP_CONCAT(DISTINCT CASE WHEN t.token_type='SYN' THEN t.token END
                 ORDER BY t.token SEPARATOR ', '),
    ', ',
    15
  ) AS syn_tokens_sample

FROM auction_item ai
JOIN auction a
  ON a.pbac_no = ai.pbac_no
LEFT JOIN customs_office co
  ON co.cstm_sgn = a.cstm_sgn
LEFT JOIN bonded_warehouse bw
  ON bw.snar_sgn = a.snar_sgn
LEFT JOIN cargo_type ct
  ON ct.cargo_tpcd = a.cargo_tpcd
LEFT JOIN item_classification ic
  ON ic.pbac_no=ai.pbac_no AND ic.pbac_srno=ai.pbac_srno AND ic.cmdt_ln_no=ai.cmdt_ln_no
LEFT JOIN category c
  ON c.category_id = ic.category_id
LEFT JOIN item_search_token t
  ON t.pbac_no=ai.pbac_no AND t.pbac_srno=ai.pbac_srno AND t.cmdt_ln_no=ai.cmdt_ln_no

GROUP BY
  ai.pbac_no, ai.pbac_srno, ai.cmdt_ln_no,
  a.pbac_strt_dttm, a.pbac_end_dttm,
  co.cstm_name, bw.snar_name, ct.cargo_name,
  ai.cmdt_nm, ai.cmdt_qty, ai.cmdt_qty_ut_cd, ai.cmdt_wght, ai.cmdt_wght_ut_cd, ai.pbac_prng_prc,
  c.name_ko, ic.model_name, ic.confidence, ic.rationale

ORDER BY
  ai.pbac_no, ai.cmdt_ln_no;


/* =========================================================
   4) 검토용 VIEW
   ---------------------------------------------------------
   [왜 체크하는가]
   섹션 3의 쿼리는 길고 JOIN이 많아 반복 실행이 번거롭다.
   vw_item_classification_review는 이를 미리 정의해두어
   SELECT * FROM vw_... 한 줄로 같은 내용을 조회할 수 있게 한다.
   - 예시 1: 최신순 전체 검토 → 분류 파이프라인 직후 빠른 확인용
   - 예시 2: fallback만 보기 → Rule/사전 보강 우선순위 파악
   - 예시 3: OpenAI 분류만 보기 → LLM 분류 품질 집중 점검
   ========================================================= */
DROP VIEW IF EXISTS vw_item_classification_review;

CREATE VIEW vw_item_classification_review AS
SELECT
  ai.pbac_no,
  ai.pbac_srno,
  ai.cmdt_ln_no,
  ai.cmdt_nm,
  ic.model_name,
  ic.model_ver,
  ic.confidence,
  ic.rationale,
  c1.name_ko AS category_lv1,
  c2.name_ko AS category_lv2,
  c3.name_ko AS category_leaf,
  MAX(CASE WHEN t.token_type='CATEGORY' AND t.token LIKE '%>%' THEN t.token END) AS category_path_token,
  SUBSTRING_INDEX(
    GROUP_CONCAT(DISTINCT CASE WHEN t.token_type='SYN' THEN t.token END ORDER BY t.token SEPARATOR ', '),
    ', ',
    20
  ) AS syn_tokens_sample,
  ic.updated_at
FROM auction_item ai
LEFT JOIN item_classification ic
  ON ic.pbac_no=ai.pbac_no AND ic.pbac_srno=ai.pbac_srno AND ic.cmdt_ln_no=ai.cmdt_ln_no
LEFT JOIN category c3 ON c3.category_id = ic.category_id
LEFT JOIN category c2 ON c2.category_id = c3.parent_id
LEFT JOIN category c1 ON c1.category_id = c2.parent_id
LEFT JOIN item_search_token t
  ON t.pbac_no=ai.pbac_no AND t.pbac_srno=ai.pbac_srno AND t.cmdt_ln_no=ai.cmdt_ln_no
GROUP BY
  ai.pbac_no, ai.pbac_srno, ai.cmdt_ln_no, ai.cmdt_nm,
  ic.model_name, ic.model_ver, ic.confidence, ic.rationale,
  c1.name_ko, c2.name_ko, c3.name_ko, ic.updated_at;

-- 예시 1) 전체를 최신순으로 검토
SELECT *
FROM vw_item_classification_review
ORDER BY updated_at DESC, pbac_no, pbac_srno, cmdt_ln_no;

-- 예시 2) fallback만 보기
SELECT *
FROM vw_item_classification_review
WHERE category_lv1='기타' AND category_lv2='미분류' AND category_leaf='기타'
ORDER BY pbac_no, pbac_srno, cmdt_ln_no;

-- 예시 3) OpenAI 분류만 보기
SELECT *
FROM vw_item_classification_review
WHERE model_name='openai'
ORDER BY updated_at DESC;


/* =========================================================
   sanity check 3종 (빠른 최종 확인)
   ---------------------------------------------------------
   [왜 체크하는가]
   분류 파이프라인 실행 후 가장 기본적인 세 가지 이상 유무를 수치로
   빠르게 확인한다. 세 쿼리 모두 0이 나와야 정상이다.

   1) missing_class: auction_item이 있는데 item_classification이 없는 건수
      → 분류가 누락된 물품이 있으면 검색 카테고리 필터에서 제외됨
      → 원인: build_classification.py 미실행 또는 도중 에러로 일부 누락

   2) missing_tokens: auction_item이 있는데 item_search_token이 없는 건수
      → 토큰이 없으면 해당 물품은 키워드 검색에서 아예 노출되지 않음
      → 원인: 분류는 됐지만 토큰 생성 단계에서 예외 발생

   3) bad_category_tokens: CATEGORY 토큰으로 '기타' 또는 '미분류'가
      저장된 건수
      → 분류 코드의 CATEGORY_STOPWORDS 필터가 정상 동작하면 0이어야 함
      → 이 값이 있으면 카테고리 검색 시 노이즈 토큰으로 작동해
         관련 없는 물품이 함께 검색됨
   ========================================================= */
SELECT COUNT(*) AS missing_class
FROM auction_item ai
LEFT JOIN item_classification ic
  ON ic.pbac_no=ai.pbac_no AND ic.pbac_srno=ai.pbac_srno AND ic.cmdt_ln_no=ai.cmdt_ln_no
WHERE ic.pbac_no IS NULL;

SELECT COUNT(*) AS missing_tokens
FROM auction_item ai
LEFT JOIN item_search_token t
  ON t.pbac_no=ai.pbac_no AND t.pbac_srno=ai.pbac_srno AND t.cmdt_ln_no=ai.cmdt_ln_no
WHERE t.pbac_no IS NULL;

SELECT COUNT(*) AS bad_category_tokens
FROM item_search_token
WHERE token_type='CATEGORY' AND token IN ('기타','미분류');


/* =========================================================
   5) 스키마 v3 패치 후 데이터 정합성 확인
   ---------------------------------------------------------
   schema_patch_v3.sql 적용 직후 반드시 실행한다.
   패치가 기존 데이터에 부작용 없이 적용됐는지 확인하는 쿼리들이다.
   ========================================================= */

/* ---------------------------------------------------------
   atnt_cmdt ENUM 값 분포
   [왜 체크하는가]
   atnt_cmdt 컬럼을 CHAR(1)에서 ENUM('Y','N')으로 변경했다.
   ENUM 마이그레이션 시 기존 데이터 중 'Y'/'N'/NULL 이외의 값이
   있었다면 MySQL이 해당 행을 빈 문자열('')로 강제 변환하거나
   INSERT를 거부했을 수 있다.
   - 결과에 Y, N, NULL만 있으면 정상
   - ''(빈 문자열)이나 다른 값이 보이면 원천 데이터 품질 문제이므로
     해당 행을 직접 확인하고 UPDATE로 보정해야 한다
   --------------------------------------------------------- */
SELECT atnt_cmdt, COUNT(*) AS cnt
FROM auction_item
GROUP BY atnt_cmdt;

/* ---------------------------------------------------------
   cmdt_qty 소수 수량 존재 여부
   [왜 체크하는가]
   cmdt_qty를 INT에서 DECIMAL(12,2)로 변경한 이유는 소수점 수량
   (예: 0.5 KG, 2.75개)이 실제 데이터에 존재하기 때문이다.
   - 결과가 0건이면 현재 데이터에는 소수 수량이 없는 것(정상).
     INT 시절에도 데이터 손실이 없었다는 뜻이므로 마이그레이션은
     안전하게 완료된 것이다.
   - 결과가 있으면 기존에 INT로 잘렸던 값들이 이제 올바르게
     저장되고 있음을 확인할 수 있다.
     ETL을 재실행하면 소수 수량이 정확히 반영된다.
   --------------------------------------------------------- */
SELECT cmdt_qty, cmdt_qty_ut_cd, COUNT(*) AS cnt
FROM auction_item
WHERE cmdt_qty IS NOT NULL
  AND cmdt_qty != FLOOR(cmdt_qty)
GROUP BY cmdt_qty, cmdt_qty_ut_cd
ORDER BY cnt DESC
LIMIT 20;

/* ---------------------------------------------------------
   synonym_dictionary 중복 확인
   [왜 체크하는가]
   UNIQUE 제약을 (src_term, norm_term) 2컬럼에서
   (src_term, norm_term, lang, term_type) 4컬럼으로 변경했다.
   이제 동일한 (src_term, norm_term) 쌍이 lang 또는 term_type이
   다르면 별개 레코드로 공존할 수 있다.
   예) WINE → 와인 (EN, TRANSLATION) 과 WINE → 와인 (KO, SYN) 은
   이제 모두 유효한 레코드다.
   이 쿼리는 새 UNIQUE 기준에서 (src_term, norm_term)이 2개 이상인
   항목과 그 lang/term_type 조합을 보여준다.
   - 의도한 분리(서로 다른 lang/type)면 정상
   - 동일 lang/type에 중복이 있으면 seed 파일에 오류가 있는 것이므로
     seed_synonym.sql을 점검한다
   --------------------------------------------------------- */
SELECT src_term, norm_term, COUNT(*) AS cnt,
       GROUP_CONCAT(CONCAT(lang,'/',term_type) ORDER BY lang SEPARATOR ' | ') AS variants
FROM synonym_dictionary
GROUP BY src_term, norm_term
HAVING cnt > 1
ORDER BY cnt DESC;

/* ---------------------------------------------------------
   category 고아 노드 확인
   [왜 체크하는가]
   category 테이블의 FK를 ON DELETE SET NULL에서
   ON DELETE RESTRICT로 변경했다.
   ON DELETE SET NULL이던 시절에 부모 카테고리가 삭제되면
   자식의 parent_id가 NULL이 되어 level > 1인 카테고리가
   마치 최상위(level 1)처럼 동작하는 고아 노드가 생겼을 수 있다.
   이 쿼리는 그런 고아 노드가 남아있는지 확인한다.
   - 0이면 정상: 모든 level > 1 카테고리는 부모가 있음
   - 0이 아니면: 해당 카테고리들은 분류 경로 탐색 시 최상위로
     잘못 취급될 수 있어 직접 parent_id를 UPDATE해야 한다
   --------------------------------------------------------- */
SELECT COUNT(*) AS orphan_categories
FROM category
WHERE parent_id IS NULL AND level > 1;
