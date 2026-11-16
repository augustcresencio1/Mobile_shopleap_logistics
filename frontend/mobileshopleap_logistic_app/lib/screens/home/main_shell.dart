import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

import '../../core/services/live_refresh.dart';
import '../../core/services/api_client.dart';
import '../../core/services/chat_service.dart';
import '../../core/services/order_service.dart';
import '../../core/services/notification_service.dart';
import '../../services/auth_service.dart';
import '../../models/courier.dart';
import '../../models/order.dart';
import '../../models/courier_notification.dart';
import '../../widgets/money_error.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/rider_tracking_banner.dart';
import '../../core/services/rider_tracking_service.dart';
import '../account/account_screen.dart';
import '../auth/auth_gate.dart';
import '../chat/chat_list_screen.dart';
import '../dashboard/courier_dashboard_screen.dart';
import '../dashboard/delivery_dashboard_screen.dart';
import '../dashboard/pickup_dashboard_screen.dart';
import '../history/delivery_history_screen.dart';
import '../profit/profit_screen.dart';
import '../money/cash_screen.dart';
import '../scan/scan_screen.dart';
import '../settings/settings_screen.dart';
import '../support/help_support_screen.dart';
import 'app_drawer.dart';

class MainShell extends StatefulWidget {
  /// Optional. If not provided, the default logout is:
  /// delete the token and return to AuthGate -> LoginScreen.
  final VoidCallback? onLogout;
  const MainShell({super.key, this.onLogout});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _i = 0;
  int _lastPoked = -1;
  bool _sessionEnding = false;
  bool _appResumed = true;
  int _chatUnreadCount = 0;
  int _pickupCountValue = 0;
  int _deliverCountValue = 0;
  Timer? _chatTimer;

  /// True kapag ang kasalukuyang page ay pinili mula sa sidebar (drawer).
  /// Kapag pinindot ang back, babalik sa Home at bubukas ulit ang sidebar.
  bool _fromDrawer = false;

  final Set<int> _readyPages = {0};
  List<CourierNotification> _notifications = [];
  int _notificationUnread = 0, _notificationPage = 1, _notificationLastPage = 1;
  bool _notificationLoading = false;
  Object? _notificationError;
  DateTime? _notificationsCheckedAt;
  DateTime _notificationPush = DateTime.fromMillisecondsSinceEpoch(0);
  int _moneyNotifRequest = 0;
  String? _cashReceiptReference, _payoutReceiptReference;
  int _cashNavigationRevision = 0, _payoutNavigationRevision = 0;

  // Bell data (galing sa parehong API na gamit ng dashboard).
  List<Order> _notifRequests = [];
  List<Order> _notifInProgress = [];
  final _notifRevision = ValueNotifier<int>(0);
  Timer? _notifTimer;
  int _notifRequest = 0;

  int get _openRequestCount => _notifRequests.length + _notificationUnread;

  static const _titles = [
    'Dashboard',
    'Delivery Tasks',
    'Delivery Tasks',
    'Profit / Earnings',
    'Delivery history',
    'Chat',
    'Account',
    'Settings',
    'Help / Support',
    'Cash',
  ];

  // Bottom bar: 0 Home, 1 Pickup, 2 Scan, 3 Delivery, 4 Chat
  static const _barToPage = {0: 0, 1: 1, 3: 5, 4: 6};

  bool get _onBar => _barToPage.containsValue(_i) || _i == 2;

  /// -1 kapag nasa screen na wala sa bar (Profit, History, Account, ...).
  int get _barIndex {
    if (_i == 2) return 1;
    for (final e in _barToPage.entries) {
      if (e.value == _i) return e.key;
    }
    return -1;
  }

  /// Lipat ng page. `fromDrawer` = true lang kapag galing sa sidebar.
  void _go(int i, {bool fromDrawer = false}) {
    setState(() {
      _i = i;
      _fromDrawer = fromDrawer && i != 0;
    });
  }

  /// Back mula sa isang page. Kung galing sa sidebar, bubuksan ang sidebar
  /// sa ibabaw ng kasalukuyang page (hindi lilipat sa Home).
  void _goBack() {
    if (_fromDrawer) {
      setState(() => _fromDrawer = false);
      _scaffoldKey.currentState?.openDrawer();
      return;
    }
    setState(() {
      _i = 0;
      _fromDrawer = false;
    });
  }

