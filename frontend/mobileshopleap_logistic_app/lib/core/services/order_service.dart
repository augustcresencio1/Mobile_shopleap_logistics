import '../../models/order.dart';
import '../../models/navigation.dart';

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;

import '../../models/earnings.dart';
import '../utils/money.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'earnings_service.dart';
import 'live_refresh.dart';
import 'rider_tracking_service.dart';
export 'api_exception.dart';
import 'api_config.dart';

typedef CourierHomeData = ({
  List<Order> requests,
  List<Order> pickups,
  List<Order> deliveries,
  List<Order> inProgress,
  List<Order> recent,
  String? earned,
  String? earnedToday,
  String currency,
});

/// Lahat ng tawag ng courier side sa Laravel API (orders, pickup, delivery, profit).
/// Ang http, token, at 401 handling ay nasa ApiClient.
///
/// Ang Order.id sa app ay String, kaya ang database id (hal. 1002) ay
/// ginagawang '1002'. Pickup and delivery actions use the public orderNumber.
class OrderService {
  /// Use the same v4 courier contract as AuthService.
  static const bool _v3 = ApiConfig.v4;

  /// Galing sa GET /courier/deliveries (v4). Kina-cache kapag nabasa.
  static List<String> _failureReasons = const [];

  // ---------- JSON -> Order ----------

