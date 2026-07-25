/*
services/geocodeService.js
카카오 로컬 API를 이용한 주소 → 좌표 변환
문서: https://developers.kakao.com/docs/latest/ko/local/dev-guide#address-coord
*/

const axios = require('axios');

const KAKAO_GEOCODE_URL = 'https://dapi.kakao.com/v2/local/search/address.json';
const KAKAO_REVERSE_GEOCODE_URL = 'https://dapi.kakao.com/v2/local/geo/coord2address.json';

const _authHeader = () => {
  const apiKey = process.env.KAKAO_REST_API_KEY;
  if (!apiKey) throw new Error('KAKAO_REST_API_KEY가 설정되지 않았습니다 (.env 확인 필요)');
  return { Authorization: `KakaoAK ${apiKey}` };
};

// address 문자열을 받아 { latitude, longitude }를 반환. 매칭 실패 시 null.
exports.geocodeAddress = async (address) => {
  const { data } = await axios.get(KAKAO_GEOCODE_URL, {
    params: { query: address },
    headers: _authHeader(),
  });

  const first = data.documents && data.documents[0];
  if (!first) return null;

  return {
    latitude: parseFloat(first.y),
    longitude: parseFloat(first.x),
  };
};

// 좌표(GPS)를 받아 사람이 읽을 수 있는 주소 문자열로 변환. 매칭 실패 시 null.
exports.reverseGeocodeAddress = async (latitude, longitude) => {
  const { data } = await axios.get(KAKAO_REVERSE_GEOCODE_URL, {
    params: { x: longitude, y: latitude },
    headers: _authHeader(),
  });

  const first = data.documents && data.documents[0];
  if (!first) return null;

  return first.road_address?.address_name || first.address?.address_name || null;
};
