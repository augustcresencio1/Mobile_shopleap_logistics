import 'dart:convert';
import 'proof_fixture.dart';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobileshopleap_logistic_app/core/services/live_refresh.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';
import 'package:mobileshopleap_logistic_app/core/services/order_service.dart';
import 'package:mobileshopleap_logistic_app/models/order.dart';
import 'package:mobileshopleap_logistic_app/screens/dashboard/courier_dashboard_screen.dart';
import 'package:mobileshopleap_logistic_app/widgets/cod_amount_dialog.dart';

void main() {
  testWidgets(
    'COD confirmation rejects invalid cash and returns the exact amount',
    (tester) async {
      String? amount;
      final order = Order(
        id: '1234',
        item: 'Parcel',
        seller: 'Seller',
        from: '',
        buyer: 'Buyer',
        to: '',
        fee: null,
        status: OrderStatus.delivery,
        codAmount: '140.00',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    amount = await askCodAmount(context, order),
                child: const Text('Deliver'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Deliver'));
      await tester.pumpAndSettle();
      expect(find.text('140.00'), findsOneWidget);
      for (final invalid in ['-1', '1.234', 'NaN', 'Infinity']) {
        await tester.enterText(find.byType(TextField), invalid);
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Yes, delivered'),
              )
              .onPressed,
          isNull,
        );
      }
      await tester.enterText(find.byType(TextField), '120.25');
      await tester.pump();
      expect(
        find.textContaining('This differs from the COD amount.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Yes, delivered'));
      await tester.pumpAndSettle();
      expect(amount, '120.25');
    },
  );

  testWidgets(
    'Dashboard uses saved earned_today and refreshes while another tab is active',
    (tester) async {
      ApiClient.invalidateCache();
      FlutterSecureStorage.setMockInitialValues({
        'auth_token:${ApiClient.baseUrl}': 'courier-token',
      });
      var dashboardCalls = 0;
      final client = MockClient((request) async {
        Object body = {};
        switch (request.url.path) {
          case '/api/courier/dashboard':
            dashboardCalls++;
            body = {
              'requests': [],
              'pickups': [],
              'deliveries': [],
              'recent': [],
              'earned_week': '999.99',
              'earned_today': dashboardCalls == 1 ? '20.25' : '40.50',
              'currency': 'PHP',
            };
          case '/api/courier/deliveries/1234/delivered':
            body = {
              'proof': {'uploaded': true},
              'earning': {
                'amount': '20.25',
                'currency': 'PHP',
                'recorded_at': null,
              },
            };
        }
        return http.Response(jsonEncode(body), 200);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: CourierDashboardScreen(onGo: (_) {})),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('\u20B120.25'), findsOneWidget);
        expect(find.text('Earned today'), findsOneWidget);
        expect(find.text('\u20B1999.99'), findsNothing);
        LiveRefresh.activePage = 2;
        await OrderService.deliverOrder(
          '1234',
          amount: '140.00',
          proofImage: proofPhoto,
        );
        await tester.pumpAndSettle();
        expect(dashboardCalls, 2);
        expect(find.text('\u20B140.50'), findsOneWidget);
        // COD summary uses the existing 400 ms mock delay.
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => client);
    },
  );
}
