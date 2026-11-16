import '../../models/courier_notification.dart';
import 'api_client.dart';
import 'financial_session.dart';

class NotificationService {
  NotificationService._();

  static Future<CourierNotificationPage> page({
    int page = 1,
    bool forceRefresh = false,
  }) {
    if (page < 1) throw ArgumentError.value(page, 'page', 'Must be at least 1');
    return financialRead(
      () async => CourierNotificationPage.fromJson(
        Map<String, dynamic>.from(
          await ApiClient.get(
                '/courier/notifications',
                query: {'page': '$page'},
                cacheFor: const Duration(seconds: 60),
                forceRefresh: forceRefresh,
              )
              as Map,
        ),
      ),
    );
  }

  static Future<void> markRead(String id) async {
    await ApiClient.post(
      '/courier/notifications/${Uri.encodeComponent(id)}/read',
      refreshCache: false,
    );
  }

  static Future<void> markAllRead() async {
    await ApiClient.post(
      '/courier/notifications/read-all',
      refreshCache: false,
    );
  }
}
