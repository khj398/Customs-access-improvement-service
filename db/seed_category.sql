/* =========================================================
   Seed: Category Tree (Draft v1)
   - 산업·장비 중심 분류 체계
   - 대(1) / 중(2) / 소(3) 중심, 세(4)는 추후 확장
   ========================================================= */

USE customs_auction;

-- (선택) 기존 카테고리 비우고 다시 넣고 싶을 때만 사용
-- 주의: FK로 참조되는 데이터(item_classification 등)가 있으면 실패할 수 있음
-- TRUNCATE TABLE category;

-- -----------------------------
-- LEVEL 1 (대분류)
-- -----------------------------
INSERT INTO category (parent_id, level, name_ko, name_en) VALUES
(NULL, 1, '산업·장비', 'Industrial & Equipment'),
(NULL, 1, '전자·전기', 'Electronics & Electrical'),
(NULL, 1, '컴퓨터·모바일', 'Computers & Mobile'),
(NULL, 1, '부품·소모품', 'Parts & Consumables'),
(NULL, 1, '가전', 'Home Appliances'),
(NULL, 1, '의류·패션잡화', 'Fashion'),
(NULL, 1, '생활·주방', 'Home & Kitchen'),
(NULL, 1, '식품·음료', 'Food & Beverage'),
(NULL, 1, '뷰티·위생', 'Beauty & Hygiene'),
(NULL, 1, '스포츠·레저', 'Sports & Leisure'),
(NULL, 1, '자동차·공구', 'Automotive & Tools'),
(NULL, 1, '기타', 'Others');

-- ROOT ID 가져오기
SELECT category_id INTO @ROOT_INDUSTRY FROM category WHERE parent_id IS NULL AND name_ko='산업·장비' LIMIT 1;
SELECT category_id INTO @ROOT_ELECTRIC FROM category WHERE parent_id IS NULL AND name_ko='전자·전기' LIMIT 1;
SELECT category_id INTO @ROOT_COMPUTER FROM category WHERE parent_id IS NULL AND name_ko='컴퓨터·모바일' LIMIT 1;
SELECT category_id INTO @ROOT_PARTS    FROM category WHERE parent_id IS NULL AND name_ko='부품·소모품' LIMIT 1;
SELECT category_id INTO @ROOT_HOMEAPP  FROM category WHERE parent_id IS NULL AND name_ko='가전' LIMIT 1;
SELECT category_id INTO @ROOT_FASHION  FROM category WHERE parent_id IS NULL AND name_ko='의류·패션잡화' LIMIT 1;
SELECT category_id INTO @ROOT_HOME     FROM category WHERE parent_id IS NULL AND name_ko='생활·주방' LIMIT 1;
SELECT category_id INTO @ROOT_FOOD     FROM category WHERE parent_id IS NULL AND name_ko='식품·음료' LIMIT 1;
SELECT category_id INTO @ROOT_BEAUTY   FROM category WHERE parent_id IS NULL AND name_ko='뷰티·위생' LIMIT 1;
SELECT category_id INTO @ROOT_SPORTS   FROM category WHERE parent_id IS NULL AND name_ko='스포츠·레저' LIMIT 1;
SELECT category_id INTO @ROOT_AUTO     FROM category WHERE parent_id IS NULL AND name_ko='자동차·공구' LIMIT 1;
SELECT category_id INTO @ROOT_OTHER    FROM category WHERE parent_id IS NULL AND name_ko='기타' LIMIT 1;


-- -----------------------------
-- LEVEL 2 (중분류) - 산업·장비 중심
-- -----------------------------
INSERT INTO category (parent_id, level, name_ko, name_en) VALUES
(@ROOT_INDUSTRY, 2, '산업장비', 'Industrial Equipment'),
(@ROOT_INDUSTRY, 2, '계측·시험', 'Measurement & Test'),
(@ROOT_INDUSTRY, 2, '안전·보호', 'Safety & Protection'),
(@ROOT_INDUSTRY, 2, '유체·배관', 'Fluid & Piping'),
(@ROOT_INDUSTRY, 2, '모터·구동', 'Motor & Drive');

SELECT category_id INTO @IND_EQUIP FROM category WHERE parent_id=@ROOT_INDUSTRY AND name_ko='산업장비' LIMIT 1;
SELECT category_id INTO @IND_MEAS  FROM category WHERE parent_id=@ROOT_INDUSTRY AND name_ko='계측·시험' LIMIT 1;
SELECT category_id INTO @IND_SAFE  FROM category WHERE parent_id=@ROOT_INDUSTRY AND name_ko='안전·보호' LIMIT 1;
SELECT category_id INTO @IND_FLUID FROM category WHERE parent_id=@ROOT_INDUSTRY AND name_ko='유체·배관' LIMIT 1;
SELECT category_id INTO @IND_MOTOR FROM category WHERE parent_id=@ROOT_INDUSTRY AND name_ko='모터·구동' LIMIT 1;

