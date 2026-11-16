import 'package:flutter/material.dart';

class AppDrawer extends StatelessWidget {
  final int selected;
  final String name;
  final String photoUrl;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  const AppDrawer({
    super.key,
    required this.selected,
    required this.name,
    required this.photoUrl,
    required this.onSelect,
    required this.onLogout,
  });

  /// Ang -1 ay hindi tab. Direktang bubuksan ang screen nito.
  static const _items = [
    (0, 'Dashboard', Icons.grid_view_rounded),
    (3, 'Profit / Earnings', Icons.account_balance_wallet),
    (9, 'Cash', Icons.payments_outlined),
    (4, 'Delivery History', Icons.history),
    (7, 'Settings', Icons.settings),
    (8, 'Help / Support', Icons.help_outline),
  ];

  BoxShadow _shadow() => BoxShadow(
    color: Colors.black.withValues(alpha: 0.08),
    blurRadius: 12,
    offset: const Offset(0, 4),
  );

  Widget _avatar(ColorScheme cs) {
    final n = name.trim();
    final initial = n.isEmpty ? 'C' : n[0].toUpperCase();
    final fallback = Container(
      width: 66,
      height: 66,
      color: cs.primaryContainer,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: cs.primary,
          fontWeight: FontWeight.w800,
          fontSize: 26,
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.surface,
        shape: BoxShape.circle,
        boxShadow: [_shadow()],
      ),
      child: ClipOval(
        child: photoUrl.isEmpty
            ? fallback
            : Image.network(
                photoUrl,
                width: 66,
                height: 66,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => fallback,
              ),
      ),
    );
  }

  Widget _header(BuildContext context, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 36), child: _avatar(cs)),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.trim().isEmpty ? 'Courier' : name.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.local_shipping, size: 18, color: cs.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Courier',
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.65),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 9, color: Color(0xFF16A34A)),
                        SizedBox(width: 6),
                        Text(
                          'Online',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF166534),
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down,
                          size: 18,
                          color: Color(0xFF166534),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.close, color: cs.primary, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    ColorScheme cs,
    int idx,
    String label,
    IconData icon,
  ) {
    final sel = selected == idx;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: sel ? cs.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: sel ? cs.primaryContainer : cs.surface,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [_shadow()],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(22),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    // Kunin muna ang navigator bago mag-pop, dahil baka hindi
                    // na valid ang context ng drawer pagkatapos nitong magsara.
                    final nav = Navigator.of(context);
                    nav.pop();
                    onSelect(idx);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(icon, color: cs.primary, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: sel ? cs.primary : cs.onSurface,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: sel ? cs.primary : cs.onSurface,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _logout(BuildContext context) {
    const red = Color(0xFFDC2626);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFDE8E8),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              Navigator.pop(context);
              onLogout();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.logout, color: red, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Logout',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: red,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: red),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pageBg = Theme.of(context).scaffoldBackgroundColor;
    return Drawer(
      backgroundColor: pageBg,
      child: Container(
        color: pageBg,
        child: SafeArea(
          child: Column(
            children: [
              _header(context, cs),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(8, 12, 12, 24),
                  children: [
                    for (final it in _items)
                      _tile(context, cs, it.$1, it.$2, it.$3),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 14),
                      child: Divider(
                        height: 1,
                        color: cs.onSurface.withValues(alpha: 0.12),
                      ),
                    ),
                    _logout(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
