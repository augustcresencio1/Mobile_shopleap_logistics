import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';
import 'package:mobileshopleap_logistic_app/core/services/cash_service.dart';
import 'package:mobileshopleap_logistic_app/core/services/earnings_service.dart';
import 'package:mobileshopleap_logistic_app/core/services/notification_service.dart';
import 'package:mobileshopleap_logistic_app/core/services/receipt_service.dart';
import 'package:mobileshopleap_logistic_app/core/services/order_service.dart';
import 'package:mobileshopleap_logistic_app/core/services/live_refresh.dart';
import 'package:mobileshopleap_logistic_app/models/cash.dart';
import 'package:mobileshopleap_logistic_app/models/earnings.dart';
import 'package:mobileshopleap_logistic_app/models/courier_notification.dart';
import 'package:mobileshopleap_logistic_app/models/receipt.dart';
import 'money_fixtures.dart';
import 'proof_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.clearToken();
    await ApiClient.saveToken('rider-a');
  });

  test('Empty cash, decimal strings, nulls and shortages stay exact', () {
    expect(
      EarningsHistoryItem.fromJson({'order_id': 42}).reference,
      'Reference unavailable',
    );
    expect(
      EarningsHistoryItem.fromJson({'order_id': 'ORD-OPAQUE'}).reference,
      'ORD-OPAQUE',
    );
    final empty = CashSummary.fromJson(cashSummary(empty: true));
    expect(empty.cashOnHand, '0.00');
    expect(empty.shortageAmount, '0.00');
    expect(empty.orders, isEmpty);
    final outstanding = CashSummary.fromJson(cashSummary());
    expect(outstanding.cashOnHand, '930.00'); // Already includes the shortage.
    expect(outstanding.shortageAmount, '30.00');
    expect(outstanding.orders.single.amount, '930.00');
    final unknown = CashSummary.fromJson({
      'cash_on_hand': null,
      'shortage_amount': null,
    });
    expect(unknown.cashOnHand, isNull);
    final huge = CashSummary.fromJson(
      cashSummary(cash: '12345678901234567890.01'),
    );
    expect(huge.cashOnHand, '12345678901234567890.01');
  });

  test(
    'Full handover, shortage and settlement use received amounts and original dates',
    () {
      final rows = CashHistoryPage.fromJson(cashHistory()).items;
      expect(rows.map((r) => r.status), ['confirmed', 'short', 'settled']);
      expect(rows.map((r) => r.amount), ['930.00', '900.00', '930.00']);
      expect(rows.map((r) => r.confirmedAt).toSet().length, 1);
      expect(rows.map((r) => r.reference), [
        'HO-confirmed-1',
        'HO-short-1',
        'HO-settled-1',
      ]);
    },
  );

  test(
    'Cash paging, refresh and historical ownership never select a rider or current hub',
    () async {
      final requests = <http.Request>[];
      await http.runWithClient(
        () async {
          expect(
            (await CashService.summary()).orders.single.orderNumber,
            'ORD-ORIGINAL-RIDER',
          );
          await CashService.summary();
          await CashService.summary(forceRefresh: true);
          expect((await CashService.history(page: 2)).currentPage, 2);
          expect(() => CashService.history(page: 0), throwsArgumentError);
          expect(requests.length, 3);
          expect(requests.last.url.queryParameters, {'page': '2'});
          expect(requests.take(2).every((r) => r.url.query.isEmpty), isTrue);
        },
        () => MockClient((request) async {
          requests.add(request);
          expect(request.headers['Authorization'], 'Bearer rider-a');
          expect(request.headers['Accept'], 'application/json');
          expect(request.url.path, startsWith('/api/courier/cash/'));
          expect(request.url.path, isNot(contains('/api/api/')));
          return moneyResponse(
            request.url.path.endsWith('/summary')
                ? cashSummary()
                : cashHistory(page: 2, last: 2),
          );
        }),
      );
    },
  );

  test(
    'Accrued and paid are separate, nullable historical pay never uses the current rate',
    () async {
      await http.runWithClient(() async {
        final data = await EarningsService.overview(EarningsFilter());
        expect(data.accruedUnpaid, '20.00');
        expect(data.paid, '40.00');
        expect(data.history.items.first.amount, isNull);
        expect(data.history.items.first.payoutStatus, 'accrued');
        expect(data.history.items.last.amount, '0.00');
        expect(data.history.items.last.payoutStatus, 'paid');
      }, () => MockClient((request) async => earningsApi(request)));
    },
  );

  test(
    'Summary and all history pages use delivery-period filters, never payout-date filters',
    () async {
      final requests = <http.Request>[];
      final filter = EarningsFilter(
        period: 'custom',
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 15),
      );
      await http.runWithClient(
        () async {
          await EarningsService.overview(filter);
          await EarningsService.history(filter, page: 2);
          for (final r in requests.where(
            (r) => !r.url.path.endsWith('/rate'),
          )) {
            expect({...r.url.queryParameters}..remove('page'), filter.query);
          }
          expect(requests.map((r) => r.url.path).toSet(), {
            '/api/courier/earnings/summary',
            '/api/courier/earnings/rate',
            '/api/courier/earnings/history',
          });
        },
        () => MockClient((r) async {
          requests.add(r);
          return earningsApi(r, last: 2);
        }),
      );
    },
  );

  for (final type in ReceiptType.values) {
    test(
      'Authenticated ${type.path} HTML is uncached and preserves the backend base URL',
      () async {
        var calls = 0;
        final target = ReceiptTarget(type, 'EXACT-reference +/42');
        await http.runWithClient(
          () async {
            final receipt = await ReceiptService.fetch(target);
            await ReceiptService.fetch(target);
            expect(calls, 2);
            expect(receipt.html, contains('<html>'));
            expect(
              receipt.baseUri.resolve('/receipt.css').toString(),
              Uri.parse(ApiClient.baseUrl).resolve('/receipt.css').toString(),
            );
            expect(ApiClient.cachedGet(target.path), isNull);
          },
          () => MockClient((r) async {
            calls++;
            expect(r.headers['authorization'], 'Bearer rider-a');
            expect(r.headers['accept'], 'application/json, text/html');
            expect(r.headers['cache-control'], 'no-store');
            expect(r.followRedirects, isFalse);
            expect(r.url.pathSegments.last, target.reference);
            expect(r.url.query, isEmpty);
            return http.Response(
              '<html><link href="/receipt.css">Official receipt</html>',
              200,
              headers: {
                'content-type': 'text/html; charset=utf-8',
                'cache-control': 'private, no-store',
              },
            );
          }),
        );
      },
    );
  }

  for (final status in [401, 403, 404, 422, 503]) {
    test(
      'Receipt $status uses common error handling; only 401 expires the session',
      () async {
        final expired = ApiClient.sessionExpired.value;
        await http.runWithClient(
          () async {
            await expectLater(
              ReceiptService.fetch(
                const ReceiptTarget(ReceiptType.cashHandover, 'HO-exact'),
              ),
              throwsA(
                isA<ApiException>().having(
                  (e) => e.statusCode,
                  'status',
                  status,
                ),
              ),
            );
            expect(
              ApiClient.sessionExpired.value,
              expired + (status == 401 ? 1 : 0),
            );
            expect(
              await ApiClient.getToken(),
              status == 401 ? null : 'rider-a',
            );
          },
          () => MockClient(
            (_) async =>
                moneyResponse({'message': 'Receipt unavailable'}, status),
          ),
        );
      },
    );
  }

  test('JSON and redirects cannot be mistaken for an HTML receipt', () async {
    for (final res in [
      moneyResponse({}),
      http.Response('', 302, headers: {'location': 'https://example.com'}),
    ]) {
      await http.runWithClient(() async {
        await expectLater(
          ReceiptService.fetch(
            const ReceiptTarget(ReceiptType.riderPayout, 'PO-exact'),
          ),
          throwsA(isA<ApiException>()),
        );
      }, () => MockClient((_) async => res));
    }
  });

  test(
    'Retry-After throttles authenticated reads across money endpoints',
    () async {
      var calls = 0;
      await http.runWithClient(
        () async {
          await expectLater(
            CashService.summary(),
            throwsA(
              isA<ApiException>().having(
                (e) => e.retryAfter.inSeconds,
                'retry',
                greaterThan(50),
              ),
            ),
          );
          await expectLater(
            EarningsService.summary(EarningsFilter()),
            throwsA(
              isA<ApiException>().having((e) => e.statusCode, 'status', 429),
            ),
          );
          expect(calls, 1);
        },
        () => MockClient((_) async {
          calls++;
          return http.Response('{}', 429, headers: {'retry-after': '60'});
        }),
      );
    },
  );

  test('Retry-After also supports an HTTP date', () async {
    await http.runWithClient(
      () async {
        await expectLater(
          CashService.summary(),
          throwsA(
            isA<ApiException>().having(
              (e) => e.retryAt,
              'retry date',
              DateTime.utc(2030, 1, 1),
            ),
          ),
        );
      },
      () => MockClient(
        (_) async => http.Response(
          '{}',
          429,
          headers: {'retry-after': 'Tue, 01 Jan 2030 00:00:00 GMT'},
        ),
      ),
    );
  });

  test(
    'An in-flight old rider cash response is rejected after account change',
    () async {
      final pending = Completer<http.Response>();
      await http.runWithClient(
        () async {
          final old = CashService.summary();
          final rejected = expectLater(old, throwsA(isA<ApiException>()));
          await Future<void>.delayed(Duration.zero);
          await ApiClient.saveToken('rider-b');
          pending.complete(moneyResponse(cashSummary()));
          await rejected;
          expect((await CashService.summary()).cashOnHand, '0.00');
          await ApiClient.clearToken();
          expect(ApiClient.cachedGet('/courier/cash/summary'), isNull);
        },
        () => MockClient(
          (r) async => r.headers['authorization'] == 'Bearer rider-a'
              ? pending.future
              : moneyResponse(cashSummary(empty: true)),
        ),
      );
    },
  );

  test(
    'Delivery retries resend required proof, invalidate balances and never add money locally',
    () async {
      final before = LiveRefresh.deliveriesChanged.value;
      await http.runWithClient(
        () async {
          for (var attempt = 0; attempt < 2; attempt++) {
            await CashService.summary();
            final result = await OrderService.deliverOrder(
              'ORD-EXACT',
              amount: '930.00',
              proofImage: proofPhoto,
            );
            expect(result.earning!.amount, '20.00');
            expect(ApiClient.cachedGet('/courier/cash/summary'), isNull);
            expect((await CashService.summary()).cashOnHand, '930.00');
          }
          expect(LiveRefresh.deliveriesChanged.value, before + 2);
        },
        () => MockClient((r) async {
          if (r.method == 'GET') return moneyResponse(cashSummary());
          expect(r.url.path, '/api/courier/deliveries/ORD-EXACT/delivered');
          expect(
            r.headers['content-type'],
            startsWith('multipart/form-data; boundary='),
          );
          final multipart = latin1.decode(r.bodyBytes);
          expect(multipart, contains('name="proof_image"'));
          expect(multipart, contains('name="amount"\r\n\r\n930.00'));
          return moneyResponse({
            'proof': {'uploaded': true},
            'earning': {'amount': '20.00', 'currency': 'PHP'},
          });
        }),
      );
    },
  );

  test(
    'Notification pages retain unread, metadata and exact payout receipt references',
    () async {
      await http.runWithClient(
        () async {
          final page = await NotificationService.page(page: 2);
          expect(page.currentPage, 2);
          expect(page.unread, 3);
          expect(
            page.items.single.moneyDestination!.receipt!.reference,
            'PO-EXACT',
          );
          await NotificationService.markRead('uuid/escaped');
          await NotificationService.markAllRead();
        },
        () => MockClient((r) async {
          if (r.method == 'POST') return moneyResponse({});
          expect(r.url.queryParameters, {'page': '2'});
          return moneyResponse({
            'unread': 3,
            'data': [
              {
                'kind': 'rider.payout.paid',
                'url': null,
                'meta': {'screen': 'earnings', 'reference_no': 'PO-EXACT'},
              },
            ],
            'meta': {'current_page': 2, 'last_page': 2, 'total': 21},
          });
        }),
      );
    },
  );

  test(
    'Money routing tolerates null URLs and unknown kinds, and only maps known relative API paths',
    () {
      for (final kind in [
        'cash.handover.confirmed',
        'cash.handover.short',
        'rider.payout.paid',
      ]) {
        final n = CourierNotification.fromJson({
          'kind': kind,
          'url': null,
          'meta': {'reference_no': 'opaque-reference'},
        });
        expect(
          n.moneyDestination!.screen,
          kind.startsWith('cash.')
              ? NotificationScreen.cash
              : NotificationScreen.earnings,
        );
        expect(n.moneyDestination!.receipt!.reference, 'opaque-reference');
      }
      expect(
        CourierNotification.fromJson({
          'url': '/api/courier/earnings/history?period=all',
        }).moneyDestination!.receipt,
        isNull,
      );
      for (final url in [
        null,
        'https://evil.example/api/courier/cash/history',
        '//evil.example/api/courier/cash/history',
        '/api/unknown',
        'javascript:alert(1)',
      ]) {
        expect(
          CourierNotification.fromJson({
            'kind': 'unknown',
            'url': url,
          }).moneyDestination,
          isNull,
        );
      }
    },
  );
}
