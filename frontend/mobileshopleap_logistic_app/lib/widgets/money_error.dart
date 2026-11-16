import 'dart:async';
import 'package:flutter/material.dart';
import '../core/services/api_exception.dart';

/// Also prevents repeated taps during the server's Retry-After interval.
class MoneyError extends StatefulWidget {
  final Object error;
  final VoidCallback onRetry;
  final bool receipt;
  const MoneyError({
    super.key,
    required this.error,
    required this.onRetry,
    this.receipt = false,
  });

  @override
  State<MoneyError> createState() => _MoneyErrorState();
}

class _MoneyErrorState extends State<MoneyError> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant MoneyError oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  Duration get _remaining => widget.error is ApiException
      ? (widget.error as ApiException).retryAfter
      : Duration.zero;

  void _schedule() {
    _timer?.cancel();
    if (_remaining > Duration.zero) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() {});
        if (_remaining == Duration.zero) timer.cancel();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.error;
    final status = error is ApiException ? error.statusCode : null;
    final title = switch (status) {
      401 => 'Please sign in again',
      403 =>
        widget.receipt
            ? 'Receipt unavailable for this account'
            : 'Account or hub unavailable',
      404 => widget.receipt ? 'Receipt not found' : 'Money records unavailable',
      422 => 'Check the selected details',
      429 => 'Please wait before retrying',
      _ =>
        'Unable to load ${widget.receipt ? 'receipt' : 'current money records'}',
    };
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text('$error', textAlign: TextAlign.center),
          TextButton(
            onPressed: _remaining > Duration.zero ? null : widget.onRetry,
            child: Text(
              _remaining > Duration.zero
                  ? 'Retry in ${_remaining.inSeconds + 1}s'
                  : 'Try again',
            ),
          ),
        ],
      ),
    );
  }
}
