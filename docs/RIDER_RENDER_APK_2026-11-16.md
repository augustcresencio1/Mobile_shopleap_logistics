# Shopleap Rider APK connected to August's Render service

The owner requested a separate rider APK connected directly to the rider backend on Render, while deferring the missing backend features. This release uses `https://shopleap-rider-api-august.onrender.com/api` and has no fallback to the previous `shopleap.shop` API. The default in `lib/core/services/api_config.dart` now also selects Render.

**[Download the rider APK connected to Render](https://pub-08abb33dded04b0daaa0e3029235c29c.r2.dev/mobile-demo/2026-11-17/Shopleap-Rider-Render-c858c09df3ce.apk)** — 81,118,926 bytes (approximately 77.4 MiB).

SHA-256: `c858c09df3ce435e6ef6777ecabc19b35e2685111db0a06d68b0b76047aea0dc`. The Android signature verified successfully. The packaged Dart code for ARM32, ARM64 and x86-64 was inspected and contains the exact Render API URL. The full public download returned HTTP 200 and matched the local APK's byte count and SHA-256 hash.

Application ID: `com.example.mobileshopleap_logistic_app`; label: **Shopleap Rider**; version: `1.0.0`; build number: `20261117`, higher than the previous rider APK's `20261116`. It uses the same local development signing key for this school demo. Existing web-server tokens are not reused on Render because tokens are scoped to the API URL.

## Install

1. Download the Render-connected APK using the link above.
2. Open it on Android, permit installation from the browser/Files app if prompted, and choose **Update** or **Install**. It replaces the previous rider build; the buyer/seller app has a different package and remains separate.
3. Open the app and sign in again with an existing approved rider's **Shopleap password**, not a Google account password.
4. Test with Wi-Fi off and mobile data on, then with Wi-Fi. Camera and location permissions are needed for the scanner/proof/GPS features. Rehearse with the development PC turned off.

## What is and is not verified

The Render service is Live on Free/Singapore in the August account. Live public verification returned health HTTP 200, hub/database read HTTP 200 JSON, empty login HTTP 422 JSON, and unauthenticated profile HTTP 401 JSON. The Flutter authentication/API/cache suite passed 22 tests with the Render URL supplied. These are mocked application tests, not signed-in phone checks.

The owner deferred the missing backend work. Cash and receipt routes, notification read actions and response differences, account/avatar/reapplication differences, and HTTPS OTP mail delivery remain incomplete on this backend. Supabase broadcast credentials were also absent from the source environment. Registration, password reset, cash and receipts must not be represented as verified working flows. See `mobile-api-route-audit.md`, `mobile-account-integration.md`, `rider-money-integration.md`, and `RENDER_DEPLOYMENT_2026-11-16.md` for details.

Use an existing approved rider account for initial login testing. Signed-in home, pickup/delivery, proof uploads, chat and camera/GPS still require a phone rehearsal. Coordinate actions that change orders with the demo team because the online database is shared.

## Before presenting

Open https://shopleap-rider-api-august.onrender.com/up a few minutes before the demo and wait for a health response. A free service can sleep after idle time; retry the app request after the server wakes. Keep mobile data available.

Backend fixes at this same API address can normally be deployed without replacing the APK if the response contract stays compatible. Flutter changes need another APK with the same application ID and signing key and a higher build number.

## Rebuild

From `frontend/mobileshopleap_logistic_app`:

```powershell
flutter build apk --release --build-number=20261117 --dart-define=API_BASE_URL=https://shopleap-rider-api-august.onrender.com/api
```

Output: `build/app/outputs/flutter-apk/app-release.apk`.
