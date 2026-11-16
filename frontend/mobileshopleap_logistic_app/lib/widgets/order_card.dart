import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/money.dart';
import '../models/order.dart';

/// Order card: product tile, COD chip, icon rows, at buttons sa ilalim.
class OrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback? onTap;
  final List<Widget> actions;
  const OrderCard({
    super.key,
    required this.order,
    this.onTap,
    this.actions = const [],
  });

  static String _join(List<String> parts) =>
      parts.map((e) => e.trim()).where((e) => e.isNotEmpty).join(', ');

  Widget _tile(BuildContext context, IconData icon, double size) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(icon, color: cs.primary, size: size * 0.5),
    );
  }

  Widget _line(BuildContext context, IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.3,
                color: cs.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pickup = _join([order.seller, order.from]);
    final deliver = _join([order.buyer, order.to]);
    final cod =
        'COD ${formatMoney(order.codAmount, currency: order.currency)}';

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBrandBlue.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: kBrandBlue.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _tile(context, Icons.inventory_2_outlined, 64),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  order.item,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  cod,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: cs.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          _line(
                            context,
                            Icons.qr_code_2_outlined,
                            order.reference,
                          ),
                          if (pickup.isNotEmpty)
                            _line(
                              context,
                              Icons.storefront_outlined,
                              'Pickup: $pickup',
                            ),
                          if (order.day.trim().isNotEmpty)
                            _line(
                              context,
                              Icons.calendar_today_outlined,
                              order.day,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Divider(
                    height: 1,
                    color: cs.onSurface.withValues(alpha: 0.10),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _tile(context, Icons.location_on, 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: 'Deliver to: ',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            TextSpan(
                              text: deliver.isEmpty ? 'Not available' : deliver,
                            ),
                          ],
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  if (actions.length <= 2)
                    Row(
                      children: [
                        for (var i = 0; i < actions.length; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(child: actions[i]),
                        ],
                      ],
                    )
                  else
                    Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DetailRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const DetailRow(this.icon, this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) =>
      ListTile(leading: Icon(icon), title: Text(label), subtitle: Text(value));
}

class EmptyNote extends StatelessWidget {
  final String text;
  const EmptyNote(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Center(child: Text(text)),
  );
}