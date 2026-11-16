import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';
import 'package:mobileshopleap_logistic_app/core/services/auth_service.dart';
import 'package:mobileshopleap_logistic_app/core/services/cash_service.dart';
import 'package:mobileshopleap_logistic_app/core/services/earnings_service.dart';
import 'package:mobileshopleap_logistic_app/models/earnings.dart';

import 'money_fixtures.dart';
import 'proof_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.clearToken();
    await ApiClient.saveToken('rider-a');
  });

  for (final status in [500, 502, 503, 504, 0, 200]) {
    test(
      'Concurrent reads share one recovery after transient $status',
      () async {
        var calls = 0;
        await http.runWithClient(
          () async {
            final reads = await Future.wait([
              ApiClient.get('/courier/dashboard'),
              ApiClient.get('/courier/dashboard'),
            ]);
            expect(reads, [
              {'earned_today': '15.00'},
              {'earned_today': '15.00'},
            ]);
            expect(calls, 2);
          },
          () => MockClient((request) async {
            expect(request.headers['authorization'], 'Bearer rider-a');
            if (++calls == 1) {
              if (status == 0) throw http.ClientException('offline');
              return status == 200
                  ? http.Response('<html>Service starting</html>', 200)
                  : http.Response('{}', status);
            }
            return moneyResponse({'earned_today': '15.00'});
          }),
        );
      },
    );
  }

  test('A persistent server failure stops after two attempts', () async {
    var calls = 0;
    await http.runWithClient(
      () async {
        await expectLater(
          ApiClient.get('/courier/dashboard'),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 503),
          ),
        );
        expect(calls, 2);
        expect(ApiClient.cachedGet('/courier/dashboard'), isNull);
      },
      () => MockClient((_) async {
        calls++;
        return http.Response('{}', 503);
      }),
    );
  });

  for (final status in [401, 403, 404, 422, 429]) {
    test('An HTTP $status is returned without automatic retry', () async {
      var calls = 0;
      await http.runWithClient(
        () async {
          await expectLater(
            ApiClient.get('/courier/cash/summary'),
            throwsA(
              isA<ApiException>().having((e) => e.statusCode, 'status', status),
            ),
          );
          expect(calls, 1);
        },
        () => MockClient((_) async {
          calls++;
          return http.Response('{}', status);
        }),
      );
    });
  }

  test(
    'Polling keeps a slow read shared without caching its outdated result',
    () async {
      final response = Completer<http.Response>();
      var calls = 0;
      await http.runWithClient(
        () async {
          final first = ApiClient.get('/courier/dashboard');
          await Future<void>.delayed(Duration.zero);
          ApiClient.invalidateCache(keepPending: true);
          final second = ApiClient.get('/courier/dashboard');
          await Future<void>.delayed(Duration.zero);
          expect(calls, 1);
          response.complete(moneyResponse({'earned_today': '15.00'}));
          expect(await first, await second);
          expect(ApiClient.cachedGet('/courier/dashboard'), isNull);
        },
        () => MockClient((_) {
          calls++;
          return response.future;
        }),
      );
    },
  );

  test('An account switch during backoff cancels the old read retry', () async {
    var calls = 0;
    await http.runWithClient(
      () async {
        final read = ApiClient.get('/courier/dashboard');
        final assertion = expectLater(read, throwsA(isA<ApiException>()));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await ApiClient.saveToken('rider-b');
        await assertion;
        expect(calls, 1);
      },
      () => MockClient((_) async {
        calls++;
        return http.Response('{}', 503);
      }),
    );
  });

  test(
    'Registration and trip writes are never automatically replayed',
    () async {
      var calls = 0;
      await http.runWithClient(
        () async {
          await expectLater(
            ApiClient.post('/courier/tracking/start'),
            throwsA(isA<ApiException>()),
          );
          final file = XFile.fromData(proofPhoto, name: 'document.jpg');
          expect(
            await AuthService.register(fields: {}, orCr: file, license: file),
            'Verification email could not be sent. Please try again later.',
          );
          expect(calls, 2);
        },
        () => MockClient((_) async {
          calls++;
          return moneyResponse({'code': 'REGISTRATION_EMAIL_UNAVAILABLE'}, 503);
        }),
      );
    },
  );

  test('Cash and earnings recover using saved server values', () async {
    final attempts = <String, int>{};
    await http.runWithClient(
      () async {
        final cash = await CashService.summary();
        expect(cash.cashOnHand, '930.00');
        final earnings = await EarningsService.summary(
          EarningsFilter(period: 'all'),
        );
        expect(earnings['total_earned'], '135.00');
        expect(attempts.values, everyElement(2));
      },
      () => MockClient((request) async {
        final path = request.url.path;
        attempts[path] = (attempts[path] ?? 0) + 1;
        if (attempts[path] == 1) return http.Response('{}', 500);
        return path.endsWith('/cash/summary')
            ? moneyResponse(cashSummary())
            : moneyResponse({'total_earned': '135.00'});
      }),
    );
  });

  test(
    'Invalid and oversized registration photos fail before upload',
    () async {
      final valid = XFile.fromData(proofPhoto, name: 'photo.jpg');
      await http.runWithClient(
        () async {
          for (final invalid in [
            XFile.fromData(
              Uint8List.fromList(utf8.encode('not an image')),
              name: 'fake.jpg',
            ),
            XFile.fromData(Uint8List(5 * 1024 * 1024 + 1), name: 'big.jpg'),
          ]) {
            expect(
              await AuthService.register(
                fields: {},
                orCr: invalid,
                license: valid,
              ),
              contains('photo'),
            );
          }
        },
        () => MockClient(
          (_) async => fail('Invalid documents must not be uploaded'),
        ),
      );
    },
  );
}
