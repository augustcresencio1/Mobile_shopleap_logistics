import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';
import 'package:mobileshopleap_logistic_app/models/receipt.dart';
import 'package:mobileshopleap_logistic_app/screens/money/receipt_screen.dart';
import 'money_fixtures.dart';

class ReceiptPlatform extends WebViewPlatform {
  late ReceiptController controller;
  late ReceiptDelegate delegate;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller = ReceiptController(params);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => delegate = ReceiptDelegate(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => ReceiptWidget(params);
}

class ReceiptController extends PlatformWebViewController {
  ReceiptController(super.params) : super.implementation();
  String? html, base;
  int clears = 0;
  JavaScriptMode? mode;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {
    mode = javaScriptMode;
  }

  @override
  Future<void> clearCache() async {
    clears++;
  }

  @override
  Future<void> clearLocalStorage() async {}
  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}
  @override
  Future<void> loadHtmlString(String value, {String? baseUrl}) async {
    html = value;
    base = baseUrl;
  }
}

class ReceiptDelegate extends PlatformNavigationDelegate {
  ReceiptDelegate(super.params) : super.implementation();
  late NavigationRequestCallback onNavigate;
  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {
    onNavigate = callback;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class ReceiptWidget extends PlatformWebViewWidget {
  ReceiptWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) =>
      const Text('Native HTML receipt viewer');
}

void main() {
  late ReceiptPlatform platform;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.clearToken();
    await ApiClient.saveToken('rider-a');
    platform = ReceiptPlatform();
    WebViewPlatform.instance = platform;
  });

  testWidgets('A receipt network failure offers retry without showing HTML', (
    tester,
  ) async {
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          const MaterialApp(
            home: ReceiptScreen(
              target: ReceiptTarget(ReceiptType.cashHandover, 'HO-exact'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Unable to load receipt'), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);
        expect(find.text('Native HTML receipt viewer'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      () => MockClient(
        (_) async => throw http.ClientException('Network unavailable'),
      ),
    );
  });

  testWidgets(
    'HTML viewer uses original origin, disables scripts and erases on logout',
    (tester) async {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            const MaterialApp(
              home: ReceiptScreen(
                target: ReceiptTarget(ReceiptType.cashHandover, 'HO-exact'),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Native HTML receipt viewer'), findsOneWidget);
          expect(platform.controller.mode, JavaScriptMode.disabled);
          expect(platform.controller.html, '<html>Receipt</html>');
          expect(
            platform.controller.base,
            '${ApiClient.baseUrl}/courier/receipts/cash-handovers/HO-exact',
          );
          expect(
            await platform.delegate.onNavigate(
              const NavigationRequest(
                url: 'https://other.example',
                isMainFrame: true,
              ),
            ),
            NavigationDecision.prevent,
          );
          expect(platform.controller.clears, 1);
          await ApiClient.clearToken();
          await tester.pumpAndSettle();
          expect(find.text('Native HTML receipt viewer'), findsNothing);
          expect(platform.controller.html, '<html></html>');
          expect(platform.controller.clears, 2);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((r) async {
          expect(r.headers['authorization'], 'Bearer rider-a');
          expect(r.url.query, isEmpty);
          return http.Response(
            '<html>Receipt</html>',
            200,
            headers: {'content-type': 'text/html'},
          );
        }),
      );
    },
  );

  for (final status in [401, 403, 404]) {
    testWidgets('Receipt $status displays an explicit state and no HTML', (
      tester,
    ) async {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            const MaterialApp(
              home: ReceiptScreen(
                target: ReceiptTarget(ReceiptType.riderPayout, 'PO-exact'),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(switch (status) {
              401 => 'Please sign in again',
              403 => 'Receipt unavailable for this account',
              _ => 'Receipt not found',
            }),
            findsOneWidget,
          );
          expect(find.text('Native HTML receipt viewer'), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient(
          (r) async => moneyResponse({'message': 'Unavailable'}, status),
        ),
      );
    });
  }
}
