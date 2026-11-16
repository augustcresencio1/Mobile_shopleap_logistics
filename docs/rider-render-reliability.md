# Rider Render reliability fixes

Prepared on 16 November 2026. These changes are local and have not been deployed
to the live Render service.

## Findings

- The rider service is `https://shopleap-rider-api-august.onrender.com` from
  `augustcresencio1/Mobile_shopleap_logistics`, branch `main`.
- Public live checks returned `/up` 200, `/api/hubs` 200,
  `/api/courier/home` 401 and `/api/courier/cash/summary` 404.
- The rider repository originally lacked cash, receipt and stored-notification
  endpoints and paid/unpaid earnings fields. A read adapter now exposes the
  existing web ledger records; no replacement balances or historical entries
  are generated.
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
  development signing key, and uses build number 20261119 / version 1.0.2.
- `CourierMoneyService` follows the main web app's `MoneyMovementQueries` and
  `PayoutQueries`: only frozen rider ownership and unreversed delivery postings
  qualify for cash/payout calculations. Handover allocations reduce parcel cash;
  shortages are already part of cash on hand. Current hub changes never reassign
  old money. Paid/unpaid totals use delivery dates rather than payout dates.
- Cash summary/history, rider-owned handover/payout HTML receipts, and stored
  notification read/read-all routes match the existing APK. Receipts are native
  HTML with inline styles and escaped values, without web build assets or scripts.
  Paid/unpaid values remain unavailable when payout tables are missing; cash
  returns a 503 instead of pretending that an absent schema means zero cash.
- New deliveries now post through the main web app's `LedgerService` and its
  idempotency keys inside the same transaction as proof metadata, COD, status,
  frozen earnings and order events. Seller funds use the same logistics-routing
  entries and `seller_settlement_orders` allocation as the main web backend.
  Missing or inconsistent financial data rolls back the delivery and removes the
  new proof file. A committed retry returns the original snapshot without posting
  again. Missing rates keep pay unavailable while recording real collected cash.

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
LOGISTICS_SELLER_SETTLEMENTS=true
```

An existing Render environment value overrides Docker defaults. In particular,
change an existing `MAIL_MAILER=smtp` value. An API key alone does not establish
sender verification or live delivery. Do not paste keys or passwords into chat.
Match `LOGISTICS_SELLER_SETTLEMENTS` to the main web backend (its source default
is true). No migrations, historical reconstruction, backfill or production record
changes were performed during development. New live deliveries will create their
normal balanced postings after deployment. The startup script rebuilds Laravel's
configuration and route caches on deployment.

Install the new APK over the existing rider app and sign in again if necessary.
Rebuilding an APK alone does not deploy Laravel fixes. An existing APK can use
compatible backend fixes after the same Render API URL is redeployed.

## Validation and remaining work

- Full Flutter suite: 219 passed. Final startup test also checks that unvisited
  account tabs do not make extra profile requests.
- Full Laravel suite: 102 tests, 1,377 assertions, passed on isolated in-memory
  SQLite. Mail tests use synthetic credentials and mocked HTTPS responses.
- Flutter analysis: no errors or warnings; existing informational findings remain.
- Release APK built for ARM32, ARM64 and x86-64; Android signature verified.
- No phone is connected. Installed-app upgrade, approved-rider live login, GPS,
  real OTP delivery, signed-in earnings and money/receipt ownership remain to be
  verified after backend deployment.
- Git access subsequently succeeded. The authoritative money implementation was
  inspected on `feature/money-remittance` at `bca762a` and the latest `main` at
  `fb497769ca0345856a25cddf28c2c1baed848397` in
  `delmundo-maverick/Shopleap-Web-App`. Reference source is in
  `.reference/shopleap-money`; the old Downloads checkout was not changed.
- The delivery posting gap has been closed by `CourierDeliveryLedgerService`,
  adapting `OrderLedger::delivered` and `SellerSettlements::routeOrder` while
  sharing the canonical `LedgerService`, references, accounts and keys. Tests
  cover cash/earnings visibility, balanced debit/credit entries, seller routing,
  missing rates, commission validation, schema failures, storage cleanup,
  changed-payload rejection and lost commit acknowledgements. Older delivered
  orders are never backfilled by a retry or a Cash read.
- Before deploying, confirm the Render service uses the same PostgreSQL database
  containing `wallet_accounts`, `ledger_transactions`, `ledger_entries`,
  `seller_settlement_orders`, `rider_cash_handovers`,
  `rider_cash_handover_items`, `rider_payouts`, `rider_payout_items`, and
  `notifications`, as well as the recorded `orders.commission_amount`. These
  migrations belong to the main financial backend and were not run from this
  workspace. The new APK retains the same endpoint contract and a higher version
  code for installation over the existing rider app.
