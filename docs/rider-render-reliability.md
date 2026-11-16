# Rider Render reliability fixes

Prepared on 16 November 2026. These changes are local and have not been deployed
to the live Render service.

## Findings

- The rider service is `https://shopleap-rider-api-august.onrender.com` from
  `augustcresencio1/Mobile_shopleap_logistics`, branch `main`.
- Public live checks returned `/up` 200, `/api/hubs` 200,
  `/api/courier/home` 401 and `/api/courier/cash/summary` 404.
- The rider repository has no cash ledger, cash handover, payout or money receipt
  implementation. Its earnings service reads saved order earnings but cannot
  supply paid/unpaid totals without the financial backend.
- Historical local logs show SQLSTATE 26000, prepared statement does not exist,
  on Supabase's transaction pooler, port 6543. The PostgreSQL connection now
  enables PDO emulated prepares by default; `DB_EMULATE_PREPARES=false` can opt out.
  This avoids server prepared statements on the transaction pooler. Live Render
  logs are still needed to establish which failures occurred on that deployment.
- Render's deployed Docker configuration selected SMTP. Render Free blocks
  outbound SMTP on ports 25, 465 and 587. OTP needs HTTPS email delivery.
  Reference: https://render.com/docs/free

## Changes

- JSON GETs share a single retry after 800 ms for network errors, HTTP
  500/502/503/504, and successful responses containing invalid JSON. Persistent
  failures stop after two attempts. Account changes cancel the old retry.
  401/403/404/422/429 and writes are never retried automatically.
- Background polling preserves pending reads without caching responses started
  before invalidation. Startup no longer mounts every hidden tab.
- Registration validates photo types and 5 MiB limits before uploading and sends
  an explicit image MIME type. A failed submission always releases the spinner.
- Registration cleans incomplete documents/cache after storage or mail failure.
  Safe error codes identify email unavailability, and logs record only failure
  stage and exception class, never passwords, OTPs, documents or provider bodies.
- `resend_http` delivers Laravel OTP/password messages through the Resend HTTPS
  API without an extra SDK. Redirects and automatic email retries are disabled.
  Provider failures remain errors and never count as successful registration.
  Reference: https://resend.com/docs/api-reference/emails/send-email
- Avatar POST/DELETE routes match the app, accepting both `avatar` and the legacy
  `photo` upload field. Account profile/photo/password routes are accessible before
  approval. Province and municipality are now saved by the profile controller.
- The APK targets the rider Render API, retains the existing application ID and
  development signing key, and uses build number 20261118 / version 1.0.1.

## Render deployment

The prepared repository is `Mobile_shopleap_logistics`, on local branch
`fix/rider-api-reliability`, based on `origin/main` commit
`9ebb5fefc22a4c20e3f087d1200aa65aa5d2ed7c`.

Set these environment values in Render before deploying the reviewed backend:

```dotenv
DB_EMULATE_PREPARES=true
MAIL_MAILER=resend_http
RESEND_API_KEY=<set securely in Render>
MAIL_FROM_ADDRESS=<sender verified with the email provider>
MAIL_FROM_NAME=Shopleap Rider
```

An existing Render environment value overrides Docker defaults. In particular,
change an existing `MAIL_MAILER=smtp` value. An API key alone does not establish
sender verification or live delivery. Do not paste keys or passwords into chat.
No migrations, ledger reconstruction, backfill or production record changes are
part of this patch. The existing startup script rebuilds Laravel's configuration
and route caches on deployment.

Install the new APK over the existing rider app and sign in again if necessary.
Rebuilding an APK alone does not deploy Laravel fixes. An existing APK can use
compatible backend fixes after the same Render API URL is redeployed.

## Validation and remaining work

- Full Flutter suite: 219 passed. Final startup test also checks that unvisited
  account tabs do not make extra profile requests.
- Full Laravel suite: 86 tests, 1,183 assertions, passed on isolated in-memory
  SQLite. Mail tests use synthetic credentials and mocked HTTPS responses.
- Flutter analysis: no errors or warnings; existing informational findings remain.
- Release APK built for ARM32, ARM64 and x86-64; Android signature verified.
- No phone is connected. Installed-app upgrade, approved-rider live login, GPS,
  real OTP delivery, signed-in earnings and money/receipt ownership remain to be
  verified after backend deployment.
- `delmundo-maverick/Shopleap-Web-App` could not be fetched with the available
  GitHub credentials. The local copy at `C:/Users/PC/Downloads/Shopleap-Web-App`
  is on a 24 October commit and lacks money code. Read access to the current
  financial implementation is required to finish cash, receipts, paid/unpaid
  earnings and notification-read integration. No replacement balances were made.