  static Order _toOrder(Map<String, dynamic> j, OrderStatus status) {
    final items = (j['items'] as List?) ?? const [];
    final sellerObj = j['seller'] is Map
        ? Map<String, dynamic>.from(j['seller'] as Map)
        : null;
    final buyerObj = j['buyer'] is Map
        ? Map<String, dynamic>.from(j['buyer'] as Map)
        : null;
    final oid = j['order_id'] ?? j['id'];
    final orderNumber = (j['order_number'] ?? '').toString().trim();
    final waybillCode = (j['waybill_code'] ?? '').toString().trim();
    final reference = orderNumber.isNotEmpty
        ? orderNumber
        : (waybillCode.isNotEmpty ? waybillCode : '$oid');
    final rawAddress = j['shipping_address'];
    Map<String, dynamic> shippingAddress = {};
    if (rawAddress is Map) {
      shippingAddress = Map<String, dynamic>.from(rawAddress);
    }
    if (rawAddress is String) {
      try {
        final decoded = jsonDecode(rawAddress);
        if (decoded is Map) {
          shippingAddress = Map<String, dynamic>.from(decoded);
        }
      } on FormatException {
        /* An unavailable pin falls back to the address. */
      }
    }
    final deliveryPin = GeoPoint.parse(
      buyerObj?['latitude'],
      buyerObj?['longitude'],
    );
    GeoPoint? shippingPin;
    for (final candidate in [
      shippingAddress,
      shippingAddress['location'],
      shippingAddress['pin'],
    ]) {
      if (candidate is Map) {
        shippingPin = GeoPoint.parse(
          candidate['latitude'] ?? candidate['lat'],
          candidate['longitude'] ?? candidate['lng'] ?? candidate['lon'],
        );
        if (shippingPin != null) break;
      }
    }
    final itemText = items.isEmpty
        ? (j['items_count'] != null
              ? 'Order #$reference (${j['items_count']} items)'
              : 'Order #$reference')
        : items.map((i) => '${i['product_name']} x${i['quantity']}').join(', ');

    final toAddr =
        (buyerObj != null
                ? <dynamic>[buyerObj['address']]
                : <dynamic>[
                    j['ship_street'],
                    j['ship_barangay'],
                    j['ship_municipality'],
                    j['ship_province'],
                  ])
            .where((e) => e != null && e.toString().trim().isNotEmpty)
            .join(', ');

    // v4 pickup: walang buyer, ang pupuntahan ay ang hub.
    final to = (toAddr.isEmpty && j['deliver_to_hub'] != null)
        ? 'Hub: ${j['deliver_to_hub']}'
        : toAddr;

    // Schedule ng pickup (petsa at oras)
    final when = [
      j['pickup_date'],
      j['pickup_time_slot'] ?? j['pickup_window'],
    ].where((e) => e != null && e.toString().trim().isNotEmpty).join(' ');

    // Address ng seller (galing sa seller_profiles)
    final sellerAddr = sellerObj != null
        ? '${sellerObj['address'] ?? ''}'
        : [
                j['seller_street'],
                j['seller_barangay'],
                j['seller_municipality'],
                j['seller_province'],
              ]
              .where((e) => e != null && e.toString().trim().isNotEmpty)
              .join(', ');

    final String fromText;
    if (sellerAddr.isNotEmpty) {
      fromText = when.isEmpty ? sellerAddr : '$sellerAddr ($when)';
    } else {
      fromText = when.isEmpty ? 'no schedule yet' : when;
    }

    // updated_at / finished_at: i-convert sa Asia/Manila (UTC+8) para tugma sa Profit.
    // v4 history ay may finished_at (ISO na may +08:00).
    String day = '';
    final raw = (j['finished_at'] ?? j['updated_at'] ?? '').toString().trim();
    if (raw.isNotEmpty) {
      final hasZone =
          raw.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(raw);
      final dt = DateTime.tryParse(
        hasZone ? raw : '${raw.replaceFirst(' ', 'T')}Z',
      );
      if (dt != null) {
        final m = dt.toUtc().add(const Duration(hours: 8));
        day =
            '${m.year}-${m.month.toString().padLeft(2, '0')}-'
            '${m.day.toString().padLeft(2, '0')}';
      }
    }

    // v4: cod_amount galing sa server (items + shipping).
    // Lokal: total_amount + shipping_fee (tugma sa "Buyer pays (COD)" sa seller page).
    return Order(
      id: '$oid',
      orderNumber: orderNumber,
      waybillCode: waybillCode,
      item: itemText,
      seller:
          ((sellerObj != null
                      ? sellerObj['name']
                      : (j['seller'] is String
                            ? j['seller']
                            : j['seller_name'])) ??
                  '')
              .toString(),
      from: fromText,
      pickupAddress: sellerAddr,
      pickupPin: GeoPoint.parse(
        sellerObj?['latitude'] ?? j['seller_latitude'],
        sellerObj?['longitude'] ?? j['seller_longitude'],
      ),
      deliveryPin: deliveryPin ?? shippingPin,
      sellerContact:
          ((sellerObj != null
                      ? sellerObj['contact_no']
                      : j['seller_contact']) ??
                  '')
              .toString()
              .trim(),
      buyerContact:
          '${buyerObj?['phone'] ?? buyerObj?['contact_no'] ?? j['ship_contact_no'] ?? shippingAddress['phone'] ?? ''}',
      buyer: (j['buyer_name'] ?? buyerObj?['name'] ?? '').toString().trim(),
      to: to,
      // Lokal: rider_fee. v4 history: earning.
      fee: decimalMoney(
        j.containsKey('earning') ? j['earning'] : j['rider_fee'],
      ),
      currency: j['currency']?.toString() ?? 'PHP',
      status: status,
      day: day,
      codAmount:
          decimalMoney(j['cod_amount']) ??
          addMoney(j['total_amount'], j['shipping_fee']),
      pickupStatus: (j['pickup_status'] ?? '').toString(),
      backendStatus: (j['status'] ?? '').toString().toUpperCase(),
      attempts:
          (num.tryParse('${j['attempts'] ?? j['delivery_attempts']}') ?? 0)
              .toInt(),
      maxAttempts: (num.tryParse('${j['max_attempts']}') ?? 3).toInt(),
      shopName: (j['seller_shop'] ?? '').toString(),
      weightKg: num.tryParse('${j['parcel_weight_kg']}')?.toDouble() ?? 0,
      lines: [
        for (final item in items)
          OrderLine(
            name: (item['product_name'] ?? '').toString(),
            qty: num.tryParse('${item['quantity']}')?.toInt() ?? 0,
            variant: (item['variant'] ?? '').toString(),
          ),
      ],
    );
  }

