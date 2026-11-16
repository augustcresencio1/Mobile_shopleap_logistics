import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:mobileshopleap_logistic_app/core/services/account_service.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';
import 'package:mobileshopleap_logistic_app/models/courier.dart';
import 'package:mobileshopleap_logistic_app/screens/account/account_screen.dart';

import 'proof_fixture.dart';

const photoUrl =
    'https://photos.example.test/courier_photos/10/new.jpg?signature=synthetic';
const previousPhotoUrl =
    'https://photos.example.test/courier_photos/10/old.jpg';

class MemoryPicker extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile.fromData(proofPhoto, name: 'profile.jpg');
}

Map<String, dynamic> profile({String? photo}) => {
  'user': {'id': 1, 'name': 'Test Rider', 'email': 'rider@example.test'},
  'name': 'Test Rider',
  'email': 'rider@example.test',
  'courier': {
    'id': 10,
    'first_name': 'Test',
    'last_name': 'Rider',
    'contact_no': '09123456789',
    'vehicle_type': 'Motor',
    'plate_number': 'ABC123',
    'province': 'Laguna',
    'municipality': 'Santa Cruz',
    'barangay': 'Poblacion',
    'street_address': '123 Main Street',
    'photo_url': photo,
  },
};

http.Response response(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ImagePickerPlatform originalPicker;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await ApiClient.clearToken();
    await ApiClient.saveToken('synthetic-courier-token');
    Courier.current = Courier.fromJson(profile());
    originalPicker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = MemoryPicker();
  });

  tearDown(() {
    ImagePickerPlatform.instance = originalPicker;
  });

  test(
    'Upload uses the avatar route, bearer and locally validated photo field',
    () async {
      late http.Request uploaded;
      await http.runWithClient(
        () async {
          final result = await AccountService.uploadPhoto(
            XFile.fromData(proofPhoto, name: 'profile.jpg'),
          );
          expect(Courier.fromJson(result).photoUrl, photoUrl);
          expect(Courier.fromJson(result).id, 10);
        },
        () => MockClient((request) async {
          uploaded = request;
          return response({
            'message': 'Photo updated.',
            ...profile(photo: photoUrl),
          });
        }),
      );
      expect(uploaded.method, 'POST');
      expect(uploaded.url.path, '/api/courier/account/avatar');
      expect(
        uploaded.headers['authorization'],
        'Bearer synthetic-courier-token',
      );
      expect(
        uploaded.headers['content-type'],
        startsWith('multipart/form-data;'),
      );
      expect(latin1.decode(uploaded.bodyBytes), contains('name="photo"'));
      expect(uploaded.bodyBytes, containsAllInOrder(proofPhoto));
    },
  );

  test('Avatar-only responses preserve the rest of the account', () {
    final before = Courier.fromJson(profile());
    final updated = Courier.fromJson({
      'avatar_url': photoUrl,
    }, fallback: before);
    expect(updated.photoUrl, photoUrl);
    expect(updated.id, 10);
    expect(updated.email, 'rider@example.test');
    expect(updated.province, 'Laguna');
    expect(updated.municipality, 'Santa Cruz');
    expect(
      Courier.fromJson({'avatar_url': null}, fallback: updated).photoUrl,
      isEmpty,
    );
  });

  test('Remove uses authenticated DELETE and accepts an empty 204', () async {
    await http.runWithClient(
      () async => expect(await AccountService.removePhoto(), isEmpty),
      () => MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/api/courier/account/avatar');
        expect(
          request.headers['authorization'],
          'Bearer synthetic-courier-token',
        );
        return http.Response('', 204);
      }),
    );
  });

  testWidgets('Save preserves the address from me without reselecting it', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: AccountScreen())),
        );
        await tester.pumpAndSettle();
        expect(find.text('Santa Cruz, Laguna'), findsOneWidget);
        final save = find.text('Save changes');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(saved, {
          'first_name': 'Test',
          'last_name': 'Rider',
          'email': 'rider@example.test',
          'contact_no': '09123456789',
          'vehicle_type': 'Motor',
          'plate_number': 'ABC123',
          'province': 'Laguna',
          'municipality': 'Santa Cruz',
          'barangay': 'Poblacion',
          'street_address': '123 Main Street',
        });
        expect(find.text('Changes saved.'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      () => MockClient((request) async {
        if (request.method == 'POST') {
          expect(request.url.path, '/api/courier/account/profile');
          saved = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        }
        return response(profile());
      }),
    );
  });

  for (final success in [true, false]) {
    testWidgets(
      success
          ? 'Remove clears the saved avatar'
          : 'Failed removal keeps the avatar',
      (tester) async {
        final previous = profile(photo: photoUrl);
        Courier.current = Courier.fromJson(previous);
        tester.view.physicalSize = const Size(1100, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              const MaterialApp(home: Scaffold(body: AccountScreen())),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('Change photo'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Remove photo'));
            await tester.pumpAndSettle();
            expect(Courier.current.photoUrl, success ? '' : photoUrl);
            expect(Courier.current.id, 10);
            expect(
              find.text(success ? 'Profile photo removed.' : 'Removal failed.'),
              findsOneWidget,
            );
            final images = tester.widgetList<Image>(find.byType(Image));
            expect(
              images.where((image) => image.image is NetworkImage),
              success ? isEmpty : hasLength(1),
            );
            await tester.pumpWidget(const SizedBox.shrink());
          },
          () => MockClient((request) async {
            if (request.method == 'GET') return response(previous);
            expect(request.method, 'DELETE');
            expect(request.url.path, '/api/courier/account/avatar');
            return success
                ? http.Response('', 204)
                : response({'message': 'Removal failed.'}, 422);
          }),
        );
      },
    );
  }

  for (final success in [true, false]) {
    testWidgets(
      success
          ? 'Account displays the upload response URL without a second profile GET'
          : 'Failed upload clears the preview and keeps the existing photo',
      (tester) async {
        Courier.current = Courier.fromJson(profile(photo: previousPhotoUrl));
        var profileReads = 0;
        MockClient api() => MockClient((request) async {
          if (request.method == 'GET') {
            profileReads++;
            return response(profile(photo: previousPhotoUrl));
          }
          return success
              ? response({'message': 'Photo updated.', 'avatar_url': photoUrl})
              : response({'message': 'The photo field must be an image.'}, 422);
        });
        tester.view.physicalSize = const Size(1100, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await http.runWithClient(() async {
          await tester.pumpWidget(
            const MaterialApp(home: Scaffold(body: AccountScreen())),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Change photo'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Choose from gallery'));
          await tester.pumpAndSettle();
          expect(profileReads, 1);
          expect(
            Courier.current.photoUrl,
            success ? photoUrl : previousPhotoUrl,
          );
          expect(Courier.current.id, 10);
          final images = tester.widgetList<Image>(find.byType(Image));
          expect(images.where((image) => image.image is MemoryImage), isEmpty);
          if (success) {
            expect(
              images.where(
                (image) =>
                    image.image is NetworkImage &&
                    (image.image as NetworkImage).url == photoUrl,
              ),
              hasLength(1),
            );
            expect(find.text('Profile photo updated.'), findsOneWidget);
          } else {
            expect(
              images.where(
                (image) =>
                    image.image is NetworkImage &&
                    (image.image as NetworkImage).url == previousPhotoUrl,
              ),
              hasLength(1),
            );
            expect(
              find.text('The photo field must be an image.'),
              findsOneWidget,
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }, api);
      },
    );
  }
}
