import 'package:flutter/material.dart';

import '../../core/services/live_refresh.dart';
import '../../core/services/api_client.dart';
import '../../core/utils/money.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/order_service.dart';
import '../../models/courier.dart';
import '../../models/order.dart';
import '../../widgets/order_card.dart';
import '../orders/deliver_order_screen.dart';
import '../orders/pickup_order_screen.dart';

class CourierDashboardScreen extends StatefulWidget {
  /// Lilipat ng tab sa drawer (index ng page).
  final void Function(int) onGo;
  const CourierDashboardScreen({super.key, required this.onGo});

  @override
  State<CourierDashboardScreen> createState() => _CourierDashboardScreenState();
}

class _DashData {
  final List<Order> pickups, deliveries, requests, recent;
  final String? earned;
  final String currency;
  _DashData({
    required this.pickups,
    required this.deliveries,
    required this.requests,
    required this.recent,
    required this.earned,
    required this.currency,
  });
}

class _CourierDashboardScreenState extends State<CourierDashboardScreen> {
  _DashData? _data;
  Object? _error;
  bool _loading = true;
  bool _inflight = false;
  bool _pushPending = false;
  DateTime _loadStarted = DateTime.fromMillisecondsSinceEpoch(0);
  int _seq = 0;
  bool _nameLoaded = false;

  @override
  void initState() {
    super.initState();
    _nameLoaded = Courier.current.id > 0;
    ApiClient.sessionChanged.addListener(_clearSession);
    _load();
    LiveRefresh.tick.addListener(_onTick);
    LiveRefresh.deliveriesChanged.addListener(_onDelivery);
  }

  @override
  void dispose() {
    ApiClient.sessionChanged.removeListener(_clearSession);
    LiveRefresh.tick.removeListener(_onTick);
    LiveRefresh.deliveriesChanged.removeListener(_onDelivery);
    super.dispose();
  }

  void _clearSession() {
    _seq++;
    setState(() {
      _data = null;
      _loading = false;
      _error = 'Your account changed. Refresh to continue.';
    });
  }

  void _onTick() {
    if (LiveRefresh.activePage == 0) _load(silent: true);
  }

  void _onDelivery() {
    _load();
  }

