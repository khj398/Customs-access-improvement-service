/*
app.js
Express 애플리케이션 설정 및 라우팅 연결
*/

const express = require('express');
const cors    = require('cors');
const path    = require('path');
require('dotenv').config();

const app = express();

const authRoutes     = require('./routes/auth');
const auctionRoutes  = require('./routes/auctions');
const itemRoutes     = require('./routes/items');
const bidRoutes      = require('./routes/bids');
const likeRoutes     = require('./routes/likes');
const userRoutes     = require('./routes/users');
const fileRoutes     = require('./routes/files');
const categoryRoutes = require('./routes/categories');

app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// 업로드 이미지 정적 파일 서빙 (cais_back/uploads/)
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// ETL 수집 이미지 정적 파일 서빙 (프로젝트 루트/downloaded_images/)
app.use('/downloaded_images', express.static(path.join(__dirname, '..', 'downloaded_images')));

app.use((req, res, next) => {
  console.log(`${req.method} ${req.url}`);
  next();
});

app.use('/api/auth',       authRoutes);
app.use('/api/auctions',   auctionRoutes);
app.use('/api/items',      itemRoutes);
app.use('/api/bids',       bidRoutes);
app.use('/api/likes',      likeRoutes);
app.use('/api/users',      userRoutes);
app.use('/api/files',      fileRoutes);
app.use('/api/categories', categoryRoutes);

app.get('/', (req, res) => {
  res.json({ message: 'CAIS API Server' });
});

app.use((err, req, res, next) => {
  console.error('Error:', err);
  res.status(500).json({ message: 'Server error', error: err.message });
});

module.exports = app;
