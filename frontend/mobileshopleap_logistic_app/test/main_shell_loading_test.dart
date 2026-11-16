import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';
import 'package:mobileshopleap_logistic_app/models/courier.dart';
import 'package:mobileshopleap_logistic_app/screens/home/main_shell.dart';
import 'money_fixtures.dart';

void main() {
  testWidgets(
    'Startup shares deployed home reads; money requests start on entry',
    (tester) async {
      ApiClient.invalidateCache();
      FlutterSecureStorage.setMockInitialValues({
        'auth_token:${ApiClient.baseUrl}': 'courier-token',
      });
      Courier.current = Courier(name: '', phone: '', vehicle: '', plate: '');
      GoogleFonts.config.allowRuntimeFetching = false;
      tester.view.physicalSize = const Size(1100, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <String>[];
      await http.runWithClient(
        () async {
          await tester.pumpWidget(const MaterialApp(home: MainShell()));
          await tester.pumpAndSettle();
          for (final path in [
            '/dashboard',
            '/pickups',
            '/deliveries',
            '/history',
          ]) {
            expect(
              requests.where((p) => p.endsWith(path)).length,
              path == '/pickups' ? 2 : 1,
            );
          }
          expect(requests.any((path) => path.endsWith('/home')), isFalse);
          // Unvisited history/settings/account tabs must stay unmounted.
          expect(requests.where((p) => p.endsWith('/me')).length, 1);
          expect(
            requests.any(
              (p) => p.contains('/earnings') || p.contains('/cash/'),
            ),
            isFalse,
          );
          await tester.tap(find.byTooltip('Open navigation menu'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Profit / Earnings'));
          await tester.pumpAndSettle();
          expect(find.text('Total earned'), findsOneWidget);
          expect(
            requests.where((p) => p.endsWith('/earnings/summary')).length,
            1,
          );
          await tester.tap(find.byIcon(Icons.arrow_back));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Cash').first);
          await tester.pumpAndSettle();
          expect(find.text('Cash on Hand'), findsOneWidget);
          expect(requests.where((p) => p.endsWith('/cash/summary')).length, 1);
          expect(
            requests.any((p) => p.contains('/overview') || p.contains('/cod/')),
            isFalse,
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((r) async {
          final path = r.url.path;
          requests.add(path);
          if (path.contains('/earnings/')) return earningsApi(r);
          if (path.endsWith('/cash/summary')) {
            return moneyResponse(cashSummary(empty: true));
          }
          if (path.endsWith('/cash/history')) {
            return moneyResponse(cashHistory(empty: true));
          }
          if (path.endsWith('/dashboard')) {
            return moneyResponse({
              'requests': [],
              'pickups': [],
              'deliveries': [],
              'recent': [],
              'earned_week': '20.25',
              'earned_today': '20.25',
              'currency': 'PHP',
            });
          }
          if (path.endsWith('/me')) {
            return moneyResponse({
              'name': 'Test Rider',
              'courier': {'id': 0},
            });
          }
          return moneyResponse({
            'data': [],
            'unread': 0,
            'meta': {'current_page': 1, 'last_page': 1, 'total': 0},
          });
        }),
      );
    },
  );
}