-- LEVEL 3 (소분류) - 산업·장비
INSERT INTO category (parent_id, level, name_ko, name_en) VALUES
(@IND_EQUIP, 3, '산업기계', 'Machinery'),
(@IND_EQUIP, 3, '공정장비', 'Process Equipment'),

(@IND_MEAS,  3, '측정기기', 'Meters & Gauges'),
(@IND_MEAS,  3, '센서·계측', 'Sensors & Instrumentation'),
(@IND_MEAS,  3, '시험·검사장비', 'Testing Equipment'),

(@IND_SAFE,  3, '안전장비', 'Safety Gear'),
(@IND_SAFE,  3, '보호구', 'Protective Equipment'),

(@IND_FLUID, 3, '펌프', 'Pump'),
(@IND_FLUID, 3, '밸브', 'Valve'),
(@IND_FLUID, 3, '배관·피팅', 'Pipes & Fittings'),

(@IND_MOTOR, 3, '모터', 'Motor'),
(@IND_MOTOR, 3, '감속기·구동부품', 'Reducer & Drive Parts');


-- -----------------------------
-- LEVEL 2/3 (중/소분류) - 전자·전기
-- -----------------------------
INSERT INTO category (parent_id, level, name_ko, name_en) VALUES
(@ROOT_ELECTRIC, 2, '전자부품', 'Electronic Components'),
(@ROOT_ELECTRIC, 2, '전기부품', 'Electrical Components'),
(@ROOT_ELECTRIC, 2, '전원·변환', 'Power & Conversion');

SELECT category_id INTO @ELC_EPART FROM category WHERE parent_id=@ROOT_ELECTRIC AND name_ko='전자부품' LIMIT 1;
SELECT category_id INTO @ELC_PART  FROM category WHERE parent_id=@ROOT_ELECTRIC AND name_ko='전기부품' LIMIT 1;
SELECT category_id INTO @ELC_PWR   FROM category WHERE parent_id=@ROOT_ELECTRIC AND name_ko='전원·변환' LIMIT 1;

INSERT INTO category (parent_id, level, name_ko, name_en) VALUES
(@ELC_EPART, 3, 'PCB·모듈', 'PCB & Modules'),
(@ELC_EPART, 3, '커넥터·케이블', 'Connectors & Cables'),
(@ELC_EPART, 3, '센서·계측', 'Sensors & Instrumentation'),

(@ELC_PART,  3, '스위치·릴레이', 'Switches & Relays'),
(@ELC_PART,  3, '차단기·퓨즈', 'Breakers & Fuses'),

(@ELC_PWR,   3, '전원공급장치', 'Power Supply'),
(@ELC_PWR,   3, '변압·인버터', 'Transformer & Inverter');


-- -----------------------------
-- LEVEL 2/3 - 컴퓨터·모바일
-- -----------------------------
INSERT INTO category (parent_id, level, name_ko, name_en) VALUES
(@ROOT_COMPUTER, 2, '컴퓨터', 'Computer'),
(@ROOT_COMPUTER, 2, '모바일', 'Mobile'),
(@ROOT_COMPUTER, 2, '저장장치', 'Storage');

SELECT category_id INTO @CMP_PC   FROM category WHERE parent_id=@ROOT_COMPUTER AND name_ko='컴퓨터' LIMIT 1;
SELECT category_id INTO @CMP_MOB  FROM category WHERE parent_id=@ROOT_COMPUTER AND name_ko='모바일' LIMIT 1;
SELECT category_id INTO @CMP_STOR FROM category WHERE parent_id=@ROOT_COMPUTER AND name_ko='저장장치' LIMIT 1;

INSERT INTO category (parent_id, level, name_ko, name_en) VALUES
(@CMP_PC,   3, '본체·서버', 'Desktop & Server'),
(@CMP_PC,   3, '주변기기', 'Peripherals'),
(@CMP_MOB,  3, '스마트폰·태블릿', 'Phone & Tablet'),
(@CMP_MOB,  3, '액세서리', 'Accessories'),
(@CMP_STOR, 3, 'HDD·SSD·메모리', 'HDD/SSD/Memory');


-- -----------------------------
-- LEVEL 2/3 - 부품·소모품
-- -----------------------------
INSERT INTO category (parent_id, level, name_ko, name_en) VALUES
(@ROOT_PARTS, 2, '배터리·전지', 'Battery'),
(@ROOT_PARTS, 2, '화학·오일·윤활', 'Chemical & Oil'),
(@ROOT_PARTS, 2, '포장·소모품', 'Packaging');

SELECT category_id INTO @PRT_BATT  FROM category WHERE parent_id=@ROOT_PARTS AND name_ko='배터리·전지' LIMIT 1;
SELECT category_id INTO @PRT_CHEM  FROM category WHERE parent_id=@ROOT_PARTS AND name_ko='화학·오일·윤활' LIMIT 1;
SELECT category_id INTO @PRT_PACK  FROM category WHERE parent_id=@ROOT_PARTS AND name_ko='포장·소모품' LIMIT 1;

INSERT INTO category (parent_id, level, name_ko, name_en) VALUES
(@PRT_BATT, 3, '리튬배터리', 'Lithium Battery'),
(@PRT_BATT, 3, '일반 배터리', 'Battery'),

