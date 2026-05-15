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
    String? categoryId,
    String? cstmSgn,
    int page = 1,
    int limit = ApiConfig.defaultPageSize,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'limit': '$limit',
    };
    if (keyword != null && keyword.isNotEmpty) params['keyword'] = keyword;
    if (categoryId != null) params['categoryId'] = categoryId;
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
