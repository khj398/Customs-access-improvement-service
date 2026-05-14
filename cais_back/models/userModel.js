/*
models/userModel.js
사용자 DB 모델 — app_user 스키마 사용
  app_user.app_user    : user_id, email, password_hash, status, ...
  app_user.user_profile: user_id, nickname, locale, ...

동일 MySQL 서버 내 cross-DB 쿼리로 접근.
authController.js 등 기존 코드가 사용하는 필드명(userId, userEmail,
userPassword, userName, preferredCstmSgn)을 AS 별칭으로 그대로 유지한다.
*/

const pool = require('../config/db');

// SELECT 시 공통 컬럼 별칭
const SELECT_COLS = `
  au.user_id       AS userId,
  au.email         AS userEmail,
  au.password_hash AS userPassword,
  COALESCE(up.nickname, '') AS userName,
  up.locale        AS preferredCstmSgn,
  au.created_at    AS createdAt
`;

exports.findByEmail = async (email) => {
  const [rows] = await pool.query(
    `SELECT ${SELECT_COLS}
     FROM app_user.app_user au
     LEFT JOIN app_user.user_profile up ON au.user_id = up.user_id
     WHERE au.email = ? AND au.status = 'ACTIVE'`,
    [email]
  );
  return rows[0];
};

exports.findById = async (id) => {
  const [rows] = await pool.query(
    `SELECT ${SELECT_COLS}
     FROM app_user.app_user au
     LEFT JOIN app_user.user_profile up ON au.user_id = up.user_id
     WHERE au.user_id = ? AND au.status = 'ACTIVE'`,
    [id]
  );
  return rows[0];
};

exports.create = async (userEmail, hashedPassword, userName) => {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    // 1) 기본 계정 생성
    const [result] = await conn.query(
      `INSERT INTO app_user.app_user (email, password_hash) VALUES (?, ?)`,
      [userEmail, hashedPassword]
    );
    const userId = result.insertId;

    // 2) 프로필 생성
    await conn.query(
      `INSERT INTO app_user.user_profile (user_id, nickname) VALUES (?, ?)`,
      [userId, userName]
    );

    await conn.commit();
    return userId;
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
};

exports.update = async (id, data) => {
  const updates = [];
  const values  = [];
  if (data.userName !== undefined) {
    updates.push('nickname = ?');
    values.push(data.userName);
  }
  if (data.preferredCstmSgn !== undefined) {
    // locale 컬럼을 관심 세관 코드 임시 저장 필드로 활용
    updates.push('locale = ?');
    values.push(data.preferredCstmSgn);
  }
  if (updates.length === 0) return;

  values.push(id);
  await pool.query(
    `UPDATE app_user.user_profile SET ${updates.join(', ')} WHERE user_id = ?`,
    values
  );
};

exports.checkEmailExists = async (email) => {
  const [rows] = await pool.query(
    `SELECT COUNT(*) AS cnt FROM app_user.app_user WHERE email = ?`,
    [email]
  );
  return rows[0].cnt > 0;
};
