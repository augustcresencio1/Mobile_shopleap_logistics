# Rider money integration

The Flutter app follows the supplied `feature/money-remittance` contract. Cash
and earnings are server-owned, read-only records. The old mock COD remittance
workflow and its unsupported mutation endpoints have been removed.

## Mobile changes

- `models/cash.dart`, `cash_service.dart`, `screens/money/cash_screen.dart`: exact
  decimal balances, remaining parcel cash, paginated handovers, confirmed/short/
  settled statuses, receipt actions. Shortage is displayed as a component of cash
  on hand. Neither current hub nor delivery history selects or reconstructs cash.
- `models/earnings.dart`, `earnings_service.dart`, `profit_screen.dart`: separate
  accrued/unpaid and paid totals and per-order badges. Summary, current rate and
  first history page are composed using the three documented endpoints. Every
  history page receives the same delivery-date period filter. Null historical
  amounts and null rates remain unavailable, without historical recalculation.
- `models/receipt.dart`, `receipt_service.dart`, `receipt_screen.dart`: in-memory
  authenticated HTML fetch with redirects disabled, native WebView rendering,
  original receipt URL as the asset base, scripts disabled, navigation blocked
  outside the receipt, no token in the WebView or URLs, and cache/storage cleanup
  on entry, exit and session change. Viewer API reference:
  https://pub.dev/packages/webview_flutter
  (`pubspec.yaml` and `pubspec.lock` include the viewer and its test interface).
- `courier_notification.dart`, `notification_service.dart`, `main_shell.dart`:
  paginated stored notifications, unread/read actions, allowlisted native money
  navigation and exact receipt references. Existing pickup/delivery bell entries
  retain their navigation. Unknown kinds and absent URLs are tolerated. No push
  transport or arbitrary browser navigation is introduced.
- `api_client.dart`, `financial_session.dart`, `money_error.dart`: common account,
  HTTP and retry states; Retry-After seconds or HTTP dates gate authenticated
  requests. Token changes clear screen state and prevent old financial responses
  from being applied. A failed refresh does not keep old balances on screen.
- Cash and earnings refresh on entry, delivery completion, notification entry,
  app resume and pull-to-refresh. Cash has no periodic balance polling; notification
  checks are limited to once per minute plus explicit opening/refresh. Financial
  screens load lazily in the existing shell.
- `order_service.dart`, `proof_delivery_screen.dart`: every delivery request,
  including a saved retry, sends the immutable multipart request with its exact
  COD amount and required proof photo. Success invalidates/refetches
  server totals rather than incrementing balances. Existing 409/413/422/503 proof
  handling and the encrypted draft are preserved.

## Backend release coordination

The mobile default is now `https://shopleap.shop/api`, with the existing
`API_BASE_URL` compile-time override retained for local development. The
logistics subdomain serves the hub portal, not courier money routes. Deployed
mobile operation requires neither local Laravel clones nor USB API forwarding.

Sign in through `POST /courier/login` on this backend. Stored bearer tokens are
scoped to the API base URL; legacy unscoped tokens require a fresh login. JSON
requests use `Accept: application/json`. Receipts keep the authenticated,
in-memory HTML flow described above.

Deployment checks established route availability only. Authenticated validation
requires an approved, active rider: review cash and earnings summary/history,
notification navigation, a rider-owned HTML receipt, logout/account isolation,
and error/empty states. Those checks must not assume historical ledger coverage.
Report missing records with endpoint, HTTP status and a sanitized response to
the backend team. Do not create replacement balances or records.

Do not run migrations, ledger backfills or backend verification commands from
this mobile workspace. Backend release work and any historical backfill belong
to the backend team's separate review procedure.

Actual contract limits:

- No rider payout-history JSON endpoint or payout reference in order earnings
  history. Payout receipts are offered from notification metadata only.
- No rider endpoints to confirm a handover, settle a shortage or issue a payout.
- No shortage-settlement notification; refresh is necessary to see settlement.
- No push transport and no public proof image URL.

## Verification

From `frontend/mobileshopleap_logistic_app`:

```powershell
flutter pub get
flutter analyze --no-fatal-infos
flutter test --reporter expanded
flutter build apk --debug
```

Automated coverage includes exact/nullable amounts, empty cash, all handover
statuses, shortage inclusion, accrual versus payment, delivery-period query
consistency, opaque references, historical rider ownership without hub filtering,
HTML authentication/error/no-cache handling, native notification routing,
pagination, refresh/resume, account isolation, and idempotent delivery retries.
Native Android/iOS receipt rendering still requires an on-device smoke check
against the complete backend release.

Checks completed in this workspace:

- Focused money, notifications, receipts, authentication/cache, public-reference
  and delivery-proof suite: **103 passed**. This includes the two additional
  regression cases for resume invalidation while a request is still in flight.
- Full regression run: **132 passed, 5 failed** in untouched test cases. Four
  `pickup_seller_contact_test.dart` cases still look for an `OutlinedButton`,
  while the current screen uses `GradientFilledButton`. The first live-GPS case
  in `rider_navigation_card_test.dart` does not handle the existing location
  explanation dialog before expecting a permission request. These failures are
  outside the money integration.
- `flutter analyze --no-fatal-infos`: no errors or warnings; 20 existing
  informational findings in unrelated app files and the older proof-screen test.
- Dart formatting applied to the changed files. Android debug APK built with
  the native receipt viewer dependency.

The results above describe the earlier mobile integration. They do not establish
authenticated results or historical balance completeness on the deployed API.

## Deployed API switch verification (2026-11-16)

- Focused login, cash, earnings, HTML receipts, notifications, cache and error
  suite: **71 passed**. The same login/money flow also passed both tests with the
  local `API_BASE_URL` override.
