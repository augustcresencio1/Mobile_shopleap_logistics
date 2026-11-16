import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';

http.Response response(Object data) => http.Response(jsonEncode(data), 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ApiClient.invalidateCache();
    FlutterSecureStorage.setMockInitialValues({
      'auth_token:${ApiClient.baseUrl}': 'rider-a',
    });
  });

  test('Location telemetry preserves already-loaded screen data', () async {
    var reads = 0;
    await http.runWithClient(
      () async {
        await ApiClient.get('/courier/home');
        final revision = ApiClient.revision;
        await ApiClient.post(
          '/courier/tracking/start',
          body: {},
          refreshCache: false,
        );
        await ApiClient.put(
          '/courier/tracking/location',
          body: {},
          refreshCache: false,
        );
        await ApiClient.get('/courier/home');
        expect(ApiClient.revision, revision);
        expect(reads, 1);
      },
      () => MockClient((request) async {
        if (request.method == 'GET') reads++;
        return response({});
      }),
    );
  });

  test(
    'Concurrent identical GETs share one request and reuse the result',
    () async {
      final pending = Completer<http.Response>();
      var calls = 0;
      await http.runWithClient(
        () async {
          final first = ApiClient.get('/courier/home');
          final second = ApiClient.get('/courier/home');
          await Future<void>.delayed(Duration.zero);
          expect(calls, 1);
          pending.complete(response({'earned_today': '20.25'}));
          expect(await first, await second);
          expect(await ApiClient.get('/courier/home'), {
            'earned_today': '20.25',
          });
          expect(calls, 1);
        },
        () => MockClient((_) {
          calls++;
          return pending.future;
        }),
      );
    },
  );

  test(
    'Mutations and explicit refresh bypass previously cached totals',
    () async {
      var reads = 0;
      await http.runWithClient(
        () async {
          await ApiClient.get('/courier/home');
          await ApiClient.get('/courier/home', forceRefresh: true);
          expect(reads, 2);
          await ApiClient.post(
            '/courier/deliveries/1/delivered',
            body: {'amount': '140.00'},
          );
          expect(ApiClient.cachedGet('/courier/home'), isNull);
          await ApiClient.get('/courier/home');
          expect(reads, 3);
        },
        () => MockClient((request) async {
          if (request.method == 'GET') reads++;
          return response({'revision': reads});
        }),
      );
    },
  );

  test(
    'An old account request cannot populate the next account cache',
    () async {
      final oldResponse = Completer<http.Response>();
      await http.runWithClient(
        () async {
          final old = ApiClient.get('/courier/home');
          await Future<void>.delayed(Duration.zero);
          await ApiClient.saveToken('rider-b');
          expect(await ApiClient.get('/courier/home'), {'rider': 'b'});
          oldResponse.complete(response({'rider': 'a'}));
          await old;
          expect(ApiClient.cachedGet('/courier/home'), {'rider': 'b'});
          await ApiClient.clearToken();
          expect(ApiClient.cachedGet('/courier/home'), isNull);
        },
        () => MockClient(
          (request) async =>
              request.headers['Authorization'] == 'Bearer rider-a'
              ? oldResponse.future
              : response({'rider': 'b'}),
        ),
      );
    },
  );
}
