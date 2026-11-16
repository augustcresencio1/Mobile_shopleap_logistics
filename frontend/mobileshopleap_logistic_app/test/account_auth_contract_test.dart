import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_config.dart';
import 'package:mobileshopleap_logistic_app/core/services/auth_service.dart';
import 'package:mobileshopleap_logistic_app/core/services/order_service.dart';
import 'package:mobileshopleap_logistic_app/models/courier.dart';
import 'package:mobileshopleap_logistic_app/screens/auth/auth_gate.dart';
import 'package:mobileshopleap_logistic_app/screens/auth/login_screen.dart';

import 'proof_fixture.dart';

http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.clearToken();
    Courier.current = Courier(name: '', phone: '', vehicle: '', plate: '');
  });

  test(
    'API bases normalize the api prefix exactly once and reject the portal',
    () {
      for (final base in [
        'https://shopleap.shop',
        'https://shopleap.shop/',
        'https://shopleap.shop/api',
        'https://shopleap.shop/api/',
        'https://shopleap.shop/api/api/',
      ]) {
        expect(ApiConfig.normalizeBaseUrl(base), 'https://shopleap.shop/api');
      }
      expect(
        ApiConfig.normalizeBaseUrl('http://127.0.0.1:8000/api/'),
        'http://127.0.0.1:8000/api',
      );
      for (final invalid in [
        'https://logistics.shopleap.shop/api',
        '/api',
        'https://shopleap.shop/api?token=invalid',
      ]) {
        expect(() => ApiConfig.normalizeBaseUrl(invalid), throwsArgumentError);
      }
    },
  );

  test(
    'Relative paths join the API base without duplicate slashes or prefixes',
    () async {
      await http.runWithClient(
        () async {
          for (final path in ['/hubs', 'hubs', '/api/hubs', 'api/api/hubs']) {
            ApiClient.invalidateCache();
            await ApiClient.get(path, auth: false);
          }
        },
        () => MockClient((request) async {
          expect(request.url.toString(), '${ApiConfig.baseUrl}/hubs');
          return jsonResponse([]);
        }),
      );
    },
  );

  test(
    'Hub and hub barangay reads are public and parse arrays or data envelopes',
    () async {
      await ApiClient.saveToken('existing-session');
      await http.runWithClient(
        () async {
          expect((await AuthService.hubs(q: ' hub ')).single['id'], 20);
          expect(await AuthService.hubBarangays('20'), ['Poblacion']);
        },
        () => MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.headers['authorization'], isNull);
          if (request.url.path.endsWith('/barangays')) {
            expect(request.url.path, '/api/hubs/20/barangays');
            return jsonResponse({
              'data': ['Poblacion'],
            });
          }
          expect(request.url.path, '/api/hubs');
          expect(request.url.queryParameters, {'q': 'hub'});
          return jsonResponse([
            {'id': 20, 'hub_name': 'Test hub'},
          ]);
        }),
      );
    },
  );

  test(
    'Registration and OTP use the public production paths and upload keys',
    () async {
      final calls = <String>[];
      final file = XFile.fromData(proofPhoto, name: 'document.jpg');
      await http.runWithClient(
        () async {
          expect(
            await AuthService.register(
              fields: {
                'hub_id': '20',
                'email': 'rider@example.test',
                'middle_initial': '',
              },
              orCr: file,
              license: file,
            ),
            isNull,
          );
          expect(
            await AuthService.verifyOtp(' rider@example.test ', ' 123456 '),
            isNull,
          );
          expect(await AuthService.resendOtp(' rider@example.test '), isNull);
          expect(calls, [
            '/api/courier/register',
            '/api/courier/verify-otp',
            '/api/courier/resend-otp',
          ]);
        },
        () => MockClient((request) async {
          calls.add(request.url.path);
          expect(request.method, 'POST');
          expect(request.headers['authorization'], isNull);
          if (request.url.path.endsWith('/register')) {
            final multipart = latin1.decode(request.bodyBytes);
            for (final field in ['hub_id', 'or_cr_upload', 'license_upload']) {
              expect(multipart, contains('name="$field"'));
            }
            expect(multipart, isNot(contains('name="middle_initial"')));
            return jsonResponse({'message': 'Verification sent.'}, 201);
          }
          expect(jsonDecode(request.body), {
            'email': 'rider@example.test',
            if (request.url.path.endsWith('/verify-otp')) 'otp': '123456',
          });
          return jsonResponse({'message': 'Success.'});
        }),
      );
    },
  );

  test(
    'Password reset submits the OTP directly without a verify endpoint',
    () async {
      final paths = <String>[];
      await http.runWithClient(
        () async {
          await AuthService.forgotPassword(' rider@example.test ');
          final code = await AuthService.verifyResetCode(
            'rider@example.test',
            ' 123456 ',
          );
          await AuthService.resetPassword(
            ' rider@example.test ',
            code,
            'new-password',
            'new-password',
          );
          expect(paths, [
            '/api/courier/forgot-password',
            '/api/courier/reset-password',
          ]);
        },
        () => MockClient((request) async {
          paths.add(request.url.path);
          expect(request.headers['authorization'], isNull);
          expect(request.method, 'POST');
          expect(jsonDecode(request.body), {
            'email': 'rider@example.test',
            if (request.url.path.endsWith('/reset-password')) ...{
              'otp': '123456',
              'password': 'new-password',
              'password_confirmation': 'new-password',
            },
          });
          return jsonResponse({'message': 'Success.'});
        }),
      );
    },
  );

  test(
    'Pending couriers retain their bearer for me, profile, password and reapply',
    () async {
      final paths = <String>[];
      await http.runWithClient(
        () async {
          expect(
            (await AuthService.login(
              'rider@example.test',
              'password',
            )).courierStatus,
            'pending',
          );
          expect((await AuthService.me())!['courier_status'], 'pending');
          await OrderService.updateAccount({
            'province': 'Laguna',
            'municipality': 'Santa Cruz',
          });
          await OrderService.changePassword(
            'old-password',
            'new-password',
            'new-password',
          );
          expect((await AuthService.reapply())['courier_status'], 'pending');
          expect(
            paths,
            containsAll([
              '/api/courier/me',
              '/api/courier/account/profile',
              '/api/courier/account/password',
              '/api/courier/reapply',
            ]),
          );
        },
        () => MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('/login')) {
            return jsonResponse({
              'token': 'pending-token',
              'courier': {'status': 'pending'},
            });
          }
          expect(request.headers['authorization'], 'Bearer pending-token');
          expect(
            request.method,
            request.url.path.endsWith('/me') ? 'GET' : 'POST',
          );
          if (request.url.path.endsWith('/password')) {
            expect(jsonDecode(request.body), {
              'current_password': 'old-password',
              'password': 'new-password',
              'password_confirmation': 'new-password',
            });
          }
          return jsonResponse({
            'courier_status': 'pending',
            'courier': {'status': 'pending'},
          });
        }),
      );
    },
  );

  test(
    'Authenticated 401 clears the session and cache; public 401 preserves them',
    () async {
      await ApiClient.saveToken('rider-token');
      var status = 200;
      await http.runWithClient(() async {
        await ApiClient.get('/courier/me');
        expect(ApiClient.cachedGet('/courier/me'), isNotNull);
        status = 401;
        final expired = ApiClient.sessionExpired.value;
        await expectLater(
          AuthService.login('rider@example.test', 'wrong'),
          throwsA(isA<AuthException>()),
        );
        expect(await ApiClient.getToken(), 'rider-token');
        expect(ApiClient.sessionExpired.value, expired);
        await expectLater(
          ApiClient.delete('/courier/account/avatar'),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 401),
          ),
        );
        expect(await ApiClient.getToken(), isNull);
        expect(ApiClient.cachedGet('/courier/me'), isNull);
        expect(ApiClient.sessionExpired.value, expired + 1);
      }, () => MockClient((_) async => jsonResponse({}, status)));
    },
  );

  test(
    'Authenticated calls with no token expire locally without sending a request',
    () async {
      final expired = ApiClient.sessionExpired.value;
      await http.runWithClient(
        () async {
          await expectLater(
            ApiClient.post('/courier/reapply'),
            throwsA(
              isA<ApiException>().having((e) => e.statusCode, 'status', 401),
            ),
          );
          expect(ApiClient.sessionExpired.value, expired + 1);
        },
        () =>
            MockClient((_) async => fail('Missing bearer must never be sent.')),
      );
    },
  );

  test('403 and 404 show errors while preserving the token', () async {
    await ApiClient.saveToken('rider-token');
    var status = 403;
    await http.runWithClient(() async {
      await expectLater(
        AuthService.me(),
        throwsA(
          isA<AuthException>()
              .having((e) => e.statusCode, 'status', 403)
              .having((e) => e.message, 'message', contains('permission')),
        ),
      );
      status = 404;
      await expectLater(
        ApiClient.get('/courier/missing'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('not found'),
          ),
        ),
      );
      expect(await ApiClient.getToken(), 'rider-token');
    }, () => MockClient((_) async => jsonResponse({}, status)));
  });

  test(
    '422 exposes every field message and retains the validation map',
    () async {
      await ApiClient.saveToken('rider-token');
      final errors = {
        'province': ['The province field is required.'],
        'municipality': ['The municipality field is required.'],
      };
      await http.runWithClient(
        () async {
          await expectLater(
            OrderService.updateAccount({}),
            throwsA(
              isA<ApiException>()
                  .having((e) => e.statusCode, 'status', 422)
                  .having((e) => e.errors, 'errors', errors)
                  .having(
                    (e) => e.message,
                    'message',
                    errors.values.expand((v) => v).join('\n'),
                  ),
            ),
          );
        },
        () => MockClient(
          (_) async =>
              jsonResponse({'message': 'Invalid.', 'errors': errors}, 422),
        ),
      );
    },
  );

  for (final auth in [true, false]) {
    test(
      '429 exposes Retry-After for ${auth ? 'authenticated' : 'public'} calls',
      () async {
        await ApiClient.saveToken('rider-token');
        final before = DateTime.now();
        await http.runWithClient(
          () async {
            await expectLater(
              ApiClient.post('/courier/test-rate-limit', auth: auth),
              throwsA(
                isA<ApiException>()
                    .having((e) => e.statusCode, 'status', 429)
                    .having(
                      (e) => e.retryAt!.isAfter(before),
                      'retryAt',
                      isTrue,
                    )
                    .having(
                      (e) => e.retryAfter.inSeconds,
                      'retryAfter',
                      inInclusiveRange(58, 60),
                    ),
              ),
            );
            expect(await ApiClient.getToken(), 'rider-token');
          },
          () => MockClient(
            (_) async =>
                http.Response('{}', 429, headers: {'retry-after': '60'}),
          ),
        );
      },
    );
  }

  test('An old 401 cannot expire a newly signed-in account', () async {
    await ApiClient.saveToken('old-rider');
    final pending = Completer<http.Response>();
    await http.runWithClient(() async {
      final request = ApiClient.get('/courier/me');
      final check = expectLater(request, throwsA(isA<ApiException>()));
      await Future<void>.delayed(Duration.zero);
      await ApiClient.saveToken('new-rider');
      final expired = ApiClient.sessionExpired.value;
      pending.complete(jsonResponse({}, 401));
      await check;
      expect(await ApiClient.getToken(), 'new-rider');
      expect(ApiClient.sessionExpired.value, expired);
    }, () => MockClient((_) => pending.future));
  });

  testWidgets(
    'Startup shows 403 without discarding the authenticated session',
    (tester) async {
      await ApiClient.saveToken('forbidden-token');
      await http.runWithClient(
        () async {
          await tester.pumpWidget(const MaterialApp(home: AuthGate()));
          await tester.pumpAndSettle();
          expect(find.text('Account is unavailable.'), findsOneWidget);
          expect(find.text('Try again'), findsOneWidget);
          expect(find.byType(LoginScreen), findsNothing);
          expect(await ApiClient.getToken(), 'forbidden-token');
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient(
          (_) async =>
              jsonResponse({'message': 'Account is unavailable.'}, 403),
        ),
      );
    },
  );

  testWidgets(
    'A pending courier can open settings; an expired session returns to login',
    (tester) async {
      await ApiClient.saveToken('pending-token');
      var reads = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(const MaterialApp(home: AuthGate()));
          await tester.pumpAndSettle();
          expect(find.text('Waiting for approval'), findsOneWidget);
          await tester.tap(find.text('Account settings'));
          await tester.pumpAndSettle();
          expect(find.byType(LoginScreen), findsOneWidget);
          expect(await ApiClient.getToken(), isNull);
          expect(Courier.current.id, 0);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient((request) async {
          expect(request.url.path, '/api/courier/me');
          expect(request.headers['authorization'], 'Bearer pending-token');
          return ++reads == 1
              ? jsonResponse({
                  'courier_status': 'pending',
                  'courier': {'id': 10, 'status': 'pending'},
                })
              : jsonResponse({}, 401);
        }),
      );
    },
  );

  testWidgets('Rejected courier reapplication refreshes the approval status', (
    tester,
  ) async {
    await ApiClient.saveToken('rejected-token');
    var status = 'rejected';
    await http.runWithClient(
      () async {
        await tester.pumpWidget(const MaterialApp(home: AuthGate()));
        await tester.pumpAndSettle();
        expect(find.text('Registration rejected'), findsOneWidget);
        expect(find.text('Please update your address.'), findsOneWidget);
        await tester.tap(find.text('Reapply'));
        await tester.pumpAndSettle();
        expect(find.text('Waiting for approval'), findsOneWidget);
        expect(await ApiClient.getToken(), 'rejected-token');
        await tester.pumpWidget(const SizedBox.shrink());
      },
      () => MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer rejected-token');
        if (request.method == 'POST') {
          expect(request.url.path, '/api/courier/reapply');
          status = 'pending';
        }
        return jsonResponse({
          'courier_status': status,
          'courier': {
            'id': 10,
            'status': status,
            'rejection_reason': 'Please update your address.',
          },
        });
      }),
    );
  });
}
