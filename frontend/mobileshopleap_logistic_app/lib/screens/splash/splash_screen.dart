import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/auth_gate.dart';

/// Intro bago pumasok sa app: papasok ang rider, iikot ang gulong, gagalaw ang
/// mga building, at aalis ang rider papunta sa susunod na screen (AuthGate).
///
/// Mga asset na kailangan (ilagay sa assets/images/):
///   logo.png, rider.png, wheel.png
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  // Kabuuang haba ng animation. Palitan para pabilisin o pabagalin.
  static const double _seconds = 3.6;

  // Posisyon ng mga gulong sa loob ng rider.png (fraction ng lapad/taas).
  static const _rearX = 0.2711, _frontX = 0.8688, _wheelY = 0.8480;
  static const _wheelFrac = 0.1866; // diameter ng wheel.png / lapad ng rider.png
  static const _riderAspect = 296 / 343; // taas / lapad ng rider.png

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_seconds * 1000).round()),
  );

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(_go);
  }

  Future<void> _go() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => const AuthGate(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 0..1 na progreso sa pagitan ng [a, b] ng kabuuang oras.
  double _p(double a, double b, [Curve curve = Curves.linear]) =>
      curve.transform(((_c.value - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    final bg = dark ? const Color(0xFF0F172A) : const Color(0xFFE6F1FC);
    final titleColor = dark ? Colors.white : const Color(0xFF0F2A6B);
    final blue = dark ? const Color(0xFF7DB2F5) : const Color(0xFF1456AE);
    final skyNear = dark ? const Color(0xFF1E293B) : const Color(0xFFD3E5F8);
    final skyFar = dark ? const Color(0xFF172033) : const Color(0xFFE0EDFA);
    final ground = dark ? const Color(0xFF1E3A5F) : const Color(0xFFAFC9EC);
    final pinColor = dark ? const Color(0xFF7DB2F5) : const Color(0xFF8FB8EC);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: bg,
        body: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            final h = box.maxHeight;

            final riderW = w * 0.42;
            final riderH = riderW * _riderAspect;
            final sceneH = riderH + 40;

            return AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _c.value * _seconds; // segundo

                // --- paglabas ng logo / title / pill ---
                final logoIn = _p(0.00, 0.18, Curves.easeOutBack);
                final titleIn = _p(0.10, 0.28, Curves.easeOut);
                final pillIn = _p(0.18, 0.36, Curves.easeOut);
                final loadIn = _p(0.25, 0.42, Curves.easeOut);

                // --- galaw ng rider ---
                final startX = -(riderW * 1.3 + (w - riderW) / 2);
                final entry = _p(0.05, 0.38, Curves.easeOutCubic);
                final exit = _p(0.84, 1.0, Curves.easeInCubic);
                final dx = startX * (1 - entry) + exit * (w * 1.1);
                final bob = math.sin(t * 9) * 1.8;
                final tilt = -0.06 * exit + 0.012 * math.sin(t * 9);
                final wheelAngle = t * 14; // radians

                return Stack(
                  children: [
                    // ---------- logo ----------
                    Positioned(
                      top: h * 0.15,
                      left: 0,
                      right: 0,
                      child: Opacity(
                        opacity: logoIn.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: 0.6 + 0.4 * logoIn,
                          child: Center(
                            child: Image.asset(
                              'assets/images/logo.png',
                              width: w * 0.26,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.local_shipping_rounded,
                                size: w * 0.2,
                                color: blue,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // ---------- title ----------
                    Positioned(
                      top: h * 0.305,
                      left: 0,
                      right: 0,
                      child: Opacity(
                        opacity: titleIn,
                        child: Transform.translate(
                          offset: Offset(0, 18 * (1 - titleIn)),
                          child: Center(
                            child: Text(
                              'Shopleap',
                              style: TextStyle(
                                color: titleColor,
                                fontSize: w * 0.12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // ---------- pill ----------
                    Positioned(
                      top: h * 0.305 + w * 0.12 * 1.1 + 10,
                      left: 0,
                      right: 0,
                      child: Opacity(
                        opacity: pillIn,
                        child: Transform.translate(
                          offset: Offset(0, 14 * (1 - pillIn)),
                          child: Center(
                            child: Container(
                              width: w * 0.45,
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              decoration: BoxDecoration(
                                color: blue,
                                borderRadius: BorderRadius.circular(40),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'Courier App',
                                style: TextStyle(
                                  color: dark
                                      ? const Color(0xFF0B1B33)
                                      : Colors.white,
                                  fontSize: w * 0.042,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 3,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // ---------- eksena ng rider ----------
                    Positioned(
                      left: 0,
                      right: 0,
                      top: h * 0.50,
                      height: sceneH,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // mga building (gumagalaw pakaliwa)
                          Positioned.fill(
                            bottom: 22,
                            child: CustomPaint(
                              painter: _SkylinePainter(
                                offset: t * w * 0.22,
                                near: skyNear,
                                far: skyFar,
                              ),
                            ),
                          ),
                          // location pin
                          Positioned(
                            right: w * 0.13,
                            top: sceneH * 0.10 + math.sin(t * 3) * 4,
                            child: Icon(
                              Icons.location_on,
                              size: w * 0.09,
                              color: pinColor,
                            ),
                          ),
                          // anino sa lupa
                          Positioned(
                            left: w * 0.2,
                            right: w * 0.2,
                            bottom: 10,
                            child: Container(
                              height: 10,
                              decoration: BoxDecoration(
                                color: ground,
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                          // rider
                          Positioned(
                            left: (w - riderW) / 2,
                            bottom: 14,
                            width: riderW,
                            height: riderH,
                            child: Transform.translate(
                              offset: Offset(dx, bob),
                              child: Transform.rotate(
                                angle: tilt,
                                alignment: Alignment.bottomCenter,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    // guhit ng bilis
                                    Positioned(
                                      left: -riderW * 0.36,
                                      top: riderH * 0.40,
                                      width: riderW * 0.34,
                                      height: riderH * 0.24,
                                      child: CustomPaint(
                                        painter: _SpeedLinesPainter(
                                          t: t,
                                          color: dark
                                              ? const Color(0xFF7DB2F5)
                                              : const Color(0xFF3E8DE3),
                                        ),
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: Image.asset(
                                        'assets/images/rider.png',
                                        fit: BoxFit.fill,
                                      ),
                                    ),
                                    _wheel(riderW, riderH, _rearX, wheelAngle),
                                    _wheel(riderW, riderH, _frontX, wheelAngle),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ---------- loading ----------
                    Positioned(
                      top: h * 0.50 + sceneH + h * 0.045,
                      left: 0,
                      right: 0,
                      child: Opacity(
                        opacity: loadIn,
                        child: Column(
                          children: [
                            SizedBox(
                              width: 38,
                              height: 38,
                              child: CircularProgressIndicator(
                                strokeWidth: 4.5,
                                color: blue,
                                backgroundColor: blue.withValues(alpha: 0.2),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Loading...',
                              style: TextStyle(
                                color: blue,
                                fontSize: w * 0.045,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Umiikot na gulong na nakapatong sa eksaktong lugar ng gulong sa rider.png.
  Widget _wheel(double riderW, double riderH, double fx, double angle) {
    final d = riderW * _wheelFrac;
    return Positioned(
      left: fx * riderW - d / 2,
      top: _wheelY * riderH - d / 2,
      width: d,
      height: d,
      child: Transform.rotate(
        angle: angle,
        child: Image.asset('assets/images/wheel.png', fit: BoxFit.fill),
      ),
    );
  }
}

/// Mga building na gumagalaw pakaliwa, dalawang layer (malayo at malapit).
class _SkylinePainter extends CustomPainter {
  _SkylinePainter({
    required this.offset,
    required this.near,
    required this.far,
  });

  final double offset;
  final Color near, far;

  // [x, lapad, taas] bilang fraction ng tile / taas ng eksena
  static const _nearB = <List<double>>[
    [0.02, 0.10, 0.50],
    [0.16, 0.08, 0.80],
    [0.28, 0.12, 0.58],
    [0.45, 0.09, 0.95],
    [0.58, 0.13, 0.52],
    [0.76, 0.10, 0.72],
    [0.90, 0.08, 0.42],
  ];
  static const _farB = <List<double>>[
    [0.08, 0.12, 0.36],
    [0.24, 0.10, 0.56],
    [0.40, 0.14, 0.42],
    [0.62, 0.10, 0.62],
    [0.80, 0.12, 0.40],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final tile = size.width * 1.25;

    void layer(List<List<double>> b, double speed, Color color) {
      final paint = Paint()..color = color;
      final shift = (offset * speed) % tile;
      for (var k = -1; k <= 2; k++) {
        for (final e in b) {
          final left = k * tile + e[0] * tile - shift;
          final width = e[1] * tile;
          if (left > size.width || left + width < 0) continue;
          final height = e[2] * size.height;
          canvas.drawRRect(
            RRect.fromLTRBAndCorners(
              left,
              size.height - height,
              left + width,
              size.height,
              topLeft: const Radius.circular(5),
              topRight: const Radius.circular(5),
            ),
            paint,
          );
        }
      }
    }

    layer(_farB, 0.5, far);
    layer(_nearB, 1.0, near);
  }

  @override
  bool shouldRepaint(covariant _SkylinePainter old) =>
      old.offset != offset || old.near != near || old.far != far;
}

/// Tatlong guhit ng bilis sa likod ng rider na tumatakbo pakaliwa at nawawala.
class _SpeedLinesPainter extends CustomPainter {
  _SpeedLinesPainter({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const ys = [0.12, 0.50, 0.88];
    const lens = [0.60, 0.95, 0.45];
    for (var i = 0; i < 3; i++) {
      final f = (t * 1.6 + i * 0.33) % 1.0; // 0..1
      final shift = f * size.width * 0.45;
      final right = size.width - shift;
      final len = size.width * lens[i];
      final paint = Paint()
        ..color = color.withValues(alpha: (1 - f) * 0.9)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(right - len, size.height * ys[i]),
        Offset(right, size.height * ys[i]),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedLinesPainter old) =>
      old.t != t || old.color != color;
}