  /// Tumatanggap ng {data:[...]} o plain array. Kina-cache din ang
  /// `failure_reasons` kapag kasama sa response (v4 /courier/deliveries).
  static Future<List<Map<String, dynamic>>> _rawList(
    String path, {
    Map<String, String>? query,
    Duration cacheFor = const Duration(seconds: 3),
  }) async {
    final body = await ApiClient.get(path, query: query, cacheFor: cacheFor);
    if (body is Map && body['failure_reasons'] is List) {
      _failureReasons = (body['failure_reasons'] as List)
          .map((e) => '$e')
          .toList();
    }
    final list = body is Map
        ? (body['data'] as List? ?? const [])
        : (body as List);
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<List<Order>> _orders(
    String path,
    OrderStatus status, {
    Map<String, String>? query,
  }) async {
    final raw = await _rawList(path, query: query);
    return raw.map((j) => _toOrder(j, status)).toList();
  }

  // ---------- Scan helpers ----------

  /// Preserve the scanned payload for the controller's `scan` validator.
  static String normalizeScan(String raw) => raw.trim();

  // ---------- Dashboards ----------

  /// Pickup requests na naghihintay ng accept/decline mo.
  /// v4: /courier/pickups?filter=awaiting_accept
  static Future<List<Order>> pickupRequests() => _v3
      ? _orders(
          '/courier/pickups',
          OrderStatus.request,
          query: {'filter': 'awaiting_accept'},
        )
      : _orders('/courier/pickup-requests', OrderStatus.request);

  /// GET /courier/pickups returns accepted pickups by default.
  static Future<List<Order>> itemsForPickup() async {
    final list = await _orders('/courier/pickups', OrderStatus.pickup);
    if (!_v3) return list;
    return list.where((o) => o.pickupStatus != 'assigned').toList();
  }

  /// Items for delivery (ASSIGNED_TO_RIDER at OUT_FOR_DELIVERY).
  static Future<List<Order>> itemsForDelivery() =>
      _orders('/courier/deliveries', OrderStatus.delivery);

  /// Delivery history (delivered / returned). v4: 20 bawat page.
  static Future<List<Order>> deliveryHistory({int page = 1}) => _v3
      ? _orders('/courier/history', OrderStatus.done, query: {'page': '$page'})
      : _orders('/courier/history', OrderStatus.done);

  /// The deployed v4 API exposes dashboard counts and separate order lists.
  static Future<CourierHomeData> home() async {
    const cacheFor = Duration(seconds: 10);
    final reads = await Future.wait<dynamic>([
      ApiClient.get('/courier/dashboard', cacheFor: cacheFor),
      _rawList('/courier/pickups', cacheFor: cacheFor),
      _rawList('/courier/deliveries', cacheFor: cacheFor),
      _rawList('/courier/history', query: {'page': '1'}, cacheFor: cacheFor),
      _rawList(
        '/courier/pickups',
        query: {'filter': 'awaiting_accept'},
        cacheFor: cacheFor,
      ),
    ]);
    return _homeFromReads(
      Map<String, dynamic>.from(reads[0] as Map),
      reads[1] as List<Map<String, dynamic>>,
      reads[2] as List<Map<String, dynamic>>,
      reads[3] as List<Map<String, dynamic>>,
      reads[4] as List<Map<String, dynamic>>,
    );
  }

  static CourierHomeData? cachedHome() {
    final summary = ApiClient.cachedGet('/courier/dashboard');
    final pickups = ApiClient.cachedGet('/courier/pickups');
    final requests = ApiClient.cachedGet(
      '/courier/pickups',
      query: {'filter': 'awaiting_accept'},
    );
    final deliveries = ApiClient.cachedGet('/courier/deliveries');
    final history = ApiClient.cachedGet(
      '/courier/history',
      query: {'page': '1'},
    );
    if (summary is! Map ||
        pickups == null ||
        requests == null ||
        deliveries == null ||
        history == null) {
      return null;
    }
    List<Map<String, dynamic>> rows(dynamic body) => [
      for (final row
          in (body is Map ? body['data'] : body) as List? ?? const [])
        Map<String, dynamic>.from(row as Map),
    ];
    return _homeFromReads(
      Map<String, dynamic>.from(summary),
      rows(pickups),
      rows(deliveries),
      rows(history),
      rows(requests),
    );
  }

  static CourierHomeData _homeFromReads(
    Map<String, dynamic> summary,
    List<Map<String, dynamic>> pickups,
    List<Map<String, dynamic>> deliveries,
    List<Map<String, dynamic>> history,
    List<Map<String, dynamic>> requests,
  ) => _homeData({
    ...summary,
    'requests': requests,
    'pickups': pickups
        .where((row) => row['pickup_status'] != 'assigned')
        .toList(),
    'deliveries': deliveries,
    'recent': history.take(5).toList(),
  });

  static CourierHomeData _homeData(Map<String, dynamic> body) {
    List<Order> list(String key, OrderStatus s) =>
        ((body[key] as List?) ?? const [])
            .map((e) => _toOrder(Map<String, dynamic>.from(e as Map), s))
            .toList();

    final pickups = list('pickups', OrderStatus.pickup);
    final deliveries = list('deliveries', OrderStatus.delivery);
    final inProgress = body['in_progress'] is List
        ? (body['in_progress'] as List).map((row) {
            final json = Map<String, dynamic>.from(row as Map);
            return _toOrder(
              json,
              json['notification_role'] == 'delivery'
                  ? OrderStatus.delivery
                  : OrderStatus.pickup,
            );
          }).toList()
        : [...pickups, ...deliveries];

    return (
      requests: list('requests', OrderStatus.request),
      pickups: pickups,
      deliveries: deliveries,
      inProgress: inProgress,
      recent: list('recent', OrderStatus.done),
      earned: decimalMoney(body['earned_week']),
      earnedToday: decimalMoney(body['earned_today']),
      currency: body['currency']?.toString() ?? 'PHP',
    );
  }

  /// v4 /courier/dashboard: {pickups:{awaiting_accept, accepted, total},
  /// deliveries:{to_deliver, out_for_delivery, waiting_hub_decision},
  /// delivered_today, earned_today, currency}
  static Future<Map<String, dynamic>> dashboard() async {
    final body = await ApiClient.get('/courier/dashboard');
    return Map<String, dynamic>.from(body as Map);
  }

  /// Lokal: [{id, order_id, status, title, note, created_at}]
  /// v4: [{id (string), kind, title, body, meta:{order_id}, read, created_at}]
  static Future<List<Map<String, dynamic>>> notifications() async {
    final body = await ApiClient.get('/courier/notifications') as Map;
    return (body['data'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// v4 lang. Ang id ay string.
  static Future<void> markNotificationRead(String id) =>
      ApiClient.post('/courier/notifications/$id/read');

  /// v4 lang.
  static Future<void> markAllNotificationsRead() =>
      ApiClient.post('/courier/notifications/read-all');

  // ---------- Pickup flow ----------

  static String _orderPath(String group, String orderNumber, String action) {
    final number = orderNumber.trim();
    if (number.isEmpty) {
      throw ApiException(
        'Refresh the order to obtain its public order number.',
      );
    }
    return '/courier/$group/${Uri.encodeComponent(number)}/$action';
  }

  static Future<void> acceptPickup(String orderNumber) =>
      ApiClient.post(_orderPath('pickups', orderNumber, 'accept'));

  /// The controller requires a reason of at most 500 characters.
  static Future<void> declinePickup(String orderNumber, String reason) =>
      ApiClient.post(
        _orderPath('pickups', orderNumber, 'decline'),
        body: {'reason': reason},
      );

  /// Nakuha na ang parcel sa seller.
  /// The controller accepts the scanned waybill/QR in the `scan` field.
  static Future<void> pickupOrder(
    String orderNumber, {
    String? scannedCode,
  }) async {
    await ApiClient.post(
      _orderPath('pickups', orderNumber, 'confirm'),
      body: {if (scannedCode != null) 'scan': normalizeScan(scannedCode)},
    );
  }

  // ---------- Delivery flow ----------

  static Future<void> startDelivery(String orderNumber) =>
      ApiClient.post(_orderPath('deliveries', orderNumber, 'out'));

  static final Set<String> _deliveryUploads = {};

  /// Actual COD collected, including items and shipping; never rider pay.
  /// A retry resends the same proof and fields. Confirmation requires HTTP 200
  /// and an explicit proof.uploaded == true acknowledgement.
  static Future<DeliveryResult> deliverOrder(
    String orderNumber, {
    required String amount,
    required Uint8List proofImage,
    String? capturedAt,
    double? latitude,
    double? longitude,
    String? notes,
    String? trackingOrderId,
    void Function(int sent, int total)? onProgress,
  }) async {
    final cash = decimalMoney(amount);
    if (cash == null || cash.startsWith('-')) {
      throw ApiException(
        'Enter a valid cash amount with up to two decimal places.',
      );
    }
    if (orderNumber.trim().isEmpty) {
      throw ApiException('Refresh the order to obtain its public order code.');
    }
    if (proofImage.isEmpty || proofImage.length > 5 * 1024 * 1024) {
      throw ApiException('A proof photo of at most 5 MB is required.');
    }
    final decoder = img.findDecoderForData(proofImage);
    final type = switch (decoder?.format) {
      img.ImageFormat.jpg => 'jpeg',
      img.ImageFormat.png => 'png',
      img.ImageFormat.webp => 'webp',
      _ => null,
    };
    final info = decoder?.startDecode(proofImage);
    if (type == null ||
        info == null ||
        info.width < 640 ||
        info.height < 640 ||
        info.width * info.height > 40000000) {
      throw ApiException(
        'Use a JPEG, PNG, or WebP photo with each side at least 640 pixels and at most 40 megapixels.',
      );
    }
    if ((latitude != null &&
            (!latitude.isFinite || latitude < -90 || latitude > 90)) ||
        (longitude != null &&
            (!longitude.isFinite || longitude < -180 || longitude > 180)) ||
        (notes != null && notes.runes.length > 255) ||
        (capturedAt != null &&
            (DateTime.tryParse(capturedAt) == null ||
                !RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(capturedAt)))) {
      throw ApiException(
        'Check the photo timestamp, location, and notes (maximum 255 characters).',
      );
    }
    if (!_deliveryUploads.add(orderNumber)) {
      throw ApiException('This delivery is already uploading.');
    }
    dynamic body;
    try {
      body = await ApiClient.postMultipart(
        '/courier/deliveries/${Uri.encodeComponent(orderNumber)}/delivered',
        fields: {
          'amount': cash,
          'captured_at': ?capturedAt,
          if (latitude != null) 'latitude': '$latitude',
          if (longitude != null) 'longitude': '$longitude',
          'notes': ?notes,
        },
        files: [
          http.MultipartFile.fromBytes(
            'proof_image',
            proofImage,
            filename: 'proof.${type == 'jpeg' ? 'jpg' : type}',
            contentType: MediaType('image', type),
          ),
        ],
        onProgress: onProgress,
        requiredStatusCode: 200,
        diagnosticOrderNumber: orderNumber,
      );
    } on ApiException catch (e) {
      if (e.statusCode == 403 || e.statusCode == 409) {
        ApiClient.invalidateCache();
        LiveRefresh.pokeNow();
        // Refresh assignment/status even when its dashboard is not visible.
        try {
          await itemsForDelivery();
        } catch (_) {
          /* Keep the server's original error. */
        }
      }
      rethrow;
    } finally {
      _deliveryUploads.remove(orderNumber);
    }
    return _completeDelivery(body, orderNumber, trackingOrderId);
  }

  static Future<DeliveryResult> _completeDelivery(
    dynamic body,
    String orderNumber,
    String? trackingOrderId,
  ) async {
    if (body is! Map ||
        body['proof'] is! Map ||
        body['proof']['uploaded'] != true) {
      throw ApiException(
        'The server did not confirm the proof upload. Your photo and details are saved. Refresh delivery history before retrying; completed orders cannot attach a new photo here.',
        200,
      );
    }
    final result = DeliveryResult.fromJson(Map<String, dynamic>.from(body));
    LiveRefresh.deliveryCompleted();
    // A tracking cleanup failure cannot turn a confirmed delivery into a retry.
    try {
      await RiderTrackingService.instance.finish(
        trackingOrderId ?? orderNumber,
        'delivery',
      );
    } catch (_) {}
    return result;
  }

  /// The controller accepts only a required reason (maximum 500 characters).
  static Future<void> failDelivery(
    String orderNumber,
    String reason, {
    String? trackingOrderId,
  }) async {
    await ApiClient.post(
      _orderPath('deliveries', orderNumber, 'failed'),
      body: {'reason': reason},
    );
    await RiderTrackingService.instance.finish(
      trackingOrderId ?? orderNumber,
      'delivery',
    );
  }

  /// v4: kasama sa response ng GET /courier/deliveries (`failure_reasons`).
  /// Lokal: walang ganito, kaya blangko (gagamitin ng UI ang sarili nitong listahan).
  static Future<List<String>> failureReasons() async {
    if (!_v3) return const [];
    if (_failureReasons.isEmpty) await itemsForDelivery();
    return _failureReasons;
  }

  // ---------- Scan ----------

  /// Match the controller's CourierScanCode parser against assigned list rows.
  static ({String column, String value})? _scanSelector(String raw) {
    var code = normalizeScan(raw);
    if (code.isEmpty || code.length > 256) return null;
    code = code
        .replaceFirst(RegExp(r'^SHOPLEAP:ORDER:', caseSensitive: false), '')
        .trim();
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(code)) {
      final uri = Uri.tryParse(code);
      final parts = uri?.pathSegments.where((part) => part.isNotEmpty).toList();
      if (parts == null || parts.isEmpty) return null;
      code = parts.last;
    }
    final legacy = RegExp(
      r'^(WB|SL)[A-Z0-9]{14}$',
      caseSensitive: false,
    ).firstMatch(code);
    if (legacy != null) {
      return (
        column: legacy[1]!.toUpperCase() == 'WB'
            ? 'waybill_code'
            : 'order_number',
        value: code.toUpperCase(),
      );
    }
    final public = RegExp(
      r'^(WB|SL)-?([A-Z0-9]{6,20})$',
      caseSensitive: false,
    ).firstMatch(code);
    if (public != null) {
      final prefix = public[1]!.toUpperCase();
      return (
        column: prefix == 'WB' ? 'waybill_code' : 'order_number',
        value: '$prefix-${public[2]!.toUpperCase()}',
      );
    }
    final numeric = RegExp(
      r'^(?:SL-ORDER-)?([0-9]+)$',
      caseSensitive: false,
    ).firstMatch(code);
    final id = numeric == null ? null : int.tryParse(numeric[1]!);
    return id != null && id > 0 ? (column: 'id', value: '$id') : null;
  }

  /// Resolve a waybill to its public order number using the working list APIs.
  /// Confirmation is a separate POST /courier/pickups/{order_number}/confirm.
  static Future<({Order order, String status, String role})> scan(
    String code,
  ) async {
    final selector = _scanSelector(code);
    if (selector == null) {
      throw ApiException('Invalid waybill or order code.', 422);
    }
    for (final role in ['pickup', 'delivery']) {
      final rows = await _rawList(
        role == 'pickup' ? '/courier/pickups' : '/courier/deliveries',
        cacheFor: Duration.zero,
      );
      for (final row in rows) {
        if ('${row[selector.column] ?? ''}'.trim() != selector.value) continue;
        return (
          order: _toOrder(
            row,
            role == 'pickup' ? OrderStatus.pickup : OrderStatus.delivery,
          ),
          status: (row['status'] ?? '').toString(),
          role: role,
        );
      }
    }
    throw ApiException('No such order, or it is not assigned to you.', 404);
  }

  // ---------- Profit ----------

  /// Saved earnings for a period. COD is separate from rider pay.
  static Future<Map<String, dynamic>> earnings({
    DateTime? from,
    DateTime? to,
    String period = 'month',
  }) async {
    if (_v3) {
      return EarningsService.summary(
        EarningsFilter(
          period: from != null || to != null ? 'custom' : period,
          from: from,
          to: to,
        ),
      );
    }
    String d(DateTime x) => x.toIso8601String().substring(0, 10);
    final body = await ApiClient.get(
      '/courier/earnings',
      query: {if (from != null) 'from': d(from), if (to != null) 'to': d(to)},
    );
    return Map<String, dynamic>.from(body as Map);
  }

  // ---------- Chat ----------
  // Lokal na bersyon (per-order). Iba ang v4 (/courier/chat/*, per-conversation),
  // kaya hindi pa ginagalaw hangga't hindi ko nakikita ang api_client.dart.

  /// [{id, sender_id, sender_name, body, created_at, mine}]
  static Future<List<Map<String, dynamic>>> messages(
    String orderId, {
    String party = 'seller',
  }) async {
    final body = await ApiClient.get(
      '/courier/orders/$orderId/messages',
      query: {'with': party},
    );
    final list = ((body as Map)['data'] as List?) ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> sendMessage(
    String orderId,
    String text, {
    String party = 'seller',
  }) => ApiClient.post(
    '/courier/orders/$orderId/messages',
    body: {'body': text, 'with': party},
  );

  // ---------- Account ----------

  /// {email, courier: {...}}
  static Future<Map<String, dynamic>> account({
    bool forceRefresh = false,
  }) async {
    final body = await ApiClient.get(
      '/courier/me',
      cacheFor: const Duration(minutes: 2),
      forceRefresh: forceRefresh,
    );
    return Map<String, dynamic>.from(body as Map);
  }

  /// contact_no (09xxxxxxxxx), vehicle_type (Trike/Motor/Van),
  /// plate_number, province, municipality, barangay, street_address.
  static Future<Map<String, dynamic>> updateAccount(
    Map<String, dynamic> data,
  ) async {
    final body = await ApiClient.post('/courier/account/profile', body: data);
    return Map<String, dynamic>.from(body as Map);
  }

  static Future<void> changePassword(
    String current,
    String password,
    String confirm,
  ) => ApiClient.post(
    '/courier/account/password',
    body: {
      'current_password': current,
      'password': password,
      'password_confirmation': confirm,
    },
  );
}
