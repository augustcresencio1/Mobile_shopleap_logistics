import '../core/utils/money.dart';
import 'delivery_proof.dart';

/// The same immutable filter is sent to the summary and every history page.
class EarningsFilter {
  final Map<String, String> query;

  EarningsFilter({
    String period = 'month',
    String? preset,
    DateTime? from,
    DateTime? to,
  }) : query = Map.unmodifiable(_query(period, preset, from, to));

  static DateTime manilaToday([DateTime? now]) {
    final date = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
    return DateTime.utc(date.year, date.month, date.day);
  }

  static Map<String, String> _query(
    String period,
    String? preset,
    DateTime? from,
    DateTime? to,
  ) {
    const periods = {'today', 'week', 'month', 'all', '7d', '30d', 'custom'};
    const presets = {'today', '7d', '30d', 'custom'};
    final selected = preset ?? period;
    if (!(preset == null ? periods : presets).contains(selected)) {
      throw ArgumentError('Unsupported earnings period.');
    }
    final result = <String, String>{
      if (preset != null) 'preset': preset else 'period': period,
    };
    if (selected == 'custom') {
      if (from == null || to == null) {
        throw ArgumentError('Choose both dates for a custom range.');
      }
      final start = DateTime.utc(from.year, from.month, from.day);
      final end = DateTime.utc(to.year, to.month, to.day);
      final days = end.difference(start).inDays + 1;
      if (days < 1 || days > 366) {
        throw ArgumentError('Choose a range of 1 to 366 calendar days.');
      }
      result['from'] = start.toIso8601String().substring(0, 10);
      result['to'] = end.toIso8601String().substring(0, 10);
    }
    return result;
  }
}

class EarningSnapshot {
  final String? amount;
  final String currency;
  final String? recordedAt;

  EarningSnapshot.fromJson(Map<String, dynamic> json)
    : amount = decimalMoney(json['amount']),
      currency = json['currency']?.toString() ?? 'PHP',
      recordedAt = json['recorded_at']?.toString();
}

class DeliveryResult {
  final String message;
  final EarningSnapshot? earning;
  final DeliveryProof proof;

  DeliveryResult.fromJson(Map<String, dynamic> json)
    : proof = DeliveryProof.fromJson(json['proof']),
      message = json['message']?.toString() ?? 'Delivery recorded. Thank you.',
      earning = json['earning'] is Map
          ? EarningSnapshot.fromJson(
              Map<String, dynamic>.from(json['earning'] as Map),
            )
          : null;
}

class EarningsHistoryItem extends EarningSnapshot {
  final String? payoutStatus;
  String get payoutLabel => switch (payoutStatus) {
    'accrued' => 'Accrued / unpaid',
    'paid' => 'Paid',
    _ => 'Payment status unavailable',
  };
  final DeliveryProof proof;
  final String orderId;
  final bool _orderIdIsPublic;
  final String orderNumber, waybillCode;

  String get reference => orderNumber.isNotEmpty
      ? orderNumber
      : (waybillCode.isNotEmpty
            ? waybillCode
            : _orderIdIsPublic && orderId.isNotEmpty
            ? orderId
            : 'Reference unavailable');
  final String? deliveredAt;

  EarningsHistoryItem.fromJson(super.json)
    : payoutStatus = json['payout_status']?.toString(),
      proof = DeliveryProof.fromJson(json['proof']),
      orderId = json['order_id']?.toString() ?? '',
      _orderIdIsPublic = json['order_id'] is String,
      orderNumber = (json['order_number'] ?? '').toString().trim(),
      waybillCode = (json['waybill_code'] ?? '').toString().trim(),
      deliveredAt = json['delivered_at']?.toString(),
      super.fromJson();
}

class EarningsHistoryPage {
  final List<EarningsHistoryItem> items;
  final int currentPage, lastPage, total;

  EarningsHistoryPage.fromJson(Map<String, dynamic> json)
    : items = [
        for (final item in (json['data'] as List? ?? const []))
          EarningsHistoryItem.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
      currentPage = (json['meta']['current_page'] as num).toInt(),
      lastPage = (json['meta']['last_page'] as num).toInt(),
      total = (json['meta']['total'] as num).toInt();
}

class EarningsOverview {
  final Map<String, dynamic> summary, rate;
  final EarningsHistoryPage history;
  String? get accruedUnpaid => decimalMoney(summary['accrued_unpaid']);
  String? get paid => decimalMoney(summary['paid']);

  EarningsOverview({
    required this.summary,
    required this.rate,
    required this.history,
  });

  EarningsOverview.fromJson(Map<String, dynamic> json)
    : summary = Map<String, dynamic>.from(json['summary'] as Map),
      rate = Map<String, dynamic>.from(json['rate'] as Map),
      history = EarningsHistoryPage.fromJson(
        Map<String, dynamic>.from(json['history'] as Map),
      );
}
