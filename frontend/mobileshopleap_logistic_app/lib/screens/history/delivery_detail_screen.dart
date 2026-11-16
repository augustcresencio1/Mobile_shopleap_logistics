import 'package:flutter/material.dart';

import '../../core/services/history_service.dart';
import '../../core/utils/money.dart';
import '../../core/theme/app_typography.dart';

const Color _kBrand = Color(0xFF1B5BB8);
const Color _kMuted = Color(0xFF6B7A90);
const Color _kText = Color(0xFF1B2A41);
const Color _kLine = Color(0xFFE6ECF4);
const Color _kSoft = Color(0xFFF1F5FB);

TextStyle _f(double size, FontWeight weight, Color color) => TextStyle(
  fontFamily: kAppFontFamily,
  fontSize: size,
  fontWeight: weight,
  color: color,
);

class DeliveryDetailScreen extends StatelessWidget {
  final HistoryItem item;
  const DeliveryDetailScreen({super.key, required this.item});

  Widget _statusPill(bool returned) {
    final bg = returned ? const Color(0xFFEDEFF3) : const Color(0xFFDDF5E5);
    final fg = returned ? const Color(0xFF4A5568) : const Color(0xFF1E8E4E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        returned ? 'Returned' : 'Delivered',
        style: _f(13, FontWeight.w700, fg),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFFE8F0FC),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _kBrand, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: _f(12.5, FontWeight.w400, _kMuted)),
                const SizedBox(height: 2),
                Text(value, style: _f(15, FontWeight.w600, _kText)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, color: _kLine);

  @override
  Widget build(BuildContext context) {
    final o = item;
    final n = o.itemsCount;
    final rows = <Widget>[];

    void add(IconData icon, String label, String value) {
      if (value.trim().isEmpty) return;
      if (rows.isNotEmpty) rows.add(_divider());
      rows.add(_row(icon, label, value));
    }

    add(Icons.person_outline, 'Customer', o.customer);
    add(
      Icons.location_on_outlined,
      'Delivery address',
      o.address.isNotEmpty ? o.address : o.place,
    );
    add(Icons.schedule, o.returned ? 'Returned on' : 'Delivered on', o.when);
    if (n != null) {
      add(
        Icons.inventory_2_outlined,
        'Items',
        '$n ${n == 1 ? 'item' : 'items'}',
      );
    }
    add(
      Icons.payments_outlined,
      'Cash collected',
      formatMoney(
        o.codCollected,
        currency: o.currency,
        missing: 'Not recorded',
      ),
    );
    add(
      Icons.account_balance_wallet_outlined,
      'Your earning',
      formatMoney(o.earning, currency: o.currency, missing: 'Not recorded'),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _kText,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('Delivery details', style: _f(18, FontWeight.w700, _kText)),
      ),
      body: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: kAppFontFamily),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Order #${o.orderId}',
                      style: _f(20, FontWeight.w700, _kText),
                    ),
                  ),
                  _statusPill(o.returned),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: _kLine),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(children: rows),
            ),
          ],
        ),
      ),
    );
  }
}
