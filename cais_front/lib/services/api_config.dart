import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

class ApiConfig {
  static String get baseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) return envUrl;
    // dart:io Platform은 web에서 사용 불가 → kIsWeb으로 먼저 분기
    if (kIsWeb) return 'http://localhost:3000';
    // Android 에뮬레이터는 10.0.2.2 → 호스트 localhost
    if (Platform.isAndroid) return 'http://10.0.2.2:3000';
    return 'http://localhost:3000';
  }

  static const int timeoutSeconds = 10;
  static const int defaultPageSize = 20;
}
