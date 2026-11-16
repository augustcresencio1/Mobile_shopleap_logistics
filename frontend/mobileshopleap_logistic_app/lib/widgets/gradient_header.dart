import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';

/// Page heading with an optional solid blue background.
class GradientPageHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final bool plain;

  /// Optional na widget sa ilalim ng title (hal. avatar).
  final Widget? child;

  const GradientPageHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onBack,
    this.plain = false,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final foreground = plain ? cs.onSurface : Colors.white;
    final iconColor = plain ? cs.primary : Colors.white;
    final overlay = plain && theme.brightness == Brightness.light
        ? SystemUiOverlayStyle.dark
        : SystemUiOverlayStyle.light;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay.copyWith(statusBarColor: Colors.transparent),
      child: Container(
        width: double.infinity,
        color: plain ? theme.scaffoldBackgroundColor : kBrandBlue,
        padding: EdgeInsets.fromLTRB(8, top + 4, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (onBack != null)
              IconButton(
                tooltip: 'Back',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                color: iconColor,
              )
            else
              const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: plain
                          ? cs.primary.withValues(alpha: 0.10)
                          : Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: iconColor, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: foreground.withValues(
                              alpha: plain ? 0.65 : 0.85,
                            ),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (child != null) ...[
              const SizedBox(height: 18),
              Center(child: child!),
            ],
          ],
        ),
      ),
    );
  }
}

/// Rounded card na may icon at title. Pwedeng collapsible.
class SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final double gap;
  final bool collapsible;
  final bool expanded;
  final VoidCallback? onToggle;

  const SectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.gap = 10,
    this.collapsible = false,
    this.expanded = true,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) spaced.add(SizedBox(height: gap));
      spaced.add(children[i]);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: collapsible ? onToggle : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 19, color: cs.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                        ),
                      ),
                    ),
                    if (collapsible)
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                    child: Column(children: spaced),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
