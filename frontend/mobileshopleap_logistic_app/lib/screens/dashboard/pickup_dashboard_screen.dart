import 'package:flutter/material.dart';
import '../../core/services/live_refresh.dart';
import '../../core/services/order_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/order.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/order_card.dart';
import '../../widgets/styled_parts.dart';
import '../orders/pickup_order_screen.dart';
import '../navigation/rider_route_screen.dart';

class PickupDashboardScreen extends StatefulWidget {
  const PickupDashboardScreen({super.key});

  @override
  State<PickupDashboardScreen> createState() => _PickupDashboardScreenState();
}

class _PickupDashboardScreenState extends State<PickupDashboardScreen> {
  List<List<Order>>? _data;
  Object? _error;
  bool _loading = true;
  bool _inflight = false;
  bool _pushPending = false;
  DateTime _loadStarted = DateTime.fromMillisecondsSinceEpoch(0);
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    final home = OrderService.cachedHome();
    if (home != null) {
      _data = [home.requests, home.pickups];
      _loading = false;
    }
    if (_data == null || LiveRefresh.activePage == 1) _load();
    LiveRefresh.tick.addListener(_onTick);
  }

  @override
  void dispose() {
    LiveRefresh.tick.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (LiveRefresh.activePage == 1) _load(silent: true);
  }

  // [0] = pickup requests (galing sa sellers/hub), [1] = items for pickup
  Future<List<List<Order>>> _fetch() => Future.wait([
    OrderService.pickupRequests(),
    OrderService.itemsForPickup(),
  ]);

  /// silent = true: auto-refresh sa background. Walang spinner, at hindi
  /// binubura ang kasalukuyang data kung mabigo.
  Future<void> _load({bool silent = false}) async {
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
        if (mounted && _pushPending && LiveRefresh.activePage == 1) {
          _load(silent: true);
        }
      }
    }
  }

  void _refresh() => _load();

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _run(Future<void> Function() action, String okMsg) async {
    try {
      await action();
      _toast(okMsg);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('May error: $e');
    }
    _refresh();
  }

  Future<void> _decline(Order o) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Decline pickup'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Dahilan'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kanselahin'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('I-decline'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    await _run(
      () => OrderService.declinePickup(o.orderNumber, reason),
      'Pickup declined.',
    );
  }

  Widget _padded(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    return SoftPage(
      child: RefreshIndicator(
        onRefresh: () => _load(),
        child: Builder(
          builder: (context) {
            if (_loading && _data == null) {
              return const Center(child: CircularProgressIndicator());
            }

            if (_data == null) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  Text(_error.toString(), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Center(
                    child: FilledButton(
                      onPressed: _refresh,
                      child: const Text('Try again'),
                    ),
                  ),
                ],
              );
            }

            final requests = _data![0];
            final items = _data![1];

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              children: [
                const _SectionHeader(
                  icon: Icons.notifications_none,
                  title: 'Notifications from Sellers',
                ),
                if (requests.isEmpty)
                  const InfoNoticeCard(message: 'No new pickup requests.'),
                for (final o in requests)
                  _padded(
                    OrderCard(
                      order: o,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PickupOrderScreen(order: o),
                        ),
                      ).then((_) => _refresh()),
                      actions: [
                        GradientFilledButton(
                          label: 'Accept',
                          icon: Icons.check_circle_outline,
                          expand: true,
                          onPressed: () => _run(
                            () => OrderService.acceptPickup(o.orderNumber),
                            'Pickup accepted.',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _decline(o),
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Decline'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 52),
                            foregroundColor: kBrandBlue,
                            side: const BorderSide(
                              color: kBrandBlue,
                              width: 1.5,
                            ),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                const _SectionHeader(
                  icon: Icons.inventory_2_outlined,
                  title: 'Items for Pickup',
                ),
                const FullRouteButton(role: 'pickup'),
                if (items.isEmpty) ...[
                  const SizedBox(height: 16),
                  EmptyState(
                    art: EmptyStateArt.pickup,
                    title: 'No items to pick up.',
                    message:
                        'New pickup requests from sellers will appear here.',
                  ),
                ],
                for (final o in items)
                  _padded(
                    OrderCard(
                      order: o,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PickupOrderScreen(order: o),
                        ),
                      ).then((_) => _refresh()),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Section title na may icon chip sa kaliwa.
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: cs.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
