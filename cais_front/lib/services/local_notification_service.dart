/*
services/local_notification_service.dart
앱이 foreground일 때 수신한 FCM 메시지를 실제 시스템 알림으로 띄운다.
(FCM은 앱이 foreground면 시스템 알림을 자동으로 띄워주지 않으므로,
 background/killed 상태와 동일하게 알림창에 남도록 직접 처리)
*/

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'cais_push_channel';
  static const _channelName = '공매 알림';
  static const _channelDesc = '경매 임박 · 관심 검색어 신규 물품 알림';

  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> show(String title, String body) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }
}
