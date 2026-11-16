import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';
import 'package:mobileshopleap_logistic_app/core/services/live_refresh.dart';
import 'package:mobileshopleap_logistic_app/models/courier.dart';
import 'package:mobileshopleap_logistic_app/screens/home/main_shell.dart';
import 'money_fixtures.dart';

void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.clearToken();
    await ApiClient.saveToken('rider-a');
    Courier.current = Courier(name: '', phone: '', vehicle: '', plate: '');
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('Push refreshes the bell within its 60 second polling throttle', (
    tester,
  ) async {
    var notificationReads = 0;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(const MaterialApp(home: MainShell()));
        await tester.pumpAndSettle();
        expect(notificationReads, 1);
        LiveRefresh.pokeNow();
        await tester.pumpAndSettle();
        expect(notificationReads, 1);
        ApiClient.invalidateCache();
        LiveRefresh.lastPush = DateTime.now();
        LiveRefresh.pokeNow();
        await tester.pumpAndSettle();
        expect(notificationReads, 2);
        await tester.pumpWidget(const SizedBox.shrink());
        LiveRefresh.pokeNow();
        await tester.pump();
        expect(notificationReads, 2);
      },
      () => MockClient((request) async {
        if (request.url.path.endsWith('/notifications')) notificationReads++;
        if (request.url.path.endsWith('/me')) {
          return moneyResponse({
            'courier': {'id': 0},
          });
        }
        return moneyResponse({
          'requests': [],
          'pickups': [],
          'deliveries': [],
          'recent': [],
          'unread': 0,
          'data': [],
          'meta': {'current_page': 1, 'last_page': 1, 'total': 0},
        });
      }),
    );
  });

  for (final status in [200, 403, 404, 0]) {
    testWidgets(
      'Notification $status distinguishes empty results from failures',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await http.runWithClient(
          () async {
            await tester.pumpWidget(const MaterialApp(home: MainShell()));
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('Notifications'));
            await tester.pumpAndSettle();
            expect(
              find.text('You are all caught up.'),
              status == 200 ? findsOneWidget : findsNothing,
            );
            if (status != 200) {
              expect(
                find.text(switch (status) {
                  403 => 'Account or hub unavailable',
                  404 => 'Money records unavailable',
                  _ => 'Unable to load current money records',
                }),
                findsOneWidget,
              );
              expect(find.text('Try again'), findsOneWidget);
            }
            await tester.pumpWidget(const SizedBox.shrink());
          },
          () => MockClient((request) async {
            if (request.url.path.endsWith('/notifications')) {
              if (status == 0) {
                throw http.ClientException('Network unavailable');
              }
              if (status != 200) {
                return moneyResponse({'message': 'Unavailable'}, status);
              }
            }
            if (request.url.path.endsWith('/dashboard')) {
              return moneyResponse({
                'requests': [],
                'pickups': [],
                'deliveries': [],
                'recent': [],
              });
            }
            if (request.url.path.endsWith('/me')) {
              return moneyResponse({
                'courier': {'id': 0},
              });
            }
            return moneyResponse({
              'unread': 0,
              'data': [],
              'meta': {'current_page': 1, 'last_page': 1, 'total': 0},
            });
          }),
        );
      },
    );
  }

  for (final kind in [
    'cash.handover.confirmed',
    'cash.handover.short',
    'rider.payout.paid',
  ]) {
    testWidgets(
      '$kind navigates natively, refreshes and offers the exact receipt',
      (tester) async {
        final payout = kind == 'rider.payout.paid';
        final reference = payout
            ? 'PO-EXACT-NOTIFICATION'
            : 'HO-EXACT-NOTIFICATION';
        final requests = <http.Request>[];
        var read = false;
        tester.view.physicalSize = const Size(1100, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await http.runWithClient(
          () async {
            await tester.pumpWidget(const MaterialApp(home: MainShell()));
            await tester.pumpAndSettle();
            // Load the destination once so the notification must refresh existing state.
            await tester.tap(find.byTooltip('Open navigation menu'));
            await tester.pumpAndSettle();
            await tester.tap(
              find.text(payout ? 'Profit / Earnings' : 'Cash').last,
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byIcon(Icons.arrow_back));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Dashboard').last);
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('Notifications'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Money event'));
            await tester.pumpAndSettle();
            expect(find.byType(BottomSheet), findsNothing);
            expect(find.text('View receipt $reference'), findsOneWidget);
            expect(read, isTrue);
            final summaries = requests
                .where(
                  (r) => r.url.path.endsWith(
                    payout ? '/earnings/summary' : '/cash/summary',
                  ),
                )
                .toList();
            expect(summaries.length, 2);
            if (payout) {
              expect(summaries.last.url.queryParameters, {'period': 'all'});
              expect(find.text('Total earned'), findsOneWidget);
            } else {
              expect(summaries.last.url.query, isEmpty);
              expect(find.text('Cash on Hand'), findsOneWidget);
            }
            expect(
              requests.any((r) => r.url.path.contains('payout-history')),
              isFalse,
            );
            await tester.pumpWidget(const SizedBox.shrink());
          },
          () => MockClient((r) async {
            requests.add(r);
            final path = r.url.path;
            if (path.endsWith('/notifications/notice-1/read')) {
              read = true;
              return moneyResponse({});
            }
            if (path.endsWith('/notifications')) {
              return moneyResponse({
                'unread': read ? 0 : 1,
                'data': [
                  {
                    'id': 'notice-1',
                    'kind': kind,
                    'title': 'Money event',
                    'body': 'Recorded by your hub',
                    'url': payout
                        ? '/api/courier/earnings/history?period=all'
                        : null,
                    'meta': {
                      'screen': payout ? 'earnings' : 'cash',
                      'reference_no': reference,
                    },
                    'read': read,
                  },
                ],
                'meta': {'current_page': 1, 'last_page': 1, 'total': 1},
              });
            }
            if (path.contains('/earnings/')) return earningsApi(r);
            if (path.endsWith('/cash/summary')) {
              return moneyResponse(cashSummary());
            }
            if (path.endsWith('/cash/history')) {
              return moneyResponse(cashHistory());
            }
            if (path.endsWith('/dashboard')) {
              return moneyResponse({
                'requests': [],
                'pickups': [],
                'deliveries': [],
                'recent': [],
                'earned_today': '0.00',
              });
            }
            if (path.endsWith('/me')) {
              return moneyResponse({
                'name': 'Rider',
                'courier': {'id': 0},
              });
            }
            return moneyResponse({
              'data': [],
              'meta': {'current_page': 1, 'last_page': 1, 'total': 0},
            });
          }),
        );
      },
    );
  }
}
