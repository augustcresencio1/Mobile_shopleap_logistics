import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

import '../../core/services/order_service.dart';
import '../../models/order.dart';
import '../../core/utils/money.dart';
import 'proof_delivery_screen.dart';
import '../../widgets/delivery_failed_dialog.dart';
import '../../widgets/rider_navigation_card.dart';

class DeliverOrderScreen extends StatefulWidget {
  final Order order;
  const DeliverOrderScreen({super.key, required this.order});

  @override
  State<DeliverOrderScreen> createState() => _DeliverOrderScreenState();
}

class _DeliverOrderScreenState extends State<DeliverOrderScreen> {
  bool _busy = false;

  String get _cod =>
      formatMoney(widget.order.codAmount, currency: widget.order.currency);

  Future<void> _run(
    Future<void> Function() action,
    String okMsg, {
    bool close = true,
  }) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(okMsg)));
      if (close && mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('May error: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deliver() async {
    if (_busy) return;
    setState(() => _busy = true);
    final delivered = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ProofDeliveryScreen(order: widget.order),
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (delivered == true) Navigator.pop(context, true);
  }

  /// v4: dropdown mula sa failure_reasons ng server + optional note.
  /// Lokal: text field lang (walang listahan).
  Future<({String reason, String note})?> _askFailure() async {
    List<String> reasons = const [];
    try {
      reasons = await OrderService.failureReasons();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return null;
    } catch (_) {
      reasons = const [];
    }
    if (!mounted) return null;
    return showDeliveryFailedDialog(context, reasons: reasons);
  }

  Future<void> _fail() async {
    final r = await _askFailure();
    if (r == null || !mounted) return;
    await _run(
      () => OrderService.failDelivery(
        widget.order.orderNumber,
        r.reason,
        trackingOrderId: widget.order.id,
      ),
      'Failed delivery reported.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final cs = Theme.of(context).colorScheme;
    final pageBg = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        toolbarHeight: 48,
        backgroundColor: kBrandBlue,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Deliver ${order.reference}',
          style: const TextStyle(fontSize: 18),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: _cardDecoration(cs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoDetail(
                        icon: Icons.inventory_2_outlined,
                        label: 'Item to deliver',
                        value: order.item,
                        valueSize: 15,
                      ),
                      if (order.attempts > 0) ...[
                        const SizedBox(height: 6),
                        _Pill(
                          text:
                              'Attempt ${order.attempts + 1} of ${order.maxAttempts}',
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _InfoDetail(
                              icon: Icons.person_outline,
                              label: 'Buyer',
                              value: order.buyer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _InfoDetail(
                              icon: Icons.store_outlined,
                              label: 'Seller',
                              value: order.seller,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _InfoDetail(
                        icon: Icons.location_on_outlined,
                        label: 'Delivery address',
                        value: order.to,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _CodCard(amount: _cod),
                RiderNavigationCard(
                  order: order,
                  role: 'delivery',
                  compact: true,
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kBrandBlue,
                              minimumSize: const Size.fromHeight(48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              side: const BorderSide(color: kBrandBlue),
                              textStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            icon: const Icon(
                              Icons.local_shipping_outlined,
                              size: 18,
                            ),
                            label: const Text('Start delivery'),
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () => OrderService.startDelivery(
                                      order.orderNumber,
                                    ),
                                    'Delivery started.',
                                    close: false,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: kBrandBlue,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            icon: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check,
                                size: 14,
                                color: kBrandBlue,
                              ),
                            ),
                            label: const Text('Mark delivered'),
                            onPressed: _busy ? null : _deliver,
                          ),
                        ),
                      ],
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: cs.error,
                        minimumSize: const Size(0, 48),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      icon: const Icon(
                        Icons.error_outline,
                        color: kBrandBlue,
                        size: 18,
                      ),
                      label: const Text('Delivery failed'),
                      onPressed: _busy ? null : _fail,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _cardDecoration(ColorScheme cs) => BoxDecoration(
  color: cs.surface,
  borderRadius: BorderRadius.circular(16),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ],
);

class _IconChip extends StatelessWidget {
  final IconData icon;
  const _IconChip({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: kBrandBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, color: kBrandBlue, size: 18),
    );
  }
}

class _InfoDetail extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final double valueSize;
  const _InfoDetail({
    required this.icon,
    required this.label,
    required this.value,
    this.valueSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IconChip(icon: icon),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: TextStyle(
                  fontSize: valueSize,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CodCard extends StatelessWidget {
  final String amount;
  const _CodCard({required this.amount});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(kBrandBlue.withValues(alpha: 0.08), cs.surface),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBrandBlue.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          const _IconChip(icon: Icons.account_balance_wallet_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'COD to collect',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              amount,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: kBrandBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  const _Pill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: kBrandBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: kBrandBlue,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
