import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';
import 'package:mobileshopleap_logistic_app/core/services/live_refresh.dart';
import 'package:mobileshopleap_logistic_app/core/services/pending_delivery_store.dart';
import 'package:mobileshopleap_logistic_app/models/courier.dart';
import 'package:mobileshopleap_logistic_app/models/order.dart';
import 'package:mobileshopleap_logistic_app/screens/orders/proof_delivery_screen.dart';

import 'proof_fixture.dart';

class MemoryStore extends PendingDeliveryStore {
  PendingDelivery? draft;
  MemoryStore(this.draft);
  @override
  Future<PendingDelivery?> load(int riderId, String orderNumber) async => draft;
  @override
  Future<void> save(PendingDelivery value) async {
    draft = value;
  }

  @override
  Future<void> clear(int riderId, String orderNumber) async {
    draft = null;
  }
}

class DeniedGps extends GeolocatorPlatform {
  int requests = 0;
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.denied;
  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return LocationPermission.denied;
  }
}

Order parcel() => Order(
  id: '42',
  orderNumber: 'SL-PUBLIC42',
  item: '',
  seller: '',
  from: '',
  buyer: 'Synthetic buyer',
  to: '',
  fee: null,
  codAmount: '140.00',
  status: OrderStatus.delivery,
);

PendingDelivery draft(Order order, {bool attempted = false}) => PendingDelivery(
  riderId: 7,
  order: order,
  photo: proofPhoto,
  capturedAt: '2026-11-15T06:30:00Z',
  amount: attempted ? '140.00' : null,
  notes: 'Saved note',
  attempted: attempted,
);

