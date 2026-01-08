USE customs_auction;

-- 부모 ID 가져오기
SELECT category_id INTO @L1_AUTO    FROM category WHERE parent_id IS NULL AND name_ko='자동차·공구' LIMIT 1;
SELECT category_id INTO @L1_PARTS   FROM category WHERE parent_id IS NULL AND name_ko='부품·소모품' LIMIT 1;
SELECT category_id INTO @L1_SPORTS  FROM category WHERE parent_id IS NULL AND name_ko='스포츠·레저' LIMIT 1;

-- 자동차부품 / 공구 부모
SELECT category_id INTO @AUTO_PART  FROM category WHERE parent_id=@L1_AUTO AND name_ko='자동차부품' LIMIT 1;

-- 부품·소모품 > 화학·오일·윤활 부모
SELECT category_id INTO @PART_CHEM  FROM category WHERE parent_id=@L1_PARTS AND name_ko='화학·오일·윤활' LIMIT 1;

-- 스포츠·레저 부모 (없으면 추가)
INSERT IGNORE INTO category (parent_id, level, name_ko, name_en) VALUES
(@L1_SPORTS, 2, '수영·물놀이', 'Swimming & Water'),
(@L1_SPORTS, 2, '취미·악기', 'Hobby & Musical Instruments');

SELECT category_id INTO @SPORT_WATER FROM category WHERE parent_id=@L1_SPORTS AND name_ko='수영·물놀이' LIMIT 1;
SELECT category_id INTO @SPORT_HOBBY FROM category WHERE parent_id=@L1_SPORTS AND name_ko='취미·악기' LIMIT 1;

-- (3) 세부 추가
-- 1) 자동차부품 > 냉난방·에어컨
INSERT IGNORE INTO category (parent_id, level, name_ko, name_en) VALUES
(@AUTO_PART, 3, '냉난방·에어컨', 'HVAC & Air Conditioning');

-- 2) 부품·소모품 > 화학·오일·윤활 > 화학물질
INSERT IGNORE INTO category (parent_id, level, name_ko, name_en) VALUES
(@PART_CHEM, 3, '화학물질', 'Chemicals');

-- 3) 스포츠·레저 > 수영·물놀이 > 풀/물놀이 용품
INSERT IGNORE INTO category (parent_id, level, name_ko, name_en) VALUES
(@SPORT_WATER, 3, '풀·물놀이 용품', 'Pool & Water Accessories');

-- 4) 스포츠·레저 > 취미·악기 > 악기
INSERT IGNORE INTO category (parent_id, level, name_ko, name_en) VALUES
(@SPORT_HOBBY, 3, '악기', 'Musical Instruments');


