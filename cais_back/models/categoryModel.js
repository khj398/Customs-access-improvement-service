/*
models/categoryModel.js
카테고리 DB 모델
*/

const pool = require('../config/db');

// 대분류(Level 1) 카테고리 전체 조회
// GROUP BY name_ko 로 seed 스크립트 중복 삽입 방지
// (MySQL은 parent_id IS NULL인 경우 UNIQUE 키 중복을 허용하므로 DB에 중복 행이 존재할 수 있음)
exports.findAllRoots = async () => {
  const [rows] = await pool.query(`
    SELECT
      MIN(category_id) AS categoryId,
      name_ko          AS nameKo,
      MAX(name_en)     AS nameEn
    FROM category
    WHERE parent_id IS NULL
      AND is_active = 1
    GROUP BY name_ko
    ORDER BY MIN(category_id)
  `);
  return rows;
};

// 특정 부모의 하위 카테고리 조회
exports.findChildren = async (parentId) => {
  const [rows] = await pool.query(`
    SELECT
      category_id AS categoryId,
      parent_id   AS parentId,
      level,
      name_ko     AS nameKo,
      name_en     AS nameEn
    FROM category
    WHERE parent_id = ?
      AND is_active = 1
    ORDER BY category_id
  `, [parentId]);
  return rows;
};
