import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';
import 'package:mobileshopleap_logistic_app/core/services/order_service.dart';
import 'package:mobileshopleap_logistic_app/screens/dashboard/pickup_dashboard_screen.dart';
import 'package:mobileshopleap_logistic_app/screens/orders/pickup_order_screen.dart';

Map<String, dynamic> pickup(String status, String? contact) => {
  'id': status == 'assigned' ? 41 : 42,
  'pickup_status': status,
  'status': 'READY_FOR_PICKUP',
  'buyer_name': 'Waybill recipient',
  'buyer': {'phone': '09171234567'},
  'seller': {
    'name': 'Test seller',
    'address': '15 Seller Road',
    'contact_no': contact,
    // Other fields must never override contact_no, including when it is null.
    'seller_phone': '09999999999',
    'phone': '09888888888',
  },
  'seller_contact': '09777777777',
  'items': [
    {'product_name': '$status parcel', 'quantity': 1},
  ],
};

http.Response response(Object body) => http.Response(jsonEncode(body), 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');
  late List<MethodCall> launches;
  var canOpenDialer = true;

  setUp(() {
    ApiClient.invalidateCache();
    FlutterSecureStorage.setMockInitialValues({
      'auth_token:${ApiClient.baseUrl}': 'courier-token',
    });
    launches = [];
    canOpenDialer = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, (call) async {
          launches.add(call);
          return canOpenDialer;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, null);
    ApiClient.invalidateCache();
  });

  MockClient api(String? contact) => MockClient((request) async {
    if (request.url.path == '/api/courier/pickups') {
      expect(request.method, 'GET');
      return response({
        'data': request.url.queryParameters['filter'] == 'awaiting_accept'
            ? [pickup('assigned', contact)]
            : [pickup('assigned', contact), pickup('accepted', contact)],
      });
    }
    expect(request.url.path, '/api/courier/navigation/route');
    return response({
      'stops': [
        {'order_id': 42, 'name': 'Route seller', 'phone': '09666666666'},
      ],
    });
  });

  Future<void> openPickup(WidgetTester tester, String status) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PickupDashboardScreen())),
    );
    await tester.pumpAndSettle();
    final parcel = find.text('$status parcel x1');
    expect(parcel, findsOneWidget);
    await tester.ensureVisible(parcel);
    await tester.tap(parcel);
    await tester.pumpAndSettle();
    expect(find.byType(PickupOrderScreen), findsOneWidget);
    expect(find.text('Test seller'), findsOneWidget);
    expect(find.text('Waybill recipient'), findsOneWidget);
    expect(find.text('15 Seller Road'), findsOneWidget);
    expect(
      find.text('Scan & confirm pickup'),
      status == 'accepted' ? findsOneWidget : findsNothing,
    );
  }

  for (final status in ['assigned', 'accepted']) {
    for (final contact in ['09171234567', ' +63 917-123-4567 ']) {
      testWidgets('$status pickup displays contact_no and opens tel:$contact', (
        tester,
      ) async {
        await http.runWithClient(() async {
          await openPickup(tester, status);
          expect(find.text(contact.trim()), findsOneWidget);
          expect(find.text('Phone number unavailable'), findsNothing);
          final call = find.text('Call Seller');
          expect(call, findsOneWidget);
          await tester.tap(call);
          await tester.pumpAndSettle();
          expect(launches, hasLength(1));
          expect(launches.single.method, 'launch');
          expect(
            launches.single.arguments['url'],
            contact.contains('+63') ? 'tel:+639171234567' : 'tel:09171234567',
          );
          expect(launches.single.arguments['useWebView'], isFalse);
          expect(launches.single.arguments['useSafariVC'], isFalse);
          await tester.pumpWidget(const SizedBox());
        }, () => api(contact));
      });
    }

    for (final contact in [null, '', '   ']) {
      testWidgets('$status pickup with contact_no [$contact] hides call', (
        tester,
      ) async {
        await http.runWithClient(() async {
          await openPickup(tester, status);
          expect(find.text('Phone number unavailable'), findsOneWidget);
          expect(find.text('Call Seller'), findsNothing);
          expect(find.text('Call'), findsNothing);
          expect(launches, isEmpty);
          await tester.pumpWidget(const SizedBox());
        }, () => api(contact));
      });
    }
  }

  testWidgets('Dialer failure shows feedback without losing pickup details', (
    tester,
  ) async {
    canOpenDialer = false;
    await http.runWithClient(() async {
      await openPickup(tester, 'accepted');
      await tester.tap(find.text('Call Seller'));
      await tester.pumpAndSettle();
      expect(find.text('Could not open the phone dialer.'), findsOneWidget);
      expect(find.byType(PickupOrderScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, () => api('09171234567'));
  });

  test('Local flat seller_contact remains compatible', () async {
    await http.runWithClient(
      () async {
        final orders = await OrderService.itemsForPickup();
        expect(orders.single.sellerContact, '09171234567');
      },
      () => MockClient(
        (_) async => response({
          'data': [
            {
              'id': 42,
              'pickup_status': 'accepted',
              'seller_name': 'Local seller',
              'seller_contact': ' 09171234567 ',
            },
          ],
        }),
      ),
    );
  });
}
