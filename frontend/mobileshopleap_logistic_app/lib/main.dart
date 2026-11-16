import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/services/theme_controller.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_typography.dart';
import 'screens/splash/splash_screen.dart';

// Shared solid brand color and supporting neutral colors.
const _brand = kBrandBlue;
const _brandPale = Color(0xFFE3EEFA);
const _pageBg = Color(0xFFF8FAFC);
const _charcoal = Color(0xFF1F2933);
const _border = Color(0xFFE2E8F0);
const _chipBg = Color(0xFFE9EEF5);

// Dark mode colors
const _darkBrand = Color(0xFF7DB2F5);
const _darkBrandContainer = Color(0xFF1E3A5F);
const _darkPageBg = Color(0xFF0F172A);
const _darkSurface = Color(0xFF1E293B);
const _darkText = Color(0xFFE5E7EB);
const _darkBorder = Color(0xFF334155);
const _darkChipBg = Color(0xFF334155);

// Palitan ng totoong values mula sa Supabase Dashboard > Project Settings > API.
// Anon/publishable key lang ang ilagay dito, HINDI ang service_role key.
const _supabaseUrl = 'https://gelkmdviiqyldritback.supabase.co';
const _supabaseAnonKey = 'sb_publishable_J1hf0xbTdXFK_b46OigO4g_Y6kCKGv2';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.load();

  await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);

  runApp(const MyApp());
}

ThemeData _buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;

  final surface = dark ? _darkSurface : Colors.white;
  final pageBg = dark ? _darkPageBg : _pageBg;
  final text = dark ? _darkText : _charcoal;
  final border = dark ? _darkBorder : _border;
  final primary = dark ? _darkBrand : _brand;

  final scheme = ColorScheme.fromSeed(seedColor: _brand, brightness: brightness)
      .copyWith(
        primary: primary,
        onPrimary: dark ? const Color(0xFF0B1B33) : Colors.white,
        primaryContainer: dark ? _darkBrandContainer : _brandPale,
        onPrimaryContainer: dark ? const Color(0xFFD6E6FA) : _brand,
        onSurface: text,
        surface: surface,
      );

  return ThemeData(
    useMaterial3: true,
    fontFamily: kAppFontFamily,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: pageBg,
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: dark ? _darkBrandContainer : _brandPale,
    ),
    drawerTheme: DrawerThemeData(backgroundColor: surface),
    dividerTheme: DividerThemeData(color: border),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: dark ? _darkChipBg : _chipBg,
      selectedColor: primary,
      showCheckmark: false,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: TextStyle(
        color: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? (dark ? const Color(0xFF0B1B33) : Colors.white)
              : text,
        ),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Courier App',
          debugShowCheckedModeBanner: false,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          themeMode: mode,
          // Intro animation muna, saka lilipat sa AuthGate (login, pending, o dashboard).
home: const SplashScreen(),
        );
      },
    );
  }
}