Future<void> open(WidgetTester tester, Order order, MemoryStore store) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProofDeliveryScreen(order: order, store: store),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String text, {bool settle = true}) async {
  await reveal(tester, text);
  await tester.tap(find.text(text));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> reveal(WidgetTester tester, String text) async {
  if (find.text(text).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.text(text),
      200,
      scrollable: find.byType(Scrollable).first,
    );
  } else {
    await tester.ensureVisible(find.text(text));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GeolocatorPlatform originalGps;
  late DeniedGps gps;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'auth_token:${ApiClient.baseUrl}': 'synthetic-token',
    });
    ApiClient.invalidateCache();
    Courier.current = Courier(
      id: 7,
      name: '',
      phone: '',
      vehicle: '',
      plate: '',
    );
    originalGps = GeolocatorPlatform.instance;
    gps = DeniedGps();
    GeolocatorPlatform.instance = gps;
  });
  tearDown(() {
    GeolocatorPlatform.instance = originalGps;
  });

  testWidgets('new delivery requires camera photo before COD or confirmation', (
    tester,
  ) async {
    await open(tester, parcel(), MemoryStore(null));
    expect(find.text('Take parcel photo'), findsOneWidget);
    expect(find.text('Confirm photo and delivery'), findsNothing);
    expect(find.text('Yes, delivered'), findsNothing);
    expect(gps.requests, 0);
  });

  testWidgets(
    'preview offers Retake, location denial is optional, existing COD confirms exact amount',
    (tester) async {
      final order = parcel();
      final store = MemoryStore(draft(order));
      var uploads = 0;
      await http.runWithClient(
        () async {
          await open(tester, order, store);
          expect(find.byType(Image), findsOneWidget);
          expect(find.text('Retake'), findsOneWidget);
          expect(gps.requests, 0);
          await tap(tester, 'Attach location (optional)');
          expect(gps.requests, 1);
          expect(
            find.textContaining('You can still confirm delivery.'),
            findsOneWidget,
          );
          await tap(tester, 'Confirm photo and delivery', settle: false);
          expect(find.text('Mark delivered?'), findsOneWidget);
          expect(find.text('140.00'), findsOneWidget);
          expect(uploads, 0);
          await tester.enterText(
            find.widgetWithText(TextField, '140.00'),
            '120.25',
          );
          await tester.pump();
          expect(
            find.textContaining('This differs from the COD amount.'),
            findsOneWidget,
          );
          await tap(tester, 'Yes, delivered');
          expect(uploads, 1);
          expect(order.status, OrderStatus.done);
          expect(store.draft, isNull);
          expect(find.text('Open'), findsOneWidget);
        },
        () => MockClient((request) async {
          uploads++;
          expect(
            request.url.path,
            '/api/courier/deliveries/SL-PUBLIC42/delivered',
          );
          expect(store.draft!.attempted, isTrue);
          expect(store.draft!.amount, '120.25');
          expect(store.draft!.latitude, isNull);
          expect(store.draft!.capturedAt, '2026-11-15T06:30:00Z');
          return http.Response(
            jsonEncode({
              'earning': null,
              'proof': {'uploaded': true},
            }),
            200,
          );
        }),
      );
    },
  );

  testWidgets(
    '503 keeps immutable draft across reopening, disables duplicate upload and retries to 200',
    (tester) async {
      final order = parcel();
      final store = MemoryStore(draft(order, attempted: true));
      final original = store.draft!.toJson();
      final response = Completer<http.Response>();
      var uploads = 0;
      final before = LiveRefresh.deliveriesChanged.value;
      await http.runWithClient(
        () async {
          await open(tester, order, store);
          expect(find.text('Retake'), findsNothing);
          expect(find.text('Yes, delivered'), findsNothing);
          await reveal(tester, 'Retry');
          await tester.tap(find.text('Retry'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(uploads, 1);
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Retry'),
                )
                .onPressed,
            isNull,
          );
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
          expect(order.status, OrderStatus.delivery);
          expect(store.draft!.toJson(), original);
          response.complete(http.Response('Unavailable', 503));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('server may have recorded'),
            findsOneWidget,
          );
          expect(store.draft!.toJson(), original);
          expect(LiveRefresh.deliveriesChanged.value, before);
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tap(tester, 'Open');
          await tap(tester, 'Retry');
          expect(uploads, 2);
          expect(store.draft, isNull);
          expect(order.status, OrderStatus.done);
          expect(LiveRefresh.deliveriesChanged.value, before + 1);
          expect(gps.requests, 0);
        },
        () => MockClient((request) async {
          uploads++;
          expect(request.url.path.endsWith('/delivered'), isTrue);
          expect(
            request.headers['content-type'],
            startsWith('multipart/form-data; boundary='),
          );
          expect(
            latin1.decode(request.bodyBytes),
            contains('name="proof_image"'),
          );
          expect(store.draft!.toJson(), original);
          return uploads == 1
              ? response.future
              : http.Response(
                  '{"earning":null,"proof":{"uploaded":true}}',
                  200,
                );
        }),
      );
    },
  );

  for (final proof in [
    null,
    {'uploaded': false},
  ]) {
    testWidgets(
      'HTTP 200 with unconfirmed proof preserves the saved photo: $proof',
      (tester) async {
        final order = parcel();
        final store = MemoryStore(draft(order, attempted: true));
        final original = store.draft!.toJson();
        var uploads = 0;
        await http.runWithClient(
          () async {
            await open(tester, order, store);
            await tap(tester, 'Retry');
            expect(uploads, 1);
            expect(order.status, OrderStatus.delivery);
            expect(store.draft!.toJson(), original);
            expect(
              find.textContaining('did not confirm the proof upload'),
              findsOneWidget,
            );
            expect(find.text('Proof uploaded'), findsNothing);
            expect(find.text('Finish'), findsNothing);
            await tester.pageBack();
            await tester.pumpAndSettle();
            await tap(tester, 'Open');
            expect(store.draft!.toJson(), original);
            expect(find.byType(Image), findsOneWidget);
          },
          () => MockClient((_) async {
            uploads++;
            return http.Response(
              jsonEncode({'earning': null, 'proof': ?proof}),
              200,
            );
          }),
        );
      },
    );
  }

  testWidgets('422 photo validation keeps draft and permits retake', (
    tester,
  ) async {
    final order = parcel();
    final store = MemoryStore(draft(order, attempted: true));
    await http.runWithClient(
      () async {
        await open(tester, order, store);
        await tap(tester, 'Retry');
        expect(find.text('Use a clearer parcel photo.'), findsOneWidget);
        expect(find.text('Retake'), findsOneWidget);
        expect(store.draft!.attempted, isFalse);
        expect(store.draft!.photo, proofPhoto);
        expect(order.status, OrderStatus.delivery);
      },
      () => MockClient(
        (_) async => http.Response(
          jsonEncode({
            'errors': {
              'proof_image': ['Use a clearer parcel photo.'],
            },
          }),
          422,
        ),
      ),
    );
  });
}
