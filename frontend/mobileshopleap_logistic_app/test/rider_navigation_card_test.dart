import 'dart:async';
import 'dart:convert';
import 'proof_fixture.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';
import 'package:mobileshopleap_logistic_app/core/services/order_service.dart';
import 'package:mobileshopleap_logistic_app/core/services/rider_tracking_service.dart';
import 'package:mobileshopleap_logistic_app/models/order.dart';
import 'package:mobileshopleap_logistic_app/widgets/rider_navigation_card.dart';

class PhoneGps extends GeolocatorPlatform {
  LocationPermission permission = LocationPermission.denied;
  LocationPermission requestedPermission = LocationPermission.whileInUse;
  int requests = 0, reads = 0;
  final positions = StreamController<Position>.broadcast();
  var position = Position(
    latitude: 14.6,
    longitude: 120.98,
    timestamp: DateTime.utc(2026, 11, 8, 6),
    accuracy: 8,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );

  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return permission = requestedPermission;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    reads++;
    return position;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      positions.stream;
}

http.Response response(Object body) => http.Response(jsonEncode(body), 200);
const liveSession = 'c068ce66-c908-4d93-95fb-f265f3d5203e';
http.Response trackingResponse(http.Request request) =>
    request.url.path.endsWith('/tracking/start')
    ? response({
        'data': {'session_id': liveSession},
      })
    : response(route());
Map<String, dynamic> route() => {
  'station': {'id': 10, 'name': 'Assigned hub', 'address': 'Hub Road'},
  'stops': [
    {
      'order_id': 1234,
      'name': 'Customer',
      'address': 'Customer Road',
      'latitude': 14.601,
      'longitude': 120.98,
    },
  ],
};

