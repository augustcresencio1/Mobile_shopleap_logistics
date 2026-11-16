import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';
import 'package:mobileshopleap_logistic_app/core/services/live_refresh.dart';
import 'package:mobileshopleap_logistic_app/core/services/order_service.dart';
import 'package:mobileshopleap_logistic_app/screens/profit/profit_screen.dart';
import 'money_fixtures.dart';
import 'proof_fixture.dart';

void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.clearToken();
    await ApiClient.saveToken('courier-token');
    LiveRefresh.activePage = 3;
  });

  Future<void> showProfit(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ProfitScreen())),
    );
  }

  testWidgets('Push bypasses the polling throttle and replaces an older load', (
    tester,
  ) async {
    var summaries = 0;
    final inFlight = Completer<http.Response>();
    await http.runWithClient(
      () async {
        await showProfit(tester);
        await tester.pumpAndSettle();
        LiveRefresh.pokeNow();
        await tester.pumpAndSettle();
        expect(summaries, 1);

        ApiClient.invalidateCache();
        LiveRefresh.lastPush = DateTime.now();
        LiveRefresh.pokeNow();
        await tester.pump();
        expect(summaries, 2);

        ApiClient.invalidateCache();
        LiveRefresh.lastPush = DateTime.now();
        LiveRefresh.pokeNow();
        await tester.pump();
        expect(summaries, 3);
        inFlight.complete(moneyResponse(earningsSummary()));
        await tester.pumpAndSettle();
        expect(summaries, 3);
        await tester.pumpWidget(const SizedBox.shrink());
        LiveRefresh.pokeNow();
        await tester.pump();
        expect(summaries, 3);
      },
      () => MockClient((r) async {
        if (r.url.path.endsWith('/summary') && ++summaries == 2) {
          return inFlight.future;
        }
        return earningsApi(r);
      }),
    );
  });

  testWidgets(
    'Empty earnings show backend zeros and an empty delivery history',
    (tester) async {
      await http.runWithClient(
        () async {
          await showProfit(tester);
          await tester.pumpAndSettle();
          expect(
            find.text('No deliveries in this period yet'),
            findsNWidgets(2),
          );
          expect(
            find.text('No delivery rate is currently configured.'),
            findsOneWidget,
          );
          expect(find.text('Order #ORD-PUBLIC-1'), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/summary')) {
            return moneyResponse({
              'currency': 'PHP',
              'deliveries': 0,
              'total_earned': '0.00',
              'accrued_unpaid': '0.00',
              'paid': '0.00',
              'daily': [],
            });
          }
          if (request.url.path.endsWith('/rate')) {
            return moneyResponse(earningsRate(missing: true));
          }
          return moneyResponse({
            'data': [],
            'meta': {'current_page': 1, 'last_page': 1, 'total': 0},
          });
        }),
      );
    },
  );

  testWidgets(
    'Accrued and paid cards, nullable pay, proof, badges and paging use documented reads',
    (tester) async {
      final requests = <http.Request>[];
      await http.runWithClient(
        () async {
          await showProfit(tester);
          await tester.pumpAndSettle();
          expect(find.text('Accrued / unpaid'), findsNWidgets(2));
          expect(find.text('Paid'), findsNWidgets(2));
          expect(find.text('₱60.00'), findsOneWidget);
          expect(find.text('₱40.00'), findsOneWidget);
          expect(find.text('Not recorded'), findsOneWidget);
          expect(find.text('₱0.00'), findsOneWidget);
          expect(find.text('Proof uploaded'), findsOneWidget);
          expect(
            find.textContaining('Totals follow order delivery dates'),
            findsOneWidget,
          );
          await tester.tap(find.text('Load more'));
          await tester.pumpAndSettle();
          expect(find.text('Order #ORD-PUBLIC-2'), findsOneWidget);
          expect(find.text('₱12.50'), findsOneWidget);
          expect(find.text('Load more'), findsNothing);
          expect(requests.last.url.queryParameters, {
            'period': 'month',
            'page': '2',
          });
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((r) async {
          requests.add(r);
          return earningsApi(r, last: 2);
        }),
      );
    },
  );

  testWidgets(
    'Changing a delivery-date filter discards a slower previous period response',
    (tester) async {
      final old = Completer<http.Response>();
      await http.runWithClient(
        () async {
          await showProfit(tester);
          await tester.pump();
          await tester.tap(find.text('Today'));
          await tester.pumpAndSettle();
          expect(find.text('₱7.25'), findsOneWidget);
          old.complete(moneyResponse(earningsSummary(total: '999.99')));
          await tester.pumpAndSettle();
          expect(find.text('₱999.99'), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((r) async {
          if (r.url.path.endsWith('/summary') &&
              r.url.queryParameters['period'] == 'month') {
            return old.future;
          }
          return earningsApi(r, total: '7.25');
        }),
      );
    },
  );

  for (final status in [403, 404, 503]) {
    testWidgets('Earnings $status removes stale earnings and offers retry', (
      tester,
    ) async {
      var fail = false;
      await http.runWithClient(
        () async {
          await showProfit(tester);
          await tester.pumpAndSettle();
          fail = true;
          LiveRefresh.deliveryCompleted();
          await tester.pumpAndSettle();
          if (status == 503) {
            await tester.pump(const Duration(milliseconds: 800));
            await tester.pumpAndSettle();
          }
          expect(find.text('₱60.00'), findsNothing);
          expect(
            find.text(switch (status) {
              403 => 'Account or hub unavailable',
              404 => 'Money records unavailable',
              _ => 'Unable to load current money records',
            }),
            findsOneWidget,
          );
          fail = false;
          await tester.tap(find.text('Try again'));
          await tester.pumpAndSettle();
          expect(find.text('₱60.00'), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient(
          (r) async => fail ? moneyResponse({}, status) : earningsApi(r),
        ),
      );
    });
  }

  for (final unauthorized in [true, false]) {
    testWidgets(
      unauthorized
          ? 'Earnings 401 clears the session and requests sign-in'
          : 'Earnings network failure shows retry instead of empty balances',
      (tester) async {
        await http.runWithClient(
          () async {
            await showProfit(tester);
            await tester.pumpAndSettle();
            expect(
              find.text(
                unauthorized
                    ? 'Please sign in again'
                    : 'Unable to load current money records',
              ),
              findsOneWidget,
            );
            expect(find.text('Total earned'), findsNothing);
            if (unauthorized) expect(await ApiClient.getToken(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
          () => MockClient((_) async {
            if (unauthorized) {
              return moneyResponse({'message': 'Unauthenticated.'}, 401);
            }
            throw http.ClientException('Network unavailable');
          }),
        );
      },
    );
  }

  testWidgets(
    'Resume invalidation replaces an earnings request already in flight',
    (tester) async {
      final old = Completer<http.Response>();
      var summaries = 0;
      await http.runWithClient(
        () async {
          await showProfit(tester);
          await tester.pump();
          ApiClient.invalidateCache();
          LiveRefresh.pokeNow();
          await tester.pumpAndSettle();
          expect(find.text('₱7.25'), findsOneWidget);
          old.complete(moneyResponse(earningsSummary(total: '999.99')));
          await tester.pumpAndSettle();
          expect(find.text('₱999.99'), findsNothing);
          expect(summaries, 2);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((r) async {
          if (r.url.path.endsWith('/summary') && ++summaries == 1) {
            return old.future;
          }
          return earningsApi(r, total: '7.25');
        }),
      );
    },
  );

  testWidgets(
    'Screen reentry and delivery retries refetch saved totals without adding earnings',
    (tester) async {
      var summaries = 0;
      await http.runWithClient(
        () async {
          await showProfit(tester);
          await tester.pumpAndSettle();
          LiveRefresh.activePage = 0;
          LiveRefresh.pokeNow();
          LiveRefresh.activePage = 3;
          LiveRefresh.pokeNow();
          await tester.pumpAndSettle();
          for (var attempt = 0; attempt < 2; attempt++) {
            await OrderService.deliverOrder(
              'ORD-PUBLIC',
              amount: '930.00',
              proofImage: proofPhoto,
            );
            await tester.pumpAndSettle();
            expect(find.text('₱60.00'), findsOneWidget);
          }
          expect(summaries, 4);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((r) async {
          if (r.method == 'POST') {
            return moneyResponse({
              'earning': {'amount': '20.00'},
              'proof': {'uploaded': true},
            });
          }
          if (r.url.path.endsWith('/summary')) summaries++;
          return earningsApi(r);
        }),
      );
    },
  );

  testWidgets(
    'Account change immediately clears earnings; no-rate and nullable pay fit a phone',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await http.runWithClient(() async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: ProfitScreen())),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Order #ORD-PUBLIC-1'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        expect(find.text('Not recorded'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await ApiClient.saveToken('another-rider');
        await tester.pumpAndSettle();
        expect(find.text('Order #ORD-PUBLIC-1'), findsNothing);
        expect(find.text('₱60.00'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => MockClient((r) async => earningsApi(r, missingRate: true)));
    },
  );
}
