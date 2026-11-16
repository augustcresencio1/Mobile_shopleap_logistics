import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';
import 'package:mobileshopleap_logistic_app/core/services/live_refresh.dart';
import 'package:mobileshopleap_logistic_app/models/courier.dart';
import 'package:mobileshopleap_logistic_app/screens/home/main_shell.dart';

Map<String, dynamic> order(int id, String status, {String role = 'pickup'}) => {
  'id': id,
  'status': status,
  'notification_role': role,
  'seller_name': 'Seller',
  'pickup_status': status == 'REQUEST' ? 'assigned' : 'accepted',
  'items': [
    {'product_name': 'Item $id', 'quantity': 1},
  ],
};

Map<String, dynamic> home({bool requests = true}) => {
  'requests': requests ? [order(100, 'REQUEST')] : [],
  'pickups': [order(101, 'READY_FOR_PICKUP')],
  'deliveries': [order(103, 'OUT_FOR_DELIVERY', role: 'delivery')],
  'in_progress': [
    order(101, 'READY_FOR_PICKUP'),
    order(102, 'PICKED_UP'),
    order(103, 'OUT_FOR_DELIVERY', role: 'delivery'),
    order(104, 'DELIVERED'),
    order(105, 'DELIVERY_FAILED'),
  ],
  'recent': [],
  'earned_week': '0.00',
  'earned_today': '0.00',
};

http.Response response(Object body) => http.Response(jsonEncode(body), 200);

void main() {
  setUp(() {
    ApiClient.invalidateCache();
    FlutterSecureStorage.setMockInitialValues({
      'auth_token:${ApiClient.baseUrl}': 'courier-token',
    });
    Courier.current = Courier(name: '', phone: '', vehicle: '', plate: '');
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  MockClient api(Map<String, dynamic> Function() currentHome) =>
      MockClient((request) async {
        final home = currentHome();
        if (request.url.path.endsWith('/dashboard')) {
          return response({'earned_today': home['earned_today']});
        }
        if (request.url.path.endsWith('/pickups')) {
          final progress = home['in_progress'] as List?;
          return response({
            'data': request.url.queryParameters['filter'] == 'awaiting_accept'
                ? home['requests']
                : [
                    if (progress != null)
                      ...progress.where(
                        (row) => row['notification_role'] != 'delivery',
                      )
                    else
                      ...home['pickups'] as List,
                  ],
          });
        }
        if (request.url.path.endsWith('/deliveries')) {
          return response({'data': home['deliveries']});
        }
        if (request.url.path.endsWith('/history')) {
          return response({'data': home['recent']});
        }
        if (request.url.path.endsWith('/overview')) {
          return response({
            'summary': {
              'total_earned': '0.00',
              'deliveries': 0,
              'recorded_earnings': 0,
              'daily': [],
            },
            'rate': {'amount': null},
            'history': {
              'data': [],
              'meta': {'current_page': 1, 'last_page': 1, 'total': 0},
            },
          });
        }
        if (request.url.path.endsWith('/me')) {
          return response({
            'name': 'Rider',
            'courier': {'id': 0},
          });
        }
        return response({
          'data': [],
          'meta': {'current_page': 1, 'last_page': 1, 'total': 0},
        });
      });

  Future<void> showShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: MainShell()));
    await tester.pumpAndSettle();
  }

  Badge bell(WidgetTester tester) => tester.widget<Badge>(
    find.descendant(
      of: find.byTooltip('Notifications'),
      matching: find.byType(Badge),
    ),
  );

  Finder sheetText(String text) => find.descendant(
    of: find.byType(BottomSheet),
    matching: find.textContaining(text),
  );

  testWidgets(
    'Dashboard and Chat count only requests; bell retains labeled progress',
    (tester) async {
      await http.runWithClient(() async {
        await showShell(tester);
        expect(bell(tester).isLabelVisible, isTrue);
        expect((bell(tester).label as Text).data, '1');
        await tester.tap(find.byTooltip('Notifications'));
        await tester.pumpAndSettle();
        expect(sheetText('Open requests (1)'), findsOneWidget);
        expect(sheetText('In progress (3)'), findsOneWidget);
        expect(sheetText('To pick up'), findsOneWidget);
        expect(sheetText('Picked up'), findsOneWidget);
        expect(sheetText('Out for delivery'), findsOneWidget);
        expect(sheetText('Item 104'), findsNothing);
        expect(sheetText('Item 105'), findsNothing);
        Navigator.of(tester.element(find.byType(BottomSheet))).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chat'));
        await tester.pumpAndSettle();
        expect(bell(tester).isLabelVisible, isTrue);
        expect((bell(tester).label as Text).data, '1');
        await tester.pumpWidget(const SizedBox());
      }, () => api(() => home()));
    },
  );

  testWidgets(
    'Zero requests hides both badges while progress remains visible',
    (tester) async {
      await http.runWithClient(() async {
        await showShell(tester);
        expect(bell(tester).isLabelVisible, isFalse);
        await tester.tap(find.byTooltip('Notifications'));
        await tester.pumpAndSettle();
        expect(sheetText('In progress (3)'), findsOneWidget);
        expect(sheetText('You are all caught up.'), findsNothing);
        Navigator.of(tester.element(find.byType(BottomSheet))).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Chat'));
        await tester.pumpAndSettle();
        expect(bell(tester).isLabelVisible, isFalse);
        await tester.pumpWidget(const SizedBox());
      }, () => api(() => home(requests: false)));
    },
  );

  testWidgets(
    'An open bell moves accepted requests to progress and removes finished orders',
    (tester) async {
      var body = home();
      await http.runWithClient(() async {
        await showShell(tester);
        await tester.tap(find.byTooltip('Notifications'));
        await tester.pumpAndSettle();
        body = home(requests: false);
        (body['in_progress'] as List).add(order(100, 'READY_FOR_PICKUP'));
        ApiClient.invalidateCache();
        LiveRefresh.pokeNow();
        await tester.pumpAndSettle();
        expect(sheetText('Open requests'), findsNothing);
        expect(sheetText('In progress (4)'), findsOneWidget);
        expect(sheetText('Item 100'), findsOneWidget);
        (body['in_progress'] as List).removeWhere((row) => row['id'] == 100);
        ApiClient.invalidateCache();
        LiveRefresh.pokeNow();
        await tester.pumpAndSettle();
        expect(sheetText('Item 100'), findsNothing);
        expect(sheetText('In progress (3)'), findsOneWidget);
        Navigator.of(tester.element(find.byType(BottomSheet))).pop();
        await tester.pumpAndSettle();
        expect(bell(tester).isLabelVisible, isFalse);
        await tester.pumpWidget(const SizedBox());
      }, () => api(() => body));
    },
  );

  for (final item in [
    (100, 'Items for pickup'),
    (102, 'Items for pickup'),
    (103, 'Items for delivery'),
  ]) {
    testWidgets('Bell item ${item.$1} opens ${item.$2}', (tester) async {
      await http.runWithClient(() async {
        await showShell(tester);
        await tester.tap(find.byTooltip('Notifications'));
        await tester.pumpAndSettle();
        await tester.tap(sheetText('Item ${item.$1}'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Delivery Tasks'),
          ),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      }, () => api(() => home()));
    });
  }
}
