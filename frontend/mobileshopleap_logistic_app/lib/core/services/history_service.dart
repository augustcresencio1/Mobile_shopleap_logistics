import 'package:intl/intl.dart';

import 'api_client.dart';
import 'api_config.dart';
import 'order_service.dart';
import '../utils/money.dart';
import '../../models/delivery_proof.dart';

class HistoryItem {
  final DeliveryProof proof;
  final String orderId;
  final String outcome; // delivered | returned
  final String title;
  final String place;
  final String? codCollected;
  final String? earning;
  final String currency;
  final String when;

  // Bago: para sa hiwalay na linya ng customer at address
  final String customer;
  final String address;
  final int? itemsCount;

  const HistoryItem({
    required this.orderId,
    required this.outcome,
    required this.title,
    required this.place,
    required this.codCollected,
    required this.earning,
    required this.when,
    this.currency = 'PHP',
    this.customer = '',
    this.address = '',
    this.itemsCount,
    this.proof = const DeliveryProof(),
  });

  bool get returned => outcome == 'returned';
}

class HistoryPage {
  final List<HistoryItem> items;
  final int currentPage;
  final int lastPage;
  final int total;
  const HistoryPage({
    required this.items,
    required this.currentPage,
    required this.lastPage,
    required this.total,
  });
}

class HistoryService {
  HistoryService._();

  /// ISO na may zone (hal. 2026-10-24T14:10:00+08:00) -> "Oct 24, 2026 \u00B7 02:10 PM" (Asia/Manila).
  static String _fmt(String raw) {
    final r = raw.trim();
    if (r.isEmpty) return '';
    final hasZone = r.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(r);
    final dt = DateTime.tryParse(hasZone ? r : '${r.replaceFirst(' ', 'T')}Z');
    if (dt == null) return r;
    final m = dt.toUtc().add(const Duration(hours: 8));
    return DateFormat('MMM d, yyyy \u00B7 hh:mm a').format(m);
  }

  static String _d(DateTime x) => x.toIso8601String().substring(0, 10);

  /// Ligtas na string: null -> ''
  static String _s(dynamic v) => v == null ? '' : v.toString().trim();

  static double? _num(dynamic v) =>
      v == null ? null : num.tryParse('$v')?.toDouble();

  /// Lokal: kinukuha ang kasalukuyang history (isang page).
  /// v4: GET /courier/history?page=&from=&to=&status=
  static Future<HistoryPage> fetch({
    int page = 1,
    DateTime? from,
    DateTime? to,
    String? status, // delivered | returned
  }) async {
    if (!ApiConfig.v4) {
      final list = await OrderService.deliveryHistory();
      return HistoryPage(
        items: [
          for (final o in list)
            HistoryItem(
              orderId: o.reference,
              outcome: 'delivered',
              title: o.item,
              place: '${o.buyer} \u00B7 ${o.to}',
              codCollected: null,
              earning: o.fee,
              currency: o.currency,
              when: o.day,
              customer: o.buyer,
              address: o.to,
            ),
        ],
        currentPage: 1,
        lastPage: 1,
        total: list.length,
      );
    }

    final body = await ApiClient.get(
      '/courier/history',
      query: {
        'page': '$page',
        if (from != null) 'from': _d(from),
        if (to != null) 'to': _d(to),
        'status': ?status,
      },
    );
    final map = body is Map
        ? Map<String, dynamic>.from(body)
        : <String, dynamic>{};
    final data = (map['data'] as List?) ?? const [];
    final meta = map['meta'] is Map
        ? Map<String, dynamic>.from(map['meta'] as Map)
        : <String, dynamic>{};

    final items = data.map((e) {
      final j = Map<String, dynamic>.from(e as Map);

      final orderNo = [
        j['order_number'],
        j['order_id'],
        j['id'],
      ].map(_s).firstWhere((x) => x.isNotEmpty, orElse: () => '');
      final count = _num(j['items_count'])?.toInt();
      final customer = _s(j['customer_name']).isNotEmpty
          ? _s(j['customer_name'])
          : _s(j['buyer_name']);
      final address = _s(j['address']).isNotEmpty
          ? _s(j['address'])
          : [
              j['barangay'],
              j['municipality'],
            ].map(_s).where((x) => x.isNotEmpty).join(', ');
      final place = [customer, address].where((x) => x.isNotEmpty).join(', ');
      final outcome = _s(j['outcome']).isNotEmpty
          ? _s(j['outcome'])
          : (j['is_returned'] == true ? 'returned' : 'delivered');

      final title = count != null
          ? 'Order #$orderNo ($count ${count == 1 ? 'item' : 'items'})'
          : 'Order #$orderNo';

      return HistoryItem(
        proof: DeliveryProof.fromJson(j['proof']),
        orderId: orderNo,
        outcome: outcome,
        title: title,
        place: place,
        codCollected: decimalMoney(
          j.containsKey('cod_collected')
              ? j['cod_collected']
              : j['cash_collected'],
        ),
        earning: decimalMoney(
          j.containsKey('earning') ? j['earning'] : j['rider_fee'],
        ),
        currency: j['currency']?.toString() ?? 'PHP',
        when: _fmt(_s(j['finished_at'])),
        customer: customer,
        address: address,
        itemsCount: count,
      );
    }).toList();

    return HistoryPage(
      items: items,
      currentPage: (num.tryParse('${meta['current_page']}') ?? page).toInt(),
      lastPage: (num.tryParse('${meta['last_page']}') ?? page).toInt(),
      total: (num.tryParse('${meta['total']}') ?? items.length).toInt(),
    );
  }
}
