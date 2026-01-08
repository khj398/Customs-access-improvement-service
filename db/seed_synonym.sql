/* =========================================================
   Seed: synonym_dictionary (Draft v1)
   - 목적: 영문 물품명 기반 한글/동의어 검색 강화
   - 중복 실행 안전: UNIQUE(src_term, norm_term) + UPSERT
   ========================================================= */

USE customs_auction;

-- -----------------------------
-- Helper: UPSERT 패턴
-- -----------------------------
-- src_term: 매칭 기준(영문 토큰/부분문자열)
-- norm_term: 검색에 쓰일 토큰(한글/동의어)
-- term_type: SYN / TRANSLATION / CATEGORY_HINT
-- weight: 중요도(랭킹/우선순위)

-- =============================
-- 1) 식품·음료 / 주류
-- =============================
INSERT INTO synonym_dictionary (src_term, norm_term, lang, term_type, weight) VALUES
('WINE',       '와인', 'MIX', 'TRANSLATION', 2.00),
('WINE',       '주류', 'MIX', 'CATEGORY_HINT', 1.60),
('WINE',       '술',   'MIX', 'SYN', 1.40),

('WHISKY',     '위스키', 'MIX', 'TRANSLATION', 2.00),
('WHISKEY',    '위스키', 'MIX', 'TRANSLATION', 2.00),
('VODKA',      '보드카', 'MIX', 'TRANSLATION', 2.00),
('GIN',        '진',     'MIX', 'TRANSLATION', 1.80),
('RUM',        '럼',     'MIX', 'TRANSLATION', 1.80),
('BEER',       '맥주',   'MIX', 'TRANSLATION', 1.90),
('CHAMPAGNE',  '샴페인', 'MIX', 'TRANSLATION', 2.00),

('ALCOHOL',    '주류', 'MIX', 'CATEGORY_HINT', 1.60),
('ALCOHOL',    '술',   'MIX', 'SYN', 1.30)
ON DUPLICATE KEY UPDATE
  lang=VALUES(lang), term_type=VALUES(term_type), weight=VALUES(weight), updated_at=CURRENT_TIMESTAMP;

-- =============================
-- 2) 배터리/전지
-- =============================
INSERT INTO synonym_dictionary (src_term, norm_term, lang, term_type, weight) VALUES
('BATTERY',   '배터리', 'MIX', 'TRANSLATION', 2.00),
('BATTERY',   '전지',   'MIX', 'SYN', 1.60),
('CELL',      '전지',   'MIX', 'TRANSLATION', 1.50),

('LITHIUM',   '리튬',         'MIX', 'TRANSLATION', 1.80),
('LI-ION',    '리튬이온',     'MIX', 'TRANSLATION', 2.00),
('LIION',     '리튬이온',     'MIX', 'TRANSLATION', 2.00),
('LIPO',      '리튬폴리머',   'MIX', 'TRANSLATION', 2.00),
('LI-PO',     '리튬폴리머',   'MIX', 'TRANSLATION', 2.00),

('LITHIUM',   '리튬배터리',   'MIX', 'CATEGORY_HINT', 1.70),
('LI-ION',    '리튬배터리',   'MIX', 'CATEGORY_HINT', 1.90),
('LIION',     '리튬배터리',   'MIX', 'CATEGORY_HINT', 1.90)
ON DUPLICATE KEY UPDATE
  lang=VALUES(lang), term_type=VALUES(term_type), weight=VALUES(weight), updated_at=CURRENT_TIMESTAMP;

-- =============================
-- 3) 산업·장비(계측/시험) - 산업 중심
-- =============================
INSERT INTO synonym_dictionary (src_term, norm_term, lang, term_type, weight) VALUES
('GAUGE',      '게이지',   'MIX', 'TRANSLATION', 2.00),
('GAUGE',      '측정기',   'MIX', 'SYN', 1.60),
('GAUGE',      '계측기',   'MIX', 'SYN', 1.60),

('METER',      '미터',     'MIX', 'TRANSLATION', 1.40),
('METER',      '측정기',   'MIX', 'SYN', 1.60),
('INDICATOR',  '표시기',   'MIX', 'TRANSLATION', 1.40),

('SENSOR',     '센서',     'MIX', 'TRANSLATION', 2.00),
('TRANSMITTER','송신기',   'MIX', 'TRANSLATION', 1.60),
('INSTRUMENT', '계측기',   'MIX', 'SYN', 1.70),

('TEST',       '시험',     'MIX', 'TRANSLATION', 1.60),
('TESTER',     '테스터',   'MIX', 'TRANSLATION', 1.60),
('INSPECTION', '검사',     'MIX', 'TRANSLATION', 1.60),
('ANALYZER',   '분석기',   'MIX', 'TRANSLATION', 1.70),
('ANALYSER',   '분석기',   'MIX', 'TRANSLATION', 1.70),

('GAUGE',      '측정기기', 'MIX', 'CATEGORY_HINT', 1.80),
('METER',      '측정기기', 'MIX', 'CATEGORY_HINT', 1.70),
('SENSOR',     '센서·계측','MIX', 'CATEGORY_HINT', 1.80),
('TESTER',     '시험·검사장비','MIX','CATEGORY_HINT', 1.70)
ON DUPLICATE KEY UPDATE
  lang=VALUES(lang), term_type=VALUES(term_type), weight=VALUES(weight), updated_at=CURRENT_TIMESTAMP;