- Full mobile suite: **149 passed, 5 failed**. The remaining failures are the
  previously documented four pickup-contact `OutlinedButton` assertions and
  the live-GPS permission-dialog case. Fixture token keys were updated for
  backend-specific secure storage; those failures do not involve money routes.
- Flutter analysis: no errors or warnings; existing informational findings
  remain. A separate analysis of the changed runtime files and new integration
  tests found no issues.
- Android debug APK built with the explicit deployed URL, installed on CPH2819,
  and verified by matching installed/built APK SHA-256 hashes. Port-8000 reverse
  forwarding is absent.
- Unauthenticated GETs to cash summary/history, earnings summary/history/rate,
  notifications and both receipt route families returned **401** with sanitized
  response `{"message":"Unauthenticated."}`. This proves route availability only.
- Approved-rider sign-in and authenticated live reads were subsequently verified
  as described below. A live receipt still needs a legitimate rider-owned
  reference. No migrations, ledger backfills or replacement records were run.

Changed runtime files (under `frontend/mobileshopleap_logistic_app/lib`):

- `core/services/api_config.dart`: deployed default and retained local override.
- `core/services/api_client.dart`: secure token keys scoped to API base URL.
- `core/services/auth_service.dart`: shared v4 contract comment.
- `core/services/order_service.dart`: compose Home from deployed dashboard,
  pickup, delivery and history reads instead of the missing aggregate route.
- `screens/home/main_shell.dart`: failed notifications cannot show an empty-success message.
- `screens/money/cash_screen.dart`, `screens/profit/profit_screen.dart`: explicit
  sign-in state after session expiry.

Changed tests (under the same mobile project's `test` directory):
`deployed_api_test.dart` (new), `courier_home_api_test.dart` (new),
`api_cache_test.dart`, `cash_screen_test.dart`,
`chat_notifications_test.dart`, `deliver_order_layout_test.dart`,
`earnings_api_test.dart`, `main_shell_loading_test.dart`, `money_api_test.dart`,
`money_notification_test.dart`, `notification_bell_test.dart`,
`pickup_seller_contact_test.dart`, `profit_screen_test.dart`,
`proof_delivery_screen_test.dart`, `proof_delivery_test.dart`,
`public_order_reference_test.dart`, `receipt_screen_test.dart`,
`rider_navigation_card_test.dart`, and `widget_test.dart`. Tests also update mock
token keys and Home fixtures for the deployed endpoints.
The mobile `README.md` and this document describe configuration and validation.

## Home route fix and authenticated device checks (2026-11-16)

The installed app initially requested `/api/courier/home`, which returned **404**
with sanitized response `{"message":"The route api/courier/home could not be found."}`.
`/api/home` also returned 404. Neither is a deployed v4 courier endpoint.

`OrderService.home()` now composes `GET /courier/dashboard`, `/courier/pickups`,
`/courier/deliveries`, and `/courier/history?page=1`. Dashboard earnings are read
from the server's `earned_today`; unavailable earnings stay unavailable. These
reads share the existing token-scoped cache, retain request coalescing, and warm
the pickup/delivery tabs. Recent deliveries display the first five returned
history rows. The app no longer requests either missing Home route.

Validation of this fix:

- **7** new API regressions passed, including concurrent request reuse, cached
  Home clearing on logout, missing earnings, 401/403/404/503 and network failures.
- **21** dashboard, startup, chat/notification and money-navigation regressions
  also passed with the updated deployed response fixtures.
- Analysis of the changed service and regression tests found no issues.
- The corrected Android APK was built and installed over the existing app;
  installed and built SHA-256 hashes matched. The signed-in Home screen rendered
  successfully with its server earnings, empty active lists and recent history.
- `GET /api/courier/me`: **200**, sanitized response
  `{"courier":{"status":"approved"}}`.
- Dashboard, pickups, deliveries and delivery history: authenticated **200**.
  History returned nine rows; active pickup/delivery lists were empty.
- Cash and earnings screens rendered successfully. JSON reads had a bearer
  header and `Accept: application/json`; the token itself was never printed.
- Notifications: authenticated **200**, 20 rows, zero money notifications and
  zero money receipt references. The notification sheet rendered. Money receipt
  navigation remains covered by automated tests; no eligible live money notice
  was available for that check.
- A real logout returned the app to an empty sign-in form. Automated tests cover
  account switches and stale/in-flight response isolation. Temporary HTTP
  profiling was disabled and its in-memory data cleared before logout.

Sanitized authenticated results for backend ledger review (all **HTTP 200**):

```json
{
  "/api/courier/cash/summary": {
    "cash_on_hand": "0.00",
    "shortage_amount": "0.00",
    "currency": "PHP",
    "orders": []
  },
  "/api/courier/cash/history?page=1": {
    "data": [],
    "meta": {"current_page": 1, "last_page": 1, "total": 0}
  },
  "/api/courier/earnings/summary?period=all": {
    "currency": "PHP",
    "total_earned": "135.00",
    "accrued_unpaid": "0.00",
    "paid": "0.00",
    "deliveries": 9,
    "recorded_earnings": 9
  },
  "/api/courier/earnings/history?period=all&page=1": {
    "data_count": 9,
    "meta": {"current_page": 1, "last_page": 1, "total": 9}
  }
}
```

These are observed responses, not proof of complete historical ledger coverage.
The backend team must review the empty cash ledger and the earnings total versus
the zero paid/unpaid totals. Do not manufacture cash records or infer replacement
balances from the nine historical orders. A rider-owned cash handover or payout
reference is still required to finish the live HTML receipt check. No backfill
or database changes were performed from this workspace.
