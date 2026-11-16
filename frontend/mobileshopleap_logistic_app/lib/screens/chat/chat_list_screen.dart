import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'package:intl/intl.dart';
import '../../core/services/chat_service.dart';
import '../../core/services/live_refresh.dart';
import '../../core/services/order_service.dart' show ApiException;
import 'chat_room_screen.dart';

/// Laman ng listahan: mga thread at kabuuang unread.
class _ChatData {
  final List<ChatThread> threads;
  const _ChatData(this.threads);
}

class ChatListScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onBell;
  final int bellCount;
  const ChatListScreen({
    super.key,
    this.onBack,
    this.onBell,
    this.bellCount = 0,
  });
  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  static const _filters = [
    ('all', 'All'),
    ('seller', 'Sellers'),
    ('buyer', 'Customers'),
    ('logistics', 'Logistics (hub)'),
  ];

  _ChatData? _data;
  bool _loading = true;
  String? _error;
  bool _inflight = false;
  bool _reloadPending = false;

  String _filter = 'all';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    ChatService.threadUpdates.addListener(_onThreadsChanged);
    LiveRefresh.tick.addListener(_onTick);
    _data = _ChatData(ChatService.threadUpdates.value);
    _load();
  }

  @override
  void dispose() {
    ChatService.threadUpdates.removeListener(_onThreadsChanged);
    LiveRefresh.tick.removeListener(_onTick);
    _search.dispose();
    super.dispose();
  }

  void _onTick() {
    if (LiveRefresh.activePage != 5) return;
    if (_inflight) {
      _reloadPending = true;
    } else {
      _load(silent: true, forceRefresh: true);
    }
  }

  void _onThreadsChanged() {
    if (!mounted) return;
    setState(() {
      _data = _ChatData(ChatService.threadUpdates.value);
      _loading = false;
      _error = null;
    });
  }

  Future<void> _load({bool silent = false, bool forceRefresh = false}) async {
    if (_inflight) return;
    _inflight = true;
    _reloadPending = false;
    try {
      final t = await ChatService.threads(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _data = _ChatData(t);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : e.toString();
      });
    } finally {
      _inflight = false;
      if (mounted && _reloadPending) {
        _load(silent: true, forceRefresh: true);
      }
    }
  }

  Future<void> _refresh() async {
    await _load(forceRefresh: true);
  }

  void _open(ChatThread t) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          orderId: t.orderId,
          party: t.party,
          title: t.name,
          subtitle: t.subtitle,
        ),
      ),
    ).then((_) {
      if (mounted) _load(silent: true, forceRefresh: true);
    });
  }

  String _timeLabel(DateTime? at) {
    if (at == null) return '';
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return DateFormat('h:mm a').format(at);
    if (diff == 1) return 'Yesterday';
    if (at.year == now.year) return DateFormat('MMM d').format(at);
    return DateFormat('MMM d, y').format(at);
  }

  IconData _icon(String party) => switch (party) {
    'seller' => Icons.storefront_outlined,
    'buyer' => Icons.person_outline,
    _ => Icons.warehouse_outlined,
  };

  List<ChatThread> _visible() {
    final all = _data?.threads ?? const <ChatThread>[];
    final q = _search.text.trim().toLowerCase();
    return all.where((t) {
      if (_filter != 'all' && t.party != _filter) return false;
      if (q.isEmpty) return true;
      return t.name.toLowerCase().contains(q) ||
          t.subtitle.toLowerCase().contains(q) ||
          (t.lastMessage ?? '').toLowerCase().contains(q);
    }).toList();
  }

  // ---------- filter bar ----------

  BoxShadow _softShadow([double a = 0.07]) => BoxShadow(
    color: Colors.black.withValues(alpha: a),
    blurRadius: 12,
    offset: const Offset(0, 4),
  );

  Color _tint(String party, ColorScheme cs) => switch (party) {
    'seller' => cs.primary,
    'buyer' => cs.primary,
    _ => cs.primary,
  };

  IconData _filterIcon(String key) => switch (key) {
    'seller' => Icons.storefront_outlined,
    'buyer' => Icons.people_outline,
    'logistics' => Icons.warehouse_outlined,
    _ => Icons.chat_bubble_outline,
  };

  Widget _pill(String key, String label) {
    final cs = Theme.of(context).colorScheme;
    final selected = _filter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => setState(() => _filter = key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? cs.primary : cs.surface,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [_softShadow(selected ? 0.18 : 0.08)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _filterIcon(key),
                size: 16,
                color: selected ? cs.onPrimary : cs.primary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? cs.onPrimary : cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterBar() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [_softShadow(0.1)],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, color: cs.onSurface),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(fontSize: 15),
                          decoration: const InputDecoration(
                            hintText: 'Search conversations...',
                            isCollapsed: true,
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_search.text.isNotEmpty)
                        GestureDetector(
                          onTap: () => setState(() => _search.clear()),
                          child: const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(Icons.close),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => setState(() {
                  _filter = 'all';
                  _search.clear();
                }),
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: cs.surface,
                    shape: BoxShape.circle,
                    boxShadow: [_softShadow(0.1)],
                  ),
                  child: Icon(Icons.tune, color: cs.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [for (final f in _filters) _pill(f.$1, f.$2)]),
          ),
        ],
      ),
    );
  }

  // ---------- row ----------

  Widget _tile(ChatThread t) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasUnread = t.unread > 0;
    final tint = _tint(t.party, cs);
    final subtitle = t.subtitle
        .replaceAll('\u00B7', '\u2022')
        .replaceAll('#', 'No. ');
    final previewStyle = tt.bodyMedium?.copyWith(
      fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w400,
      color: hasUnread ? cs.onSurface : cs.onSurface.withValues(alpha: 0.65),
    );
    final Widget preview = t.lastMessage == null
        ? Text(
            'No messages yet',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: previewStyle,
          )
        : Text.rich(
            TextSpan(
              style: previewStyle,
              children: [
                if (t.lastIsMine)
                  TextSpan(
                    text: 'You: ',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                TextSpan(text: t.lastMessage!),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [_softShadow()],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Material(
              color: cs.surface,
              child: InkWell(
                onTap: () => _open(t),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: tint.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(_icon(t.party), color: tint, size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.titleSmall?.copyWith(
                                fontWeight: hasUnread
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 3),
                            preview,
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _timeLabel(t.lastAt),
                            style: tt.bodySmall?.copyWith(
                              color: hasUnread
                                  ? cs.primary
                                  : cs.onSurface.withValues(alpha: 0.55),
                              fontWeight: hasUnread
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (hasUnread)
                            Container(
                              constraints: const BoxConstraints(
                                minWidth: 22,
                                minHeight: 22,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: cs.primary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                t.unread > 99 ? '99+' : '${t.unread}',
                                style: TextStyle(
                                  color: cs.onPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            )
                          else if (t.lastIsMine && t.lastMessage != null)
                            Tooltip(
                              message: 'Sent',
                              child: Icon(
                                Icons.check_circle_outline,
                                size: 22,
                                color: cs.primary,
                                semanticLabel: 'Sent',
                              ),
                            )
                          else
                            const SizedBox(height: 22),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (hasUnread)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: ColoredBox(color: cs.primary),
              ),
          ],
        ),
      ),
    );
  }
  // ---------- body ----------

  Widget _list() {
    if (_error != null && _data == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Center(
            child: FilledButton(
              onPressed: () {
                setState(() => _loading = true);
                _load();
              },
              child: const Text('Try again'),
            ),
          ),
        ],
      );
    }

    final threads = _visible();
    if (threads.isEmpty) {
      final searching = _search.text.trim().isNotEmpty || _filter != 'all';
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                searching
                    ? 'No chats found.'
                    : 'No chats yet. Your orders will appear here.',
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: threads.length,
      itemBuilder: (context, i) => _tile(threads[i]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    return Column(
      children: [
        Container(
          color: kBrandBlue,
          padding: EdgeInsets.fromLTRB(8, top + 4, 8, 0),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: widget.onBack,
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      'Chat',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: widget.onBell,
                    icon: Badge(
                      isLabelVisible: widget.bellCount > 0,
                      label: Text(
                        widget.bellCount > 99 ? '99+' : '${widget.bellCount}',
                      ),
                      smallSize: 9,
                      child: Icon(
                        Icons.notifications_none,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _filterBar(),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(onRefresh: _refresh, child: _list()),
        ),
      ],
    );
  }
}
