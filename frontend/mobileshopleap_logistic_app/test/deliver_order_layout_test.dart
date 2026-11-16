import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';
import 'package:mobileshopleap_logistic_app/core/theme/app_colors.dart';
import 'package:mobileshopleap_logistic_app/core/theme/app_typography.dart';
import 'package:mobileshopleap_logistic_app/models/order.dart';
import 'package:mobileshopleap_logistic_app/screens/orders/deliver_order_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader(kAppFontFamily);
    for (final face in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(
        rootBundle.load(
          'assets/fonts/instrument_sans/InstrumentSans-$face.ttf',
        ),
      );
    }
    await loader.load();
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'auth_token:${ApiClient.baseUrl}': 'test-courier',
    });
    ApiClient.invalidateCache();
  });

  Future<void> showDelivery(WidgetTester tester, {double textScale = 1}) async {
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              fontFamily: kAppFontFamily,
              colorScheme: ColorScheme.fromSeed(seedColor: kBrandBlue),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: DeliverOrderScreen(
              order: Order(
                id: '42',
                orderNumber: 'SL-PZ7NKDPW',
                item: 'Wireless headphones',
                buyer: 'Juan Dela Cruz',
                seller: 'Maverick Denver Del Mundo',
                from: 'Seller address',
                to: '10 Para sa street, Bagumbayan, Santa Cruz, Laguna',
                buyerContact: '09171234567',
                codAmount: '2438.00',
                fee: null,
                status: OrderStatus.delivery,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      },
      () => MockClient(
        (_) async => http.Response(jsonEncode({'stops': []}), 200),
      ),
    );
  }

  for (final size in [const Size(360, 740), const Size(411, 873)]) {
    testWidgets('Delivery fits $size without scrolling', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      tester.view.padding = FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);

      await showDelivery(tester);

      expect(tester.takeException(), isNull);
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scrollable.position.maxScrollExtent, 0);
      for (final element in find.byType(Icon).evaluate()) {
        if (element.findAncestorWidgetOfExactType<AppBar>() != null) continue;
        final icon = element.widget as Icon;
        expect(icon.color ?? IconTheme.of(element).color, kBrandBlue);
      }
      for (final label in [
        'Item to deliver',
        'Buyer',
        'Seller',
        'Delivery address',
        'COD to collect',
        'Navigate',
        'Call',
        'Text',
        'Start live trip',
        'Arrived',
        'Full route',
        'Start delivery',
        'Mark delivered',
        'Delivery failed',
      ]) {
        expect(find.text(label).hitTestable(), findsOneWidget, reason: label);
      }
    });
  }

  testWidgets('Large text keeps delivery actions reachable without overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 740);
    addTearDown(tester.view.reset);

    await showDelivery(tester, textScale: 1.5);

    expect(tester.takeException(), isNull);
    expect(find.text('Mark delivered').hitTestable(), findsOneWidget);
    expect(find.text('Delivery failed').hitTestable(), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Full route').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
