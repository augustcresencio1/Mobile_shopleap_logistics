# Rider proof of delivery: implementation and release handoff

Status (2026-11-15): SL-K49B32DN is already COMPLETED with no proof, as confirmed by the backend investigation. Retrying this order cannot attach a photo. Keep its status and earnings intact and verify with a new OUT_FOR_DELIVERY order. See [the investigation report](proof-delivery-investigation-SL-K49B32DN.md) for installed-build evidence and remaining live checks. Other backend deployments must receive the code and migration together.

## Existing behavior reused

- Order details and waybill scanning remain the two delivery entry points.
- The existing COD dialog, decimal money validation, amount discrepancy warning, and items-plus-shipping calculation remain in use. Rider earnings remain separate from COD, including missing and zero earnings.
- Sanctum token storage, `Accept: application/json`, session expiry on 401, and the shared cache/refresh notifiers are reused.
- `LiveRefresh.deliveryCompleted()` already refreshes deliveries, history, earnings, and dashboard totals. It still fires only for confirmed success, including idempotent retries.
- Start-delivery, pickup, and failed-delivery endpoints, request fields, reasons, notes, and attempt handling were left intact. Upload errors never call a failed-delivery endpoint.

## Flutter changes

- Both delivery actions open the same camera-only parcel photo screen. Preview includes Retake and confirmation followed by the existing COD confirmation.
- Photo processing runs in an isolate. JPEG, PNG, and WebP are accepted; originals below a 640 px shortest side or over 40,000,000 pixels are rejected. Uploads become upright JPEGs, normally resized to a 1600 px shortest side, progressively compressed/resized if needed, never below 640 px, and checked against 5 MiB. EXIF/GPS metadata is removed after orientation and capture time are extracted.
- `captured_at` uses the camera's original EXIF timestamp and offset when available, or the UTC time the camera result reaches Flutter. It is persisted before upload and never regenerated during Retry. Native camera confirmation can delay the fallback timestamp on devices that omit EXIF capture time; verify this during device acceptance.
- Location is attached only when the rider taps the optional location action. Only foreground permission is requested; denial, disabled services, or a GPS timeout does not block delivery. Notes are limited to 255 characters.
- Confirmation posts multipart data to `/api/courier/deliveries/{order_number}/delivered`, using `order.orderNumber` (public code), never the internal numeric ID or the display fallback. The HTTP library sets its boundary. `amount` and `proof_image` are always present; optional fields retain their original values on retry.
- The upload exposes byte progress and a separate waiting-for-confirmation state. UI actions and concurrent requests for the same public order code are disabled during submission. Only HTTP 200 together with explicit `proof.uploaded:true` marks an order delivered locally.
- A photo and all request fields are encrypted together with AES-256-GCM in private application storage. A random key, nonce, and opaque file pointer are kept in secure storage, scoped to rider ID and order code. The rider/order scope is authenticated. iOS keys are limited to the unlocked device. No token is copied into the pending submission.
- The exact request is saved before sending. Network errors, timeouts, 503, and all other non-200 results retain it. An uncertain submission cannot be retaken or edited; Retry uses its original photo and fields because the server may already have committed it. Definitive 422/413 rejections allow corrections. No automatic delivery retry runs in the background.
- `Pending delivery uploads` is accessible from Items for delivery, including when no active deliveries remain. This permits recovery after an accepted request times out, the app restarts, or the rider signs back into the same account. Different riders cannot see each other's drafts.
- HTTP 403/409 shows the API message and refetches assignments/status. HTTP 422 exposes field messages. HTTP 413 gives a reduce-size message even for an HTML infrastructure response. HTTP 401 reuses existing expiry handling.
- On HTTP 200 with `proof.uploaded:true`, the pending encrypted file/key are removed and existing refresh signals run. Missing proof or `uploaded:false` keeps the pending submission and explains that upload is unconfirmed. Cleanup failure offers Finish to retry cleanup without uploading again in that screen. Tracking cleanup failure cannot turn a confirmed delivery into an upload failure.
- Delivery and earnings history parse optional `proof` data and show a small `Proof uploaded` indicator only when `uploaded == true`. Missing proof, `uploaded:false`, nullable capture time, and nullable earnings remain supported. No proof URL or image viewer is introduced.
- Debug diagnostics allow only the effective API hostname/port/base path, build override flag, order code, HTTP status, response format, and proof presence/upload boolean. Tokens, photo contents, coordinates, notes, raw messages, response bodies, and multipart bodies are excluded.

