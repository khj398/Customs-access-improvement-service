/*
config/db.js
MySQL 연결 풀 설정
*/

const mysql = require('mysql2/promise');

const pool = mysql.createPool({
  host:     process.env.DB_HOST     || 'localhost',
  port:     parseInt(process.env.DB_PORT || '3306'),
  user:     process.env.DB_USER     || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME     || 'customs_auction',
  charset:  'utf8mb4',
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
  // BIGINT(LONGLONG) 값을 JS Number로 변환 (JSON 직렬화 안전 보장)
  typeCast: function(field, next) {
    if (field.type === 'LONGLONG') {
      const val = field.string();
      return val === null ? null : Number(val);
    }
    return next();
  },
});

module.exports = pool;
