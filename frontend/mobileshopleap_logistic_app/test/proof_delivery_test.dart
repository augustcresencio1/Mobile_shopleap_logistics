import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';
import 'package:mobileshopleap_logistic_app/core/services/delivery_photo.dart';
import 'package:mobileshopleap_logistic_app/core/services/delivery_upload_diagnostics.dart';
import 'package:mobileshopleap_logistic_app/core/services/history_service.dart';
import 'package:mobileshopleap_logistic_app/core/services/live_refresh.dart';
import 'package:mobileshopleap_logistic_app/core/services/order_service.dart';
import 'package:mobileshopleap_logistic_app/core/services/pending_delivery_store.dart';
import 'package:mobileshopleap_logistic_app/models/earnings.dart';
import 'package:mobileshopleap_logistic_app/models/order.dart';

import 'proof_fixture.dart';

const publicCode = 'SL-PUBLIC42';
const capturedAt = '2026-11-15T06:30:00Z';
http.Response response(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

Order order() => Order(
  id: '42',
  orderNumber: publicCode,
  buyer: 'Synthetic buyer',
  item: '',
  seller: '',
  from: '',
  to: '',
  fee: null,
  codAmount: '140.00',
  status: OrderStatus.delivery,
);

Future<Map<String, List<int>>> multipart(http.Request request) async {
  final boundary = MediaType.parse(
    request.headers['content-type']!,
  ).parameters['boundary']!;
  final fields = <String, List<int>>{};
  for (final part
      in latin1.decode(request.bodyBytes).split('--$boundary').skip(1)) {
    if (part.startsWith('--')) break;
    final headerEnd = part.indexOf('\r\n\r\n');
    final headers = part.substring(0, headerEnd);
    final name = RegExp(r'name="([^"]+)"').firstMatch(headers)!.group(1)!;
    fields[name] = latin1.encode(
      part.substring(headerEnd + 4, part.length - 2),
    );
    if (name == 'proof_image') {
      expect(headers.toLowerCase(), contains('content-type: image/jpeg'));
    }
  }
  return fields;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'auth_token:${ApiClient.baseUrl}': 'synthetic-token',
    });
    ApiClient.invalidateCache();
  });

  test(
    'public code, Sanctum headers, multipart proof, frozen fields and progress on retry',
    () async {
      final requests = <Map<String, List<int>>>[];
      final progress = <int>[];
      final before = LiveRefresh.deliveriesChanged.value;
      await http.runWithClient(
        () async {
          for (var attempt = 0; attempt < 2; attempt++) {
            final result = await OrderService.deliverOrder(
              publicCode,
              trackingOrderId: '42',
              amount: '140',
              proofImage: proofPhoto,
              capturedAt: capturedAt,
              latitude: 14.2,
              longitude: 121.1,
              notes: 'Parcel at buyer',
              onProgress: (sent, total) {
                expect(sent, lessThanOrEqualTo(total));
                progress.add(sent);
              },
            );
            expect(result.earning, isNull);
            expect(result.proof.uploaded, isTrue);
            expect(result.proof.capturedAt, isNull);
          }
        },
        () => MockClient((request) async {
          expect(request.method, 'POST');
          expect(
            request.url.path,
            '/api/courier/deliveries/$publicCode/delivered',
          );
          expect(request.headers['authorization'], 'Bearer synthetic-token');
          expect(request.headers['accept'], 'application/json');
          final fields = await multipart(request);
          expect(fields['proof_image'], proofPhoto);
          expect(utf8.decode(fields['amount']!), '140.00');
          expect(utf8.decode(fields['captured_at']!), capturedAt);
          expect(utf8.decode(fields['latitude']!), '14.2');
          expect(utf8.decode(fields['longitude']!), '121.1');
          expect(utf8.decode(fields['notes']!), 'Parcel at buyer');
          requests.add(fields);
          return response({
            'earning': null,
            'proof': {'uploaded': true, 'captured_at': null},
          });
        }),
      );
      expect(requests[0], requests[1]);
      expect(progress, isNotEmpty);
      expect(LiveRefresh.deliveriesChanged.value, before + 2);
    },
  );

  test(
    'optional fields omitted, zero COD and zero earning preserved',
    () async {
      await http.runWithClient(
        () async {
          final result = await OrderService.deliverOrder(
            publicCode,
            amount: '0',
            proofImage: proofPhoto,
          );
          expect(result.earning!.amount, '0.00');
          expect(result.proof.uploaded, isTrue);
        },
        () => MockClient((request) async {
          expect((await multipart(request)).keys.toSet(), {
            'amount',
            'proof_image',
          });
          return response({
            'earning': {'amount': '0.00', 'recorded_at': null},
            'proof': {'uploaded': true},
          });
        }),
      );
    },
  );

  for (final status in [201, 204, 401, 403, 409, 422, 413, 503]) {
    test(
      '$status does not complete delivery or report a failed delivery',
      () async {
        final before = LiveRefresh.deliveriesChanged.value;
        final expiry = ApiClient.sessionExpired.value;
        var refreshes = 0;
        await http.runWithClient(
          () async {
            await expectLater(
              OrderService.deliverOrder(
                publicCode,
                amount: '140',
                proofImage: proofPhoto,
              ),
              throwsA(
                isA<ApiException>()
                    .having((e) => e.statusCode, 'status', status)
                    .having(
                      (e) => e.message,
                      'message',
                      status == 422
                          ? 'Retake a clearer photo.'
                          : status == 413
                          ? contains('Reduce the photo size')
                          : isNotEmpty,
                    ),
              ),
            );
          },
          () => MockClient((request) async {
            expect(request.url.path.endsWith('/fail'), isFalse);
            if (request.method == 'GET') {
              expect(request.url.path, '/api/courier/deliveries');
              refreshes++;
              return response({'data': []});
            }
            if (status == 413) {
              return http.Response('<html>Request too large</html>', 413);
            }
            return response({
              'message': 'Server message',
              if (status == 422)
                'errors': {
                  'proof_image': ['Retake a clearer photo.'],
                },
            }, status);
          }),
        );
        expect(LiveRefresh.deliveriesChanged.value, before);
        expect(refreshes, status == 403 || status == 409 ? 1 : 0);
        expect(
          ApiClient.sessionExpired.value,
          expiry + (status == 401 ? 1 : 0),
        );
      },
    );
  }

  test('duplicate submissions are blocked while a request is active', () async {
    final sent = Completer<void>(), release = Completer<http.Response>();
    var requests = 0;
    await http.runWithClient(
      () async {
        final first = OrderService.deliverOrder(
          publicCode,
          amount: '140',
          proofImage: proofPhoto,
        );
        await sent.future;
        await expectLater(
          OrderService.deliverOrder(
            publicCode,
            amount: '140',
            proofImage: proofPhoto,
          ),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              contains('already uploading'),
            ),
          ),
        );
        release.complete(
          response({
            'earning': null,
            'proof': {'uploaded': true},
          }),
        );
        await first;
      },
      () => MockClient((_) async {
        requests++;
        sent.complete();
        return release.future;
      }),
    );
    expect(requests, 1);
  });

  for (final body in [
    <String, dynamic>{},
    {'proof': null},
    {'proof': <String, dynamic>{}},
    {
      'proof': {'uploaded': false},
    },
    {
      'proof': {'uploaded': 'true'},
    },
    {
      'proof': {'uploaded': 1},
    },
    <dynamic>[],
  ]) {
    test('HTTP 200 requires explicit proof confirmation: $body', () async {
      final before = LiveRefresh.deliveriesChanged.value;
      await http.runWithClient(() async {
        await expectLater(
          OrderService.deliverOrder(
            publicCode,
            amount: '140',
            proofImage: proofPhoto,
          ),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'actual HTTP status', 200)
                .having(
                  (e) => e.message,
                  'message',
                  contains('did not confirm'),
                ),
          ),
        );
      }, () => MockClient((_) async => response(body)));
      expect(LiveRefresh.deliveriesChanged.value, before);
      expect(DeliveryUploadDiagnostics.last!['http_status'], 200);
    });
  }

  test(
    'diagnostics omit all untrusted response data and capture the HTTP status',
    () {
      DeliveryUploadDiagnostics.record(
        publicCode,
        statusCode: 500,
        body: jsonEncode({
          'message': 'sensitive response text',
          'token': 'private-token-value',
          'proof_image': 'private-photo-content',
          'latitude': 'private-coordinate',
          'longitude': 'another-private-coordinate',
          'notes': 'private-note-value',
          'proof': {'uploaded': false, 'path': 'private-photo-path'},
        }),
      );
      final diagnostic = DeliveryUploadDiagnostics.last!;
      expect(diagnostic['http_status'], 500);
      expect(diagnostic['order_code'], publicCode);
      expect(diagnostic['response'], {
        'format': 'json_object',
        'proof_present': true,
        'proof': {'uploaded': false},
      });
      expect(jsonEncode(diagnostic), isNot(contains('private-')));
      expect(
        jsonEncode(diagnostic),
        isNot(contains('sensitive response text')),
      );
    },
  );

  test('network failure and timeout do not complete delivery', () async {
    final before = LiveRefresh.deliveriesChanged.value;
    await http.runWithClient(() async {
      await expectLater(
        OrderService.deliverOrder(
          publicCode,
          amount: '140',
          proofImage: proofPhoto,
        ),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'status', isNull),
        ),
      );
    }, () => MockClient((_) async => throw const SocketException('offline')));
    await http.runWithClient(() async {
      await expectLater(
        ApiClient.postMultipart(
          '/courier/deliveries/$publicCode/delivered',
          fields: {'amount': '140.00'},
          requiredStatusCode: 200,
          requestTimeout: const Duration(milliseconds: 20),
        ),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'status', isNull),
        ),
      );
    }, () => MockClient((_) => Completer<http.Response>().future));
    expect(LiveRefresh.deliveriesChanged.value, before);
  });

  test('invalid image and optional fields are rejected before HTTP', () async {
    await http.runWithClient(
      () async {
        for (final bytes in [
          Uint8List(0),
          Uint8List(5 * 1024 * 1024 + 1),
          img.encodePng(img.Image(width: 639, height: 800)),
          img.encodeGif(img.Image(width: 640, height: 640)),
        ]) {
          await expectLater(
            OrderService.deliverOrder(
              publicCode,
              amount: '140',
              proofImage: bytes,
            ),
            throwsA(isA<ApiException>()),
          );
        }
        for (final latitude in [double.nan, -90.1, 90.1]) {
          await expectLater(
            OrderService.deliverOrder(
              publicCode,
              amount: '140',
              proofImage: proofPhoto,
              latitude: latitude,
            ),
            throwsA(isA<ApiException>()),
          );
        }
        await expectLater(
          OrderService.deliverOrder(
            publicCode,
            amount: '140',
            proofImage: proofPhoto,
            longitude: 180.1,
          ),
          throwsA(isA<ApiException>()),
        );
        await expectLater(
          OrderService.deliverOrder(
            publicCode,
            amount: '140',
            proofImage: proofPhoto,
            notes: 'x' * 256,
          ),
          throwsA(isA<ApiException>()),
        );
        await expectLater(
          OrderService.deliverOrder(
            publicCode,
            amount: '140',
            proofImage: proofPhoto,
            capturedAt: '2026-11-15T06:30:00',
          ),
          throwsA(isA<ApiException>()),
        );
      },
      () =>
          MockClient((_) async => throw StateError('Unexpected HTTP request')),
    );
  });

  test(
    'processing bakes orientation, preserves shutter time and strips EXIF',
    () {
      final source = img.Image(width: 640, height: 800);
      img.fill(source, color: img.ColorRgb8(240, 0, 0));
      source.exif.imageIfd.orientation = 6;
      source.exif.exifIfd[0x9003] = img.IfdValueAscii('2026:11:15 14:30:00');
      source.exif.exifIfd[0x9011] = img.IfdValueAscii('+08:00');
      final result = prepareCapturedDeliveryPhoto({
        'bytes': img.encodeJpg(source),
        'received_at': '2026-11-15T06:35:00Z',
      });
      final upright = img.decodeJpg(result.bytes)!;
      expect([upright.width, upright.height], [800, 640]);
      expect(upright.getPixel(20, 20).r, greaterThan(220));
      expect(upright.exif.isEmpty, isTrue);
      expect(DateTime.parse(result.capturedAt), DateTime.parse(capturedAt));
      expect(result.bytes.length, lessThanOrEqualTo(5 * 1024 * 1024));
      expect(
        () => prepareDeliveryPhoto(
          img.encodePng(img.Image(width: 639, height: 800)),
        ),
        throwsFormatException,
      );
      // Oversized JPEG dimensions are rejected before allocating declared pixels.
      final huge = Uint8List.fromList(proofPhoto);
      for (var i = 0; i < huge.length - 9; i++) {
        if (huge[i] == 0xff && huge[i + 1] == 0xc0) {
          ByteData.sublistView(huge).setUint16(i + 5, 6000);
          ByteData.sublistView(huge).setUint16(i + 7, 8000);
          break;
        }
      }
      expect(() => prepareDeliveryPhoto(huge), throwsFormatException);
    },
  );

  test('PNG above 5 MB is compressed within bounds and WebP is accepted', () {
    final large = img.Image(width: 1800, height: 2000);
    final png = img.encodePng(large, level: 0);
    expect(png.length, greaterThan(5 * 1024 * 1024));
    final compressed = prepareDeliveryPhoto(png);
    final decoded = img.decodeJpg(compressed)!;
    expect(compressed.length, lessThanOrEqualTo(5 * 1024 * 1024));
    expect(decoded.width, 1600);
    expect(decoded.height, greaterThanOrEqualTo(640));
    final webp = img.encodeWebP(img.Image(width: 640, height: 800));
    expect(img.decodeJpg(prepareDeliveryPhoto(webp))!.width, 640);
  });

  test(
    'secure draft survives restart, isolates riders, authenticates bytes and clears after success',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'proof_delivery_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = PendingDeliveryStore(directory: () async => directory);
      final draft = PendingDelivery(
        riderId: 7,
        order: order(),
        photo: proofPhoto,
        capturedAt: capturedAt,
        amount: '140.00',
        latitude: 14.2,
        longitude: 121.1,
        notes: 'Synthetic private note',
        attempted: true,
      );
      await store.save(draft);
      final files = await Directory(
        '${directory.path}/pending_delivery',
      ).list().toList();
      expect(files, hasLength(1));
      final encrypted = await File(files.single.path).readAsBytes();
      expect(
        utf8.decode(encrypted, allowMalformed: true),
        isNot(contains('Synthetic private note')),
      );
      expect(encrypted.take(3), isNot(proofPhoto.take(3)));
      final restarted = PendingDeliveryStore(directory: () async => directory);
      final restored = (await restarted.list(7)).single;
      expect(restored.toJson(), draft.toJson());
      expect(await restarted.load(8, publicCode), isNull);
      expect(await restarted.list(8), isEmpty);
      encrypted[30] ^= 1;
      await File(files.single.path).writeAsBytes(encrypted);
      await expectLater(restarted.load(7, publicCode), throwsA(anything));
      await store.save(draft);
      await restarted.clear(7, publicCode);
      expect(await restarted.load(7, publicCode), isNull);
      expect(
        await Directory('${directory.path}/pending_delivery').list().toList(),
        isEmpty,
      );
      // Simulate interruption after success/file cleanup but before key deletion.
      await store.save(draft);
      const secureStorage = FlutterSecureStorage();
      final entry = (await secureStorage.readAll()).entries.singleWhere(
        (e) => e.key.startsWith('pending_delivery_v1_7_'),
      );
      final pointer = Map<String, dynamic>.from(jsonDecode(entry.value) as Map);
      await secureStorage.write(
        key: entry.key,
        value: jsonEncode({...pointer, 'confirmed': true}),
      );
      await File(
        '${directory.path}/pending_delivery/${pointer['file']}',
      ).delete();
      expect(await restarted.load(7, publicCode), isNull);
      expect(await restarted.list(7), isEmpty);
    },
  );

  test(
    'proof stays uploaded after repeated uncached history refreshes',
    () async {
      var uploaded = false;
      var posts = 0;
      var historyReads = 0;
      await http.runWithClient(
        () async {
          expect(
            (await HistoryService.fetch()).items.single.proof.uploaded,
            isFalse,
          );
          final delivery = await OrderService.deliverOrder(
            publicCode,
            amount: '140',
            proofImage: proofPhoto,
          );
          expect(delivery.proof.uploaded, isTrue);
          expect(
            (await HistoryService.fetch()).items.single.proof.uploaded,
            isTrue,
          );
          ApiClient.invalidateCache();
          expect(
            (await HistoryService.fetch()).items.single.proof.uploaded,
            isTrue,
          );
        },
        () => MockClient((request) async {
          if (request.method == 'POST') {
            posts++;
            uploaded = true;
            return response({
              'proof': {'uploaded': true},
            });
          }
          historyReads++;
          return response({
            'data': [
              {
                'order_id': 42,
                'order_number': publicCode,
                'outcome': 'delivered',
                'proof': {'uploaded': uploaded},
              },
            ],
            'meta': {'current_page': 1, 'last_page': 1, 'total': 1},
          });
        }),
      );
      expect(posts, 1);
      expect(historyReads, 3);
    },
  );

  test(
    'history proof is backward compatible and does not change money',
    () async {
      for (final proof in [
        null,
        {'uploaded': false},
        {'uploaded': true, 'captured_at': null},
      ]) {
        final item = EarningsHistoryItem.fromJson({
          'order_id': 42,
          'amount': '20.00',
          'proof': proof,
        });
        expect(item.proof.uploaded, proof?['uploaded'] == true);
        expect(item.proof.capturedAt, isNull);
        expect(item.amount, '20.00');
        await http.runWithClient(
          () async {
            final history = await HistoryService.fetch();
            expect(
              history.items.single.proof.uploaded,
              proof?['uploaded'] == true,
            );
            expect(history.items.single.codCollected, '140.00');
          },
          () => MockClient(
            (_) async => response({
              'data': [
                {
                  'order_number': publicCode,
                  'proof': proof,
                  'cod_collected': '140.00',
                },
              ],
            }),
          ),
        );
        ApiClient.invalidateCache();
      }
    },
  );
}
