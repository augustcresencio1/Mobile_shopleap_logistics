import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/services/api_client.dart';
import '../../core/services/api_exception.dart';
import '../../core/services/receipt_service.dart';
import '../../models/receipt.dart';
import '../../widgets/money_error.dart';

class ReceiptScreen extends StatefulWidget {
  final ReceiptTarget target;
  const ReceiptScreen({super.key, required this.target});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  WebViewController? _controller;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    ApiClient.sessionChanged.addListener(_clearSession);
    _load();
  }

  void _clearSession() {
    _generation++;
    final controller = _controller;
    setState(() {
      _controller = null;
      _error = ApiException(
        ApiClient.hasSession
            ? 'Your account changed. Open the receipt again.'
            : 'Please sign in again.',
        ApiClient.hasSession ? null : 401,
      );
    });
    if (controller != null) unawaited(_erase(controller));
  }

  Future<void> _erase(WebViewController controller) async {
    for (final erase in <Future<void> Function()>[
      () => controller.loadHtmlString('<html></html>'),
      controller.clearCache,
      controller.clearLocalStorage,
    ]) {
      try {
        await erase();
      } catch (_) {
        /* Continue cleanup even if the native view has already been disposed. */
      }
    }
  }

  Future<void> _load() async {
    await ApiClient.getToken();
    if (!mounted) return;
    final generation = ++_generation;
    final previous = _controller;
    setState(() {
      _controller = null;
      _error = null;
    });
    if (previous != null) await _erase(previous);
    try {
      final receipt = await ReceiptService.fetch(widget.target);
      if (!mounted || generation != _generation) return;
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.disabled);
      await controller.clearCache();
      await controller.clearLocalStorage();
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              request.url == receipt.baseUri.toString() ||
                  request.url == 'about:blank'
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onWebResourceError: (error) {
            if (error.isForMainFrame == true &&
                mounted &&
                generation == _generation) {
              setState(() {
                _controller = null;
                _error = 'Receipt could not be displayed. Please try again.';
              });
              unawaited(_erase(controller));
            }
          },
        ),
      );
      // The authenticated HTML stays in memory. The WebView never receives a token.
      await controller.loadHtmlString(
        receipt.html,
        baseUrl: receipt.baseUri.toString(),
      );
      if (!mounted || generation != _generation) {
        await _erase(controller);
        return;
      }
      setState(() => _controller = controller);
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _generation++;
    ApiClient.sessionChanged.removeListener(_clearSession);
    final controller = _controller;
    if (controller != null) unawaited(_erase(controller));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.target.reference),
      actions: [
        IconButton(
          tooltip: 'Refresh receipt',
          onPressed: _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _error != null
        ? Center(
            child: MoneyError(error: _error!, onRetry: _load, receipt: true),
          )
        : _controller == null
        ? const Center(child: CircularProgressIndicator())
        : WebViewWidget(controller: _controller!),
  );
}
