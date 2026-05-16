import 'dart:convert';
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

  Map<String, String> _authHeaders() => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  void _saveAuth(Map<String, dynamic> data) {
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
