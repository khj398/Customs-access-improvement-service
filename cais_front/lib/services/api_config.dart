import 'dart:io';

class ApiConfig {
  static String get baseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) return envUrl;
    // Android 에뮬레이터는 10.0.2.2 → 호스트 localhost
    // iOS 시뮬레이터 / 웹은 localhost
    if (Platform.isAndroid) return 'http://10.0.2.2:3000';
    return 'http://localhost:3000';
  }

  static const int timeoutSeconds = 10;
  static const int defaultPageSize = 20;
}
