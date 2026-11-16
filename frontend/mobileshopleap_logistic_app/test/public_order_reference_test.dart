import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';
import 'package:mobileshopleap_logistic_app/core/services/order_service.dart';
import 'package:mobileshopleap_logistic_app/widgets/order_card.dart';
import 'package:mobileshopleap_logistic_app/models/earnings.dart';
import 'package:mobileshopleap_logistic_app/core/services/history_service.dart';

const reference = 'SL23456789ABCDEF';
const waybill = 'WB23456789ABCDEF';
Map<String, dynamic> parcel() => {
  'id': 42,
  'order_number': reference,
  'waybill_code': waybill,
  'status': 'READY_FOR_PICKUP',
  'pickup_status': 'accepted',
  'total_amount': '90.00',
  'shipping_fee': '40.00',
  'cod_amount': '130.00',
  'buyer_name': 'Synthetic buyer',
  'seller_name': 'Synthetic seller',
  'items': [
    {'product_name': 'Synthetic parcel', 'quantity': 1},
  ],
};
http.Response response(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'auth_token:${ApiClient.baseUrl}': 'synthetic-courier-test-only',
    });
    ApiClient.invalidateCache();
  });
  test(
    'pickup resolves the waybill and confirms the public order number',
    () async {
      await http.runWithClient(
        () async {
          final result = await OrderService.scan(waybill);
          expect(result.order.reference, reference);
          expect(result.order.waybillCode, waybill);
          await OrderService.pickupOrder(
            result.order.orderNumber,
            scannedCode: 'SHOPLEAP:ORDER:$waybill',
          );
        },
        () => MockClient((request) async {
          if (request.method == 'GET') {
            expect(request.url.path, '/api/courier/pickups');
            return response({
              'data': [parcel()],
            });
          }
          expect(request.url.path, '/api/courier/pickups/$reference/confirm');
          expect(jsonDecode(request.body), {'scan': 'SHOPLEAP:ORDER:$waybill'});
          return response({'message': 'OK'});
        }),
      );
    },
  );
  for (final fixture in [
    {'order_number': null, 'waybill_code': waybill, 'expected': waybill},
    {'order_number': '', 'waybill_code': null, 'expected': '42'},
    {'order_number': '   ', 'waybill_code': '', 'expected': '42'},
  ]) {
    test(
      'legacy display fallback ${fixture['expected']} keeps internal id 42',
      () async {
        await http.runWithClient(
          () async {
            final result = await OrderService.scan('42');
            expect(result.order.id, '42');
            expect(result.order.reference, fixture['expected']);
          },
          () => MockClient(
            (request) async => response({
              'data': [
                {...parcel(), ...fixture},
              ],
            }),
          ),
        );
      },
    );
  }
  test(
    'delivery history and profit keep public references separately from numeric route ids',
    () async {
      final earning = EarningsHistoryItem.fromJson({
        'order_id': 42,
        'order_number': reference,
        'waybill_code': waybill,
        'amount': '20.25',
        'currency': 'PHP',
      });
      expect(earning.orderId, '42');
      expect(earning.reference, reference);
      await http.runWithClient(
        () async {
          final result = await HistoryService.fetch();
          expect(result.items.single.orderId, reference);
          expect(result.items.single.codCollected, '130.00');
        },
        () => MockClient(
          (request) async => response({
            'data': [
              {...parcel(), 'cod_collected': '130.00'},
            ],
            'meta': {'current_page': 1, 'last_page': 1, 'total': 1},
          }),
        ),
      );
    },
  );
  test(
    'actual Flutter normalizer preserves new WB/QR codes and old numeric labels',
    () {
      expect(OrderService.normalizeScan(' $waybill '), waybill);
      expect(
        OrderService.normalizeScan('SHOPLEAP:ORDER:$waybill'),
        'SHOPLEAP:ORDER:$waybill',
      );
      expect(OrderService.normalizeScan('42'), '42');
    },
  );
  test('public QR lookup uses the authenticated pickups list', () async {
    await http.runWithClient(
      () async {
        final result = await OrderService.scan('SHOPLEAP:ORDER:$waybill');
        expect(
          result.order.id,
          '42',
        ); // Internal mutation route identity remains separate.
        expect(result.order.codAmount, '130.00');
        expect(result.role, 'pickup');
      },
      () => MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/courier/pickups');
        expect(
          request.headers['Authorization'],
          'Bearer synthetic-courier-test-only',
        );
        return response({
          'data': [parcel()],
        });
      }),
    );
  });
  test(
    'actual scan service exposes the courier backend public-code rejection',
    () async {
      await http.runWithClient(
        () async {
          await expectLater(
            OrderService.scan(waybill),
            throwsA(
              isA<ApiException>().having(
                (e) => e.message,
                'message',
                'Invalid code',
              ),
            ),
          );
        },
        () => MockClient(
          (request) async => response({'message': 'Invalid code'}, 422),
        ),
      );
    },
  );
  testWidgets(
    'ACCEPTANCE: courier order card displays the saved public order reference',
    (tester) async {
      await http.runWithClient(
        () async {
          final result = await OrderService.scan(waybill);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(body: OrderCard(order: result.order)),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.textContaining(reference),
            findsOneWidget,
            reason:
                'The API public order_number must be visible; showing only internal id 42 loses cross-app identification.',
          );
        },
        () => MockClient(
          (request) async => response({
            'data': [parcel()],
          }),
        ),
      );
    },
  );

  for (final code in [
    'WB-CMSJY2NW5X',
    'wb-cmsjy2nw5x',
    'WBCMSJY2NW5X',
    'SL-PZ7NKDPW',
    '42',
    '0000000042',
    'SHOPLEAP:ORDER:42',
    'SHOPLEAP:ORDER:WB-CMSJY2NW5X',
    'https://shopleap.shop/track/WB-CMSJY2NW5X?print=1',
  ]) {
    test(
      'scan/manual input $code resolves the stored public order number',
      () async {
        await http.runWithClient(
          () async {
            final result = await OrderService.scan(code);
            expect(result.order.orderNumber, 'SL-PZ7NKDPW');
            await OrderService.pickupOrder(
              result.order.orderNumber,
              scannedCode: code,
            );
          },
          () => MockClient((request) async {
            expect(
              request.headers['authorization'],
              'Bearer synthetic-courier-test-only',
            );
            if (request.method == 'GET') {
              expect(request.url.path, '/api/courier/pickups');
              return response({
                'data': [
                  {
                    ...parcel(),
                    'order_number': 'SL-PZ7NKDPW',
                    'waybill_code': 'WB-CMSJY2NW5X',
                  },
                ],
              });
            }
            expect(request.method, 'POST');
            expect(
              request.url.path,
              '/api/courier/pickups/SL-PZ7NKDPW/confirm',
            );
            expect(jsonDecode(request.body), {'scan': code});
            return response({'message': 'OK', 'status': 'PICKED_UP'});
          }),
        );
      },
    );
  }

  test(
    'delivery scan falls through to deliveries without a scan endpoint',
    () async {
      final paths = <String>[];
      await http.runWithClient(
        () async {
          final result = await OrderService.scan(waybill);
          expect(result.role, 'delivery');
          expect(result.status, 'OUT_FOR_DELIVERY');
          expect(result.order.orderNumber, reference);
          expect(paths, ['/api/courier/pickups', '/api/courier/deliveries']);
        },
        () => MockClient((request) async {
          paths.add(request.url.path);
          return response({
            'data': request.url.path.endsWith('/pickups')
                ? []
                : [
                    {...parcel(), 'status': 'OUT_FOR_DELIVERY'},
                  ],
          });
        }),
      );
    },
  );

  test('unassigned waybill never falls back to a numeric suffix', () async {
    await http.runWithClient(
      () async {
        await expectLater(
          OrderService.scan('WB23456789ABCDE2'),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 404),
          ),
        );
      },
      () => MockClient(
        (request) async => response({
          'data': [parcel()],
        }),
      ),
    );
  });

  test(
    'pickup and delivery mutations use public paths and exact controller bodies',
    () async {
      final requests = <http.Request>[];
      await http.runWithClient(
        () async {
          await OrderService.acceptPickup(reference);
          await OrderService.declinePickup(reference, 'Cannot reach seller');
          await OrderService.startDelivery(reference);
          await OrderService.failDelivery(reference, 'Recipient unavailable');
          expect(requests.map((r) => r.url.path), [
            '/api/courier/pickups/$reference/accept',
            '/api/courier/pickups/$reference/decline',
            '/api/courier/deliveries/$reference/out',
            '/api/courier/deliveries/$reference/failed',
          ]);
          expect(jsonDecode(requests[1].body), {
            'reason': 'Cannot reach seller',
          });
          expect(jsonDecode(requests[3].body), {
            'reason': 'Recipient unavailable',
          });
          expect(jsonDecode(requests[0].body), <String, dynamic>{});
          expect(jsonDecode(requests[2].body), <String, dynamic>{});
        },
        () => MockClient((request) async {
          expect(request.method, 'POST');
          expect(
            request.headers['authorization'],
            'Bearer synthetic-courier-test-only',
          );
          requests.add(request);
          return response({'message': 'OK'});
        }),
      );
    },
  );

  test(
    'buyer_name is authoritative even when a buyer object has no name',
    () async {
      await http.runWithClient(
        () async {
          final result = await OrderService.itemsForPickup();
          expect(result.single.recipientName, 'Synthetic buyer');
        },
        () => MockClient(
          (_) async => response({
            'data': [
              {
                ...parcel(),
                'buyer': {'phone': '09171234567'},
              },
            ],
          }),
        ),
      );
    },
  );
}
