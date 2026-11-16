import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../models/courier.dart';
import '../../core/services/api_client.dart';
import '../account/account_screen.dart';
import '../home/main_shell.dart';
import 'login_screen.dart';

/// Unang screen ng app. Nagche-check ng token sa Laravel:
///  - walang token / invalid     -> LoginScreen
///  - courier na approved        -> MainShell (rider dashboard)
///  - courier na pending pa      -> PendingApprovalScreen
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<Widget> _future = _decide();

  Future<Widget> _decide() async {
    try {
      final me = await AuthService.me();
      if (me == null) {
        Courier.current = Courier(name: '', phone: '', vehicle: '', plate: '');
        return const LoginScreen();
      }

      Courier.current = Courier.fromJson(me);
      final status =
          me['courier_status'] ??
          ((me['courier'] is Map) ? me['courier']['status'] : null);
      if (status == 'approved') {
        return const MainShell();
      }

      return PendingApprovalScreen(
        courierStatus: status?.toString() ?? 'pending',
        rejectionReason: me['courier'] is Map
            ? me['courier']['rejection_reason']?.toString()
            : null,
      );
    } catch (e) {
      return _AccountLoadError(message: e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data ?? const LoginScreen();
      },
    );
  }
}

class _AccountLoadError extends StatelessWidget {
  final String message;
  const _AccountLoadError({required this.message});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const AuthGate()),
                ),
                child: const Text('Try again'),
              ),
              TextButton(
                onPressed: () async {
                  await AuthService.logout();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (_) => false,
                  );
                },
                child: const Text('Logout'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class PendingApprovalScreen extends StatefulWidget {
  final String courierStatus;
  final String? rejectionReason;
  const PendingApprovalScreen({
    super.key,
    this.courierStatus = 'pending',
    this.rejectionReason,
  });

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  bool _reapplying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ApiClient.sessionExpired.addListener(_onSessionExpired);
  }

  @override
  void dispose() {
    ApiClient.sessionExpired.removeListener(_onSessionExpired);
    super.dispose();
  }

  void _onSessionExpired() {
    if (!mounted) return;
    Courier.current = Courier(name: '', phone: '', vehicle: '', plate: '');
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _reapply() async {
    setState(() {
      _reapplying = true;
      _error = null;
    });
    try {
      await AuthService.reapply();
      if (mounted) _refresh(context);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _reapplying = false);
    }
  }

  Future<void> _logout(BuildContext context) async {
    await AuthService.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  void _refresh(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.hourglass_top,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  widget.courierStatus == 'rejected'
                      ? 'Registration rejected'
                      : 'Waiting for approval',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.courierStatus == 'rejected'
                      ? widget.rejectionReason ??
                            'Update your account information before reapplying.'
                      : 'Your registration is still under review. You will get an email once it is approved.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (_error != null) Text(_error!),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('Account settings')),
                        body: const AccountScreen(),
                      ),
                    ),
                  ),
                  child: const Text('Account settings'),
                ),
                if (widget.courierStatus == 'rejected')
                  FilledButton(
                    onPressed: _reapplying ? null : _reapply,
                    child: Text(_reapplying ? 'Submitting...' : 'Reapply'),
                  ),
                FilledButton(
                  onPressed: () => _refresh(context),
                  child: const Text('I-refresh'),
                ),
                TextButton(
                  onPressed: () => _logout(context),
                  child: const Text('Logout'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
