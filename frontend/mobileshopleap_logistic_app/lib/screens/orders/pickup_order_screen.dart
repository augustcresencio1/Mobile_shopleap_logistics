// ignore_for_file: unused_import
import 'package:flutter/material.dart';

import '../../core/services/navigation_service.dart';
import '../../core/services/order_service.dart';
import '../../models/order.dart';
import '../../widgets/order_card.dart';
import '../../widgets/rider_navigation_card.dart';
import '../../widgets/styled_parts.dart';
import '../scan/scan_screen.dart';

class PickupOrderScreen extends StatefulWidget {
  final Order order;
  const PickupOrderScreen({super.key, required this.order});

  @override
  State<PickupOrderScreen> createState() => _PickupOrderScreenState();
}

class _PickupOrderScreenState extends State<PickupOrderScreen> {
  bool _busy = false;

  Future<void> _callSeller() async {
    final phone = widget.order.sellerContact.trim();
    if (phone.isEmpty) return;
    try {
      await NavigationService.open(
        Uri(scheme: 'tel', path: NavigationService.phoneNumber(phone) ?? phone),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the phone dialer.')),
      );
    }
  }

  /// Scan muna, saka lang tatawag ng pickup confirm.
  Future<void> _confirm() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final code = await navigator.push<String>(
      MaterialPageRoute(
        builder: (_) => ScanScreen(
          expectOrderId: widget.order.id,
          expectOrderReference: widget.order.reference,
        ),
      ),
    );
    if (code == null || !mounted) return; // kinansela ang scan

    setState(() => _busy = true);
    try {
      await OrderService.pickupOrder(
        widget.order.orderNumber,
        scannedCode: code,
      );
      messenger.showSnackBar(
        SnackBar(content: Text('${widget.order.reference} picked up')),
      );
      if (mounted) {
        navigator.pop(true); // true = nagbago, i-refresh ang listahan
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('May error: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final phone = order.sellerContact.trim();
    final awaitingAcceptance =
        order.status == OrderStatus.request || order.pickupStatus == 'assigned';

    // Hiwalay ang petsa sa dulo ng address, hal. "(2026-11-15 morning)".
    final m = RegExp(r'\s*(\([^()]*\))\s*$').firstMatch(order.from);
    final address = m == null ? order.from : order.from.substring(0, m.start);
    final when = m?.group(1);

    const gap = SizedBox(height: 10);

    return Scaffold(
      appBar: GradientAppBar(title: 'Pickup ${order.reference}'),
      body: SoftPage(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            TitleCard(icon: Icons.inventory_2_outlined, title: order.item),
            const SizedBox(height: 14),
            InfoCard(icon: Icons.store, label: 'Seller', value: order.seller),
            gap,
            InfoCard(
              icon: Icons.location_on,
              label: 'Pickup address',
              value: address.trim(),
              footer: when == null ? null : DateChip(text: when),
            ),
            gap,
            InfoCard(
              icon: Icons.phone,
              label: 'Seller phone',
              value: phone.isEmpty ? 'Phone number unavailable' : phone,
            ),
            if (phone.isNotEmpty) ...[
              gap,
              GradientFilledButton(
                label: 'Call Seller',
                icon: Icons.call,
                expand: true,
                onPressed: _callSeller,
              ),
            ],
            gap,
            InfoCard(
              icon: Icons.person,
              label: 'Buyer',
              value: order.recipientName,
            ),
            gap,
            InfoCard(icon: Icons.flag, label: 'Deliver to', value: order.to),
            const SizedBox(height: 6),
            RiderNavigationCard(order: order, role: 'pickup'),
            const SizedBox(height: 12),
            if (!awaitingAcceptance)
              GradientFilledButton(
                label: 'Scan & confirm pickup',
                icon: Icons.qr_code_scanner,
                expand: true,
                busy: _busy,
                onPressed: _busy ? null : _confirm,
              ),
          ],
        ),
      ),
    );
  }
}
