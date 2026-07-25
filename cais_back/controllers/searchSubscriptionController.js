/*
controllers/searchSubscriptionController.js
관심 검색어 구독 컨트롤러
*/

const searchSubscriptionModel = require('../models/searchSubscriptionModel');

exports.getMySubscriptions = async (req, res) => {
  try {
    const subscriptions = await searchSubscriptionModel.findMySubscriptions(req.user.userId);
    res.json({ subscriptions });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

exports.addSubscription = async (req, res) => {
  try {
    const { keyword } = req.body;
    if (!keyword || !keyword.trim()) return res.status(400).json({ error: 'keyword가 필요합니다' });
    const subscriptionId = await searchSubscriptionModel.add(req.user.userId, keyword.trim());
    res.json({ subscriptionId });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

exports.removeSubscription = async (req, res) => {
  try {
    await searchSubscriptionModel.remove(req.user.userId, req.params.subscriptionId);
    res.json({ message: '구독이 삭제되었습니다' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};

exports.toggleSubscription = async (req, res) => {
  try {
    const { enabled } = req.body;
    await searchSubscriptionModel.setNotifyEnabled(req.user.userId, req.params.subscriptionId, !!enabled);
    res.json({ message: '알림 설정이 변경되었습니다' });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: '서버 오류' });
  }
};
