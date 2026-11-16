import 'dart:convert';
import 'proof_fixture.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';
import 'package:mobileshopleap_logistic_app/core/services/earnings_service.dart';
import 'package:mobileshopleap_logistic_app/core/services/history_service.dart';
import 'package:mobileshopleap_logistic_app/core/services/live_refresh.dart';
import 'package:mobileshopleap_logistic_app/core/services/order_service.dart';
import 'package:mobileshopleap_logistic_app/models/earnings.dart';

http.Response response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ApiClient.invalidateCache();
    FlutterSecureStorage.setMockInitialValues({
      'auth_token:${ApiClient.baseUrl}': 'courier-token',
    });
  });

  test(
    'Summary and all history pages share filters and authenticated headers',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        expect(request.headers['Authorization'], 'Bearer courier-token');
        expect(request.headers['Accept'], 'application/json');
        expect(request.headers['Content-Type'], 'application/json');
        if (request.url.path.endsWith('/summary')) {
          return response({
            'total_earned': '20.25',
            'deliveries': 3,
            'recorded_earnings': 2,
          });
        }
        if (request.url.path.endsWith('/rate')) {
          return response({
            'amount': null,
            'currency': 'PHP',
            'effective_from': null,
          });
        }
        final page = int.parse(request.url.queryParameters['page']!);
        return response({
          'data': [
            {
              'order_id': page,
              'amount': page == 1 ? null : '0.00',
              'currency': 'PHP',
              'recorded_at': null,
              'delivered_at': '2026-11-08T14:30:00+08:00',
            },
          ],
          'meta': {'current_page': page, 'last_page': 2, 'total': 21},
        });
      });
      await http.runWithClient(() async {
        final filter = EarningsFilter(
          preset: 'custom',
          from: DateTime(2026, 11, 1),
          to: DateTime(2026, 11, 8),
        );
        expect(
          (await EarningsService.summary(filter))['total_earned'],
          '20.25',
        );
        final first = await EarningsService.history(filter);
        final next = await EarningsService.history(filter, page: 2);
        expect(first.items.single.amount, isNull);
        expect(first.items.single.recordedAt, isNull);
        expect(next.items.single.amount, '0.00');
        expect(next.currentPage, 2);
        expect(next.total, 21);
        expect((await EarningsService.rate())['amount'], isNull);
        for (final request in requests.take(3)) {
          expect(
            {...request.url.queryParameters}..remove('page'),
            filter.query,
          );
        }
      }, () => client);
    },
  );

  test(
    'Delivery retries send valid COD strings and invalidate saved totals each time',
    () async {
      final revision = LiveRefresh.deliveriesChanged.value;
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.method, 'POST');
        expect(request.url.path, '/api/courier/deliveries/1234/delivered');
        expect(
          request.headers['content-type'],
          startsWith('multipart/form-data; boundary='),
        );
        expect(request.bodyBytes, isNotEmpty);
        return response({
          'message': 'Delivery recorded. Thank you.',
          'proof': {'uploaded': true},
          'earning': {
            'amount': '20.25',
            'currency': 'PHP',
            'recorded_at': '2026-11-08T14:30:00+08:00',
          },
        });
      });
      await http.runWithClient(() async {
        final first = await OrderService.deliverOrder(
          '1234',
          amount: '140',
          proofImage: proofPhoto,
        );
        final retry = await OrderService.deliverOrder(
          '1234',
          amount: '140.00',
          proofImage: proofPhoto,
        );
        expect(first.earning!.amount, '20.25');
        expect(retry.earning!.amount, '20.25');
        expect(calls, 2);
        expect(LiveRefresh.deliveriesChanged.value, revision + 2);
      }, () => client);
    },
  );

  test(
    'Successful deliveries preserve missing and valid zero earnings',
    () async {
      var calls = 0;
      final client = MockClient(
        (_) async => response({
          'proof': {'uploaded': true},
          'earning': calls++ == 0
              ? null
              : {'amount': '0.00', 'currency': 'PHP', 'recorded_at': null},
        }),
      );
      await http.runWithClient(() async {
        expect(
          (await OrderService.deliverOrder(
            '1',
            amount: '0.00',
            proofImage: proofPhoto,
          )).earning,
          isNull,
        );
        expect(
          (await OrderService.deliverOrder(
            '2',
            amount: '0.00',
            proofImage: proofPhoto,
          )).earning!.amount,
          '0.00',
        );
      }, () => client);
    },
  );

  test(
    'History scalar money preserves null, zero, cents and currency',
    () async {
      final client = MockClient(
        (_) async => response({
          'data': [
            {
              'order_id': 1,
              'outcome': 'delivered',
              'earning': null,
              'rider_fee': '99.00',
              'cod_collected': null,
              'currency': 'PHP',
            },
            {
              'order_id': 2,
              'outcome': 'delivered',
              'earning': '0.00',
              'cod_collected': '140.00',
              'currency': 'PHP',
            },
            {
              'order_id': 3,
              'outcome': 'returned',
              'earning': '0.00',
              'cod_collected': '0.00',
              'currency': 'PHP',
            },
            {
              'order_id': 4,
              'outcome': 'delivered',
              'earning': '20.25',
              'cod_collected': '140.25',
              'currency': 'PHP',
            },
          ],
          'meta': {'current_page': 1, 'last_page': 1, 'total': 4},
        }),
      );
      await http.runWithClient(() async {
        final page = await HistoryService.fetch();
        expect(page.items.map((item) => item.earning), [
          null,
          '0.00',
          '0.00',
          '20.25',
        ]);
        expect(page.items.first.codCollected, isNull);
        expect(page.items.last.codCollected, '140.25');
        expect(page.items[2].returned, isTrue);
      }, () => client);
    },
  );

  test('401 expires invalid and missing authentication', () async {
    for (final hasToken in [true, false]) {
      FlutterSecureStorage.setMockInitialValues(
        hasToken ? {'auth_token:${ApiClient.baseUrl}': 'invalid'} : {},
      );
      final before = ApiClient.sessionExpired.value;
      await http.runWithClient(
        () async {
          await expectLater(
            EarningsService.rate(),
            throwsA(
              isA<ApiException>().having(
                (error) => error.statusCode,
                'status',
                401,
              ),
            ),
          );
          expect(await ApiClient.getToken(), isNull);
          expect(ApiClient.sessionExpired.value, before + 1);
        },
        () => MockClient(
          (_) async => response({'message': 'Unauthenticated.'}, 401),
        ),
      );
    }
  });

  for (final status in [403, 422]) {
    test(
      '$status exposes server restrictions or validation without completing delivery',
      () async {
        final revision = LiveRefresh.deliveriesChanged.value;
        await http.runWithClient(
          () async {
            await expectLater(
              OrderService.deliverOrder(
                '1234',
                amount: '140.00',
                proofImage: proofPhoto,
              ),
              throwsA(
                isA<ApiException>()
                    .having((error) => error.statusCode, 'status', status)
                    .having(
                      (error) => error.message,
                      'message',
                      'Delivery is unavailable.',
                    ),
              ),
            );
            expect(LiveRefresh.deliveriesChanged.value, revision);
          },
          () => MockClient(
            (_) async =>
                response({'message': 'Delivery is unavailable.'}, status),
          ),
        );
      },
    );
  }

  test('Invalid cash is rejected before a request', () async {
    await http.runWithClient(() async {
      for (final amount in ['-1.00', '1.234', 'Infinity', 'NaN', '']) {
        await expectLater(
          OrderService.deliverOrder(
            '1',
            amount: amount,
            proofImage: proofPhoto,
          ),
          throwsA(isA<ApiException>()),
        );
      }
    }, () => MockClient((_) async => throw StateError('Unexpected request')));
  });
}
