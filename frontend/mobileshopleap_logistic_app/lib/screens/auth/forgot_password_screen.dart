import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/auth_background.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _otp = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();

  int _step = 0; // 0 email, 1 code, 2 new password
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  String? _info;
  String _token = '';

  @override
  void dispose() {
    _email.dispose();
    _otp.dispose();
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted)
        setState(
          () => _error = 'An unexpected error occurred. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendCode() async {
    final e = _email.text.trim();
    if (e.isEmpty || !e.contains('@')) {
      setState(() => _error = 'Enter a valid email.');
      return;
    }
    await _run(() async {
      await AuthService.forgotPassword(e);
      if (!mounted) return;
      setState(() {
        _step = 1;
        _info = 'If the email is registered, a 6-digit code has been sent.';
      });
    });
  }

  Future<void> _verify() async {
    final c = _otp.text.trim();
    if (c.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    await _run(() async {
      final t = await AuthService.verifyResetCode(_email.text, c);
      if (!mounted) return;
      setState(() {
        _token = t;
        _step = 2;
      });
    });
  }

  Future<void> _reset() async {
    if (_pw.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    if (_pw.text != _pw2.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    await _run(() async {
      await AuthService.resetPassword(_email.text, _token, _pw.text, _pw2.text);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Password updated. You can now log in.')),
      );
    });
  }

  static const _brand = kBrandBlue;
  static const _navy = Color(0xFF0F2D6B);
  static const _line = Color(0xFFD3E5FA);

  InputDecoration _deco(String hint, IconData icon, {Widget? suffix}) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: BorderSide(color: c, width: w),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF5B6B7F)),
      prefixIcon: Icon(icon, color: const Color(0xFF5B6B7F)),
      suffixIcon: suffix,
      counterText: '',
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      border: border(_line),
      enabledBorder: border(_line),
      focusedBorder: border(_brand, 1.5),
    );
  }

  Widget _primaryButton(String label, IconData? icon, VoidCallback onTap) {
    return Opacity(
      opacity: _loading ? 0.7 : 1,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: kBrandBlue,
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [
            BoxShadow(
              color: Color(0x331B6FD8),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: _loading ? null : onTap,
            child: Center(
              child: _loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (icon != null) ...[
                          const SizedBox(width: 10),
                          Icon(icon, size: 20, color: Colors.white),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _illustration(IconData icon) {
    return SizedBox(
      height: 150,
      child: Center(
        child: SizedBox(
          width: 170,
          height: 140,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 160,
                height: 125,
                decoration: const BoxDecoration(
                  color: Color(0xFFD6E9FB),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(70),
                    topRight: Radius.circular(60),
                    bottomLeft: Radius.circular(55),
                    bottomRight: Radius.circular(75),
                  ),
                ),
              ),
              _step == 0
                  ? const CustomPaint(
                      size: Size(112, 88),
                      painter: _EnvelopePainter(),
                    )
                  : Icon(icon, size: 76, color: const Color(0xFF1B6FD8)),
              const Positioned(
                top: 0,
                right: 8,
                child: CustomPaint(
                  size: Size(34, 34),
                  painter: _SparkPainter(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final IconData art = _step == 0
        ? Icons.drafts_rounded
        : (_step == 1 ? Icons.pin_outlined : Icons.lock_outline);

    Widget caption(String t) => Text(
      t,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 17,
        height: 1.4,
        color: Color(0xFF4B5868),
      ),
    );

    final fields = <Widget>[];
    if (_step == 0) {
      fields.addAll([
        caption('Enter your email and we will send you a 6-digit code.'),
        const SizedBox(height: 24),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: _deco('Email', Icons.email_outlined),
          onSubmitted: (_) => _loading ? null : _sendCode(),
        ),
        const SizedBox(height: 24),
        _primaryButton('Send code', Icons.send_rounded, _sendCode),
      ]);
    } else if (_step == 1) {
      fields.addAll([
        caption('Enter the code sent to ${_email.text.trim()}.'),
        const SizedBox(height: 24),
        TextField(
          controller: _otp,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: _deco('6-digit code', Icons.pin_outlined),
          onSubmitted: (_) => _loading ? null : _verify(),
        ),
        const SizedBox(height: 16),
        _primaryButton('Verify code', Icons.arrow_forward, _verify),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _loading ? null : _sendCode,
          child: const Text(
            'Resend code',
            style: TextStyle(color: _brand, fontWeight: FontWeight.w600),
          ),
        ),
      ]);
    } else {
      fields.addAll([
        caption('Choose a new password (at least 8 characters).'),
        const SizedBox(height: 24),
        TextField(
          controller: _pw,
          obscureText: _obscure,
          decoration: _deco(
            'New password',
            Icons.lock_outline,
            suffix: IconButton(
              icon: Icon(
                _obscure ? Icons.visibility_off : Icons.visibility,
                color: const Color(0xFF5B6B7F),
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _pw2,
          obscureText: _obscure,
          decoration: _deco('Confirm new password', Icons.lock_outline),
          onSubmitted: (_) => _loading ? null : _reset(),
        ),
        const SizedBox(height: 24),
        _primaryButton('Reset password', Icons.check, _reset),
      ]);
    }

    return Scaffold(
      body: AuthBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _loading
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back, color: _navy),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Forgot password',
                      style: TextStyle(
                        color: _navy,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_info != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE3F0FC),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                _info!,
                                style: const TextStyle(color: _navy),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          _illustration(art),
                          const SizedBox(height: 16),
                          ...fields,
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: scheme.errorContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: scheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnvelopePainter extends CustomPainter {
  const _EnvelopePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const blue = Color(0xFF1B6FD8);
    const fill = Color(0xFFA9CFF7);

    final stroke = Paint()
      ..color = blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // likod ng envelope
    final back = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, h * 0.30, w, h * 0.70),
      const Radius.circular(10),
    );
    canvas.drawRRect(back, Paint()..color = fill);
    canvas.drawRRect(back, stroke);

    // papel
    final paper = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.18, 0, w * 0.64, h * 0.60),
      const Radius.circular(8),
    );
    canvas.drawRRect(paper, Paint()..color = Colors.white);
    canvas.drawRRect(paper, stroke);

    final line = Paint()
      ..color = const Color(0xFF8CC4F5)
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(w * 0.30, h * 0.20),
      Offset(w * 0.70, h * 0.20),
      line,
    );
    canvas.drawLine(
      Offset(w * 0.30, h * 0.38),
      Offset(w * 0.70, h * 0.38),
      line,
    );

    // harapan na may V na flap
    final front = Path()
      ..moveTo(0, h * 0.34)
      ..lineTo(w * 0.5, h * 0.78)
      ..lineTo(w, h * 0.34)
      ..lineTo(w, h * 0.88)
      ..quadraticBezierTo(w, h, w * 0.9, h)
      ..lineTo(w * 0.1, h)
      ..quadraticBezierTo(0, h, 0, h * 0.88)
      ..close();
    canvas.drawPath(front, Paint()..color = fill);
    canvas.drawPath(front, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF1B6FD8)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(4.4, 18.3), const Offset(6.5, 6.5), p);
    canvas.drawLine(const Offset(11, 21.2), const Offset(18.7, 12), p);
    canvas.drawLine(const Offset(15.2, 27.2), const Offset(26.4, 23.2), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
