import '../core/utils/money.dart';

class OutstandingCashOrder {
  final String orderNumber;
  final String? amount, deliveredAt;

  OutstandingCashOrder.fromJson(Map<String, dynamic> json)
    : orderNumber = json['order_number']?.toString() ?? '',
      amount = decimalMoney(json['amount']),
      deliveredAt = json['delivered_at']?.toString();
}

class CashSummary {
  final String? cashOnHand, shortageAmount;
  final String currency;
  final List<OutstandingCashOrder> orders;

  CashSummary.fromJson(Map<String, dynamic> json)
    : cashOnHand = decimalMoney(json['cash_on_hand']),
      shortageAmount = decimalMoney(json['shortage_amount']),
      currency = json['currency']?.toString() ?? 'PHP',
      orders = [
        for (final row in json['orders'] as List? ?? const [])
          OutstandingCashOrder.fromJson(Map<String, dynamic>.from(row as Map)),
      ];
}

class CashHandover {
  final String reference, currency, status;
  final String? amount, confirmedAt;

  CashHandover.fromJson(Map<String, dynamic> json, {String currency = 'PHP'})
    : reference = json['reference_no']?.toString() ?? '',
      amount = decimalMoney(json['amount']),
      currency = json['currency']?.toString() ?? currency,
      status = json['status']?.toString() ?? '',
      confirmedAt = json['confirmed_at']?.toString();

  String get statusLabel => switch (status) {
    'confirmed' => 'Confirmed',
    'short' => 'Short',
    'settled' => 'Settled',
    _ => 'Unknown status',
  };
}

class CashHistoryPage {
  final List<CashHandover> items;
  final int currentPage, lastPage, total;

  CashHistoryPage.fromJson(Map<String, dynamic> json)
    : items = [
        for (final row in json['data'] as List? ?? const [])
          CashHandover.fromJson(
            Map<String, dynamic>.from(row as Map),
            currency: json['currency']?.toString() ?? 'PHP',
          ),
      ],
      currentPage = (json['meta']['current_page'] as num).toInt(),
      lastPage = (json['meta']['last_page'] as num).toInt(),
      total = (json['meta']['total'] as num).toInt();
}
