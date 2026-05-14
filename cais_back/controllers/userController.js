/*
controllers/userController.js
사용자 컨트롤러
*/

const userModel = require('../models/userModel');
const bidModel  = require('../models/bidModel');
const likeModel = require('../models/likeModel');

exports.getMyProfile = async (req, res) => {
  try {
    const user = await userModel.findById(req.user.userId);
    if (!user) return res.status(404).json({ error: '사용자를 찾을 수 없습니다' });

    // 입찰 통계 — bid 테이블이 없는 환경에서도 프로필이 깨지지 않도록 개별 처리
    let bidCount = 0;
    let wonCount = 0;
    try {
      const biddingBids = await bidModel.findMyBids(req.user.userId, 'bidding');
      bidCount = biddingBids.length;
    } catch (_) { /* bid 테이블 미존재 시 0으로 처리 */ }
    try {
      const wonBids = await bidModel.findMyBids(req.user.userId, 'won');
      wonCount = wonBids.length;
    } catch (_) {}

    // 찜 수 — app_user.user_watchlist_target 참조
    let favoriteCount = 0;
    try {
      const likes = await likeModel.findMyLikes(req.user.userId);
      favoriteCount = likes.length;
    } catch (_) {}

    res.json({
      user,
      stats: { bidCount, wonCount, favoriteCount },
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

exports.updateProfile = async (req, res) => {
  try {
    const { userName } = req.body;
    await userModel.update(req.user.userId, { userName });
    const user = await userModel.findById(req.user.userId);
    res.json({ user });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

exports.updateLocation = async (req, res) => {
  try {
    const { preferredCstmSgn } = req.body;
    if (!preferredCstmSgn) return res.status(400).json({ error: 'preferredCstmSgn이 필요합니다' });
    await userModel.update(req.user.userId, { preferredCstmSgn });
    res.json({ message: '위치가 업데이트되었습니다', preferredCstmSgn });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

exports.getBidCalendar = async (req, res) => {
  try {
    const year  = parseInt(req.query.year  || new Date().getFullYear());
    const month = parseInt(req.query.month || new Date().getMonth() + 1);
    let data = [];
    try {
      data = await bidModel.findCalendarData(req.user.userId, year, month);
    } catch (_) { /* bid 테이블 미존재 시 빈 배열 반환 */ }
    res.json({ calendar: data });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};
