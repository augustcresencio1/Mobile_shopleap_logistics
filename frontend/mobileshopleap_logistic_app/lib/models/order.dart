import 'navigation.dart';

enum OrderStatus { request, pickup, delivery, done }

/// Isang item line sa waybill (pangalan, dami, variant).
class OrderLine {
  final String name;
  final int qty;
  final String variant;
  const OrderLine({required this.name, required this.qty, this.variant = ''});
}

class Order {
  final String id, item, seller, from, buyer, to;
  final String orderNumber, waybillCode;

  /// Recipient returned as buyer_name by the courier order lists.
  String get recipientName => buyer;

  /// Public display reference; order actions use orderNumber explicitly.
  String get reference => orderNumber.trim().isNotEmpty
      ? orderNumber.trim()
      : (waybillCode.trim().isNotEmpty ? waybillCode.trim() : id);
  final String? fee;
  final String currency;
  OrderStatus status;
  String day;
  final String codAmount;
  final String pickupStatus;
  final String backendStatus;
  final int attempts;
  final int maxAttempts;

  // Para sa waybill (scan screen). Blangko kapag wala sa server.
  final String shopName;
  final String sellerContact;
  final String buyerContact;
  final double weightKg;
  final List<OrderLine> lines;
  final String pickupAddress;
  final GeoPoint? pickupPin, deliveryPin;

  Order({
    required this.id,
    this.orderNumber = '',
    this.waybillCode = '',
    required this.item,
    required this.seller,
    required this.from,
    required this.buyer,
    required this.to,
    required this.fee,
    this.currency = 'PHP',
    required this.status,
    this.day = '',
    this.codAmount = '0.00',
    this.pickupStatus = '',
    this.backendStatus = '',
    this.attempts = 0,
    this.maxAttempts = 3,
    this.shopName = '',
    this.sellerContact = '',
    this.buyerContact = '',
    this.weightKg = 0,
    this.lines = const [],
    this.pickupAddress = '',
    this.pickupPin,
    this.deliveryPin,
  });
}
