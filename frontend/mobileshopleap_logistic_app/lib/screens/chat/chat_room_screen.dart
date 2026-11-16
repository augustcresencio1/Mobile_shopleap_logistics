import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/services/chat_service.dart';
import '../../core/services/live_refresh.dart';
import '../../core/services/order_service.dart' show ApiException;
import '../../models/order.dart';

class ChatRoomScreen extends StatefulWidget {
  /// Ibigay ang `orderId` (galing sa listahan) o ang buong `order` (lumang paraan).
  final String? orderId;
  final Order? order;
  final String party; // seller | buyer | logistics
  final String? title;
  final String? subtitle;

  const ChatRoomScreen({
    super.key,
    this.orderId,
    this.order,
    this.party = 'seller',
    this.title,
    this.subtitle,
  }) : assert(orderId != null || order != null, 'Kailangan ng orderId o order');

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen>
    with WidgetsBindingObserver {
  final _c = TextEditingController();
  final _scroll = ScrollController();
  List<ChatMessage> _msgs = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _timer;
  bool _appResumed = true;
  int _loadVersion = 0;

  String get _oid => widget.orderId ?? widget.order!.id;

  String get _title {
    if (widget.title != null && widget.title!.isNotEmpty) return widget.title!;
    final o = widget.order;
    return switch (widget.party) {
      'logistics' => 'Logistics (hub)',
      'buyer' => (o?.buyer.isNotEmpty ?? false) ? o!.buyer : 'Customer',
      _ => (o?.seller.isNotEmpty ?? false) ? o!.seller : 'Seller',
    };
  }

  String get _subtitle =>
      widget.subtitle ?? 'Order #${widget.order?.reference ?? _oid}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LiveRefresh.tick.addListener(_onTick);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_appResumed && ModalRoute.of(context)?.isCurrent == true) {
        _load(silent: true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LiveRefresh.tick.removeListener(_onTick);
    _timer?.cancel();
    _c.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onTick() {
    if (_appResumed && ModalRoute.of(context)?.isCurrent == true) {
      _load(silent: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    if (_appResumed && ModalRoute.of(context)?.isCurrent == true) {
      _load(silent: true);
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!_appResumed) return;
    final version = ++_loadVersion;
    try {
      final m = await ChatService.messages(_oid, party: widget.party);
      if (!mounted || version != _loadVersion) return;
      final grew = m.length != _msgs.length;
      setState(() {
        _msgs = m;
        _loading = false;
        _error = null;
      });
      if (grew) _toBottom();
    } catch (e) {
      if (!mounted || silent || version != _loadVersion) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : e.toString();
      });
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _c.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final sent = await ChatService.send(_oid, text, party: widget.party);
      if (!mounted) return;
      _loadVersion++;
      setState(() {
        if (!_msgs.any((message) => message.id == sent.id)) _msgs.add(sent);
        _loading = false;
        _error = null;
      });
      _c.clear();
      await _load(silent: true);
      _toBottom();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('May error: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ---------- day chip ----------

  String _dayLabel(DateTime d) {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (d.year == now.year) return DateFormat('MMM d').format(d);
    return DateFormat('MMM d, y').format(d);
  }

  Widget _dayChip(DateTime d) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _dayLabel(d),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _bubble(ChatMessage m) {
    final cs = Theme.of(context).colorScheme;
    final fg = m.mine ? cs.onPrimary : cs.onSurface;
    return Align(
      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: m.mine ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(m.body, style: TextStyle(color: fg)),
            ),
            if (m.at != null || m.mine) ...[
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (m.at != null)
                    Text(
                      DateFormat('h:mm a').format(m.at!),
                      style: TextStyle(
                        fontSize: 10,
                        color: fg.withValues(alpha: 0.7),
                      ),
                    ),
                  if (m.mine) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.check,
                      size: 14,
                      color: fg,
                      semanticLabel: 'Sent',
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _items() {
    final out = <Widget>[];
    DateTime? lastDay;
    for (final m in _msgs) {
      final at = m.at;
      if (at != null) {
        final d = DateTime(at.year, at.month, at.day);
        if (lastDay == null || d != lastDay) {
          out.add(_dayChip(d));
          lastDay = d;
        }
      }
      out.add(_bubble(m));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(_subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  )
                : _msgs.isEmpty
                ? const Center(
                    child: Text('No messages yet. Start the conversation.'),
                  )
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    children: _items(),
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _c,
                      onSubmitted: (_) => _send(),
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Type a message',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
