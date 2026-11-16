import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hawak ang napiling theme (System / Light / Dark) at sine-save ito sa phone.
class ThemeController {
  ThemeController._();

  static const _key = 'theme_mode';

  /// Pakikinggan ng MaterialApp sa main.dart.
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);

  /// Tatawagin sa main() bago mag-runApp.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      switch (prefs.getString(_key)) {
        case 'light':
          mode.value = ThemeMode.light;
          break;
        case 'dark':
          mode.value = ThemeMode.dark;
          break;
        default:
          mode.value = ThemeMode.system;
      }
    } catch (_) {
      mode.value = ThemeMode.system;
    }
  }

  /// Tatawagin ng Settings screen kapag may pinili si rider.
  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = m == ThemeMode.light
          ? 'light'
          : m == ThemeMode.dark
              ? 'dark'
              : 'system';
      await prefs.setString(_key, v);
    } catch (_) {}
  }
}