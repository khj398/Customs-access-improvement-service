USE customs_auction;

-- ─────────────────────────────────────────────────────────
-- [중복 L1 정리] seed_category.sql 실행 후 이 파일을 실행하면
-- INSERT IGNORE가 parent_id IS NULL UNIQUE 제약이 없어 중복 행을 생성했음.
-- 낮은 category_id(원본)를 남기고 높은 ID(중복)를 삭제한다.
-- ─────────────────────────────────────────────────────────
DELETE c2 FROM category c2
INNER JOIN category c1
  ON  c1.parent_id IS NULL
  AND c2.parent_id IS NULL
  AND c1.name_ko   = c2.name_ko
  AND c1.category_id < c2.category_id;

-- 확장 시드가 단독 실행되더라도 부모 카테고리를 최소 보장
-- (NOT EXISTS 조건으로 중복 생성 방지)
INSERT INTO category (parent_id, level, name_ko, name_en)
SELECT NULL, 1, t.name_ko, t.name_en FROM (
  SELECT '자동차·공구' AS name_ko, 'Automotive & Tools' AS name_en
  UNION ALL SELECT '부품·소모품', 'Parts & Consumables'
  UNION ALL SELECT '스포츠·레저', 'Sports & Leisure'
) t
WHERE NOT EXISTS (
  SELECT 1 FROM category c WHERE c.parent_id IS NULL AND c.name_ko = t.name_ko
);

-- 부모 ID 가져오기
SELECT category_id INTO @L1_AUTO   FROM category WHERE parent_id IS NULL AND name_ko='자동차·공구' LIMIT 1;
SELECT category_id INTO @L1_PARTS  FROM category WHERE parent_id IS NULL AND name_ko='부품·소모품' LIMIT 1;
SELECT category_id INTO @L1_SPORTS FROM category WHERE parent_id IS NULL AND name_ko='스포츠·레저' LIMIT 1;

-- 하위 부모 카테고리도 보장
INSERT IGNORE INTO category (parent_id, level, name_ko, name_en) VALUES
(@L1_AUTO, 2, '자동차부품', 'Auto Parts'),
(@L1_PARTS, 2, '화학·오일·윤활', 'Chemical & Oil');

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

-- 5) 스포츠·레저 > 취미·악기 > 완구
INSERT IGNORE INTO category (parent_id, level, name_ko, name_en) VALUES
(@SPORT_HOBBY, 3, '완구', 'Toys');

-- 6) 스포츠·레저 > 운동기구 / 구기·라켓 (L2 추가)
INSERT IGNORE INTO category (parent_id, level, name_ko, name_en) VALUES
(@L1_SPORTS, 2, '운동기구', 'Exercise Equipment'),
(@L1_SPORTS, 2, '구기·라켓', 'Ball & Racket Sports');

SELECT category_id INTO @SPORT_EXERCISE FROM category WHERE parent_id=@L1_SPORTS AND name_ko='운동기구' LIMIT 1;
SELECT category_id INTO @SPORT_RACKET   FROM category WHERE parent_id=@L1_SPORTS AND name_ko='구기·라켓' LIMIT 1;

INSERT IGNORE INTO category (parent_id, level, name_ko, name_en) VALUES
(@SPORT_EXERCISE, 3, '러닝머신', 'Treadmill'),
(@SPORT_RACKET,   3, '탁구·배드민턴', 'Table Tennis & Badminton');

-- ─────────────────────────────────────
-- 가전 > 주방가전 > 냉장고
-- ─────────────────────────────────────
SELECT category_id INTO @L1_HOMEAPP FROM category WHERE parent_id IS NULL AND name_ko='가전' LIMIT 1;
SELECT category_id INTO @KITCHEN_APPL FROM category WHERE parent_id=@L1_HOMEAPP AND name_ko='주방가전' LIMIT 1;

INSERT IGNORE INTO category (parent_id, level, name_ko, name_en) VALUES
(@KITCHEN_APPL, 3, '냉장고', 'Refrigerator');

-- ─────────────────────────────────────
-- 생활·주방 하위 카테고리
-- ─────────────────────────────────────
SELECT category_id INTO @L1_HOME FROM category WHERE parent_id IS NULL AND name_ko='생활·주방' LIMIT 1;

INSERT IGNORE INTO category (parent_id, level, name_ko, name_en) VALUES
(@L1_HOME, 2, '주방·식탁', 'Kitchen & Dining'),
(@L1_HOME, 2, '가구·인테리어', 'Furniture & Interior');

SELECT category_id INTO @HOME_KITCHEN FROM category WHERE parent_id=@L1_HOME AND name_ko='주방·식탁' LIMIT 1;
SELECT category_id INTO @HOME_FURNITURE FROM category WHERE parent_id=@L1_HOME AND name_ko='가구·인테리어' LIMIT 1;

INSERT IGNORE INTO category (parent_id, level, name_ko, name_en) VALUES
(@HOME_KITCHEN,   3, '식기류', 'Tableware'),
(@HOME_KITCHEN,   3, '주방용품', 'Kitchen Utensils'),
(@HOME_FURNITURE, 3, '가구', 'Furniture');

-- ─────────────────────────────────────
-- 뷰티·위생 하위 카테고리
-- ─────────────────────────────────────
SELECT category_id INTO @L1_BEAUTY FROM category WHERE parent_id IS NULL AND name_ko='뷰티·위생' LIMIT 1;

INSERT IGNORE INTO category (parent_id, level, name_ko, name_en) VALUES
(@L1_BEAUTY, 2, '화장품', 'Cosmetics'),
(@L1_BEAUTY, 2, '헤어·바디', 'Hair & Body');

SELECT category_id INTO @BEAUTY_COSM FROM category WHERE parent_id=@L1_BEAUTY AND name_ko='화장품' LIMIT 1;
SELECT category_id INTO @BEAUTY_HAIR FROM category WHERE parent_id=@L1_BEAUTY AND name_ko='헤어·바디' LIMIT 1;

INSERT IGNORE INTO category (parent_id, level, name_ko, name_en) VALUES
(@BEAUTY_COSM, 3, '스킨케어', 'Skincare'),
(@BEAUTY_COSM, 3, '색조화장', 'Makeup'),
(@BEAUTY_HAIR, 3, '헤어케어', 'Hair Care');

