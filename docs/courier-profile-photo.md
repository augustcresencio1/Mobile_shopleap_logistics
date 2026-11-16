# Courier account photo upload

**Historical local-backend investigation.** The Flutter app now targets the
production contract's `POST`/`DELETE /courier/account/avatar`. See
[Mobile account integration, part 1](mobile-account-integration.md) for the
current client behavior and the outstanding production-validation check. The
route, middleware, and deployment advice below describes the older local
`/account/photo` implementation, not the supplied production contract.

## Route comparison and the reported 404

`php artisan route:list --path=api/courier` in this checkout registers:

```text
POST api/courier/account/photo  Api\CourierProfileController@uploadPhoto
```

Flutter's `AccountService.uploadPhoto` calls that same method/path, with multipart
field `photo`. `ApiClient.baseUrl` includes `/api`. There is no local path or
HTTP-method mismatch, so no replacement route or alias was added.

Flutter defaults to `https://shopleap.shop/api` in `api_config.dart`; it uses the
local backend only when built with an `API_BASE_URL` override. A missing-route
response from the deployed API, while the route exists locally, points to a
different deployed code version, route cache or backend URL. This is an inference
from the local route registry and client configuration; no authenticated live
upload or deployment was performed.

Deploy `routes/api.php`, `CourierProfileController.php`, and their application
dependencies to the Laravel application actually serving the app's API URL.
From that deployed application's root, run:

```sh
php artisan route:clear
php artisan config:clear
php artisan route:list --path=api/courier/account/photo
```

Confirm the POST route above is present. Rebuild the production route cache with
`php artisan route:cache` if your deployment normally uses it. If it is still
absent, confirm that this is the PHP application/document root serving the app's
configured API host. Clearing the local cache does not update the remote server.

## Upload and display behavior

- The endpoint remains protected by Sanctum, the courier role and approved/active
  courier/hub middleware. It accepts JPG/JPEG, PNG and WebP, with a maximum size
  of 5120 KB (5 MB). Missing/wrong fields, unsupported types and oversized files
  return validation errors.
- Photos use the configured `r2_private` filesystem disk from
  `config/filesystems.php`. Uploads explicitly request private visibility and save
  their unique object path to the existing `courier_profiles.profile_photo_path`
  column. The old photo is deleted after the replacement profile save succeeds.
- A failed storage write cannot save a nonexistent object path. Streams are
  closed even if storage throws an exception. A false write result returns 503
  and preserves the old profile photo path.
- The existing response uses the same profile JSON shape as `/courier/me`:
  `message`, `user`, `email`, `name`, `courier_status`, and `courier`, including
  `courier.photo_url`. The object path is omitted from this payload.
- The photo URL is an absolute R2/S3 signed URL valid for six hours. The app can
  fetch the image directly using that URL, without a Laravel authorization
  header. The configured R2 endpoint must be reachable from the device, and
  the bucket credentials must allow the signed object read. Real R2 reachability
  still requires a device/environment check; tests use synthetic URLs and storage.
- R2 does **not** use `public/storage`, so `php artisan storage:link` is not
  needed for this implementation. If you later move photos to Laravel's `public`
  disk, change both storage and URL generation together, set `APP_URL` to an
  app-reachable absolute origin, and create the storage link on that server.
- Flutter now consumes the upload response directly, updates `Courier.current`,
  clears the temporary local preview and displays its returned network photo URL.
  It no longer needs a second profile GET after a successful upload. Failed
  uploads clear the temporary preview and keep the previous saved photo.

No schema change or real credential change was made. The existing
`profile_photo_path` column must already exist; the endpoint returns a 503
readiness message if it is absent.

## Files changed or created

- `app/Http/Controllers/Api/CourierProfileController.php`
- `frontend/mobileshopleap_logistic_app/lib/core/services/account_service.dart`
- `frontend/mobileshopleap_logistic_app/lib/screens/account/account_screen.dart`
- `tests/Feature/CourierProfilePhotoTest.php`
- `frontend/mobileshopleap_logistic_app/test/account_photo_test.dart`
- `frontend/mobileshopleap_logistic_app/pubspec.yaml` and `pubspec.lock` — the
  already-installed image picker platform interface is declared as a direct
  development dependency for the in-memory test picker; its version is unchanged.
- `docs/courier-profile-photo.md`

## Automated verification

- All backend tests pass: **74 tests / 549 assertions**, including the five new
  profile-photo tests (37 assertions), using SQLite in memory and fake storage.
- All three Flutter photo tests pass: request method/path/field and response
  parsing, successful Account avatar replacement with no second profile GET,
  and failed upload clearing the preview while preserving the saved avatar.
- PHP Pint passes. Dart analysis has no errors or warnings; the Account screen
  retains three pre-existing informational lint/deprecation findings.
- Flutter tests run in a temporary project copy to preserve this checkout's
  build directory. No secret-dependent live upload or storage access was performed.

## Manual verification

1. Confirm the deployed route and clear/rebuild its cache as above.
2. Ensure the backend's existing R2 private-disk settings are configured in its
   own environment. Do not put storage credentials in Flutter.
3. Run Flutter against that API and sign in as an approved rider with an active hub.
   For a local Laravel server, pass an app-reachable override:
   `flutter run --dart-define=API_BASE_URL=http://YOUR_SERVER_ADDRESS:8000/api`.
4. In Account, choose **Change photo**, then camera or gallery, and select a valid
   image smaller than 5 MB. Confirm the upload returns 200 with a nonempty absolute
   `courier.photo_url`, the success message appears, and the avatar displays it.
5. Open that returned signed URL on the device while it is valid, and check for
   an image response (200). Re-enter Account/restart the app and confirm `/courier/me`
   returns a fresh usable URL for the saved photo.
6. Try an invalid/oversized image. Confirm a validation error and that the prior
   saved avatar remains. A storage failure must not report a successful save.
