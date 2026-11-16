# Shopleap Rider Android release — November 16, 2026

**Earlier build:** this document describes the original web-API APK, build `20261116`. For the current rider APK connected directly to August's Render service, use [RIDER_RENDER_APK_2026-11-16.md](RIDER_RENDER_APK_2026-11-16.md), build `20261117`.

This APK uses the local rider application uploaded to `augustcresencio1/Mobile_shopleap_logistics` in commit `6caba1b`, with the launcher label changed to **Shopleap Rider** and cleartext network traffic explicitly disabled.

**[Download Shopleap Rider APK](https://pub-08abb33dded04b0daaa0e3029235c29c.r2.dev/mobile-demo/2026-11-17/Shopleap-Rider-b4889fbc7266.apk)** — 81,118,926 bytes (approximately 77.4 MiB), version `1.0.0`, build `20261116`.

SHA-256: `b4889fbc7266048f3808d8e28c5b0896915bccd53488671c57fd6f3e43ac8058`. The complete public download matched the local APK's byte count and hash. Android's APK signer verified the signature; the packaged manifest includes internet and camera permissions, disables cleartext traffic, and labels the app Shopleap Rider. ARM32, ARM64, and x86-64 are included.

## Current server and release status

API URL: `https://shopleap.shop/api`. The APK uses this existing online backend while the Render deployment is prepared separately. Completing the missing local backend features was deferred at the owner's request. This release does not establish that the local Laravel backend is ready to replace every existing web endpoint.

The phone needs internet; the development PC can be turned off.

## Install and test

1. Download the APK using the link above.
2. Open it on Android, allow **Install unknown apps** for the browser or Files app if prompted, and tap **Install**.
3. Sign in with an existing approved **Shopleap rider account and Shopleap password**. Do not enter a Google account password into the Shopleap login form.
4. Test with Wi-Fi turned off and mobile data enabled. Check login, home, pickups, deliveries, scanner/camera, chat, cash, earnings, and an owned receipt. Location and camera permissions are needed for the corresponding features.
5. Test Wi-Fi and the spare phone. Coordinate any real pickup, delivery, or other record-changing action with the demo team because the app uses the shared live database.

Validation before distribution: 22 focused Flutter tests passed for deployed login/API behavior, authentication contracts, and cache isolation. The online public hub endpoint returned JSON with HTTP 200. Protected profile, cash, earnings, and notification endpoints rejected unsigned requests with HTTP 401. Signed-in flows and native camera/GPS behavior still require a phone rehearsal.

## Later updates

- Backend changes at the same API URL usually need no APK replacement, provided the API remains compatible.
- Changes to Flutter code or the configured API URL need a new APK. Keep application ID `com.example.mobileshopleap_logistic_app`, use the same signing key, and increase the build number. Install the new APK over the existing app; do not uninstall first unless troubleshooting requires it.
- This school-demo release uses the existing local development signing key. Keep that key private and preserve it for compatible updates.
- To switch this build to a different API, rebuild with `--dart-define=API_BASE_URL=https://your-server/api`. This rider app currently has no runtime server switch setting.

Build command from `frontend/mobileshopleap_logistic_app`:

```powershell
flutter build apk --release --build-number=20261116 --dart-define=API_BASE_URL=https://shopleap.shop/api
```

Output: `frontend/mobileshopleap_logistic_app/build/app/outputs/flutter-apk/app-release.apk`.
