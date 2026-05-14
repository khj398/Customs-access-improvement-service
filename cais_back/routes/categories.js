/*
routes/categories.js
카테고리 라우터
*/

const express    = require('express');
const router     = express.Router();
const categoryController = require('../controllers/categoryController');

// GET /api/categories          → 대분류 전체 목록
router.get('/', categoryController.getRootCategories);

// GET /api/categories/:id/children → 하위 카테고리
router.get('/:categoryId/children', categoryController.getChildren);

module.exports = router;
