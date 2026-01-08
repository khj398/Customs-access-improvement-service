USE customs_auction;

INSERT INTO synonym_dictionary (src_term, norm_term, lang, term_type, weight) VALUES
-- GAUGE 복수형 대응
('GAUGES', '게이지', 'MIX', 'TRANSLATION', 2.00),
('GAUGES', '측정기', 'MIX', 'SYN', 1.60),
('GAUGES', '계측기', 'MIX', 'SYN', 1.60),

-- 주류 확장
('SAKE',    '사케',  'MIX', 'TRANSLATION', 2.00),
('TEQUILA', '테킬라','MIX', 'TRANSLATION', 2.00),
('LIQUEUR', '리큐르','MIX', 'TRANSLATION', 2.00),
('COCKTAIL','칵테일','MIX', 'TRANSLATION', 1.80),
('WHISKIES','위스키','MIX', 'TRANSLATION', 2.00),

-- CHEONG JU(청주) — 토큰 2개로 들어오므로 둘 다 매핑(검색 도움)
('CHEONG', '청',     'MIX', 'SYN', 1.10),
('CHEONG', '청주',   'MIX', 'CATEGORY_HINT', 1.40),
('JU',     '주',     'MIX', 'SYN', 1.05),
('CHEONG', '청주(술)', 'MIX', 'SYN', 1.30),

-- 화학물질
('CALCIUM',   '칼슘',      'MIX', 'TRANSLATION', 1.50),
('CHLORIDE',  '염화물',    'MIX', 'TRANSLATION', 1.50),
('CALCIUM',   '염화칼슘',  'MIX', 'SYN', 1.70),
('CHLORIDE',  '염화칼슘',  'MIX', 'SYN', 1.70),

-- 차량 에어컨
('AIR',         '에어',     'MIX', 'SYN', 1.00),
('CONDITIONER', '컨디셔너', 'MIX', 'SYN', 0.80),
('AIR',         '에어컨',   'MIX', 'SYN', 1.20),
('CONDITIONER', '에어컨',   'MIX', 'SYN', 1.20),
('VEHICLE',     '차량',     'MIX', 'TRANSLATION', 1.50),
('VEHICLES',    '차량',     'MIX', 'TRANSLATION', 1.50),
('CAR',         '자동차',   'MIX', 'TRANSLATION', 1.50),

-- 물놀이/풀 용품
('POOL',       '수영장',   'MIX', 'TRANSLATION', 1.70),
('INFLATABLE', '튜브',     'MIX', 'SYN', 1.40),
('FLOATING',   '물놀이',   'MIX', 'SYN', 1.20),
('MAT',        '매트',     'MIX', 'TRANSLATION', 1.20),

-- 스마트 글라스
('SMART',  '스마트', 'MIX', 'SYN', 1.10),
('GLASSES','안경',   'MIX', 'TRANSLATION', 1.60),
('AR',     '증강현실', 'MIX', 'TRANSLATION', 1.70),
('AR',     '스마트글라스', 'MIX', 'SYN', 1.60),

-- 악기
('GUITAR', '기타(악기)', 'MIX', 'TRANSLATION', 2.00),
('ELECTRIC', '일렉', 'MIX', 'SYN', 1.20),

-- 음료/아이스크림 제조기
('BEVERAGE', '음료', 'MIX', 'TRANSLATION', 1.50),
('ICE',      '아이스', 'MIX', 'SYN', 1.20),
('CREAM',    '크림',   'MIX', 'SYN', 1.00),
('ICE',      '아이스크림', 'MIX', 'SYN', 1.40),
('MAKER',    '제조기', 'MIX', 'TRANSLATION', 1.30),
('MAKERS',   '제조기', 'MIX', 'TRANSLATION', 1.30),
('MACHINE',  '기계',   'MIX', 'TRANSLATION', 1.00)

ON DUPLICATE KEY UPDATE
  lang=VALUES(lang), term_type=VALUES(term_type), weight=VALUES(weight), updated_at=CURRENT_TIMESTAMP;
