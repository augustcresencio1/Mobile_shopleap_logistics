import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/services/api_client.dart';
import '../../core/services/api_exception.dart';
import '../../core/services/cash_service.dart';
import '../../core/services/live_refresh.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money.dart';
import '../../models/cash.dart';
import '../../models/receipt.dart';
import '../../widgets/gradient_header.dart';
import '../../widgets/money_error.dart';
import '../../widgets/receipt_action.dart';
import '../../widgets/styled_parts.dart';

class CashScreen extends StatefulWidget {
  final bool embedded;
  final String? receiptReference;
  final int navigationRevision;
  const CashScreen({
    super.key,
    this.embedded = false,
    this.receiptReference,
    this.navigationRevision = 0,
  });

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> with WidgetsBindingObserver {
  CashSummary? _summary;
  List<CashHandover> _history = [];
  int _page = 1, _lastPage = 1, _total = 0, _generation = 0, _revision = -1;
  bool _loading = true,
      _loadingMore = false,
      _wasActive = false,
      _refreshing = false;
  Object? _error, _historyError;
  DateTime _lastLoad = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _active => !widget.embedded || LiveRefresh.activePage == 9;

  @override
  void initState() {
    super.initState();
    _wasActive = _active;
    WidgetsBinding.instance.addObserver(this);
    ApiClient.sessionChanged.addListener(_clearSession);
    LiveRefresh.tick.addListener(_onTick);
    LiveRefresh.deliveriesChanged.addListener(_onDelivery);
    _load();
  }

  @override
  void didUpdateWidget(covariant CashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationRevision != widget.navigationRevision) {
      debugPrint('Cash reload: navigationRevision changed');
      _load(silent: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Embedded screens receive the shell's resume invalidation.
    if (!widget.embedded && state == AppLifecycleState.resumed) {
      debugPrint('Cash reload: app resumed');
      _load(silent: true);
    }
  }

  void _clearSession() {
    _generation++;
    _refreshing = false;
    setState(() {
      _summary = null;
      _history = [];
      _loading = false;
      _error = ApiException(
        ApiClient.hasSession
            ? 'Your account changed. Refresh to continue.'
            : 'Please sign in again.',
        ApiClient.hasSession ? null : 401,
      );
    });
  }

  void _onTick() {
    final active = _active;
    final stale =
        DateTime.now().difference(_lastLoad) > const Duration(seconds: 30);
    final pushed = LiveRefresh.lastPush.isAfter(_lastLoad);
    final invalidated =
        !LiveRefresh.isPolling && _revision != ApiClient.revision;
    if (active && (!_wasActive || pushed || invalidated || stale)) {
      debugPrint('Cash reload: tick rev=${ApiClient.revision} mine=$_revision');
      _load(silent: true);
    }
    _wasActive = active;
  }

  void _onDelivery() {
    if (_active) {
      debugPrint('Cash reload: deliveriesChanged');
      _load(silent: true);
    }
  }

  /// [silent] = background refresh: keeps the current data on screen,
  /// shows no spinner. Failed reads clear stale financial records.
  Future<void> _load({bool silent = false}) async {
    // Don't stack background refreshes on top of each other.
    await ApiClient.getToken();
    if (!mounted) return;
    if (silent && _refreshing && _revision == ApiClient.revision) return;
    final generation = ++_generation;
    _revision = ApiClient.revision;
    _refreshing = true;
    _lastLoad = DateTime.now();
    final keepData = silent && _summary != null;
    setState(() {
      if (!keepData) {
        _summary = null;
        _history = [];
        _loading = true;
      }
      _loadingMore = false;
      _error = null;
      _historyError = null;
    });
    try {
      final results = await Future.wait<Object>([
        CashService.summary(forceRefresh: true),
        CashService.history(forceRefresh: true),
      ]);
      if (!mounted || generation != _generation) return;
      final history = results[1] as CashHistoryPage;
      setState(() {
        _summary = results[0] as CashSummary;
        _history = history.items;
        _page = history.currentPage;
        _lastPage = history.lastPage;
        _total = history.total;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _summary = null;
          _history = [];
          _error = error;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        _refreshing = false;
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _page >= _lastPage) return;
    final generation = _generation;
    setState(() {
      _loadingMore = true;
      _historyError = null;
    });
    try {
      final page = await CashService.history(
        page: _page + 1,
        forceRefresh: true,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _history = [..._history, ...page.items];
        _page = page.currentPage;
        _lastPage = page.lastPage;
        _total = page.total;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          if (error is ApiException && [401, 403].contains(error.statusCode)) {
            _summary = null;
            _history = [];
            _error = error;
          } else {
            _historyError = error;
          }
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loadingMore = false);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    ApiClient.sessionChanged.removeListener(_clearSession);
    LiveRefresh.tick.removeListener(_onTick);
    LiveRefresh.deliveriesChanged.removeListener(_onDelivery);
    super.dispose();
  }

  String _date(String? raw) {
    final date = DateTime.tryParse(raw ?? '');
    return date == null
        ? 'Date unavailable'
        : '${DateFormat('MMM d, yyyy · h:mm a').format(date.toUtc().add(const Duration(hours: 8)))} (Asia/Manila)';
  }

  // ---------- UI parts ----------

  /// Solid-tint stat card (walang gradient).
  Widget _statCard({
    required IconData icon,
    required String label,
    required String? amount,
    required String currency,
    required Color tint,
    required Color accent,
  }) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? cs.surface : tint,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: cs.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatMoney(amount, currency: currency, missing: 'Unavailable'),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBanner() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kBrandBlue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBrandBlue.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: cs.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Cash on hand is COD cash still owed to the hub. The shortage is '
              'already included. Hand over the full outstanding cash; rider '
              'earnings are paid separately by the hub.',
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: cs.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 32, color: cs.primary),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(CashSummary summary) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _statCard(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Cash on Hand',
                    amount: summary.cashOnHand,
                    currency: summary.currency,
                    tint: const Color(0xFFE8F0FB),
                    accent: kBrandBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statCard(
                    icon: Icons.savings_outlined,
                    label: 'Outstanding Shortage',
                    amount: summary.shortageAmount,
                    currency: summary.currency,
                    tint: const Color(0xFFFFF1E6),
                    accent: const Color(0xFFD9640A),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: _infoBanner(),
        ),
        if (widget.receiptReference case final reference?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: ReceiptAction(
              target: ReceiptTarget(ReceiptType.cashHandover, reference),
            ),
          ),
        SectionCard(
          title: 'Outstanding Parcels',
          icon: Icons.inventory_2_outlined,
          children: [
            if (summary.orders.isEmpty)
              _empty(Icons.inventory_2_outlined, 'No outstanding COD cash.'),
            for (final order in summary.orders)
              InfoCard(
                icon: Icons.inventory_2_outlined,
                label: order.orderNumber,
                value:
                    'Remaining cash: ${formatMoney(order.amount, currency: summary.currency, missing: 'Unavailable')}\n'
                    'Delivered ${_date(order.deliveredAt)}',
              ),
          ],
        ),
        SectionCard(
          title: 'Cash Handovers ($_total)',
          icon: Icons.payments_outlined,
          children: [
            Text(
              'Cash received includes later settlements. Dates show the original confirmation.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.3,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
            if (_history.isEmpty)
              _empty(Icons.receipt_long_outlined, 'No cash handovers yet.'),
            for (final handover in _history)
              InfoCard(
                icon: Icons.receipt_long_outlined,
                label: handover.reference,
                value:
                    'Cash received: ${formatMoney(handover.amount, currency: handover.currency, missing: 'Unavailable')}\n'
                    '${_date(handover.confirmedAt)}',
                footer: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Chip(label: Text(handover.statusLabel)),
                    ReceiptAction(
                      target: ReceiptTarget(
                        ReceiptType.cashHandover,
                        handover.reference,
                      ),
                    ),
                  ],
                ),
              ),
            if (_historyError != null)
              MoneyError(error: _historyError!, onRetry: _loadMore),
            if (_loadingMore)
              const Center(child: CircularProgressIndicator())
            else if (_page < _lastPage && _historyError == null)
              TextButton(
                onPressed: _loadMore,
                child: const Text('Load more handovers'),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final body = RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 16, bottom: 24),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: MoneyError(error: _error!, onRetry: _load),
                  )
                else if (_summary != null)
                  _content(_summary!),
              ],
            ),
    );
    final page = SoftPage(child: body);
    return widget.embedded
        ? page
        : Scaffold(
            backgroundColor: dark ? null : kBrandPaleBlue,
            appBar: const GradientAppBar(title: 'Cash'),
            body: page,
          );
  }
}
