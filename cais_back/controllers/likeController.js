/*
controllers/likeController.js
찜 컨트롤러
*/

const likeModel = require('../models/likeModel');

exports.getMyLikeKeys = async (req, res) => {
  try {
    const keys = await likeModel.findMyLikeKeys(req.user.userId);
    res.json({ keys });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

exports.getMyLikes = async (req, res) => {
  try {
    const likes = await likeModel.findMyLikes(req.user.userId);
    res.json({ likes });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

exports.toggleLike = async (req, res) => {
  try {
    const { pbacNo, pbacSrno, cmdtLnNo } = req.body;
    if (!pbacNo || !pbacSrno || !cmdtLnNo) {
      return res.status(400).json({ error: '필수 파라미터가 누락되었습니다' });
    }
    const existing = await likeModel.exists(req.user.userId, pbacNo, pbacSrno, cmdtLnNo);
    if (existing) {
      await likeModel.remove(req.user.userId, pbacNo, pbacSrno, cmdtLnNo);
      const count = await likeModel.count(pbacNo, pbacSrno, cmdtLnNo);
      res.json({ liked: false, likeCount: count });
    } else {
      await likeModel.add(req.user.userId, pbacNo, pbacSrno, cmdtLnNo);
      const count = await likeModel.count(pbacNo, pbacSrno, cmdtLnNo);
      res.json({ liked: true, likeCount: count });
    }
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};
