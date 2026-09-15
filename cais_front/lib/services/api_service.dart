import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import '../models/item.dart';
import 'api_config.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => 'ApiException: $message';
}

class ApiService {
  final String _base = ApiConfig.baseUrl;
  final Duration _timeout = Duration(seconds: ApiConfig.timeoutSeconds);
  static final _box = GetStorage();

  static const _kToken    = 'jwt_token';
  static const _kUserId   = 'userId';
  static const _kUserName = 'userName';
  static const _kEmail    = 'userEmail';

  static String? get token     => _box.read<String>(_kToken);
  static bool    get isLoggedIn => token != null && token!.isNotEmpty;
  static String  get userName  => _box.read<String>(_kUserName) ?? '';
  static String  get userEmail => _box.read<String>(_kEmail) ?? '';

  /// 세션이 만료된 토큰으로 사용자가 직접 시도한 요청이 401을 받았을 때 한 번 호출됨
  /// (자동으로 도는 백그라운드 조회에는 걸지 않음 — 갑자기 로그아웃되는 느낌을 피하기 위함)
  static void Function()? onUnauthorized;
  static bool _unauthorizedHandled = false;

  static void _notifyUnauthorized() {
    if (_unauthorizedHandled) return;
    _unauthorizedHandled = true;
    onUnauthorized?.call();
  }

  void _checkUnauthorized(http.Response res) {
    if (res.statusCode == 401) _notifyUnauthorized();
  }