## Changed files

Paths below are relative to `frontend/mobileshopleap_logistic_app/`.

| Files | Purpose |
| --- | --- |
| `lib/core/services/api_client.dart` | Multipart progress, exact success status, timeout cleanup, 413 handling, privacy |
| `lib/core/services/order_service.dart` | Public-code proof submission, input checks, duplicate guard, assignment refresh |
| `lib/core/services/delivery_photo.dart` | Image checks, orientation, timestamp, compression |
| `lib/core/services/pending_delivery_store.dart` | Encrypted, rider-scoped persistent retry records |
| `lib/screens/orders/proof_delivery_screen.dart` | Capture, preview, optional location/notes, COD, progress, retry |
| `lib/screens/orders/pending_delivery_screen.dart` | Recover submissions independently of active orders |
| `lib/screens/orders/deliver_order_screen.dart`, `lib/screens/scan/scan_screen.dart` | Route both actions through proof capture |
| `lib/screens/dashboard/delivery_dashboard_screen.dart` | Pending-upload entry point |
| `lib/widgets/cod_amount_dialog.dart` | Optional saved initial amount; existing validation/calculation retained |
| `lib/models/delivery_proof.dart`, `lib/models/earnings.dart`, `lib/core/services/history_service.dart` | Backward-compatible proof metadata |
| `lib/widgets/proof_uploaded_indicator.dart`, `lib/screens/history/delivery_history_screen.dart`, `lib/screens/profit/profit_screen.dart` | Small history indicator |
| `ios/Runner/Info.plist` | Camera purpose text; Android already receives camera permission from its scanner plugin |
| `pubspec.yaml`, `pubspec.lock` | Image processing, encryption, file storage, multipart media type dependencies |
| `test/proof_fixture.dart`, `test/proof_delivery_test.dart`, `test/proof_delivery_screen_test.dart` | Proof-specific API, processing, encryption, and UI coverage |
| `test/earnings_api_test.dart`, `test/profit_screen_test.dart`, `test/rider_navigation_card_test.dart`, `test/widget_test.dart` | Adapt existing delivery tests to required proof and settle the existing COD mock delay |

## Backend fix and deployment

The screenshot's failure was confirmed in `storage/logs/laravel.log` at `2026-11-15 03:13:02` UTC: the app sent `SL-K49B32DN`, but `CourierDeliveryController::delivered()` required an integer ID. Laravel raised a TypeError before handling the upload.

The endpoint is now `POST /api/courier/deliveries/{orderNumber}/delivered`, resolving `orders.order_number` exactly for the authenticated courier. There is no internal-ID or waybill fallback. The older `/orders/{id}/deliver` alias retains its internal-ID identity and also requires a proof photo.

- `CourierDeliveryProofService` validates the amount, JPEG/PNG/WebP photo (5 MiB, at least 640 px on each side, at most 40 MP), optional timestamp with timezone, coordinates and notes. Requests over 6 MiB return 413; invalid fields return 422; incompatible delivery stages return 409.
- `order_delivery_proofs` holds one record per order. Photos use opaque names on the private `r2_private` disk, configurable through `DELIVERY_PROOFS_DISK`. No proof URL, path, notes or coordinates are exposed in delivery or earnings history.
- The order row is locked while the photo, proof record, COD, existing earning snapshot and tracking events are saved. A retry returns the original proof and earning without another upload, changed cash, repricing or failed attempt. Already completed legacy orders retain missing proof rather than receiving a new photo on retry.
- Storage or transaction errors return a recoverable 503. A rolled-back transaction removes the uploaded file. If commit acknowledgement fails, the photo is retained because the transaction may already have committed. Operational exception logs contain only exception types, without SQL bindings or private fields. Programming TypeErrors propagate to Laravel's exception handler with their original message and stack.

For another backend environment, deploy these files and run only the additive migration:

```powershell
php artisan migrate --path=database/migrations/2026_11_15_040000_create_order_delivery_proofs_table.php
```

