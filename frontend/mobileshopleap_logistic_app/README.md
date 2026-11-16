# mobileshopleap_logistic_app

Shopleap courier/rider app. The default Laravel API is
`https://shopleap.shop/api`. The logistics subdomain is the hub web portal and
must not be used for courier endpoints.

## API configuration

Run the deployed configuration without a local Laravel server or USB API port
forwarding:

```powershell
flutter run --dart-define=API_BASE_URL=https://shopleap.shop/api
```

The same URL is the default for builds without a define. Service paths start
with `/courier`, so `/api` occurs only once. Rebuild/restart after changing a
compile-time define.

Local development remains available through the existing override:

```powershell
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
```

For the Android emulator, use `http://10.0.2.2:8000/api`; for a physical phone,
configure local connectivity separately. `serve.ps1` is for local development
only and is not needed for the deployed API.

Sign in through the app with an approved, active rider account. Login posts to
`/courier/login`; the returned bearer token is stored separately for each API
base URL. Older unscoped tokens are ignored, so upgrading requires signing in
again. JSON requests send `Accept: application/json`. Receipt HTML is fetched
with authentication in memory and opened in the existing native receipt viewer.

Do not run Laravel migrations or ledger backfills from this mobile workspace.
Route availability does not establish ledger completeness. Review authenticated
cash, earnings, notifications and rider-owned receipts before accepting live
balances; report missing records with endpoint, status and sanitized response.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