  Map<String, String> _authHeaders() => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  void _saveAuth(Map<String, dynamic> data) {
    _unauthorizedHandled = false;
    _box.write(_kToken,    data['token']);
    _box.write(_kUserId,   data['userId']);
    _box.write(_kUserName, data['userName']);
    _box.write(_kEmail,    data['userEmail']);
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await http.post(
      Uri.parse('$_base/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userEmail': email, 'userPassword': password}),
    ).timeout(_timeout);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode == 200) { _saveAuth(data); return data; }
    throw ApiException(data['error'] ?? '로그인에 실패했습니다', statusCode: res.statusCode);
  }

  Future<Map<String, dynamic>> register(String email, String password, String name) async {
    final res = await http.post(
      Uri.parse('$_base/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userEmail': email, 'userPassword': password, 'userName': name}),
    ).timeout(_timeout);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode == 201) { _saveAuth(data); return data; }
    throw ApiException(data['error'] ?? '회원가입에 실패했습니다', statusCode: res.statusCode);
  }

  static void logout() {
    _unauthorizedHandled = false;
    _box.remove(_kToken);
    _box.remove(_kUserId);
    _box.remove(_kUserName);
    _box.remove(_kEmail);
  }

  Future<List<AuctionItem>> fetchItems({
    String? keyword,
    int? categoryId,
    String? cstmSgn,
    int page = 1,
    int limit = ApiConfig.defaultPageSize,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'limit': '$limit',
    };
    if (keyword != null && keyword.isNotEmpty) params['keyword'] = keyword;
    if (categoryId != null) params['categoryId'] = categoryId.toString();
    if (cstmSgn != null) params['cstmSgn'] = cstmSgn;

    final uri = Uri.parse('$_base/api/items/search').replace(queryParameters: params);
    try {
      final res = await http.get(uri).timeout(_timeout);
      if (res.statusCode != 200) {
        throw ApiException('서버 오류 (${res.statusCode})', statusCode: res.statusCode);
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (body['items'] as List? ?? []);
      return items.map((e) => AuctionItem.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('네트워크 오류: $e');
    }
  }

  Future<List<AuctionItem>> fetchBundledItems(String pbacNo) async {
    final uri = Uri.parse('$_base/api/items/${Uri.encodeComponent(pbacNo)}/bundle');
    try {
      final res = await http.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final items = body['items'] as List? ?? [];
      return items.map((e) => AuctionItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchCustomsStats({double? lat, double? lng}) async {
    final params = <String, String>{
      if (lat != null) 'lat': '$lat',
      if (lng != null) 'lng': '$lng',
    };
    final uri = Uri.parse('$_base/api/items/customs-stats').replace(queryParameters: params.isEmpty ? null : params);
    try {
      final res = await http.get(uri, headers: _authHeaders()).timeout(_timeout);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(body['customs'] as List? ?? []);
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> fetchBaseLocation() async {
    if (!isLoggedIn) return null;
    try {
      final res = await http.get(
        Uri.parse('$_base/api/users/me/base-location'),
        headers: _authHeaders(),
      ).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['location'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> updateBaseLocationGps(double latitude, double longitude, {String? label}) async {
    final res = await http.put(
      Uri.parse('$_base/api/users/me/base-location'),
      headers: _authHeaders(),
      body: jsonEncode({'latitude': latitude, 'longitude': longitude, if (label != null) 'label': label}),
    ).timeout(_timeout);
    _checkUnauthorized(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) throw ApiException(body['error'] ?? '위치 저장에 실패했습니다', statusCode: res.statusCode);
    return body['location'] as Map<String, dynamic>;
  }

  /// 좌표 → 주소 미리보기 (저장 안 함). 실패 시 둘 다 null.
  Future<Map<String, String?>> reverseGeocode(double latitude, double longitude) async {
    final uri = Uri.parse('$_base/api/users/me/base-location/reverse-geocode').replace(
      queryParameters: {'latitude': '$latitude', 'longitude': '$longitude'},
    );
    try {
      final res = await http.get(uri, headers: _authHeaders()).timeout(_timeout);
      _checkUnauthorized(res);
      if (res.statusCode != 200) {
        debugPrint('reverseGeocode 실패: HTTP ${res.statusCode} ${res.body}');
        return {'roadAddress': null, 'jibunAddress': null};
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return {
        'roadAddress': body['roadAddress'] as String?,
        'jibunAddress': body['jibunAddress'] as String?,
      };
    } catch (e) {
      debugPrint('reverseGeocode 예외: $e');
      return {'roadAddress': null, 'jibunAddress': null};
    }
  }

  Future<Map<String, dynamic>> updateBaseLocationAddress(String address, {String? label}) async {
    final res = await http.put(
      Uri.parse('$_base/api/users/me/base-location'),
      headers: _authHeaders(),
      body: jsonEncode({'address': address, if (label != null) 'label': label}),
    ).timeout(_timeout);
    _checkUnauthorized(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) throw ApiException(body['error'] ?? '주소를 찾을 수 없습니다', statusCode: res.statusCode);
    return body['location'] as Map<String, dynamic>;
  }

  // 앱 시작 시 자동으로도 호출되는 백그라운드 동기화라 401이어도 세션 만료 처리를 걸지 않음
  // (사용자가 누른 적 없는데 갑자기 로그인 화면으로 튕기는 걸 방지)
  Future<void> registerDeviceToken(String fcmToken, {String platform = 'ANDROID'}) async {
    if (!isLoggedIn) return;
    await http.post(
      Uri.parse('$_base/api/users/me/device-token'),
      headers: _authHeaders(),
      body: jsonEncode({'fcmToken': fcmToken, 'platform': platform}),
    ).timeout(_timeout);
  }

  Future<void> removeDeviceToken(String fcmToken) async {
    if (!isLoggedIn) return;
    await http.delete(
      Uri.parse('$_base/api/users/me/device-token'),
      headers: _authHeaders(),
      body: jsonEncode({'fcmToken': fcmToken}),
    ).timeout(_timeout);
  }

  Future<List<Map<String, dynamic>>> fetchSearchSubscriptions() async {
    if (!isLoggedIn) return [];
    try {
      final res = await http.get(
        Uri.parse('$_base/api/search-subscriptions'),
        headers: _authHeaders(),
      ).timeout(_timeout);
      if (res.statusCode != 200) return [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(body['subscriptions'] as List? ?? []);
    } catch (_) {
      return [];
    }
  }

  Future<void> addSearchSubscription(String keyword) async {
    final res = await http.post(
      Uri.parse('$_base/api/search-subscriptions'),
      headers: _authHeaders(),
      body: jsonEncode({'keyword': keyword}),
    ).timeout(_timeout);
    _checkUnauthorized(res);
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw ApiException(body['error'] ?? '구독 등록에 실패했습니다', statusCode: res.statusCode);
    }
  }

  Future<void> removeSearchSubscription(int subscriptionId) async {
    final res = await http.delete(
      Uri.parse('$_base/api/search-subscriptions/$subscriptionId'),
      headers: _authHeaders(),
    ).timeout(_timeout);
    _checkUnauthorized(res);
  }

  Future<void> toggleSearchSubscription(int subscriptionId, bool enabled) async {
    final res = await http.patch(
      Uri.parse('$_base/api/search-subscriptions/$subscriptionId'),
      headers: _authHeaders(),
      body: jsonEncode({'enabled': enabled}),
    ).timeout(_timeout);
    _checkUnauthorized(res);
  }

  Future<Map<int, int>> fetchCategoryStats() async {
    final uri = Uri.parse('$_base/api/items/category-stats');
    try {
      final res = await http.get(uri).timeout(_timeout);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final raw = body['stats'] as Map<String, dynamic>? ?? {};
      return raw.map((k, v) => MapEntry(int.tryParse(k) ?? 0, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> fetchCategories() async {
    final uri = Uri.parse('$_base/api/categories');
    try {
      final res = await http.get(uri).timeout(_timeout);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(body['categories'] as List? ?? []);
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchSubCategories(int parentId) async {
    final uri = Uri.parse('$_base/api/categories/$parentId/children');
    try {
      final res = await http.get(uri).timeout(_timeout);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(body['categories'] as List? ?? []);
    } catch (_) {
      return [];
    }
  }

  Future<List<AuctionItem>> fetchMyLikeItems() async {
    if (!isLoggedIn) return [];
    try {
      final res = await http.get(
        Uri.parse('$_base/api/likes/my'),
        headers: _authHeaders(),
      ).timeout(_timeout);
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final likes = data['likes'] as List? ?? [];
      return likes.map((e) => AuctionItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> fetchMyLikeKeys() async {
    if (!isLoggedIn) return [];
    try {
      final res = await http.get(
        Uri.parse('$_base/api/likes/keys'),
        headers: _authHeaders(),
      ).timeout(_timeout);
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final keys = data['keys'] as List? ?? [];
      return keys.map((e) {
        final m = e as Map<String, dynamic>;
        final srno = _toInt(m['pbacSrno']);
        final ln   = _toInt(m['cmdtLnNo']);
        return '${m['pbacNo']}_${srno}_$ln';
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static int _toInt(dynamic v) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

  Future<bool> toggleLike(String pbacNo, int pbacSrno, int cmdtLnNo) async {
    final res = await http.post(
      Uri.parse('$_base/api/likes/toggle'),
      headers: _authHeaders(),
      body: jsonEncode({
        'pbacNo': pbacNo,
        'pbacSrno': pbacSrno.toString(),
        'cmdtLnNo': cmdtLnNo.toString(),
      }),
    ).timeout(_timeout);
    _checkUnauthorized(res);
    if (res.statusCode != 200) throw ApiException('찜 처리 실패', statusCode: res.statusCode);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['liked'] as bool;
  }

  Future<List<String>> fetchAutocomplete(String q, {int? categoryId}) async {
    if (q.trim().isEmpty) return [];
    final uri = Uri.parse('$_base/api/items/autocomplete').replace(
      queryParameters: {'q': q, if (categoryId != null) 'categoryId': '$categoryId'},
    );
    try {
      final res = await http.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return List<String>.from(body['suggestions'] as List? ?? []);
    } catch (_) {
      return [];
    }
  }

  Future<List<AuctionItem>> fetchCalendarItems({
    required int year,
    required int month,
  }) async {
    final uri = Uri.parse('$_base/api/items/calendar').replace(
      queryParameters: {'year': '$year', 'month': '$month'},
    );
    try {
      final res = await http.get(uri).timeout(_timeout);
      if (res.statusCode != 200) {
        throw ApiException('서버 오류 (${res.statusCode})', statusCode: res.statusCode);
      }
      final body = jsonDecode(res.body);
      final items = (body is List ? body : (body['items'] as List? ?? []));
      return items.map((e) => AuctionItem.fromJson(e as Map<String, dynamic>)).toList();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('네트워크 오류: $e');
    }
  }
}
