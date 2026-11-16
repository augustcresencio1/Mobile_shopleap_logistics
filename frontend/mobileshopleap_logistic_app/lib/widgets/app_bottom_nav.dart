import 'package:flutter/material.dart';

/// Floating bottom bar: Home, Tasks, [Scan], Chat, Account.
/// Indexes: 0 Home, 1 Tasks (pickup + delivery), 2 Scan, 3 Chat, 4 Account.
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Bilang ng hindi pa nababasang chat (0 = walang badge).
  final int chatBadge;

  /// Pinagsamang bilang ng pickup + delivery (0 = walang badge).
  final int taskBadge;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.chatBadge = 0,
    this.taskBadge = 0,
  });

  static const double _barH = 68;
  static const double _circle = 60;
  static const double _lift = 26; // taas ng bilog sa ibabaw ng bar

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: SizedBox(
          height: _barH + _lift,
          child: Stack(
            children: [
              // ang puting bar
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _barH,
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 22,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      _item(
                        context,
                        0,
                        'Home',
                        Icons.home_outlined,
                        Icons.home_rounded,
                      ),
                      _item(
                        context,
                        1,
                        'Tasks',
                        Icons.local_shipping_outlined,
                        Icons.local_shipping,
                        badge: taskBadge,
                      ),
                      const Expanded(child: SizedBox.shrink()),
                      _item(
                        context,
                        3,
                        'Chat',
                        Icons.chat_bubble_outline,
                        Icons.chat_bubble,
                        badge: chatBadge,
                      ),
                      _item(
                        context,
                        4,
                        'Account',
                        Icons.person_outline,
                        Icons.person,
                      ),
                    ],
                  ),
                ),
              ),
              // ang Scan sa gitna
              Positioned.fill(
                child: Row(
                  children: [
                    const Expanded(child: SizedBox.shrink()),
                    const Expanded(child: SizedBox.shrink()),
                    Expanded(child: _scan(context)),
                    const Expanded(child: SizedBox.shrink()),
                    const Expanded(child: SizedBox.shrink()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scan(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = currentIndex == 2;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: _circle,
            height: _circle,
            decoration: BoxDecoration(
              color: cs.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(Icons.qr_code_scanner, color: cs.onPrimary, size: 30),
          ),
          const SizedBox(height: 4),
          Text(
            'Scan',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(
    BuildContext context,
    int index,
    String label,
    IconData icon,
    IconData activeIcon, {
    int badge = 0,
  }) {
    final cs = Theme.of(context).colorScheme;
    final selected = currentIndex == index;
    final color = selected ? cs.primary : cs.onSurface.withValues(alpha: 0.78);

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(index),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? cs.primary.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(selected ? activeIcon : icon, color: color, size: 26),
                    if (badge > 0)
                      Positioned(
                        right: -8,
                        top: -4,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 16),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: cs.error,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            badge > 99 ? '99+' : '$badge',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: cs.onError,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
