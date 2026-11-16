# Proof-of-delivery investigation: SL-K49B32DN

Investigation date: 2026-11-15 (Asia/Singapore).

## Effective installed API URL

Confirmed from the installed APK's compiled constants:

```text
ApiClient.baseUrl = http://127.0.0.1:8000/api
ApiConfig.baseUrl = http://127.0.0.1:8000/api
ApiConfig.useProduction = false
```

Hostname: `127.0.0.1`; port: `8000`; base path: `/api`.

The APK was pulled from the connected CPH2819 phone for package `com.example.mobileshopleap_logistic_app` (version 1.0.0, code 1, last updated 2026-11-15 11:34:28). Its SHA-256 matched the pre-change local debug APK:

```text
APK:    F071CF590B7F7E258AEAF18D77D2BFF0B6CBF278366A30D8AF4972368A902067
Kernel: B8516C630C9D08AB6069118BBE1D52AEE6E70E15AA9CCC3BAEEF858AFA640E71
```

The APK's `assets/flutter_assets/kernel_blob.bin` was loaded into the matching local Flutter engine with app startup paused. VM service `getObject` located the original classes; `invoke` called only their original `get:baseUrl` getters and `get:useProduction`. The app's main function was not resumed. No source recompilation or source-default assumption was used. A compile-time `API_BASE_URL` override is already resolved in those getters. The old build did not expose a separate override-presence flag, so an absent override and an override identical to the default cannot be distinguished. The effective URL itself is confirmed.

On a physical phone, `127.0.0.1` is that phone. At initial inspection, `adb reverse --list` showed `tcp:8000 -> tcp:8000`, and the workstation had a listener on `127.0.0.1:8000`. The phone later disconnected; no restart or replacement installation completed. Recheck the reverse mapping when reconnecting.

## Order and actual HTTP evidence

- Affected order: `SL-K49B32DN`, already `COMPLETED`, with no proof, per the supplied confirmed backend findings.
- This investigation sent no delivery mutation for that order and made no shared-database writes. Its status and earnings were not reset or modified.
- Retrying the delivered endpoint for a completed order returns its existing proof metadata; it does not attach a newly supplied image.
- Actual phone delivery HTTP status: **not captured**.
- Actual phone sanitized response: **not captured**. The historical TypeError does not establish a captured HTTP status or response body.
- New live verification order: **pending**. A new `OUT_FOR_DELIVERY` code and collected amount were requested. The read-only shared-database lookup failed with `Illuminate\Database\QueryException`, code 7. No error SQL, connection secrets, or bindings were printed.

The isolated backend regression uses a fresh `OUT_FOR_DELIVERY` fixture named `SL-POD-VERIFY-NEW`, in SQLite memory with fake private storage. It asserts HTTP 200 and this sanitized response subset:

```json
{"proof":{"uploaded":true,"captured_at":"2026-11-08T03:59:00+00:00"}}
```

The test reads both delivery history and earnings history and asserts the same proof metadata. This is automated test evidence, **not a captured phone delivery response**.

## Exact backend TypeError

The existing Laravel log has two occurrences, at `2026-11-15 03:13:02 UTC` and `2026-11-15 03:16:25 UTC` (11:13:02 and 11:16:25 Singapore time). The application config uses UTC.

Exact message:

```text
App\Http\Controllers\Api\CourierDeliveryController::delivered(): Argument #2 ($id) must be of type int, string given, called in C:\Users\PC\MobileShopLeap_Logistic\vendor\laravel\framework\src\Illuminate\Routing\ControllerDispatcher.php on line 46
```

Throw location: `app/Http/Controllers/Api/CourierDeliveryController.php:390` in the version that produced the log.

First stack entry calling application code:

```text
#0 vendor/laravel/framework/src/Illuminate/Routing/ControllerDispatcher.php(46): App/Http/Controllers/Api/CourierDeliveryController->delivered(Object(Illuminate/Http/Request), 'SL-K49B32DN', Object(App/Services/CourierEarningsService))
```

First subsequent stack frame whose file is under `app/`:

```text
#5 app/Http/Middleware/EnsureCourierApproved.php(39): Illuminate/Pipeline/Pipeline->{closure:Illuminate/Pipeline/Pipeline::prepareDestination():178}(Object(Illuminate/Http/Request))
```

The current controller already accepts a string public order number. TypeErrors arising inside proof storage or the delivery transaction now propagate to Laravel's exception handler instead of being reduced to an exception-type-only log and a generic 503.

## Changes

Only HTTP 200 with an actual boolean `proof.uploaded:true` confirms upload. Missing proof, `uploaded:false`, string `"true"`, numeric 1, and malformed response shapes leave the encrypted pending photo and frozen request intact. Delivery refresh/tracking completion and the `Proof uploaded` success message run only after this confirmation.

The existing single `http.MultipartRequest` still sends `amount` and `proof_image` as actual file bytes, plus supplied optional fields. Its HTTP library generates the multipart boundary. No automatic delivery retry was added.

Diagnostics retain and print only allowlisted metadata in debug builds: API hostname/port/base path, override-presence flag, order code, actual HTTP status (null before an acknowledgement), response format, proof presence, and the uploaded boolean. Raw responses, messages, tokens, photo contents, coordinates, notes, private photo paths, and multipart bodies are excluded.

Changed source/documentation files:

```text
app/Http/Controllers/Api/CourierDeliveryController.php
app/Services/CourierDeliveryProofService.php
tests/Feature/CourierEarningsTest.php
docs/rider-proof-of-delivery.md
docs/proof-delivery-investigation-SL-K49B32DN.md
frontend/mobileshopleap_logistic_app/lib/core/services/api_config.dart
frontend/mobileshopleap_logistic_app/lib/core/services/api_client.dart
frontend/mobileshopleap_logistic_app/lib/core/services/delivery_upload_diagnostics.dart
frontend/mobileshopleap_logistic_app/lib/core/services/order_service.dart
frontend/mobileshopleap_logistic_app/lib/screens/orders/proof_delivery_screen.dart
frontend/mobileshopleap_logistic_app/test/proof_delivery_test.dart
frontend/mobileshopleap_logistic_app/test/proof_delivery_screen_test.dart
frontend/mobileshopleap_logistic_app/test/earnings_api_test.dart
frontend/mobileshopleap_logistic_app/test/profit_screen_test.dart
frontend/mobileshopleap_logistic_app/test/widget_test.dart
frontend/mobileshopleap_logistic_app/test/rider_navigation_card_test.dart
```

## Remaining live verification

1. Reconnect the phone and confirm the `tcp:8000 -> tcp:8000` reverse mapping for this verified loopback API URL.
2. Install the updated debug APK with the explicit `API_BASE_URL=http://127.0.0.1:8000/api` override. Its diagnostics record override presence without exposing credentials.
3. Use a new assigned `OUT_FOR_DELIVERY` order and its actual collected amount. Submit exactly one multipart delivery request with its real captured photo.
4. Capture the `delivery_upload` diagnostic event containing a non-null HTTP status and sanitized proof response. Treat only 200 plus `uploaded:true` as confirmation.
5. Refresh delivery history from the server and confirm `proof.uploaded` remains true for that new order. Preserve the pending photo for every error or uncertain result.

SL-K49B32DN is not a verification candidate.
