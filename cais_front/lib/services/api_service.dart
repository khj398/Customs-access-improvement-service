import 'dart:convert';
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
