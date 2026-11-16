import 'package:flutter/material.dart';
import '../../widgets/proof_uploaded_indicator.dart';
import 'package:intl/intl.dart';

import '../../core/services/earnings_service.dart';
import '../../core/services/api_client.dart';
import '../../core/services/api_exception.dart';
import '../../core/services/live_refresh.dart';
import '../../core/utils/money.dart';
import '../../core/theme/app_typography.dart';
import '../../models/earnings.dart';
import '../../models/receipt.dart';
import '../../widgets/money_error.dart';
import '../../widgets/receipt_action.dart';

const _kBrand = Color(0xFF1B5BB8);
const _kMuted = Color(0xFF6B7A90);
const _kText = Color(0xFF1B2A41);
const _kLine = Color(0xFFE6ECF4);
const _kSoft = Color(0xFFF1F5FB);

TextStyle _f(double size, FontWeight weight, Color color) => TextStyle(
  fontFamily: kAppFontFamily,
  fontSize: size,
  fontWeight: weight,
  color: color,
);

class ProfitScreen extends StatefulWidget {
  final String? receiptReference;
  final int navigationRevision;
  const ProfitScreen({
    super.key,
    this.receiptReference,
    this.navigationRevision = 0,
  });

  @override
  State<ProfitScreen> createState() => _ProfitScreenState();
}

class _ProfitScreenState extends State<ProfitScreen> {
  String _period = 'month';
  DateTimeRange? _range;
  EarningsOverview? _data;
  List<EarningsHistoryItem> _history = [];
  int _page = 1, _lastPage = 1, _total = 0, _generation = 0;
  bool _loading = false, _loadingMore = false;
  bool _wasActive = false;
  bool _refreshing = false;
  int _revision = 0;
  DateTime _lastLoad = DateTime.fromMillisecondsSinceEpoch(0);
  Object? _error, _historyError;

  EarningsFilter get _filter =>
      EarningsFilter(period: _period, from: _range?.start, to: _range?.end);

  @override
  void initState() {
    super.initState();
    _wasActive = LiveRefresh.activePage == 3;
    if (widget.navigationRevision > 0) _period = 'all';
    ApiClient.sessionChanged.addListener(_clearSession);
    LiveRefresh.tick.addListener(_onTick);
    LiveRefresh.deliveriesChanged.addListener(_onDelivery);
    _load();
  }

