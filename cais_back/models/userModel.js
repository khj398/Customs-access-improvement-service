/*
models/userModel.js
사용자 DB 모델 — customs_auction 스키마 사용 (단일 스키마 통합 방식)
  app_user      : user_id, email, password_hash, status, ...
  user_profile  : user_id, nickname, locale, ...
*/

const pool = require('../config/db');

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
     FROM app_user au
     LEFT JOIN user_profile up ON au.user_id = up.user_id
     WHERE au.email = ? AND au.status = 'ACTIVE'`,
    [email]
  );
  return rows[0];
};

exports.findById = async (id) => {
  const [rows] = await pool.query(
    `SELECT ${SELECT_COLS}
     FROM app_user au
     LEFT JOIN user_profile up ON au.user_id = up.user_id
     WHERE au.user_id = ? AND au.status = 'ACTIVE'`,
    [id]
  );
  return rows[0];
};

exports.create = async (userEmail, hashedPassword, userName) => {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    const [result] = await conn.query(
      `INSERT INTO app_user (email, password_hash) VALUES (?, ?)`,
      [userEmail, hashedPassword]
    );
    const userId = result.insertId;

    await conn.query(
      `INSERT INTO user_profile (user_id, nickname) VALUES (?, ?)`,
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
    updates.push('locale = ?');
    values.push(data.preferredCstmSgn);
  }
  if (updates.length === 0) return;

  values.push(id);
  await pool.query(
    `UPDATE user_profile SET ${updates.join(', ')} WHERE user_id = ?`,
    values
  );
};

exports.checkEmailExists = async (email) => {
  const [rows] = await pool.query(
    `SELECT COUNT(*) AS cnt FROM app_user WHERE email = ?`,
    [email]
  );
  return rows[0].cnt > 0;
};
