import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';

/// Pinagsasaluhang UI parts para sa Pickup at Deliver screens.
/// Ilagay sa: lib/widgets/styled_parts.dart

/// AppBar na solid blue na may kurba sa ilalim.
class GradientAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  const GradientAppBar({super.key, required this.title});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 8);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: kToolbarHeight + 8,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: Colors.white,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          color: kBrandBlue,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
      ),
    );
  }
}

/// Malambot na light-blue na background ng page (dark mode: normal na bg).
class SoftPage extends StatelessWidget {
  final Widget child;
  const SoftPage({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) return child;
    return Container(color: kBrandPaleBlue, child: child);
  }
}

BoxDecoration _cardDeco(BuildContext context, {Color? color}) {
  final cs = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: dark ? cs.surface : color ?? cs.surface,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(
      color: dark
          ? cs.onSurface.withValues(alpha: 0.1)
          : kBrandBlue.withValues(alpha: 0.10),
    ),
    boxShadow: [
      BoxShadow(
        color: kBrandBlue.withValues(alpha: 0.08),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

/// Malaking card sa taas: cube/box icon tile, divider, at pangalan ng item.
class TitleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  const TitleCard({super.key, required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDeco(context, color: kBrandPaleBlue),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: kBrandBlue,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Container(
            width: 1,
            height: 30,
            color: cs.onSurface.withValues(alpha: 0.12),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Puting card: light-blue icon tile sa kaliwa, label (bold) at value.
class InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Widget? footer;

  const InfoCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _cardDeco(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: cs.primary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.3,
                    color: cs.onSurface.withValues(alpha: 0.75),
                  ),
                ),
                if (footer != null) ...[const SizedBox(height: 8), footer!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Maliit na chip na may calendar icon (petsa ng pickup).
class DateChip extends StatelessWidget {
  final String text;
  const DateChip({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today_outlined, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// FilledButton na may solid blue at anino. FilledButton pa rin ang widget
/// sa loob, kaya gumagana pa rin ang mga test na naghahanap ng FilledButton.
class GradientFilledButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  final bool expand;
  final double height;

  const GradientFilledButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.busy = false,
    this.expand = false,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final style = FilledButton.styleFrom(
      backgroundColor: Colors.transparent,
      disabledBackgroundColor: Colors.transparent,
      shadowColor: Colors.transparent,
      foregroundColor: Colors.white,
      disabledForegroundColor: Colors.white,
      minimumSize: Size(0, height),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    );

    final Widget btn = (icon != null || busy)
        ? FilledButton.icon(
            onPressed: onPressed,
            style: style,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(icon),
            label: Text(label),
          )
        : FilledButton(onPressed: onPressed, style: style, child: Text(label));

    return Opacity(
      opacity: (!enabled && !busy) ? 0.5 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: kBrandBlue,
          borderRadius: BorderRadius.circular(height / 2),
          boxShadow: [
            BoxShadow(
              color: kBrandBlue.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: expand ? SizedBox(width: double.infinity, child: btn) : btn,
      ),
    );
  }
}