(@PRT_CHEM, 3, '윤활유·오일', 'Lubricant & Oil'),
(@PRT_CHEM, 3, '접착·수지', 'Adhesive & Resin'),

(@PRT_PACK, 3, '박스·필름', 'Box & Film'),
(@PRT_PACK, 3, '라벨·테이프', 'Label & Tape');


-- -----------------------------
-- LEVEL 2/3 - 식품·음료 (주류 포함)
-- -----------------------------
INSERT INTO category (parent_id, level, name_ko, name_en) VALUES
(@ROOT_FOOD, 2, '음료', 'Beverage'),
(@ROOT_FOOD, 2, '식품', 'Food');

SELECT category_id INTO @FOOD_BEV FROM category WHERE parent_id=@ROOT_FOOD AND name_ko='음료' LIMIT 1;
SELECT category_id INTO @FOOD_FD  FROM category WHERE parent_id=@ROOT_FOOD AND name_ko='식품' LIMIT 1;

INSERT INTO category (parent_id, level, name_ko, name_en) VALUES
(@FOOD_BEV, 3, '주류', 'Alcohol'),
(@FOOD_BEV, 3, '비주류', 'Non-alcohol'),
(@FOOD_FD,  3, '가공식품', 'Processed Food'),
(@FOOD_FD,  3, '건강식품', 'Health Food');


-- -----------------------------
-- LEVEL 2/3 - 자동차·공구
-- -----------------------------
INSERT INTO category (parent_id, level, name_ko, name_en) VALUES
(@ROOT_AUTO, 2, '자동차부품', 'Auto Parts'),
(@ROOT_AUTO, 2, '공구', 'Tools');

SELECT category_id INTO @AUTO_PART FROM category WHERE parent_id=@ROOT_AUTO AND name_ko='자동차부품' LIMIT 1;
SELECT category_id INTO @AUTO_TOOL FROM category WHERE parent_id=@ROOT_AUTO AND name_ko='공구' LIMIT 1;

INSERT INTO category (parent_id, level, name_ko, name_en) VALUES
(@AUTO_PART, 3, '타이어·휠', 'Tire & Wheel'),
(@AUTO_PART, 3, '엔진·필터', 'Engine & Filter'),
(@AUTO_TOOL, 3, '전동공구', 'Power Tools'),
(@AUTO_TOOL, 3, '수공구', 'Hand Tools');


-- -----------------------------
-- 기타(미분류) - 최소한만
-- -----------------------------
INSERT INTO category (parent_id, level, name_ko, name_en) VALUES
(@ROOT_OTHER, 2, '미분류', 'Uncategorized');

SELECT category_id INTO @OTHER_UNC FROM category WHERE parent_id=@ROOT_OTHER AND name_ko='미분류' LIMIT 1;

INSERT INTO category (parent_id, level, name_ko, name_en) VALUES
(@OTHER_UNC, 3, '기타', 'Misc');

-- -------------------------------------------------
-- [UPDATE] 가전 카테고리 보강 (주방가전/생활가전 + 하위)
-- - build_classification 룰에서 사용하는 경로를 보장하기 위함
-- -------------------------------------------------

-- L1: 가전 ID
SELECT category_id INTO @ROOT_HOMEAPP
FROM category
WHERE parent_id IS NULL AND name_ko='가전'
LIMIT 1;

-- L2: 주방가전/생활가전 (없으면 추가)
INSERT IGNORE INTO category (parent_id, level, name_ko, name_en) VALUES
(@ROOT_HOMEAPP, 2, '주방가전', 'Kitchen Appliances'),
(@ROOT_HOMEAPP, 2, '생활가전', 'Home Appliances');

-- L2 ID
SELECT category_id INTO @HOME_KITCHEN
FROM category
WHERE parent_id=@ROOT_HOMEAPP AND name_ko='주방가전'
LIMIT 1;

SELECT category_id INTO @HOME_LIVING
FROM category
WHERE parent_id=@ROOT_HOMEAPP AND name_ko='생활가전'
LIMIT 1;

-- L3: 룰에서 쓰는 소분류(없으면 추가)
INSERT IGNORE INTO category (parent_id, level, name_ko, name_en) VALUES
(@HOME_KITCHEN, 3, '커피·음료기기', 'Coffee & Beverage Machines'),
(@HOME_LIVING,  3, '공기·냉난방', 'Air & HVAC');



/* =========================================================
   Quick Check
   ========================================================= */
-- 대분류 목록 확인
SELECT category_id, name_ko, level
FROM category
WHERE parent_id IS NULL
ORDER BY category_id;

-- 산업·장비 하위 확인
SELECT c1.name_ko AS L1, c2.name_ko AS L2, c3.name_ko AS L3
FROM category c1
LEFT JOIN category c2 ON c2.parent_id = c1.category_id
LEFT JOIN category c3 ON c3.parent_id = c2.category_id
WHERE c1.name_ko = '산업·장비'
ORDER BY c2.category_id, c3.category_id;
