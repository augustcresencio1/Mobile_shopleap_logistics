import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/theme_controller.dart';
import '../../widgets/gradient_header.dart';

/// Update this by hand whenever the version in pubspec.yaml changes.
const String kAppVersion = '1.0.0+1';

class SettingsScreen extends StatefulWidget {
  /// Back arrow sa header (galing sa MainShell).
  final VoidCallback? onBack;
  const SettingsScreen({super.key, this.onBack});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _notifKey = 'notifications_enabled';
  bool _notifications = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(_notifKey) ?? true;
      if (mounted) setState(() => _notifications = v);
    } catch (_) {}
  }

  Future<void> _setNotifications(bool v) async {
    setState(() => _notifications = v);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_notifKey, v);
    } catch (_) {}
  }

  Widget _iconBox(ColorScheme cs, IconData icon) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: cs.primary.withValues(alpha: 0.12),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, size: 21, color: cs.primary),
  );

  Widget _themeRow(
    ColorScheme cs,
    ThemeMode current,
    ThemeMode value,
    String title,
    String? subtitle,
    IconData icon,
    Color iconColor,
  ) {
    final selected = current == value;
    return Material(
      color: selected ? cs.primary.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => ThemeController.set(value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 14, 6),
          child: Row(
            children: [
              Radio<ThemeMode>(value: value),
              const SizedBox(width: 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(icon, color: iconColor, size: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(
    ColorScheme cs,
    IconData icon,
    String title,
    String subtitle,
  ) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    child: Row(
      children: [
        _iconBox(cs, icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12.5,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pageBg = Theme.of(context).scaffoldBackgroundColor;

    return Container(
      color: pageBg,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          GradientPageHeader(
            icon: Icons.settings,
            title: 'Settings',
            subtitle: 'Manage your app preferences',
            onBack: widget.onBack,
          ),
          SectionCard(
            title: 'Appearance',
            icon: Icons.palette_outlined,
            gap: 4,
            children: [
              ValueListenableBuilder<ThemeMode>(
                valueListenable: ThemeController.mode,
                builder: (context, mode, _) {
                  return RadioGroup<ThemeMode>(
                    groupValue: mode,
                    onChanged: (v) {
                      if (v != null) ThemeController.set(v);
                    },
                    child: Column(
                      children: [
                        _themeRow(
                          cs,
                          mode,
                          ThemeMode.system,
                          'System default',
                          'Follow your phone settings',
                          Icons.brightness_auto,
                          cs.onSurface.withValues(alpha: 0.7),
                        ),
                        const SizedBox(height: 4),
                        _themeRow(
                          cs,
                          mode,
                          ThemeMode.light,
                          'Light',
                          null,
                          Icons.light_mode,
                          const Color(0xFFF59E0B),
                        ),
                        const SizedBox(height: 4),
                        _themeRow(
                          cs,
                          mode,
                          ThemeMode.dark,
                          'Dark',
                          null,
                          Icons.dark_mode,
                          cs.primary,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          SectionCard(
            title: 'Notifications',
            icon: Icons.notifications_none,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    _iconBox(cs, Icons.notifications_none),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Notifications',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                          ),
                          Text(
                            'New orders and chat messages',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: cs.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(value: _notifications, onChanged: _setNotifications),
                  ],
                ),
              ),
            ],
          ),
          SectionCard(
            title: 'About',
            icon: Icons.info_outline,
            gap: 2,
            children: [
              _infoRow(
                cs,
                Icons.local_shipping_outlined,
                'Courier App',
                'Shopleap rider app',
              ),
              _infoRow(cs, Icons.info_outline, 'Version', kAppVersion),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}