import 'receipt.dart';

enum NotificationScreen { cash, earnings }

class MoneyDestination {
  final NotificationScreen screen;
  final ReceiptTarget? receipt;
  const MoneyDestination(this.screen, this.receipt);
}

class CourierNotification {
  final String id, kind, title, body;
  final String? url, createdAt;
  final Map<String, dynamic> meta;
  final bool read;

  CourierNotification.fromJson(Map<String, dynamic> json)
    : id = json['id']?.toString() ?? '',
      kind = json['kind']?.toString() ?? '',
      title = json['title']?.toString() ?? 'Notification',
      body = json['body']?.toString() ?? '',
      url = json['url']?.toString(),
      createdAt = json['created_at']?.toString(),
      meta = json['meta'] is Map
          ? Map<String, dynamic>.from(json['meta'] as Map)
          : {},
      read = json['read'] == true;

  MoneyDestination? get moneyDestination {
    NotificationScreen? screen;
    if (kind == 'cash.handover.confirmed' || kind == 'cash.handover.short') {
      screen = NotificationScreen.cash;
    } else if (kind == 'rider.payout.paid') {
      screen = NotificationScreen.earnings;
    } else if (meta['screen'] == 'cash') {
      screen = NotificationScreen.cash;
    } else if (meta['screen'] == 'earnings') {
      screen = NotificationScreen.earnings;
    } else {
      final uri = Uri.tryParse(url ?? '');
      if (uri != null &&
          !uri.hasScheme &&
          !uri.hasAuthority &&
          !uri.hasFragment) {
        screen = switch (uri.path) {
          '/api/courier/cash/history' ||
          '/api/courier/cash/summary' => NotificationScreen.cash,
          '/api/courier/earnings' ||
          '/api/courier/earnings/summary' ||
          '/api/courier/earnings/history' => NotificationScreen.earnings,
          _ => null,
        };
      }
    }
    if (screen == null) return null;
    final reference = meta['reference_no']?.toString();
    return MoneyDestination(
      screen,
      reference == null || reference.isEmpty
          ? null
          : ReceiptTarget(
              screen == NotificationScreen.cash
                  ? ReceiptType.cashHandover
                  : ReceiptType.riderPayout,
              reference,
            ),
    );
  }
}

class CourierNotificationPage {
  final List<CourierNotification> items;
  final int unread, currentPage, lastPage, total;

  CourierNotificationPage.fromJson(Map<String, dynamic> json)
    : items = [
        for (final row in json['data'] as List? ?? const [])
          CourierNotification.fromJson(Map<String, dynamic>.from(row as Map)),
      ],
      unread = (json['unread'] as num?)?.toInt() ?? 0,
      currentPage = (json['meta']?['current_page'] as num?)?.toInt() ?? 1,
      lastPage = (json['meta']?['last_page'] as num?)?.toInt() ?? 1,
      total = (json['meta']?['total'] as num?)?.toInt() ?? 0;
}