void main() {
  late PhoneGps gps;
  late GeolocatorPlatform originalGps;
  setUp(() {
    SharedPreferences.setMockInitialValues({'battery_prompt_shown_v1': true});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('shopleap/rider_tracking'),
          (_) async => true,
        );
    ApiClient.invalidateCache();
    FlutterSecureStorage.setMockInitialValues({
      'auth_token:${ApiClient.baseUrl}': 'courier-token',
    });
    originalGps = GeolocatorPlatform.instance;
    gps = PhoneGps();
    GeolocatorPlatform.instance = gps;
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('shopleap/rider_tracking'),
          null,
        );
    RiderTrackingService.instance.reset();
    GeolocatorPlatform.instance = originalGps;
    await gps.positions.close();
  });

  Future<void> showCard(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RiderNavigationCard(
              role: 'delivery',
              order: Order(
                id: '1234',
                item: 'Parcel',
                seller: 'Seller',
                from: 'Seller Road',
                buyer: 'Customer',
                to: 'Customer Road',
                fee: null,
                status: OrderStatus.delivery,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Live GPS starts explicitly and survives Maps, screen lock and page changes',
    (tester) async {
      await http.runWithClient(() async {
        await showCard(tester);
        expect(gps.requests, 0);
        expect(gps.reads, 0);
        await tester.tap(find.text('Start live trip'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sige'));
        await tester.pumpAndSettle();
        expect(gps.requests, 1);
        expect(gps.positions.hasListener, isTrue);
        expect(find.textContaining('111 m straight-line'), findsOneWidget);

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(gps.positions.hasListener, isTrue);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(gps.positions.hasListener, isTrue);
        expect(gps.reads, 1);
        await tester.pumpWidget(const SizedBox());
        expect(gps.positions.hasListener, isTrue);
        await RiderTrackingService.instance.stop();
        expect(gps.positions.hasListener, isFalse);
      }, () => MockClient((request) async => trackingResponse(request)));
    },
  );

  testWidgets(
    'Arrived requests fresh GPS and posts location without a stream',
    (tester) async {
      final posts = <http.Request>[];
      await http.runWithClient(
        () async {
          await showCard(tester);
          await tester.tap(find.text('Arrived'));
          await tester.pumpAndSettle();
          expect(gps.reads, 1);
          expect(gps.positions.hasListener, isFalse);
          expect(posts.single.url.path, '/api/courier/orders/1234/arrived');
          expect(jsonDecode(posts.single.body), {
            'role': 'delivery',
            'latitude': 14.6,
            'longitude': 120.98,
            'accuracy': 8.0,
            'recorded_at': '2026-11-08T06:00:00.000Z',
          });
          expect(find.textContaining('Arrival recorded.'), findsWidgets);
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient((request) async {
          if (request.method == 'POST') {
            posts.add(request);
            return response({'message': 'Arrival recorded.'});
          }
          return response(route());
        }),
      );
    },
  );

  testWidgets('Live uploads are sequential and Stop closes a pending upload', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var now = gps.position.timestamp;
    final tracking = RiderTrackingService(now: () => now);
    final pending = Completer<http.Response>();
    final requests = <http.Request>[];
    await http.runWithClient(
      () async {
        await tracking.start('1234', 'delivery');
        final revision = ApiClient.revision;
        now = now.add(const Duration(seconds: 5));
        await tester.pump(const Duration(seconds: 5));
        expect(requests.where((r) => r.method == 'PUT'), hasLength(1));
        now = now.add(const Duration(seconds: 5));
        await tester.pump(const Duration(seconds: 5));
        expect(requests.where((r) => r.method == 'PUT'), hasLength(1));
        expect(ApiClient.revision, revision);
        final stopping = tracking.stop();
        expect(gps.positions.hasListener, isFalse);
        pending.complete(response({'data': {}}));
        await stopping;
        expect(requests.last.url.path, '/api/courier/tracking/stop');
        tracking.dispose();
      },
      () => MockClient((request) async {
        requests.add(request);
        if (request.method == 'PUT') return pending.future;
        return trackingResponse(request);
      }),
    );
  });

  testWidgets(
    'An offline upload retries and loss of assignment stops the sensors',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var now = gps.position.timestamp;
      final tracking = RiderTrackingService(now: () => now);
      var updates = 0;
      await http.runWithClient(
        () async {
          await tracking.start('1234', 'delivery');
          now = now.add(const Duration(seconds: 5));
          await tester.pump(const Duration(seconds: 5));
          expect(tracking.tracking, isTrue);
          expect(tracking.error, isNotNull);
          now = now.add(const Duration(seconds: 5));
          await tester.pump(const Duration(seconds: 5));
          expect(tracking.error, isNull);
          expect(tracking.live, isTrue);
          now = now.add(const Duration(seconds: 5));
          await tester.pump(const Duration(seconds: 5));
          expect(updates, 3);
          expect(tracking.tracking, isFalse);
          expect(gps.positions.hasListener, isFalse);
          tracking.dispose();
        },
        () => MockClient((request) async {
          if (request.method == 'PUT') {
            updates++;
            if (updates == 1) {
              return http.Response('{"message":"Offline"}', 503);
            }
            if (updates == 3) {
              return http.Response('{"message":"Trip ended"}', 403);
            }
          }
          return trackingResponse(request);
        }),
      );
    },
  );

  testWidgets(
    'Stop during start never leaves a late session or GPS stream running',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final tracking = RiderTrackingService();
      final pending = Completer<http.Response>();
      var starts = 0, stops = 0;
      await http.runWithClient(
        () async {
          final starting = tracking.start('1234', 'delivery');
          await tester.pumpAndSettle();
          expect(starts, 1);
          final stopping = tracking.stop();
          pending.complete(
            response({
              'data': {'session_id': liveSession},
            }),
          );
          await starting;
          await stopping;
          expect(stops, 1);
          expect(gps.positions.hasListener, isFalse);
          expect(tracking.tracking, isFalse);
          tracking.dispose();
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/start')) {
            starts++;
            return pending.future;
          }
          if (request.url.path.endsWith('/stop')) stops++;
          return trackingResponse(request);
        }),
      );
    },
  );

  testWidgets('Expired authentication immediately stops trip sensors', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final tracking = RiderTrackingService();
    await http.runWithClient(() async {
      await tracking.start('1234', 'delivery');
      expect(gps.positions.hasListener, isTrue);
      ApiClient.sessionExpired.value++;
      expect(tracking.tracking, isFalse);
      expect(gps.positions.hasListener, isFalse);
      tracking.dispose();
    }, () => MockClient((request) async => trackingResponse(request)));
  });

  testWidgets('Confirming a delivery ends its active live trip', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var stops = 0;
    await http.runWithClient(
      () async {
        await RiderTrackingService.instance.start('1234', 'delivery');
        await OrderService.deliverOrder(
          '1234',
          amount: '100.00',
          proofImage: proofPhoto,
        );
        expect(RiderTrackingService.instance.tracking, isFalse);
        expect(gps.positions.hasListener, isFalse);
        expect(stops, 1);
      },
      () => MockClient((request) async {
        if (request.url.path.endsWith('/stop')) stops++;
        if (request.url.path.endsWith('/delivered')) {
          return http.Response('{"proof":{"uploaded":true}}', 200);
        }
        return trackingResponse(request);
      }),
    );
  });

  testWidgets(
    'Denied GPS does not send an arrival and explains how to allow it',
    (tester) async {
      gps.permission = LocationPermission.deniedForever;
      var posts = 0;
      await http.runWithClient(
        () async {
          await showCard(tester);
          await tester.tap(find.text('Arrived'));
          await tester.pumpAndSettle();
          expect(posts, 0);
          expect(gps.reads, 0);
          expect(
            find.text('Allow location access in the phone app settings.'),
            findsOneWidget,
          );
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient((request) async {
          if (request.method == 'POST') posts++;
          return response(route());
        }),
      );
    },
  );

  test(
    'Order parsing keeps address separate from schedule and reads nested pins',
    () async {
      await http.runWithClient(
        () async {
          final order = (await OrderService.itemsForDelivery()).single;
          expect(order.pickupAddress, 'Seller Road');
          expect(order.from, contains('2026-11-08'));
          expect(order.deliveryPin?.query, '14.6,120.98');
        },
        () => MockClient(
          (_) async => response({
            'data': [
              {
                'id': 1234,
                'seller_street': 'Seller Road',
                'pickup_date': '2026-11-08',
                'shipping_address': jsonEncode({
                  'pin': {'lat': 14.6, 'lng': 120.98},
                }),
              },
            ],
          }),
        ),
      );
    },
  );
}