  @override
  void dispose() {
    _generation++;
    ApiClient.sessionChanged.removeListener(_clearSession);
    LiveRefresh.tick.removeListener(_onTick);
    LiveRefresh.deliveriesChanged.removeListener(_onDelivery);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ProfitScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationRevision != widget.navigationRevision) {
      _period = 'all';
      _range = null;
      _load(silent: true, forceRefresh: true);
    }
  }

  void _clearSession() {
    _generation++;
    _refreshing = false;
    setState(() {
      _data = null;
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
    final active = LiveRefresh.activePage == 3;
    final stale =
        DateTime.now().difference(_lastLoad) > const Duration(seconds: 30);
    final pushed = LiveRefresh.lastPush.isAfter(_lastLoad);
    final invalidated =
        !LiveRefresh.isPolling && _revision != ApiClient.revision;
    if (active && (!_wasActive || pushed || invalidated || stale)) {
      debugPrint(
        'Profit reload: tick rev=${ApiClient.revision} mine=$_revision',
      );
      _load(silent: true, forceRefresh: true);
    }
    _wasActive = active;
  }

  void _onDelivery() {
    debugPrint('Profit reload: deliveriesChanged');
    _load(silent: true, forceRefresh: true);
  }

  void _apply(EarningsOverview data) {
    _data = data;
    _history = data.history.items;
    _page = data.history.currentPage;
    _lastPage = data.history.lastPage;
    _total = data.history.total;
  }

  /// [silent] = background refresh: keeps the current data on screen,
  /// shows no spinner. Failed reads clear stale financial records.
  Future<void> _load({bool silent = false, bool forceRefresh = true}) async {
    // Don't stack background refreshes on top of each other.
    await ApiClient.getToken();
    if (!mounted) return;
    if (silent && _refreshing && _revision == ApiClient.revision) return;
    final generation = ++_generation;
    _revision = ApiClient.revision;
    _refreshing = true;
    _lastLoad = DateTime.now();
    final keepData = silent && _data != null;
    final filter = _filter;
    setState(() {
      if (!keepData) {
        _loading = true;
        _data = null;
        _history = [];
      }
      _loadingMore = false;
      _error = null;
      _historyError = null;
    });
    try {
      final data = await EarningsService.overview(
        filter,
        forceRefresh: forceRefresh,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _apply(data);
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _data = null;
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
    final filter = _filter;
    setState(() {
      _loadingMore = true;
      _historyError = null;
    });
    try {
      final page = await EarningsService.history(
        filter,
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
            _data = null;
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

  /// Shows quick presets (Last 7 / Last 30 days) and a "Choose dates..."
  /// option that opens the normal date range picker.
  Future<DateTimeRange?> _pickCustomRange() async {
    final t = EarningsFilter.manilaToday();
    final today = DateTime(t.year, t.month, t.day);

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Last 7 days'),
              onTap: () => Navigator.pop(ctx, '7d'),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Last 30 days'),
              onTap: () => Navigator.pop(ctx, '30d'),
            ),
            ListTile(
              leading: const Icon(Icons.date_range),
              title: const Text('Choose dates...'),
              onTap: () => Navigator.pop(ctx, 'pick'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return null;

    if (choice == '7d') {
      return DateTimeRange(
        start: DateTime(today.year, today.month, today.day - 6),
        end: today,
      );
    }
    if (choice == '30d') {
      return DateTimeRange(
        start: DateTime(today.year, today.month, today.day - 29),
        end: today,
      );
    }

    return showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today,
      initialDateRange: _range,
      helpText: 'Choose up to 366 days (Asia/Manila)',
    );
  }

  Future<void> _selectPeriod(String period) async {
    DateTimeRange? range;
    if (period == 'custom') {
      range = await _pickCustomRange();
      if (range == null || !mounted) return;
      try {
        EarningsFilter(period: 'custom', from: range.start, to: range.end);
      } on ArgumentError catch (error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${error.message}')));
        return;
      }
    } else if (period == _period) {
      return;
    }
    setState(() {
      _period = period;
      _range = range;
    });
    // Bagong filter: ipakita ang spinner (hindi silent).
    await _load();
  }

  String _dateLabel(String? raw, {bool withTime = false}) {
    if (raw == null || raw.isEmpty) return 'Not recorded';
    var date = DateTime.tryParse(raw);
    if (date == null) return raw;
    if (withTime) {
      date = date.toUtc().add(const Duration(hours: 8));
      return DateFormat('MMM d, yyyy \u00B7 h:mm a').format(date);
    }
    return DateFormat('MMM d, yyyy').format(date);
  }

  Widget _periodBar() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: Row(
      children: [
        for (final entry in const {
          'all': 'All',
          'today': 'Today',
          'week': 'Week',
          'month': 'Month',
          '7d': 'Last 7 days',
          '30d': 'Last 30 days',
          'custom': 'Custom',
        }.entries)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: _period == entry.key ? _kBrand : _kSoft,
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => _selectPeriod(entry.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  child: Text(
                    entry.value,
                    style: _f(
                      13.5,
                      FontWeight.w600,
                      _period == entry.key ? Colors.white : _kText,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _stat(
    IconData icon,
    Color bg,
    Color fg,
    String value,
    String label, {
    String? tooltip,
  }) => Expanded(
    child: Tooltip(
      message: tooltip ?? label,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kLine),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, color: fg, size: 21),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: _f(20, FontWeight.w700, _kText)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _f(12, FontWeight.w400, _kMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _dayCard(Map<String, dynamic> row, String currency) {
    final dayCurrency = row['currency']?.toString() ?? currency;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kLine),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dateLabel(row['date']?.toString()),
                  style: _f(15, FontWeight.w700, _kText),
                ),
                const SizedBox(height: 3),
                Text(
                  '${row['deliveries']} deliveries \u00B7 Cash collected '
                  '${formatMoney(row['cod_collected'], currency: dayCurrency)}',
                  style: _f(12.5, FontWeight.w400, _kMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatMoney(row['earned'], currency: dayCurrency),
            style: _f(15, FontWeight.w700, _kText),
          ),
        ],
      ),
    );
  }

  Widget _historyCard(EarningsHistoryItem item) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _kLine),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.reference == 'Reference unavailable'
                    ? item.reference
                    : 'Order #${item.reference}',
                style: _f(15, FontWeight.w700, _kText),
              ),
              const SizedBox(height: 3),
              Text(
                _dateLabel(item.deliveredAt, withTime: true),
                style: _f(12.5, FontWeight.w400, _kMuted),
              ),
              if (item.proof.uploaded) const ProofUploadedIndicator(),
              Chip(label: Text(item.payoutLabel)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          formatMoney(
            item.amount,
            currency: item.currency,
            missing: 'Not recorded',
          ),
          style: _f(
            item.amount == null ? 12.5 : 15,
            item.amount == null ? FontWeight.w400 : FontWeight.w700,
            item.amount == null ? _kMuted : _kText,
          ),
        ),
      ],
    ),
  );

  Widget _errorNotice(Object error, VoidCallback retry) =>
      MoneyError(error: error, onRetry: retry);

  Widget _content(EarningsOverview data) {
    final summary = data.summary;
    final currency = summary['currency']?.toString() ?? 'PHP';
    final rateCurrency = data.rate['currency']?.toString() ?? 'PHP';
    final daily = summary['daily'] as List? ?? const [];
    final deliveries = summary['deliveries'] ?? 0;
    final recorded = summary['recorded_earnings'] ?? 0;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (widget.receiptReference case final reference?)
          ReceiptAction(
            target: ReceiptTarget(ReceiptType.riderPayout, reference),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Totals follow order delivery dates. Paid earnings belong to orders delivered '
            'in this period; they do not show when the hub paid you.',
          ),
        ),
        Row(
          children: [
            _stat(
              Icons.pending_actions,
              const Color(0xFFFFF1D6),
              const Color(0xFFD98A00),
              formatMoney(data.accruedUnpaid, currency: currency),
              'Accrued / unpaid',
            ),
            const SizedBox(width: 10),
            _stat(
              Icons.task_alt,
              const Color(0xFFDDF5E5),
              const Color(0xFF1E8E4E),
              formatMoney(data.paid, currency: currency),
              'Paid',
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_error != null) _errorNotice(_error!, () => _load(silent: true)),
        if (_range != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${_dateLabel(_filter.query['from'])} \u2013 '
              '${_dateLabel(_filter.query['to'])} (Asia/Manila)',
            ),
          ),
        Row(
          children: [
            _stat(
              Icons.account_balance_wallet_outlined,
              const Color(0xFFDDF5E5),
              const Color(0xFF1E8E4E),
              formatMoney(summary['total_earned'], currency: currency),
              'Total earned',
            ),
            const SizedBox(width: 10),
            _stat(
              Icons.local_shipping_outlined,
              const Color(0xFFE0ECFD),
              _kBrand,
              '$deliveries',
              'Deliveries',
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _stat(
              Icons.toll_outlined,
              const Color(0xFFFFF1D6),
              const Color(0xFFD98A00),
              formatMoney(data.rate['amount'], currency: rateCurrency),
              'Fee per delivery',
              tooltip:
                  'Current pay per successful delivery. Previous earnings stay fixed when rates change.'
                  '${data.rate['effective_from'] == null ? '' : '\nEffective since ${_dateLabel(data.rate['effective_from'].toString(), withTime: true)} (Asia/Manila)'}',
            ),
            const SizedBox(width: 10),
            _stat(
              Icons.payments_outlined,
              const Color(0xFFDDF5E5),
              const Color(0xFF1E8E4E),
              formatMoney(summary['cod_collected'], currency: currency),
              'Cash collected',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info, color: _kBrand, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'COD cash must be handed over in full. Rider earnings are paid separately by the hub.',
                  style: _f(12.5, FontWeight.w400, _kText),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (data.rate['amount'] == null)
          Text(
            'No delivery rate is currently configured.',
            style: _f(12.5, FontWeight.w400, _kMuted),
          ),
        const SizedBox(height: 8),
        Text(
          'Recorded earnings: $recorded of $deliveries deliveries.',
          style: _f(12.5, FontWeight.w400, _kMuted),
        ),
        const SizedBox(height: 18),
        Text('Per day', style: _f(17, FontWeight.w700, _kText)),
        const SizedBox(height: 10),
        if (daily.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                'No deliveries in this period yet',
                style: _f(14, FontWeight.w400, _kMuted),
              ),
            ),
          ),
        for (final row in daily)
          _dayCard(Map<String, dynamic>.from(row as Map), currency),
        const SizedBox(height: 20),
        Text(
          'Earnings history ($_total)',
          style: _f(17, FontWeight.w700, _kText),
        ),
        const SizedBox(height: 10),
        if (_history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                'No deliveries in this period yet',
                style: _f(14, FontWeight.w400, _kMuted),
              ),
            ),
          ),
        for (final item in _history) _historyCard(item),
        if (_historyError != null) _errorNotice(_historyError!, _loadMore),
        if (_loadingMore)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_page < _lastPage && _historyError == null)
          TextButton(
            onPressed: _loading ? null : _loadMore,
            child: const Text('Load more'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: const TextStyle(fontFamily: kAppFontFamily, color: _kText),
    child: Container(
      color: const Color(0xFFF7F9FC),
      child: Column(
        children: [
          _periodBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(silent: true, forceRefresh: true),
              child: _data != null
                  ? _content(_data!)
                  : _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      children: [
                        if (_error != null) _errorNotice(_error!, _load),
                      ],
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}
