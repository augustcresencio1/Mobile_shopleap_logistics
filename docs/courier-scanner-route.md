# Courier scanner: live API route missing

Verified on 2026-11-16 for the reported `WB-CMSJY2NW5X` scan.

## Confirmed cause

The mobile app defaults to `https://shopleap.shop/api`. Its scanner calls:

```text
GET /api/courier/orders/scan/WB-CMSJY2NW5X
Accept: application/json
Authorization: Bearer <signed-in courier token>
```

An unauthenticated read of that URL returned HTTP 404 with:

```json
{"message":"The route api/courier/orders/scan/WB-CMSJY2NW5X could not be found."}
```

The numeric scanner path also returned 404. `/api/courier/me` returned 401,
confirming that the courier API is reachable at this host. Alternate GET paths
`/courier/scan/{code}`, `/courier/scan?code=...`, and
`/courier/orders/scan?code=...` also returned missing-route responses.

This checkout already registers the scanner route and resolves the reported
waybill format, including with compiled routes. The live response indicates a
missing route in the application serving that host, potentially from an older
deployment or stale route cache. These requests do not verify authentication,
the parcel's existence, or its assignment.

## Apply the server fix

In the Laravel application actually serving `https://shopleap.shop/api`, inspect
its registered route before changing anything:

```sh
php artisan route:list --path=api/courier/orders/scan -vv
```

If its source is missing the route, integrate this declaration within the
existing `courier` prefix and authenticated, approved courier middleware group:

```php
Route::get('orders/scan/{code}', [CourierDeliveryController::class, 'scan'])
    ->where('code', '.*');
```

Use this checkout's implementation as the integration source:

- `routes/api.php`: route and middleware placement.
- `app/Http/Controllers/Api/CourierDeliveryController.php`: `scan`, `scanData`,
  and their existing order/item query helpers.
- `app/Support/CourierScanCode.php`: WB/SL, QR URL, and legacy numeric parsing.

The controller imports `App\Support\CourierScanCode`. Keep the live application's
other routes and controller behavior when integrating; its deployed API also
contains endpoints that this checkout does not define.

From that server application's root, clear and, if normally used, rebuild its
route cache:

```sh
php artisan route:clear
php artisan route:list --path=api/courier/orders/scan -vv
php artisan route:cache
```

The route must appear as `GET|HEAD api/courier/orders/scan/{code}` with Sanctum,
courier role, and approved courier protection. An unauthenticated request should
then return 401 instead of the missing-route 404. Finally, scan while signed in
as the assigned courier: the response should contain `data` and `role` and
display the matching parcel before confirmation. Looking up an unassigned
parcel must remain a 404. Do not confirm a real pickup as a deployment probe.

Clearing this workstation's cache does not change the live server. The existing
app already sends the correct scanner path; this fix requires a backend rollout.

## Local verification

```sh
php artisan route:list --path=api/courier/orders/scan -vv
php vendor/bin/phpunit --do-not-cache-result --filter 'scan|public_and_legacy_labels|pickup_confirmation_validates'
```

The route is registered locally. All six focused backend tests passed with 555
assertions, covering hyphenated WB/SL references, numeric labels, QR payloads,
compiled routes, assignment isolation, and pickup scan validation. Tests use an
isolated in-memory SQLite database.

The mobile scanner contract also passed all nine tests in
`frontend/mobileshopleap_logistic_app/test/public_order_reference_test.dart`
using `flutter test --no-pub test/public_order_reference_test.dart` from the
mobile project directory. These use mocked HTTP responses, not the live API.

No live code, cache, database records, or parcel status were changed during this
investigation. Access to the deployment project or hosting environment is still
needed to apply and verify the live fix.
