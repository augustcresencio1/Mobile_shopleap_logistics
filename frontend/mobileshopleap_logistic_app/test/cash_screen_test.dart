import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';
import 'package:mobileshopleap_logistic_app/core/services/live_refresh.dart';
import 'package:mobileshopleap_logistic_app/screens/money/cash_screen.dart';
import 'money_fixtures.dart';

void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.clearToken();
    await ApiClient.saveToken('rider-a');
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: CashScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('Push bypasses the polling throttle and replaces an older load', (
    tester,
  ) async {
    var summaries = 0;
    final inFlight = Completer<http.Response>();
    await http.runWithClient(
      () async {
        await open(tester);
        LiveRefresh.pokeNow();
        await tester.pumpAndSettle();
        expect(
          summaries,
          1,
        ); // No push and less than 30 seconds since the load.

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
        inFlight.complete(moneyResponse(cashSummary()));
        await tester.pumpAndSettle();
        expect(summaries, 3);
        await tester.pumpWidget(const SizedBox.shrink());
        LiveRefresh.pokeNow();
        await tester.pump();
        expect(summaries, 3); // Listener was disposed.
      },
      () => MockClient((r) async {
        if (r.url.path.endsWith('/summary') && ++summaries == 2) {
          return inFlight.future;
        }
        return moneyResponse(
          r.url.path.endsWith('/summary') ? cashSummary() : cashHistory(),
        );
      }),
    );
  });

  testWidgets(
    'Empty cash shows zero outstanding cash and no parcels or handovers',
    (tester) async {
      await http.runWithClient(
        () async {
          await open(tester);
          expect(find.text('₱0.00'), findsNWidgets(2));
          expect(find.text('No outstanding COD cash.'), findsOneWidget);
          expect(find.text('No cash handovers yet.'), findsOneWidget);
          expect(find.textContaining('Submit'), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient(
          (r) async => moneyResponse(
            r.url.path.endsWith('/summary')
                ? cashSummary(empty: true)
                : cashHistory(empty: true),
          ),
        ),
      );
    },
  );

  testWidgets(
    'Balances do not double-count shortage, all statuses have receipts and pages append',
    (tester) async {
      await http.runWithClient(
        () async {
          await open(tester);
          expect(find.text('₱930.00'), findsOneWidget);
          expect(find.text('₱30.00'), findsOneWidget);
          expect(find.textContaining('₱960.00'), findsNothing);
          expect(find.text('ORD-ORIGINAL-RIDER'), findsOneWidget);
          for (final status in ['Confirmed', 'Short', 'Settled']) {
            expect(find.text(status), findsOneWidget);
          }
          expect(find.text('View receipt HO-short-1'), findsOneWidget);
          await tester.tap(find.text('Load more handovers'));
          await tester.pumpAndSettle();
          expect(find.text('HO-confirmed-2'), findsOneWidget);
          expect(find.text('Load more handovers'), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient(
          (r) async => moneyResponse(
            r.url.path.endsWith('/summary')
                ? cashSummary()
                : cashHistory(
                    page: int.parse(r.url.queryParameters['page']!),
                    last: 2,
                  ),
          ),
        ),
      );
    },
  );

  testWidgets(
    'Pull-to-refresh resets history to page one; resume and delivery events refresh cash',
    (tester) async {
      var summaryReads = 0;
      final pages = <String>[];
      await http.runWithClient(
        () async {
          await open(tester);
          await tester.tap(find.text('Load more handovers'));
          await tester.pumpAndSettle();
          await tester.fling(
            find.byType(ListView),
            const Offset(0, 1200),
            1500,
          );
          await tester.pumpAndSettle();
          await tester.drag(find.byType(ListView), const Offset(0, 500));
          await tester.pumpAndSettle();
          expect(pages, ['1', '2', '1']);
          LiveRefresh.deliveryCompleted();
          await tester.pumpAndSettle();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
          expect(summaryReads, 4);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((r) async {
          if (r.url.path.endsWith('/summary')) {
            summaryReads++;
            return moneyResponse(cashSummary());
          }
          pages.add(r.url.queryParameters['page']!);
          return moneyResponse(
            cashHistory(page: int.parse(pages.last), last: 2),
          );
        }),
      );
    },
  );

  for (final status in [403, 404, 503]) {
    testWidgets('$status hides stale balances and supports a manual retry', (
      tester,
    ) async {
      var fail = false;
      await http.runWithClient(
        () async {
          await open(tester);
          fail = true;
          LiveRefresh.deliveryCompleted();
          await tester.pumpAndSettle();
          expect(find.text('₱930.00'), findsNothing);
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
          expect(find.text('₱930.00'), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient(
          (r) async => fail
              ? moneyResponse({'message': 'Unavailable'}, status)
              : moneyResponse(
                  r.url.path.endsWith('/summary')
                      ? cashSummary()
                      : cashHistory(),
                ),
        ),
      );
    });
  }

  for (final unauthorized in [true, false]) {
    testWidgets(
      unauthorized
          ? 'Cash 401 clears the session and requests sign-in'
          : 'Cash network failure shows retry instead of empty balances',
      (tester) async {
        await http.runWithClient(
          () async {
            await open(tester);
            expect(
              find.text(
                unauthorized
                    ? 'Please sign in again'
                    : 'Unable to load current money records',
              ),
              findsOneWidget,
            );
            expect(find.text('No outstanding COD cash.'), findsNothing);
            expect(find.text('ORD-ORIGINAL-RIDER'), findsNothing);
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

  testWidgets('Resume invalidation replaces a cash request already in flight', (
    tester,
  ) async {
    final old = Completer<http.Response>();
    var summaries = 0;
    LiveRefresh.activePage = 9;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: CashScreen(embedded: true))),
        );
        await tester.pump();
        ApiClient.invalidateCache();
        LiveRefresh.pokeNow();
        await tester.pumpAndSettle();
        expect(find.text('₱0.00'), findsNWidgets(2));
        old.complete(moneyResponse(cashSummary(cash: '999.99')));
        await tester.pumpAndSettle();
        expect(find.text('₱999.99'), findsNothing);
        expect(summaries, 2);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      () => MockClient((r) async {
        if (r.url.path.endsWith('/summary')) {
          if (++summaries == 1) {
            return old.future;
          }
          return moneyResponse(cashSummary(empty: true));
        }
        return moneyResponse(cashHistory(empty: true));
      }),
    );
  });

  testWidgets('Logout discards visible and in-flight cash records', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    var delayed = false;
    await http.runWithClient(
      () async {
        await open(tester);
        delayed = true;
        LiveRefresh.deliveryCompleted();
        await tester.pump();
        await ApiClient.clearToken();
        pending.complete(moneyResponse(cashSummary(cash: '999.99')));
        await tester.pumpAndSettle();
        expect(find.text('₱999.99'), findsNothing);
        expect(find.text('ORD-ORIGINAL-RIDER'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      () => MockClient(
        (r) async => r.url.path.endsWith('/summary')
            ? delayed
                  ? pending.future
                  : moneyResponse(cashSummary())
            : moneyResponse(cashHistory()),
      ),
    );
  });
}
