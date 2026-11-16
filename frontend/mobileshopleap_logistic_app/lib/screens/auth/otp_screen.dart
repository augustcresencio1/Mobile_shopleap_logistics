import 'package:flutter/material.dart';
import '../../core/services/auth_service.dart';

class OtpScreen extends StatefulWidget {
  final String email;
  const OtpScreen({super.key, required this.email});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otp = TextEditingController();
  bool _loading = false;

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _verify() async {
    if (_otp.text.trim().length < 6) return _snack('Enter the 6-digit code sent to your email');
    setState(() => _loading = true);
    final err = await AuthService.verifyOtp(widget.email, _otp.text.trim());
    if (!mounted) return;
    setState(() => _loading = false);
    if (err != null) return _snack(err);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Registration submitted'),
        content: const Text("Please wait for approval. We'll notify you by email."),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _resend() async {
    final err = await AuthService.resendOtp(widget.email);
    _snack(err ?? 'A new code was sent');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Email')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('We sent a code to ${widget.email}', textAlign: TextAlign.center),
              const SizedBox(height: 20),
              TextField(
                controller: _otp,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'OTP code', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loading ? null : _verify,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: _loading
                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Verify'),
              ),
              TextButton(onPressed: _resend, child: const Text('Resend code')),
            ]),
          ),
        ),
      ),
    );
  }
}