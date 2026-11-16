import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';
import 'package:mobileshopleap_logistic_app/core/services/order_service.dart';

import 'money_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.clearToken();
    await ApiClient.saveToken('deployed-rider');
  });

  http.Response api(http.Request request, {bool missingEarnings = false}) {
    expect(request.headers['authorization'], 'Bearer deployed-rider');
    expect(request.headers['accept'], 'application/json');
    switch (request.url.path) {
      case '/api/courier/dashboard':
        return moneyResponse({
          'pickups': {'awaiting_accept': 1, 'accepted': 1, 'total': 2},
          'deliveries': {'to_deliver': 1, 'out_for_delivery': 0},
          'earned_today': missingEarnings ? null : '20.25',
          'currency': 'PHP',
        });
      case '/api/courier/pickups':
        return moneyResponse({
          'data': request.url.queryParameters['filter'] == 'awaiting_accept'
              ? [
                  {
                    'id': 1,
                    'pickup_status': 'assigned',
                    'status': 'READY_FOR_PICKUP',
                  },
                ]
              : [
                  {
                    'id': 2,
                    'pickup_status': 'accepted',
                    'status': 'READY_FOR_PICKUP',
                  },
                ],
        });
      case '/api/courier/deliveries':
        return moneyResponse({
          'data': [
            {'id': 3, 'status': 'ASSIGNED_TO_RIDER', 'rider_fee': '999.99'},
          ],
          'failure_reasons': ['Customer unavailable'],
        });
      case '/api/courier/history':
        expect(request.url.queryParameters, {'page': '1'});
        return moneyResponse({
          'data': [
            for (var id = 4; id < 12; id++) {'id': id, 'status': 'DELIVERED'},
          ],
          'meta': {'current_page': 1, 'last_page': 2, 'total': 28},
        });
      default:
        fail('Unexpected courier endpoint: ${request.url.path}');
    }
  }

  test(
    'Home composes deployed reads, shares requests and preserves server earnings',
    () async {
      final paths = <String>[];
      await http.runWithClient(
        () async {
          final homes = await Future.wait([
            OrderService.home(),
            OrderService.home(),
          ]);
          final home = homes.first;
          expect(paths.toSet(), {
            '/api/courier/dashboard',
            '/api/courier/pickups',
            '/api/courier/deliveries',
            '/api/courier/history',
          });
          expect(paths, hasLength(5));
          expect(home.requests.map((row) => row.id), ['1']);
          expect(home.pickups.map((row) => row.id), ['2']);
          expect(home.deliveries.map((row) => row.id), ['3']);
          expect(home.inProgress.map((row) => row.id), ['2', '3']);
          expect(home.recent.map((row) => row.id), ['4', '5', '6', '7', '8']);
          expect(home.earnedToday, '20.25');
          expect(home.earned, isNull);
          expect(await OrderService.failureReasons(), ['Customer unavailable']);
          expect(OrderService.cachedHome()!.earnedToday, '20.25');
          await OrderService.home();
          expect(paths, hasLength(5));
          await ApiClient.clearToken();
          expect(OrderService.cachedHome(), isNull);
        },
        () => MockClient((request) async {
          paths.add(request.url.path);
          return api(request);
        }),
      );
    },
  );

  test('Missing saved dashboard earnings remain unavailable', () async {
    await http.runWithClient(
      () async {
        expect((await OrderService.home()).earnedToday, isNull);
      },
      () => MockClient((request) async => api(request, missingEarnings: true)),
    );
  });

  for (final status in [401, 403, 404, 503, 0]) {
    test(
      'Home propagates $status without trying either missing home route',
      () async {
        await http.runWithClient(
          () async {
            await expectLater(
              OrderService.home(),
              throwsA(
                isA<ApiException>().having(
                  (error) => error.statusCode,
                  'status',
                  status == 0 ? null : status,
                ),
              ),
            );
            expect(OrderService.cachedHome(), isNull);
          },
          () => MockClient((request) async {
            expect(request.url.path, isNot(endsWith('/home')));
            if (request.url.path.endsWith('/dashboard')) {
              if (status == 0) {
                throw http.ClientException('Network unavailable');
              }
              return moneyResponse({'message': 'Unavailable'}, status);
            }
            return api(request);
          }),
        );
      },
    );
  }
}
