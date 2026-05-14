/*
controllers/categoryController.js
카테고리 컨트롤러
*/

const categoryModel = require('../models/categoryModel');

// GET /api/categories → 대분류(Level 1) 목록 반환
exports.getRootCategories = async (req, res) => {
  try {
    const categories = await categoryModel.findAllRoots();
    res.json({ categories });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

// GET /api/categories/:categoryId/children → 하위 카테고리 반환
exports.getChildren = async (req, res) => {
  try {
    const { categoryId } = req.params;
    const children = await categoryModel.findChildren(categoryId);
    res.json({ categories: children });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};
