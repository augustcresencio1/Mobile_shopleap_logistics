import 'dart:convert';
import 'package:http/http.dart' as http;

http.Response moneyResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> cashSummary({
  String cash = '930.00',
  String shortage = '30.00',
  bool empty = false,
}) => {
  'cash_on_hand': empty ? '0.00' : cash,
  'shortage_amount': empty ? '0.00' : shortage,
  'currency': 'PHP',
  'orders': [
    if (!empty)
      {
        'order_number': 'ORD-ORIGINAL-RIDER',
        'amount': cash,
        'delivered_at': '2026-11-15T10:00:00+00:00',
      },
  ],
};

Map<String, dynamic> cashHistory({
  int page = 1,
  int last = 1,
  bool empty = false,
}) => {
  'currency': 'PHP',
  'data': [
    if (!empty)
      for (final status
          in page == 1 ? ['confirmed', 'short', 'settled'] : ['confirmed'])
        {
          'reference_no': 'HO-$status-$page',
          'amount': status == 'short' ? '900.00' : '930.00',
          'currency': 'PHP',
          'status': status,
          'confirmed_at': '2026-11-15T10:30:00+00:00',
        },
  ],
  'meta': {
    'current_page': page,
    'last_page': last,
    'total': empty
        ? 0
        : last == 1
        ? 3
        : 21,
  },
};

Map<String, dynamic> earningsSummary({String total = '60.00'}) => {
  'period': 'month',
  'currency': 'PHP',
  'fee_per_delivery': '20.00',
  'deliveries': 3,
  'total_earned': total,
  'recorded_earnings': 2,
  'accrued_unpaid': '20.00',
  'paid': '40.00',
  'cod_collected': '930.00',
  'daily': [],
};

Map<String, dynamic> earningsRate({bool missing = false}) => {
  'amount': missing ? null : '20.00',
  'currency': 'PHP',
  'effective_from': null,
};

Map<String, dynamic> earningsHistory({int page = 1, int last = 1}) => {
  'data': [
    {
      'order_id': 'ORD-PUBLIC-$page',
      'order_number': 'ORD-PUBLIC-$page',
      'waybill_code': 'WB-$page',
      'amount': page == 1 ? null : '12.50',
      'currency': 'PHP',
      'recorded_at': null,
      'delivered_at': '2026-11-01T10:00:00+00:00',
      'proof': {'uploaded': true, 'captured_at': null},
      'payout_status': 'accrued',
    },
    if (page == 1)
      {
        'order_number': 'ORD-PAID',
        'amount': '0.00',
        'currency': 'PHP',
        'delivered_at': '2026-11-01T10:00:00+00:00',
        'payout_status': 'paid',
      },
  ],
  'meta': {
    'current_page': page,
    'last_page': last,
    'total': last == 1 ? 2 : 21,
  },
};

http.Response earningsApi(
  http.Request request, {
  String total = '60.00',
  int last = 1,
  bool missingRate = false,
}) {
  if (request.url.path.endsWith('/summary')) {
    return moneyResponse(earningsSummary(total: total));
  }
  if (request.url.path.endsWith('/rate')) {
    return moneyResponse(earningsRate(missing: missingRate));
  }
  if (request.url.path.endsWith('/history')) {
    return moneyResponse(
      earningsHistory(
        page: int.parse(request.url.queryParameters['page']!),
        last: last,
      ),
    );
  }
  throw StateError('Unexpected endpoint ${request.url}');
}
