import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_config.dart';
import 'package:mobileshopleap_logistic_app/core/services/auth_service.dart';
import 'package:mobileshopleap_logistic_app/core/services/cash_service.dart';
import 'package:mobileshopleap_logistic_app/core/services/earnings_service.dart';
import 'package:mobileshopleap_logistic_app/core/services/notification_service.dart';
import 'package:mobileshopleap_logistic_app/core/services/receipt_service.dart';
import 'package:mobileshopleap_logistic_app/models/earnings.dart';
import 'package:mobileshopleap_logistic_app/models/receipt.dart';

import 'money_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.clearToken();
  });

  test(
    'A backend switch requires login instead of reusing an old token',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'auth_token': 'legacy-local-token',
        'auth_token:https://another-backend.example/api': 'other-backend-token',
      });
      await http.runWithClient(
        () async {
          expect(await ApiClient.getToken(), isNull);
          expect(await AuthService.me(), isNull);
          await expectLater(
            CashService.summary(),
            throwsA(
              isA<ApiException>().having((e) => e.statusCode, 'status', 401),
            ),
          );
        },
        () => MockClient((_) async => fail('An old token must never be sent.')),
      );
    },
  );

  test(
    'Courier login supplies the bearer for JSON and HTML money reads; logout clears it',
    () async {
      final paths = <String>[];
      final api = Uri.parse(ApiConfig.baseUrl);
      expect(
        ApiConfig.baseUrl,
        const String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: 'https://shopleap.shop/api',
        ),
      );
      await http.runWithClient(
        () async {
          final login = await AuthService.login(
            ' rider@example.test ',
            'test-password',
            deviceName: 'test-device',
          );
          expect(login.courierStatus, 'approved');
          expect((await AuthService.me())!['courier']['status'], 'approved');
          expect((await CashService.summary()).cashOnHand, '930.00');
          expect((await CashService.history()).items, hasLength(3));
          expect(
            (await EarningsService.summary(EarningsFilter()))['paid'],
            '40.00',
          );
          expect(
            (await EarningsService.history(EarningsFilter())).items,
            hasLength(2),
          );
          expect((await EarningsService.rate())['amount'], '20.00');
          expect((await NotificationService.page()).items, isEmpty);
          for (final type in ReceiptType.values) {
            final target = ReceiptTarget(type, 'RIDER-OWNED-reference');
            final receipt = await ReceiptService.fetch(target);
            expect(receipt.html, '<html>Receipt</html>');
            expect(
              receipt.baseUri.toString(),
              '${ApiConfig.baseUrl}${target.path}',
            );
          }
          await AuthService.logout();
          expect(await ApiClient.getToken(), isNull);
          for (final path in [
            '/courier/cash/summary',
            '/courier/cash/history',
            '/courier/earnings/summary',
            '/courier/earnings/history',
            '/courier/notifications',
          ]) {
            expect(ApiClient.cachedGet(path), isNull);
          }
          expect(
            paths,
            containsAll([
              '/api/courier/login',
              '/api/courier/cash/summary',
              '/api/courier/cash/history',
              '/api/courier/earnings/summary',
              '/api/courier/earnings/history',
              '/api/courier/notifications',
              '/api/courier/receipts/cash-handovers/RIDER-OWNED-reference',
              '/api/courier/receipts/rider-payouts/RIDER-OWNED-reference',
              '/api/courier/logout',
            ]),
          );
        },
        () => MockClient((request) async {
          expect(request.url.origin, api.origin);
          expect(request.url.path, isNot(contains('/api/api/')));
          paths.add(request.url.path);
          if (request.url.path == '/api/courier/login') {
            expect(request.method, 'POST');
            expect(request.headers['authorization'], isNull);
            expect(request.headers['accept'], 'application/json');
            expect(jsonDecode(request.body), {
              'email': 'rider@example.test',
              'password': 'test-password',
              'device_name': 'test-device',
            });
            return moneyResponse({
              'token': 'deployed-rider-token',
              'courier_status': 'approved',
              'courier': {'status': 'approved'},
            });
          }
          expect(
            request.headers['authorization'],
            'Bearer deployed-rider-token',
          );
          if (request.url.path.contains('/receipts/')) {
            expect(request.headers['accept'], 'application/json, text/html');
            expect(request.followRedirects, isFalse);
            return http.Response(
              '<html>Receipt</html>',
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            );
          }
          expect(request.headers['accept'], 'application/json');
          return switch (request.url.path) {
            '/api/courier/me' => moneyResponse({
              'courier': {'status': 'approved'},
            }),
            '/api/courier/cash/summary' => moneyResponse(cashSummary()),
            '/api/courier/cash/history' => moneyResponse(cashHistory()),
            '/api/courier/notifications' => moneyResponse({
              'unread': 0,
              'data': [],
              'meta': {'current_page': 1, 'last_page': 1, 'total': 0},
            }),
            '/api/courier/logout' => moneyResponse({}),
            _ => earningsApi(request),
          };
        }),
      );
    },
  );
}
