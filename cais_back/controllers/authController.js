/*
controllers/authController.js
회원가입 / 로그인 컨트롤러
*/

const bcrypt = require('bcryptjs');
const jwt    = require('jsonwebtoken');
const userModel = require('../models/userModel');

exports.register = async (req, res) => {
  try {
    const { userEmail, userPassword, userName } = req.body;
    if (!userEmail || !userPassword || !userName) {
      return res.status(400).json({ error: '이메일, 비밀번호, 이름은 필수입니다' });
    }
    const exists = await userModel.checkEmailExists(userEmail);
    if (exists) return res.status(409).json({ error: '이미 사용 중인 이메일입니다' });

    const hashed = await bcrypt.hash(userPassword, 12);
    const userId = await userModel.create(userEmail, hashed, userName);

    const token = jwt.sign({ userId, userEmail, userName }, process.env.JWT_SECRET, { expiresIn: '7d' });
    res.status(201).json({ token, userId, userEmail, userName });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

exports.login = async (req, res) => {
  try {
    const { userEmail, userPassword } = req.body;
    if (!userEmail || !userPassword) {
      return res.status(400).json({ error: '이메일과 비밀번호를 입력해주세요' });
    }
    const user = await userModel.findByEmail(userEmail);
    if (!user) return res.status(401).json({ error: '이메일 또는 비밀번호가 올바르지 않습니다' });

    const match = await bcrypt.compare(userPassword, user.userPassword);
    if (!match) return res.status(401).json({ error: '이메일 또는 비밀번호가 올바르지 않습니다' });

    const token = jwt.sign(
      { userId: user.userId, userEmail: user.userEmail, userName: user.userName },
      process.env.JWT_SECRET,
      { expiresIn: '7d' }
    );
    res.json({ token, userId: user.userId, userEmail: user.userEmail, userName: user.userName });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};