  @override
  void initState() {
    super.initState();
    ChatService.reset();
    ChatService.threadUpdates.addListener(_onChatThreadsChanged);
    WidgetsBinding.instance.addObserver(this);
    ApiClient.sessionExpired.addListener(_onSessionExpired);
    ApiClient.sessionChanged.addListener(_clearNotificationSession);
    LiveRefresh.tick.addListener(_loadNotifs);
    LiveRefresh.tick.addListener(_loadChatUnread);
    // Realtime channel: rider:{CourierProfile id}. Kapag hindi pa na-load ang
    // profile (id = 0), polling muna; magre-restart kapag may id na.
    Courier.idChanged.addListener(_restartRealtime);
    LiveRefresh.start(Courier.current.id);
    _loadNotifs();
    _loadChatUnread();
    _notifTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _loadNotifs(),
    );
    // Backup for missed broadcasts; tick handles incoming messages immediately.
    _chatTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _loadChatUnread(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      ApiClient.invalidateCache();
      LiveRefresh.start(Courier.current.id);
      LiveRefresh.pokeNow();
      _loadNotifs();
    } else if (state == AppLifecycleState.paused) {
      LiveRefresh.stop(); // tipid sa battery at data
    }
  }

  @override
  void dispose() {
    Courier.idChanged.removeListener(_restartRealtime);
    ApiClient.sessionExpired.removeListener(_onSessionExpired);
    ApiClient.sessionChanged.removeListener(_clearNotificationSession);
    LiveRefresh.tick.removeListener(_loadNotifs);
    LiveRefresh.tick.removeListener(_loadChatUnread);
    ChatService.threadUpdates.removeListener(_onChatThreadsChanged);
    WidgetsBinding.instance.removeObserver(this);
    LiveRefresh.stop();
    _notifTimer?.cancel();
    _chatTimer?.cancel();
    _notifRevision.dispose();
    RiderTrackingService.instance.reset();
    super.dispose();
  }

  void _restartRealtime() {
    if (!mounted || !_appResumed) return;
    LiveRefresh.start(Courier.current.id);
  }

  void _onSessionExpired() {
    if (!mounted || _sessionEnding) return;
    _sessionEnding = true;
    Courier.current = Courier(name: '', phone: '', vehicle: '', plate: '');
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  void _clearNotificationSession() {
    _notifRequest++;
    _moneyNotifRequest++;
    setState(() {
      _notifications = [];
      _notificationUnread = 0;
      _notificationsCheckedAt = null;
      _notificationPush = DateTime.fromMillisecondsSinceEpoch(0);
      _notificationLoading = false;
      _cashReceiptReference = null;
      _payoutReceiptReference = null;
    });
    _notifRevision.value++;
  }

  Future<void> _loadMoneyNotifs({
    bool forceRefresh = false,
    bool more = false,
  }) async {
    if (!_appResumed || _sessionEnding) return;
    final pushed = LiveRefresh.lastPush.isAfter(_notificationPush);
    if (_notificationLoading && !pushed) return;
    forceRefresh = forceRefresh || pushed;
    if (!more &&
        !forceRefresh &&
        _notificationsCheckedAt != null &&
        DateTime.now().difference(_notificationsCheckedAt!) <
            const Duration(seconds: 60)) {
      return;
    }
    _notificationLoading = true;
    final request = ++_moneyNotifRequest;
    _notificationPush = LiveRefresh.lastPush;
    _notificationError = null;
    _notifRevision.value++;
    try {
      final page = await NotificationService.page(
        page: more ? _notificationPage + 1 : 1,
        forceRefresh: forceRefresh || more,
      );
      if (!mounted || _sessionEnding || request != _moneyNotifRequest) return;
      setState(() {
        _notifications = more ? [..._notifications, ...page.items] : page.items;
        _notificationUnread = page.unread;
        _notificationPage = page.currentPage;
        _notificationLastPage = page.lastPage;
        _notificationsCheckedAt = DateTime.now();
      });
    } catch (error) {
      if (mounted && request == _moneyNotifRequest) {
        _notificationError = error;
        _notificationsCheckedAt = DateTime.now();
      }
    } finally {
      if (mounted && request == _moneyNotifRequest) {
        _notificationLoading = false;
        _notifRevision.value++;
      }
    }
  }

  Future<void> _openNotification(CourierNotification notification) async {
    final destination = notification.moneyDestination;
    if (destination != null) {
      ApiClient.invalidateCache();
      setState(() {
        if (destination.screen == NotificationScreen.cash) {
          _cashReceiptReference = destination.receipt?.reference;
          _cashNavigationRevision++;
        } else {
          _payoutReceiptReference = destination.receipt?.reference;
          _payoutNavigationRevision++;
        }
      });
      _go(destination.screen == NotificationScreen.cash ? 9 : 3);
    }
    if (!notification.read) {
      try {
        await NotificationService.markRead(notification.id);
        if (mounted) await _loadMoneyNotifs(forceRefresh: true);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$error')));
        }
      }
    }
  }

  Future<void> _loadNotifs() async {
    if (!_appResumed || _sessionEnding) return;
    await ApiClient.getToken();
    if (!mounted || _sessionEnding) return;
    unawaited(_loadMoneyNotifs());
    final request = ++_notifRequest;
    try {
      final h = await OrderService.home();
      if (!mounted || request != _notifRequest) return;
      setState(() {
        _notifRequests = h.requests;
        _pickupCountValue = h.pickups.length + h.requests.length;
        _deliverCountValue = h.deliveries.length;
        _notifInProgress = h.inProgress
            .where(
              (order) => !const {
                'DELIVERED',
                'COMPLETED',
                'DELIVERY_FAILED',
                'RETURNED',
                'CANCELLED',
                'CANCELED',
              }.contains(order.backendStatus),
            )
            .toList();
      });
      _notifRevision.value++;
    } catch (_) {
      // Hindi hinaharangan ang app kung mabigo ang bell.
    }
  }

  Future<void> _loadChatUnread() async {
    if (!_appResumed || _sessionEnding) return;
    try {
      await ChatService.threads(forceRefresh: true);
    } catch (_) {
      // Keep the last known count while the connection is unavailable.
    }
  }

  void _onChatThreadsChanged() {
    final count = ChatService.threadUpdates.value.fold(
      0,
      (total, thread) => total + thread.unread,
    );
    if (!mounted || _sessionEnding || count == _chatUnreadCount) return;
    setState(() => _chatUnreadCount = count);
  }

  Future<void> _openBell() async {
    unawaited(_loadNotifs());
    unawaited(_loadMoneyNotifs(forceRefresh: true));
    if (!mounted) return;

    final cs = Theme.of(context).colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => ValueListenableBuilder<int>(
        valueListenable: _notifRevision,
        builder: (ctx, revision, child) {
          Widget section(
            String title,
            List<Order> list,
            int goTo,
            IconData icon, {
            bool progress = false,
          }) {
            if (list.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    '$title (${list.length})',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                for (final o in list)
                  ListTile(
                    leading: Icon(icon, color: cs.primary),
                    title: Text(
                      o.item,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      'Order #${o.reference} \u00B7 ${o.seller}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: progress
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _progressLabel(o),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.primary,
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(ctx);
                      _go(
                        progress
                            ? (o.status == OrderStatus.delivery ? 2 : 1)
                            : goTo,
                      );
                    },
                  ),
              ],
            );
          }

          final empty =
              _notifRequests.isEmpty &&
              _notifInProgress.isEmpty &&
              _notifications.isEmpty;

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.75,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_notifications.isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        try {
                          await NotificationService.markAllRead();
                          await _loadMoneyNotifs(forceRefresh: true);
                        } catch (error) {
                          if (mounted) {
                            _notificationError = error;
                            _notifRevision.value++;
                          }
                        }
                      },
                      child: const Text('Mark all as read'),
                    ),
                  for (final notification in _notifications)
                    ListTile(
                      leading: Icon(
                        notification.moneyDestination == null
                            ? Icons.notifications_outlined
                            : Icons.payments_outlined,
                      ),
                      title: Text(
                        notification.title,
                        style: TextStyle(
                          fontWeight: notification.read
                              ? FontWeight.normal
                              : FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(notification.body),
                      trailing: notification.moneyDestination == null
                          ? null
                          : const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(ctx);
                        unawaited(_openNotification(notification));
                      },
                    ),
                  if (_notificationLoading)
                    const Center(child: CircularProgressIndicator()),
                  if (_notificationError != null)
                    MoneyError(
                      error: _notificationError!,
                      onRetry: () => _loadMoneyNotifs(forceRefresh: true),
                    ),
                  if (!_notificationLoading &&
                      _notificationPage < _notificationLastPage)
                    TextButton(
                      onPressed: () => _loadMoneyNotifs(more: true),
                      child: const Text('Load more notifications'),
                    ),
                  if (empty &&
                      !_notificationLoading &&
                      _notificationError == null)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('You are all caught up.')),
                    )
                  else ...[
                    section(
                      'Open requests',
                      _notifRequests,
                      1,
                      Icons.notifications_active,
                    ),
                    section(
                      'In progress',
                      _notifInProgress,
                      1,
                      Icons.local_shipping,
                      progress: true,
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _progressLabel(Order order) => switch (order.backendStatus) {
    'PICKED_UP' => 'Picked up',
    'ASSIGNED_TO_RIDER' => 'To deliver',
    'OUT_FOR_DELIVERY' => 'Out for delivery',
    'CONFIRMED' || 'PREPARING' || 'READY_FOR_PICKUP' => 'To pick up',
    '' => order.status == OrderStatus.delivery ? 'To deliver' : 'To pick up',
    _ => order.backendStatus.replaceAll('_', ' ').toLowerCase(),
  };

  int get _pickupCount => _pickupCountValue;

  int get _deliverCount => _deliverCountValue;

  Widget _tasksSwitcher() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: 1,
              icon: Icon(Icons.inventory_2_outlined),
              label: Text('To pick up ($_pickupCount)'),
            ),
            ButtonSegment(
              value: 2,
              icon: Icon(Icons.local_shipping_outlined),
              label: Text('To deliver ($_deliverCount)'),
            ),
          ],
          selected: {_i},
          onSelectionChanged: (s) => _go(s.first),
        ),
      ),
    );
  }

  void _openScan() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ScanScreen()));
  }

  void _onBarTap(int b) {
    if (b == 2) {
      _openScan();
      return;
    }
    _go(_barToPage[b]!);
  }

  Future<void> _logout() async {
    await RiderTrackingService.instance.stop();
    if (widget.onLogout != null) {
      await ApiClient.clearToken();
      widget.onLogout!();
      return;
    }

    await AuthService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEA580C),
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _logout();
    }
  }

  // Larawan ng courier sa drawer. Kapag walang larawan, ang unang letra ng pangalan.

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    _readyPages.add(_i);

    // Sinasabi sa LiveRefresh kung aling tab ang nakabukas, at nagre-refresh
    // agad kapag lumipat ng tab.
    LiveRefresh.activePage = _i;
    if (_lastPoked != _i) {
      _lastPoked = _i;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => LiveRefresh.pokeNow(),
      );
    }

    final pages = <Widget>[
      CourierDashboardScreen(onGo: (i) => _go(i)),
      const PickupDashboardScreen(),
      const DeliveryDashboardScreen(),
      ProfitScreen(
        receiptReference: _payoutReceiptReference,
        navigationRevision: _payoutNavigationRevision,
      ),
      const DeliveryHistoryScreen(),
      ChatListScreen(
        onBack: () => _go(0),
        onBell: _openBell,
        bellCount: _openRequestCount,
      ),
      AccountScreen(onBack: _goBack),
      SettingsScreen(onBack: _goBack),
      const HelpSupportScreen(),
      CashScreen(
        embedded: true,
        receiptReference: _cashReceiptReference,
        navigationRevision: _cashNavigationRevision,
      ),
    ];

    return PopScope(
      // Nasa Home = pwedeng lumabas ng app. Nasa ibang page = back muna.
      canPop: _i == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final state = _scaffoldKey.currentState;
        if (state != null && state.isDrawerOpen) {
          state.closeDrawer();
          return;
        }
        _goBack();
      },
      child: Scaffold(
        key: _scaffoldKey,
        appBar: (_i == 5 || _i == 6 || _i == 7)
            ? null
            : AppBar(
                backgroundColor: _i == 0 ? kBrandBlue : cs.surface,
                foregroundColor: _i == 0 ? Colors.white : cs.onSurface,
                leading: _i == 0
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: _goBack,
                      ),
                title: _i == 0
                    ? null
                    : Text(
                        _titles[_i],
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                actions: _i == 0
                    ? [
                        IconButton(
                          tooltip: 'Notifications',
                          onPressed: _openBell,
                          icon: Badge(
                            isLabelVisible: _openRequestCount > 0,
                            label: Text(
                              _openRequestCount > 99
                                  ? '99+'
                                  : '$_openRequestCount',
                            ),
                            child: const Icon(Icons.notifications_none),
                          ),
                        ),
                      ]
                    : null,
              ),
        onDrawerChanged: (open) {
          if (open) setState(() {});
        },
        drawer: AppDrawer(
          selected: _i,
          name: Courier.current.name,
          photoUrl: Courier.current.photoUrl,
          onSelect: (i) => _go(i, fromDrawer: true),
          onLogout: _confirmLogout,
        ),
        body: Column(
          children: [
            const RiderTrackingBanner(),
            if (_i == 1 || _i == 2) _tasksSwitcher(),
            Expanded(
              child: IndexedStack(
                index: _i,
                children: [
                  for (var index = 0; index < pages.length; index++)
                    TickerMode(
                      enabled: index == _i,
                      child: _readyPages.contains(index)
                          ? pages[index]
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: AppBottomNav(
          currentIndex: _onBar ? _barIndex : -1,
          onTap: _onBarTap,
          chatBadge: _chatUnreadCount,
          taskBadge: _pickupCount + _deliverCount,
        ),
      ),
    );
  }
}