Use PHP with `pdo_pgsql` enabled. On this workstation `C:\xampp\php\php.exe` provided that driver; the other PHP installation did not. Earlier migration verification found SL-K49B32DN OUT_FOR_DELIVERY; that observation is superseded by the confirmed COMPLETED state with no proof. Do not reset it or use Retry to test attachment. The stricter client confirmation and safe diagnostics require an updated app build.

Coordinate rollout of other backend environments with rider app versions: new deliveries now require photos, including through the legacy alias, so older apps that send only JSON must be updated.

Deployment/device acceptance checklist:

1. Confirm public codes resolve only the authenticated rider's delivery and preserve existing COD and earning snapshots.
2. Accept JPEG/PNG/WebP at up to 5 MiB, shortest side >=640 px and <=40 MP. Keep total multipart infrastructure limit above the app's 5 MiB file plus fields (specified total threshold: 6 MiB).
3. Prove an accepted delivery followed by a client timeout and retry returns HTTP 200 with the original earning and proof. It must not create another proof, replace the photo, reprice an earning, or increment failed attempts.
4. Test 401 expiry, 403 reassignment, 409 stage conflict, 422 per-field errors, JSON/HTML 413, and 503. Confirm history on both endpoints includes `proof` metadata and no image URL.
5. Keep private photos, bearer tokens, coordinates, notes, and multipart request bodies out of backend, proxy, analytics, and mobile logs.

## Device acceptance still required

Test Android and iOS cameras, native Retake/cancel, denied camera permission, EXIF orientations and camera capture time (including native confirmation delay), a large photo, location denied/denied forever/services off, slow upload, a connection lost after the server commits, app restart and re-login, different rider login, and confirmed-success cleanup. Android can destroy the activity while a native camera is open; an unfinished capture may need to be retaken. Once a photo/request has been saved, recovery does not rely on the camera cache.

## Backend verification (2026-11-15)

- `php vendor/bin/phpunit --do-not-cache-result`: **56 tests, 462 assertions passed**, including the full existing backend suite.
- Delivery coverage includes the exact public code from the screenshot, real JPEG/PNG/WebP files, mandatory photo and field limits, private storage options and history metadata, assignment checks, numeric-ID rejection, stage conflicts, missing optional fields, missing legacy proof, unchanged COD/earning snapshots, rollback cleanup and recovery after a committed delivery loses its acknowledgement.
- Laravel Pint formatting passed for the changed PHP files.
- Database migration applied; private storage connectivity verified without uploading a real delivery or changing its status. Camera/device acceptance remains pending.

## Previous Flutter verification results

- `flutter pub get --offline`: passed using the installed SDK and cached dependencies.
- The final delivery regression set passed **48/48 tests** across `proof_delivery_test.dart`, `proof_delivery_screen_test.dart`, `earnings_api_test.dart`, `profit_screen_test.dart`, `widget_test.dart`, `deliver_order_layout_test.dart`, and `public_order_reference_test.dart`.
- This includes the 21 new proof-specific tests: multipart fields/headers and progress; omitted optional fields; HTTP 200-only success; 201/204/401/403/409/422/413/503 handling; duplicate prevention; network failure/timeout; input limits; EXIF orientation/camera timestamp; PNG input above 5 MiB compressed within limits; WebP input; encrypted restart recovery, account separation and tamper detection; interrupted success cleanup; older history responses; camera-first UI; optional denied location; unchanged COD confirmation; retry after reopening; and validation corrections.
- Full suite: **89 passed, 5 failed**. Four failures in `pickup_seller_contact_test.dart` expect an `OutlinedButton` labeled `Call Seller` that the unchanged pickup UI does not render. The other is the unchanged live-trip GPS permission assertion in `rider_navigation_card_test.dart` (`gps.requests` expected 1, actual 0). The delivery confirmation/stop-tracking check passes. No pickup or GPS behavior was changed to address these unrelated failures. Detailed full-suite output is in the generated `.dart_tool/proof-delivery-tests.txt`.
- `flutter analyze --no-pub`: no errors or warnings, and no diagnostics in changed files. It reports 19 informational lint/deprecation issues in untouched main, account, authentication, and splash files; those are left outside this task.
- Dart formatting was applied to all changed Dart files.
- These Flutter results were recorded before the backend fix above. No real-device camera or delivery confirmation was exercised by the backend verification.
