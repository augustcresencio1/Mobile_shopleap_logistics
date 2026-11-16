import 'package:flutter/material.dart';
import '../core/theme/app_typography.dart';

const Color _kBrand = Color(0xFF1B5BB8);
const Color _kMuted = Color(0xFF6B7A90);
const Color _kText = Color(0xFF1B2A41);
const Color _kSoft = Color(0xFFE6EFFC);
const Color _kLine = Color(0xFFE1E8F2);

TextStyle _f(double size, FontWeight weight, Color color, {double? height}) =>
    TextStyle(
      fontFamily: kAppFontFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );

/// Section heading, hal. "Notifications from sellers", "Items for pickup", "To deliver".
class ScreenSectionTitle extends StatelessWidget {
  const ScreenSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(text, style: _f(17, FontWeight.w700, _kText)),
    );
  }
}

/// Maliit na card na may bell icon, hal. "No new pickup requests."
class InfoNoticeCard extends StatelessWidget {
  const InfoNoticeCard({
    super.key,
    required this.message,
    this.icon = Icons.notifications_none_rounded,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kLine),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _kSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _kBrand),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(message, style: _f(15, FontWeight.w500, _kText)),
          ),
        ],
      ),
    );
  }
}

enum EmptyStateArt { pickup, delivery }

/// Walang laman na listahan: larawan, title, paliwanag, at "Check again".
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.art,
    required this.title,
    required this.message,
    this.onRefresh,
    this.refreshLabel = 'Check again',
  });

  final EmptyStateArt art;
  final String title;
  final String message;
  final VoidCallback? onRefresh;
  final String refreshLabel;

  Widget _stroke(double angle, double length) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: length,
        height: 3,
        decoration: BoxDecoration(
          color: _kBrand,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _illustration() {
    final isPickup = art == EmptyStateArt.pickup;
    return SizedBox(
      width: 150,
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 124,
            height: 124,
            decoration: const BoxDecoration(
              color: _kSoft,
              shape: BoxShape.circle,
            ),
          ),
          Icon(
            isPickup
                ? Icons.inventory_2_outlined
                : Icons.local_shipping_outlined,
            size: isPickup ? 62 : 68,
            color: _kBrand,
          ),
          if (isPickup) ...[
            Positioned(top: 14, right: 30, child: _stroke(-0.9, 12)),
            Positioned(top: 6, right: 48, child: _stroke(-1.4, 12)),
            Positioned(top: 26, right: 14, child: _stroke(-0.2, 12)),
          ] else ...[
            Positioned(left: 6, top: 60, child: _stroke(0, 24)),
            Positioned(left: 14, top: 72, child: _stroke(0, 16)),
            Positioned(left: 2, top: 84, child: _stroke(0, 26)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _illustration(),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: _f(21, FontWeight.w700, _kText),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: _f(14.5, FontWeight.w400, _kMuted, height: 1.4),
            ),
            if (onRefresh != null) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 22),
                label: Text(
                  refreshLabel,
                  style: _f(15, FontWeight.w600, _kBrand),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kBrand,
                  shape: const StadiumBorder(),
                  side: const BorderSide(color: Color(0xFFB9C7DC)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
