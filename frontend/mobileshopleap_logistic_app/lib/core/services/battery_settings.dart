import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BatterySettings {
  static const _batteryKey = 'battery_prompt_shown_v1';

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> openOptimizationSettings() async {
    if (!_isAndroid) return;
    const intent = AndroidIntent(
      action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
    );
    await intent.launch();
  }

  /// Ipinapaliwanag kung bakit kailangan ang lokasyon, bago lumabas ang
  /// system permission. Lalabas lang kung hindi pa humihingi ang app.
  static Future<void> explainLocationOnce(BuildContext context) async {
    if (kIsWeb) return;
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.denied) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kailangan ang lokasyon mo'),
        content: const Text(
          'Ginagamit ng ShopLeap ang GPS mo para ipakita sa hub kung nasaan ka '
          'habang may aktibong pickup o delivery, at para kumpirmahin ang pagdating mo. '
          'Hindi ito ibinabahagi kapag tapos na ang trip.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Sige'),
          ),
        ],
      ),
    );
  }

  /// Isang beses lang lalabas. Nagbabalik ng true kung binuksan ang Settings
  /// (kaya dapat huwag munang ituloy ang start dahil nasa background na ang app).
  static Future<bool> promptOnce(BuildContext context) async {
    if (!_isAndroid) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_batteryKey) == true) return false;
    if (!context.mounted) return false;

    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Panatilihing gumagana ang tracking'),
        content: const Text(
          'Ang ilang phone ay pinapatay ang app kapag naka-lock ang screen. '
          'Buksan ang battery settings at piliin ang ShopLeap > '
          '"Don\'t optimize" o "No restrictions" para tuloy-tuloy ang live trip.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Mamaya na'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Buksan ang settings'),
          ),
        ],
      ),
    );
    await prefs.setBool(_batteryKey, true);
    if (open == true) {
      await openOptimizationSettings();
      return true;
    }
    return false;
  }
}