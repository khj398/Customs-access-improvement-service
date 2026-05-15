/*
  services/api_service.dart

  백엔드 REST API 호출 서비스
  Base URL: http://10.0.2.2:3000  (Android 에뮬레이터 → localhost:3000)
*/

import 'dart:convert';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import '../models/auction_item.dart';
import '../models/bid_entry.dart';
import '../models/like_entry.dart';

class ApiService {
  static const String baseUrl = 'http://10.0.2.2:3000';
  static final _box = GetStorage();

  static const _kToken     = 'jwt_token';
  static const _kUserId    = 'userId';
  static const _kUserEmail = 'userEmail';
  static const _kUserName  = 'userName';

  // ─── Auth helpers ─────────────────────────────────────

  static String? get token => _box.read<String>(_kToken);
  static bool    get isLoggedIn => token != null && token!.isNotEmpty;

  static Map<String, String> _authHeaders() => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  static void _saveAuth(Map<String, dynamic> data) {
    _box.write(_kToken,     data['token']);
    _box.write(_kUserId,    data['userId']);
    _box.write(_kUserEmail, data['userEmail']);
    _box.write(_kUserName,  data['userName']);
  }

  static void logout() {
    _box.remove(_kToken);
    _box.remove(_kUserId);
    _box.remove(_kUserEmail);
    _box.remove(_kUserName);
  }

  // ─── Auth ─────────────────────────────────────────────

