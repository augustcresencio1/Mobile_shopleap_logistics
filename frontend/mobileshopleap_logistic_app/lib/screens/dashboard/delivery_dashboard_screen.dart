import 'package:flutter/material.dart';
import '../../core/services/live_refresh.dart';
import '../../core/services/order_service.dart';
import '../../models/order.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/order_card.dart';
import '../orders/deliver_order_screen.dart';
import '../orders/pending_delivery_screen.dart';
import '../navigation/rider_route_screen.dart';

class DeliveryDashboardScreen extends StatefulWidget {
  const DeliveryDashboardScreen({super.key});

  @override
  State<DeliveryDashboardScreen> createState() =>
      _DeliveryDashboardScreenState();
}

class _DeliveryDashboardScreenState extends State<DeliveryDashboardScreen> {
  List<Order>? _data;
  Object? _error;
  bool _loading = true;
  bool _inflight = false;
  bool _pushPending = false;
  DateTime _loadStarted = DateTime.fromMillisecondsSinceEpoch(0);
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _data = OrderService.cachedHome()?.deliveries;
    _loading = _data == null;
    if (_data == null || LiveRefresh.activePage == 2) _load();
    LiveRefresh.tick.addListener(_onTick);
  }

  @override
  void dispose() {
    LiveRefresh.tick.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (LiveRefresh.activePage == 2) _load(silent: true);
  }

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
      final d = await OrderService.itemsForDelivery();
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
        if (mounted && _pushPending && LiveRefresh.activePage == 2) {
          _load(silent: true);
        }
      }
    }
  }

  void _refresh() => _load();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Pending delivery uploads'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PendingDeliveryScreen()),
            ).then((_) => _refresh()),
          ),
        ),
        Expanded(
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

                final items = _data!;

                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    const ScreenSectionTitle('To deliver'),
                    const FullRouteButton(role: 'delivery'),
                    if (items.isEmpty) ...[
                      const SizedBox(height: 40),
                      EmptyState(
                        art: EmptyStateArt.delivery,
                        title: 'No items to deliver.',
                        message: 'Accepted delivery jobs will appear here.',
                      ),
                    ],
                    for (final o in items)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: OrderCard(
                          order: o,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DeliverOrderScreen(order: o),
                            ),
                          ).then((_) => _refresh()),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
