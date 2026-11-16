import 'package:flutter/material.dart';
import '../../widgets/proof_uploaded_indicator.dart';
import 'package:intl/intl.dart';

import '../../core/services/api_config.dart';
import '../../core/services/history_service.dart';
import '../../core/services/order_service.dart';
import '../../core/services/live_refresh.dart';
import '../../core/utils/money.dart';
import '../../core/theme/app_typography.dart';
import 'delivery_detail_screen.dart';

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

class DeliveryHistoryScreen extends StatefulWidget {
  const DeliveryHistoryScreen({super.key});

  @override
  State<DeliveryHistoryScreen> createState() => _DeliveryHistoryScreenState();
}

class _DeliveryHistoryScreenState extends State<DeliveryHistoryScreen> {
  final _scroll = ScrollController();
  final List<HistoryItem> _items = [];

  int _page = 0;
  int _last = 1;
  int _total = 0;
  bool _loading = false;
  int _generation = 0;
  String? _error;

  String? _status; // null = lahat | delivered | returned
  DateTimeRange? _range;
  String _preset = 'any'; // any | today | 7d | 30d | month | custom

  bool get _filters => ApiConfig.v4;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients &&
          _scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
        _load();
      }
    });
    _load(reset: true);
    LiveRefresh.deliveriesChanged.addListener(_onDelivery);
  }

  @override
  void dispose() {
    LiveRefresh.deliveriesChanged.removeListener(_onDelivery);
    _scroll.dispose();
    super.dispose();
  }

  void _onDelivery() => _load(reset: true, keepData: true);

  Future<void> _load({bool reset = false, bool keepData = false}) async {
    if (_loading && !reset) return;
    final generation = reset ? ++_generation : _generation;
    final next = reset ? 1 : _page + 1;
    if (!reset && next > _last) return;

    setState(() {
      _loading = true;
      _error = null;
      if (reset && !keepData) {
        _items.clear();
        _page = 0;
        _last = 1;
        _total = 0;
      }
    });
    try {
      final p = await HistoryService.fetch(
        page: next,
        from: _range?.start,
        to: _range?.end,
        status: _status,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(p.items);
        _page = p.currentPage;
        _last = p.lastPage;
        _total = p.total;
      });
    } on ApiException catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e.message);
      }
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = '$e');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  // ---------- date filter ----------

  ThemeData _pickerTheme(BuildContext c) {
    final base = Theme.of(c);
    return base.copyWith(
      colorScheme: const ColorScheme.light(
        primary: _kBrand,
        onPrimary: Colors.white,
        surface: Colors.white,
        onSurface: _kText,
      ),
      textTheme: base.textTheme.apply(fontFamily: kAppFontFamily),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: _kBrand,
        headerForegroundColor: Colors.white,
        rangeSelectionBackgroundColor: _kBrand.withValues(alpha: 0.12),
        todayBorder: const BorderSide(color: _kBrand),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: _kBrand),
      ),
    );
  }

  void _applyRange(String preset, DateTimeRange? range) {
    setState(() {
      _preset = preset;
      _range = range;
    });
    _load(reset: true);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        Widget option(String key, String label, IconData icon) {
          final selected = _preset == key;
          return ListTile(
            leading: Icon(icon, color: selected ? _kBrand : _kMuted),
            title: Text(
              label,
              style: _f(
                15,
                selected ? FontWeight.w700 : FontWeight.w500,
                selected ? _kBrand : _kText,
              ),
            ),
            trailing: selected
                ? const Icon(Icons.check_circle, color: _kBrand)
                : null,
            onTap: () => Navigator.pop(ctx, key),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Date', style: _f(20, FontWeight.w700, _kText)),
              ),
              option('any', 'Any date', Icons.all_inclusive),
              option('today', 'Today', Icons.today_outlined),
              option('7d', 'Last 7 days', Icons.date_range_outlined),
              option('30d', 'Last 30 days', Icons.date_range_outlined),
              option('month', 'This month', Icons.calendar_view_month_outlined),
              option('custom', 'Custom range', Icons.edit_calendar_outlined),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case 'any':
        _applyRange('any', null);
        break;
      case 'today':
        _applyRange('today', DateTimeRange(start: today, end: today));
        break;
      case '7d':
        _applyRange(
          '7d',
          DateTimeRange(
            start: today.subtract(const Duration(days: 6)),
            end: today,
          ),
        );
        break;
      case '30d':
        _applyRange(
          '30d',
          DateTimeRange(
            start: today.subtract(const Duration(days: 29)),
            end: today,
          ),
        );
        break;
      case 'month':
        _applyRange(
          'month',
          DateTimeRange(
            start: DateTime(today.year, today.month, 1),
            end: today,
          ),
        );
        break;
      case 'custom':
        final r = await showDateRangePicker(
          context: context,
          firstDate: DateTime(today.year - 2),
          lastDate: today,
          initialDateRange: _range,
          initialEntryMode: DatePickerEntryMode.calendarOnly,
          helpText: 'Select date range',
          saveText: 'Apply',
          builder: (c, child) => Theme(data: _pickerTheme(c), child: child!),
        );
        if (r != null) _applyRange('custom', r);
        break;
    }
  }

  String get _dateLabel {
    final r = _range;
    if (r == null) return 'Date';
    final f = DateFormat('MMM d');
    if (r.start == r.end) return f.format(r.start);
    return '${f.format(r.start)} - ${f.format(r.end)}';
  }

  // ---------- filter bar ----------

  Widget _filterPill(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? _kBrand : _kSoft,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              label,
              style: _f(
                13.5,
                FontWeight.w600,
                selected ? Colors.white : _kText,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _datePill() {
    final active = _range != null;
    return Material(
      color: active ? _kBrand.withValues(alpha: 0.12) : _kSoft,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: _pickDate,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_month_outlined,
                size: 18,
                color: active ? _kBrand : _kText,
              ),
              const SizedBox(width: 6),
              Text(
                _dateLabel,
                style: _f(13.5, FontWeight.w600, active ? _kBrand : _kText),
              ),
              if (active) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => _applyRange('any', null),
                  child: const Icon(Icons.close, size: 16, color: _kBrand),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterBar() {
    const options = [
      [null, 'All'],
      ['delivered', 'Delivered'],
      ['returned', 'Returned'],
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final f in options)
              _filterPill(f[1]!, _status == f[0], () {
                setState(() => _status = f[0]);
                _load(reset: true);
              }),
            _datePill(),
          ],
        ),
      ),
    );
  }

  // ---------- rows ----------

  Widget _statusPill(bool returned) {
    final bg = returned ? const Color(0xFFEDEFF3) : const Color(0xFFDDF5E5);
    final fg = returned ? const Color(0xFF4A5568) : const Color(0xFF1E8E4E);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        returned ? 'Returned' : 'Delivered',
        style: _f(12, FontWeight.w700, fg),
      ),
    );
  }

  // "Order #36" (bold) + "(10 items)" (muted)
  Widget _titleText(HistoryItem o) {
    final n = o.itemsCount;
    if (n == null) {
      return Text(
        o.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _f(15.5, FontWeight.w700, _kText),
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Order #${o.orderId}',
            style: _f(15.5, FontWeight.w700, _kText),
          ),
          TextSpan(
            text: '  ($n ${n == 1 ? 'item' : 'items'})',
            style: _f(12.5, FontWeight.w400, _kMuted),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  void _open(HistoryItem o) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => DeliveryDetailScreen(item: o)));
  }

  Widget _tile(HistoryItem o) {
    // kung walang hiwalay na customer/address (lokal na API), gamitin ang place
    final addr = o.address.isNotEmpty
        ? o.address
        : (o.customer.isEmpty ? o.place : '');
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _open(o),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _kLine)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8F0FC),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.inventory_2_outlined, color: _kBrand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _titleText(o)),
                        const SizedBox(width: 8),
                        _statusPill(o.returned),
                      ],
                    ),
                    if (o.customer.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          o.customer,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _f(14.5, FontWeight.w500, _kText),
                        ),
                      ),
                    if (addr.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                addr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _f(13, FontWeight.w400, _kMuted),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              color: _kMuted,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    if (o.when.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          o.when,
                          style: _f(13, FontWeight.w400, _kMuted),
                        ),
                      ),
                    if (o.proof.uploaded) const ProofUploadedIndicator(),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text:
                                  'Cash collected ${formatMoney(o.codCollected, currency: o.currency)}',
                              style: _f(13.5, FontWeight.w700, _kText),
                            ),
                            TextSpan(
                              text:
                                  '   Earned ${formatMoney(o.earning, currency: o.currency, missing: 'Not recorded')}',
                              style: _f(12.5, FontWeight.w400, _kMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- body ----------

  Widget _body() {
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && _error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Unable to load: $_error',
              textAlign: TextAlign.center,
              style: _f(14, FontWeight.w400, _kText),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _load(reset: true),
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true, keepData: true),
      child: _items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Text(
                    'No delivery history yet',
                    style: _f(14, FontWeight.w400, _kMuted),
                  ),
                ),
              ],
            )
          : ListView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _items.length + 1,
              itemBuilder: (context, i) {
                if (i < _items.length) return _tile(_items[i]);
                if (_loading) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (_error != null) {
                  return TextButton(
                    onPressed: _load,
                    child: Text('Error: $_error. Try again.'),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      _filters ? '$_total deliveries' : '',
                      style: _f(13, FontWeight.w400, _kMuted),
                    ),
                  ),
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: kAppFontFamily),
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            if (_filters) _filterBar(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }
}