  /// POST /api/auth/login
  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userEmail': email, 'userPassword': password}),
    );
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode == 200) {
      _saveAuth(data);
      return data;
    }
    throw Exception(data['error'] ?? '로그인에 실패했습니다');
  }

  /// POST /api/auth/register
  static Future<Map<String, dynamic>> register(
      String email, String password, String userName) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(
          {'userEmail': email, 'userPassword': password, 'userName': userName}),
    );
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode == 201) {
      _saveAuth(data);
      return data;
    }
    throw Exception(data['error'] ?? '회원가입에 실패했습니다');
  }

  // ─── Items ────────────────────────────────────────────

  /// GET /api/items/search?limit=N
  /// 로그인 시 인증 헤더를 함께 전송하여 isFavorite 정보를 받아온다
  static Future<List<AuctionItem>> fetchNewItems({int limit = 10}) async {
    final uri = Uri.parse('$baseUrl/api/items/search')
        .replace(queryParameters: {'limit': '$limit'});
    final response = await http.get(uri, headers: _authHeaders());
    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final List items = data['items'] ?? [];
      return items
          .map((e) => AuctionItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load new items (${response.statusCode})');
  }

  /// GET /api/items/search?keyword=&categoryId=&cstmSgn=&page=&limit=
  /// 로그인 시 인증 헤더를 함께 전송하여 isFavorite 정보를 받아온다
  static Future<List<AuctionItem>> searchItems({
    String? keyword,
    String? categoryId,
    String? cstmSgn,
    int page = 1,
    int limit = 20,
  }) async {
    final params = <String, String>{'page': '$page', 'limit': '$limit'};
    if (keyword != null && keyword.trim().isNotEmpty) {
      params['keyword'] = keyword.trim();
    }
    if (categoryId != null && categoryId.isNotEmpty) {
      params['categoryId'] = categoryId;
    }
    if (cstmSgn != null && cstmSgn.isNotEmpty) {
      params['cstmSgn'] = cstmSgn;
    }
    final uri = Uri.parse('$baseUrl/api/items/search')
        .replace(queryParameters: params);
    final response = await http.get(uri, headers: _authHeaders());
    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final List items = data['items'] ?? [];
      return items
          .map((e) => AuctionItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to search items (${response.statusCode})');
  }

  /// GET /api/items/:pbacNo/:pbacSrno/:cmdtLnNo
  static Future<AuctionItem> fetchItemDetail(
      String pbacNo, String pbacSrno, String cmdtLnNo) async {
    final uri = Uri.parse('$baseUrl/api/items/$pbacNo/$pbacSrno/$cmdtLnNo');
    final response = await http.get(uri, headers: _authHeaders());
    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return AuctionItem.fromJson(data['item'] as Map<String, dynamic>);
    }
    throw Exception('Failed to load item detail (${response.statusCode})');
  }

  // ─── Bids ─────────────────────────────────────────────

  /// GET /api/bids/my?status=bidding|won|expired
  static Future<List<BidEntry>> fetchMyBids(String status) async {
    final uri = Uri.parse('$baseUrl/api/bids/my')
        .replace(queryParameters: {'status': status});
    final response = await http.get(uri, headers: _authHeaders());
    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final List bids = data['bids'] ?? [];
      return bids
          .map((e) => BidEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load bids (${response.statusCode})');
  }

  /// POST /api/bids
  static Future<void> submitBid(
      String pbacNo, String pbacSrno, String cmdtLnNo, int bidAmount) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/bids'),
      headers: _authHeaders(),
      body: jsonEncode({
        'pbacNo': pbacNo,
        'pbacSrno': pbacSrno,
        'cmdtLnNo': cmdtLnNo,
        'bidAmount': bidAmount,
      }),
    );
    if (response.statusCode != 201) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      throw Exception(data['error'] ?? '입찰에 실패했습니다');
    }
  }

  /// DELETE /api/bids/:bidId
  static Future<void> cancelBid(int bidId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/bids/$bidId'),
      headers: _authHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('입찰 취소에 실패했습니다');
    }
  }

  // ─── Likes ────────────────────────────────────────────

  /// GET /api/likes/my
  static Future<List<LikeEntry>> fetchMyLikes() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/likes/my'),
      headers: _authHeaders(),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final List likes = data['likes'] ?? [];
      return likes
          .map((e) => LikeEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load likes (${response.statusCode})');
  }

  /// POST /api/likes/toggle  → true if now liked, false if unliked
  static Future<bool> toggleLike(
      String pbacNo, String pbacSrno, String cmdtLnNo) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/likes/toggle'),
      headers: _authHeaders(),
      body: jsonEncode(
          {'pbacNo': pbacNo, 'pbacSrno': pbacSrno, 'cmdtLnNo': cmdtLnNo}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data['liked'] as bool;
    }
    throw Exception('Failed to toggle like (${response.statusCode})');
  }

  // ─── Categories ───────────────────────────────────────

  /// GET /api/categories → { categories: [{categoryId, nameKo, nameEn}] }
  static Future<List<Map<String, dynamic>>> fetchCategories() async {
    final response = await http.get(Uri.parse('$baseUrl/api/categories'));
    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return List<Map<String, dynamic>>.from(data['categories'] ?? []);
    }
    throw Exception('Failed to load categories (${response.statusCode})');
  }

  // ─── User ─────────────────────────────────────────────

  /// GET /api/users/me  → { user: {...}, stats: {bidCount, wonCount, favoriteCount} }
  static Future<Map<String, dynamic>> fetchMyProfile() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/users/me'),
      headers: _authHeaders(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    }
    throw Exception('Failed to load profile (${response.statusCode})');
  }

  /// GET /api/users/me/calendar?year=&month=
  static Future<List<Map<String, dynamic>>> fetchBidCalendar(
      int year, int month) async {
    final uri = Uri.parse('$baseUrl/api/users/me/calendar')
        .replace(queryParameters: {'year': '$year', 'month': '$month'});
    final response = await http.get(uri, headers: _authHeaders());
    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return List<Map<String, dynamic>>.from(data['calendar'] ?? []);
    }
    throw Exception('Failed to load calendar (${response.statusCode})');
  }

  /// GET /api/items/calendar?year=&month=
  /// 해당 연월에 공매가 마감되는 물품 전체 반환 (로그인 시 isFavorite 포함)
  static Future<List<AuctionItem>> fetchItemCalendar(
      int year, int month) async {
    final uri = Uri.parse('$baseUrl/api/items/calendar')
        .replace(queryParameters: {'year': '$year', 'month': '$month'});
    final response = await http.get(uri, headers: _authHeaders());
    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final List items = data['items'] ?? [];
      return items
          .map((e) => AuctionItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load item calendar (${response.statusCode})');
  }
}