-- =============================
-- 4) 산업·장비(유체·배관)
-- =============================
INSERT INTO synonym_dictionary (src_term, norm_term, lang, term_type, weight) VALUES
('PUMP',      '펌프',     'MIX', 'TRANSLATION', 2.00),
('VALVE',     '밸브',     'MIX', 'TRANSLATION', 2.00),
('PIPE',      '배관',     'MIX', 'TRANSLATION', 1.80),
('PIPES',     '배관',     'MIX', 'TRANSLATION', 1.80),
('FITTING',   '피팅',     'MIX', 'TRANSLATION', 1.80),
('FITTINGS',  '피팅',     'MIX', 'TRANSLATION', 1.80),
('FLANGE',    '플랜지',   'MIX', 'TRANSLATION', 1.80),

('PUMP',      '유체·배관', 'MIX', 'CATEGORY_HINT', 1.40),
('VALVE',     '유체·배관', 'MIX', 'CATEGORY_HINT', 1.40),
('PIPE',      '배관·피팅', 'MIX', 'CATEGORY_HINT', 1.50),
('FITTING',   '배관·피팅', 'MIX', 'CATEGORY_HINT', 1.50)
ON DUPLICATE KEY UPDATE
  lang=VALUES(lang), term_type=VALUES(term_type), weight=VALUES(weight), updated_at=CURRENT_TIMESTAMP;

-- =============================
-- 5) 전자·전기(부품)
-- =============================
INSERT INTO synonym_dictionary (src_term, norm_term, lang, term_type, weight) VALUES
('CABLE',      '케이블',      'MIX', 'TRANSLATION', 1.90),
('CONNECTOR',  '커넥터',      'MIX', 'TRANSLATION', 1.90),
('HARNESS',    '하네스',      'MIX', 'TRANSLATION', 1.70),

('PCB',        'PCB',         'MIX', 'SYN', 1.50),
('PCB',        '회로기판',    'MIX', 'TRANSLATION', 1.80),
('BOARD',      '보드',        'MIX', 'TRANSLATION', 1.60),
('MODULE',     '모듈',        'MIX', 'TRANSLATION', 1.80),

('SWITCH',     '스위치',      'MIX', 'TRANSLATION', 1.80),
('RELAY',      '릴레이',      'MIX', 'TRANSLATION', 1.80),
('BREAKER',    '차단기',      'MIX', 'TRANSLATION', 1.80),
('FUSE',       '퓨즈',        'MIX', 'TRANSLATION', 1.80),

('POWER',      '전원',        'MIX', 'TRANSLATION', 1.50),
('SUPPLY',     '공급장치',    'MIX', 'TRANSLATION', 1.30),
('ADAPTER',    '어댑터',      'MIX', 'TRANSLATION', 1.60),
('CHARGER',    '충전기',      'MIX', 'TRANSLATION', 1.60),

('CABLE',      '커넥터·케이블','MIX', 'CATEGORY_HINT', 1.40),
('CONNECTOR',  '커넥터·케이블','MIX', 'CATEGORY_HINT', 1.40),
('PCB',        'PCB·모듈',     'MIX', 'CATEGORY_HINT', 1.40),
('MODULE',     'PCB·모듈',     'MIX', 'CATEGORY_HINT', 1.40)
ON DUPLICATE KEY UPDATE
  lang=VALUES(lang), term_type=VALUES(term_type), weight=VALUES(weight), updated_at=CURRENT_TIMESTAMP;

-- =============================
-- 6) 컴퓨터/모바일(기본)
-- =============================
INSERT INTO synonym_dictionary (src_term, norm_term, lang, term_type, weight) VALUES
('SERVER',   '서버',     'MIX', 'TRANSLATION', 1.80),
('DESKTOP',  '데스크탑', 'MIX', 'TRANSLATION', 1.80),
('PC',       'PC',       'MIX', 'SYN', 1.30),

('MONITOR',  '모니터',   'MIX', 'TRANSLATION', 1.80),
('KEYBOARD', '키보드',   'MIX', 'TRANSLATION', 1.80),
('MOUSE',    '마우스',   'MIX', 'TRANSLATION', 1.80),

('PHONE',    '스마트폰', 'MIX', 'TRANSLATION', 1.60),
('TABLET',   '태블릿',   'MIX', 'TRANSLATION', 1.60),
('CHARGER',  '충전기',   'MIX', 'SYN', 1.50),

('SSD',      'SSD',      'MIX', 'SYN', 1.30),
('HDD',      'HDD',      'MIX', 'SYN', 1.30),
('RAM',      '램',       'MIX', 'TRANSLATION', 1.60),
('MEMORY',   '메모리',   'MIX', 'TRANSLATION', 1.60)
ON DUPLICATE KEY UPDATE
  lang=VALUES(lang), term_type=VALUES(term_type), weight=VALUES(weight), updated_at=CURRENT_TIMESTAMP;

-- -----------------------------
-- Check
-- -----------------------------
SELECT term_type, COUNT(*) AS cnt
FROM synonym_dictionary
GROUP BY term_type
ORDER BY cnt DESC;

SELECT COUNT(*) AS total FROM synonym_dictionary;