  /// Pangalan ng naka-login. Hindi hinaharangan ang dashboard kung mabigo.
  Future<void> _loadName() async {
    try {
      Courier.current = Courier.fromJson(await OrderService.account());
      _nameLoaded = true;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<_DashData> _fetch() async {
    // Isang beses lang kunin ang pangalan, hindi tuwing 5 segundo.
    if (!_nameLoaded) _loadName();
    final h = await OrderService.home();

    return _DashData(
      pickups: h.pickups,
      deliveries: h.deliveries,
      requests: h.requests,
      recent: h.recent,
      earned: h.earnedToday,
      currency: h.currency,
    );
  }

  /// silent = true: auto-refresh sa background. Hindi nagpapakita ng spinner
  /// at hindi binubura ang kasalukuyang data kung mabigo.
  Future<void> _load({bool silent = false}) async {
    await ApiClient.getToken();
    if (!mounted) return;
    if (silent && _inflight) {
      if (LiveRefresh.lastPush.isAfter(_loadStarted)) _pushPending = true;
      return;
    }

    // Kapag "Try again" ang pinindot, ipakita ulit ang spinner.
    if (!silent && _data == null && _error != null) {
      setState(() {
        _error = null;
        _loading = true;
      });
    }

    final my = ++_seq;
    _inflight = true;
    _pushPending = false;
    _loadStarted = DateTime.now();
    try {
      final d = await _fetch();
      if (!mounted || my != _seq) return;
      setState(() {
        _data = d;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || my != _seq) return;
      if (!silent || _data == null) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    } finally {
      if (my == _seq) {
        _inflight = false;
        if (mounted && _pushPending && LiveRefresh.activePage == 0) {
          _load(silent: true);
        }
      }
    }
  }

  Future<void> _refresh() async {
    await _load();
  }

  String _err(Object e) {
    try {
      return (e as dynamic).message.toString();
    } catch (_) {
      return e.toString();
    }
  }

  // Ang PickupOrderScreen ay scan-first na (ScanScreen sa loob nito).
  void _openPickup(Order o) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => PickupOrderScreen(order: o)),
  ).then((_) => _refresh());

  // Ang DeliverOrderScreen ay may Start, Mark delivered (may confirm), at Failed.
  void _openDeliver(Order o) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => DeliverOrderScreen(order: o)),
  ).then((_) => _refresh());

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Builder(
      builder: (context) {
        if (_loading && _data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (_data == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Unable to load: ${_err(_error!)}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _refresh,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          );
        }

        final d = _data!;

        final headerText = cs.onSurface;

        // ---------- stat card (full width, may icon tile at divider) ----------
        Widget stat(String n, String label, IconData icon, int goTo) =>
            Container(
              height: 66,
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: kBrandBlue.withValues(alpha: 0.14),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(22),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => widget.onGo(goTo),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(9, 9, 14, 9),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: kBrandBlue,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(icon, color: Colors.white, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Container(
                          width: 1,
                          height: 32,
                          color: cs.onSurface.withValues(alpha: 0.12),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                n,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  height: 1.1,
                                ),
                              ),
                              Text(label, style: text.bodyMedium),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: cs.onSurface.withValues(alpha: 0.75),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );

        // ---------- COD wallet card ----------
        Widget codCard() {
          const tone = kBrandBlue;
          return Container(
            height: 66,
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.transparent),
              boxShadow: [
                BoxShadow(
                  color: kBrandBlue.withValues(alpha: 0.14),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => widget.onGo(9),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(9, 9, 14, 9),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: tone,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.payments_outlined,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Container(
                        width: 1,
                        height: 32,
                        color: cs.onSurface.withValues(alpha: 0.12),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cash',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                            ),
                            Text(
                              'Outstanding COD and handovers',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: cs.onSurface.withValues(alpha: 0.75),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        // ---------- section header (may icon + See all >) ----------
        Widget head(String t, IconData icon, {VoidCallback? onSeeAll}) =>
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 6),
              child: Row(
                children: [
                  Icon(icon, size: 22, color: cs.onSurface),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  if (onSeeAll != null)
                    InkWell(
                      onTap: onSeeAll,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'See all',
                              style: TextStyle(
                                color: cs.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: cs.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );

        // ---------- empty state card (may illustration) ----------
        Widget empty({
          required String title,
          required String subtitle,
          required IconData art,
          required Color accent,
          required Color tint,
          bool badge = false,
        }) => Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
          decoration: BoxDecoration(
            color: dark ? cs.surface : tint,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: dark
                  ? cs.onSurface.withValues(alpha: 0.12)
                  : accent.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            children: [
              _EmptyArt(icon: art, accent: accent, badge: badge),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: text.bodySmall?.copyWith(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

        Widget infoRow(IconData icon, String t) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: cs.onSurface.withValues(alpha: 0.7)),
              const SizedBox(width: 8),
              Expanded(child: Text(t)),
            ],
          ),
        );

        Widget pickupCard(Order o) => Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Order #${o.reference}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'PICKUP',
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(o.item, style: text.bodyMedium),
                infoRow(Icons.person_outline, '${o.seller} (Seller)'),
                infoRow(Icons.location_on_outlined, o.from),
                infoRow(
                  Icons.local_shipping_outlined,
                  'Deliver to: ${o.buyer}, ${o.to}',
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _openPickup(o),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan & confirm pickup'),
                  ),
                ),
              ],
            ),
          ),
        );

        // Open request mula sa seller na hindi pa na-accept.
        Widget requestCard(Order o) => Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Order #${o.reference}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'REQUEST',
                        style: TextStyle(
                          color: Color(0xFF92400E),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(o.item, style: text.bodyMedium),
                infoRow(Icons.person_outline, '${o.seller} (Seller)'),
                infoRow(Icons.location_on_outlined, o.from),
                infoRow(
                  Icons.local_shipping_outlined,
                  'Deliver to: ${o.buyer}, ${o.to}',
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => widget.onGo(1),
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Review request'),
                  ),
                ),
              ],
            ),
          ),
        );

        final name = Courier.current.name.trim();
        final first = (name.isEmpty || name.contains('@'))
            ? ''
            : name.split(' ').first;

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              // The blue Home bar ends above the greeting.
              Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Good day,',
                                style: TextStyle(
                                  color: headerText.withValues(alpha: 0.92),
                                  fontSize: 17,
                                ),
                              ),
                              Text(
                                first.isEmpty ? 'Courier' : first,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.headlineMedium?.copyWith(
                                  color: headerText,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.circle,
                                size: 9,
                                color: Color(0xFF16A34A),
                              ),
                              SizedBox(width: 7),
                              Text(
                                'Online',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF166534),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(width: 2),
                              Icon(
                                Icons.keyboard_arrow_down,
                                size: 20,
                                color: Color(0xFF166534),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Here is what needs your attention.',
                      style: TextStyle(
                        color: headerText.withValues(alpha: 0.85),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Mga full-width na card: pickup, earned, deliver, COD.
                    stat(
                      '${d.pickups.length + d.requests.length}',
                      'To pick up',
                      Icons.inventory_2_outlined,
                      1,
                    ),
                    const SizedBox(height: 8),
                    stat(
                      formatMoney(d.earned, currency: d.currency),
                      'Earned today',
                      Icons.account_balance_wallet_outlined,
                      3,
                    ),
                    const SizedBox(height: 8),
                    stat(
                      '${d.deliveries.length}',
                      'To deliver',
                      Icons.local_shipping_outlined,
                      2,
                    ),
                    const SizedBox(height: 8),
                    codCard(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    head(
                      'Next pickup',
                      Icons.inventory_2_outlined,
                      onSeeAll: () => widget.onGo(1),
                    ),
                    if (d.pickups.isNotEmpty)
                      pickupCard(d.pickups.first)
                    else if (d.requests.isNotEmpty)
                      requestCard(d.requests.first)
                    else
                      empty(
                        title: 'No pickups waiting.',
                        subtitle: "You're all caught up!",
                        art: Icons.inventory_2,
                        accent: const Color(0xFF1B6FE0),
                        tint: const Color(0xFFE8F1FD),
                      ),
                    head(
                      'Next delivery',
                      Icons.local_shipping_outlined,
                      onSeeAll: () => widget.onGo(2),
                    ),
                    if (d.deliveries.isEmpty)
                      empty(
                        title: 'No deliveries waiting.',
                        subtitle: "You're all caught up!",
                        art: Icons.local_shipping,
                        accent: const Color(0xFF1B8FE0),
                        tint: const Color(0xFFE3F4EF),
                      )
                    else
                      OrderCard(
                        order: d.deliveries.first,
                        actions: [
                          FilledButton(
                            onPressed: () => _openDeliver(d.deliveries.first),
                            child: const Text('Open delivery'),
                          ),
                        ],
                      ),
                    head(
                      'Recent deliveries',
                      Icons.history,
                      onSeeAll: () => widget.onGo(4),
                    ),
                    if (d.recent.isEmpty)
                      empty(
                        title: 'No deliveries yet.',
                        subtitle: 'Completed deliveries will appear here.',
                        art: Icons.assignment_outlined,
                        accent: const Color(0xFF1B6FE0),
                        tint: const Color(0xFFE8F1FD),
                        badge: true,
                      )
                    else
                      Card(
                        child: Column(
                          children: [
                            for (final o in d.recent)
                              ListTile(
                                title: Text(o.item),
                                subtitle: Text('${o.id} \u00B7 ${o.day}'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => widget.onGo(4),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Simpleng illustration para sa empty state: malaking solid blue na icon,
/// malabong anino sa baba, at maliliit na guhit na kumikislap.
/// Kung may sarili kang PNG/SVG, palitan lang ang laman ng widget na ito.
class _EmptyArt extends StatelessWidget {
  const _EmptyArt({
    required this.icon,
    required this.accent,
    this.badge = false,
  });

  final IconData icon;
  final Color accent;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // malabong anino / blob sa ilalim
          Positioned(
            bottom: 2,
            child: Container(
              width: 62,
              height: 12,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40),
                color: accent.withValues(alpha: 0.12),
              ),
            ),
          ),
          // kumikislap na guhit
          Positioned.fill(child: CustomPaint(painter: _SparklePainter(accent))),
          // pangunahing icon
          Icon(icon, size: 38, color: kBrandBlue),
          if (badge)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.check, size: 13, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  _SparklePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final cx = size.width * 0.74;
    final cy = size.height * 0.18;
    canvas.drawLine(Offset(cx - 8, cy + 6), Offset(cx - 12, cy - 2), p);
    canvas.drawLine(Offset(cx, cy), Offset(cx - 1, cy - 10), p);
    canvas.drawLine(Offset(cx + 8, cy + 4), Offset(cx + 16, cy - 2), p);
  }

  @override
  bool shouldRepaint(covariant _SparklePainter old) => old.color != color;
}
