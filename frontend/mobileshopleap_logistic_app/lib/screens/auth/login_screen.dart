import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import 'auth_gate.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await AuthService.login(_emailCtrl.text, _passwordCtrl.text);
      if (!mounted) return;

      // Pupunta sa AuthGate: rider dashboard (o pending screen).
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'An unexpected error occurred. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      border: border(_line),
      enabledBorder: border(_line),
      focusedBorder: border(_brand, 1.5),
      errorBorder: border(Colors.red.shade300),
      focusedErrorBorder: border(Colors.red.shade400, 1.5),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        color: kBrandPaleBlue,
        child: Stack(
          children: [
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Image.asset(
                            'assets/images/logo.png',
                            height: 120,
                            cacheWidth: 500,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.local_shipping,
                              size: 72,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Shopleap',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w800,
                              color: _navy,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: kBrandBlue,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Courier App',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 4,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Courier, sign in here',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: Color(0xFF4B5868),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Center(
                            child: SizedBox(
                              width: 90,
                              height: 4,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Row(
                                  children: const [
                                    Expanded(
                                      flex: 3,
                                      child: ColoredBox(color: kBrandBlue),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: ColoredBox(color: kBrandBlue),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            decoration: _deco('Email', Icons.email_outlined),
                            validator: (v) {
                              final value = (v ?? '').trim();
                              if (value.isEmpty) return 'Enter your email.';
                              if (!value.contains('@'))
                                return 'Enter a valid email.';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onFieldSubmitted: (_) =>
                                _loading ? null : _submit(),
                            decoration: _deco(
                              'Password',
                              Icons.lock_outline,
                              suffix: IconButton(
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: const Color(0xFF5B6B7F),
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Enter your password.'
                                : null,
                          ),
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
                          const SizedBox(height: 24),
                          Opacity(
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
                                  onTap: _loading ? null : _submit,
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
                                        : const Text(
                                            'Login',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: _loading
                                      ? null
                                      : () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const RegisterScreen(),
                                          ),
                                        ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.person_add_alt_1_outlined,
                                          size: 20,
                                          color: _navy,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text.rich(
                                            TextSpan(
                                              text: 'New courier? ',
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                color: _navy,
                                              ),
                                              children: const [
                                                TextSpan(
                                                  text: 'Register here',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    color: _brand,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 28,
                                color: const Color(0xFFB8CCE4),
                              ),
                              Expanded(
                                child: InkWell(
                                  onTap: _loading
                                      ? null
                                      : () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const ForgotPasswordScreen(),
                                          ),
                                        ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: const [
                                        Icon(
                                          Icons.lock_outline,
                                          size: 20,
                                          color: _brand,
                                        ),
                                        SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            'Forgot password?',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              color: _brand,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
