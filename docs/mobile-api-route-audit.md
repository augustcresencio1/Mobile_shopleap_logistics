# Mobile API route audit

This is a historical snapshot before the part 1 account changes. See
[Mobile account integration, part 1](mobile-account-integration.md) for the
current avatar routes and account contract differences.

Checked on 16 November 2026 against the Flutter source and the routes registered
by this local Laravel application.

**Six endpoint patterns used by the mobile app are missing locally.** Matching
52 mobile route variants against Laravel's router produced 46 matches with valid
controller methods and the six 404 results below. Route matching did not execute
controllers or change application records.

All paths below include Laravel's `/api` prefix.

| Method | Missing local endpoint | What fails in the mobile app | Mobile source |
| --- | --- | --- | --- |
| GET | `/api/courier/cash/summary` | Cash on Hand and Outstanding Shortage cannot load. | `lib/core/services/cash_service.dart:13` |
| GET | `/api/courier/cash/history` | Cash Handovers cannot load or paginate. | `lib/core/services/cash_service.dart:31` |
| GET | `/api/courier/receipts/cash-handovers/{reference}` | Cash handover receipts cannot open. | `lib/models/receipt.dart:2` and `:15` |
| GET | `/api/courier/receipts/rider-payouts/{reference}` | Rider payout receipts cannot open. | `lib/models/receipt.dart:3` and `:15` |
| POST | `/api/courier/notifications/{id}/read` | Opening an unread notification cannot save its read state. | `lib/core/services/notification_service.dart:30` |
| POST | `/api/courier/notifications/read-all` | Mark all as read fails. | `lib/core/services/notification_service.dart:37` |

Mobile source paths are relative to
`frontend/mobileshopleap_logistic_app/`. The Cash screen waits for summary and
history together, so either missing cash endpoint causes the screen to show its
load error instead of balances and history.

**Two existing local responses also lack fields used by the mobile app.**

| Existing endpoint | Local response compared with mobile expectations | Visible effect |
| --- | --- | --- |
| `GET /api/courier/notifications` | `CourierDeliveryController.php:300` returns up to 50 order events with `note`. The mobile notification model expects `body`, `kind`, `url`, `read`, row `meta`, top-level `unread`, and pagination `meta`. | Event titles can appear, but descriptions are blank, unread count defaults to zero, rows default to unread, pagination defaults to one page, and money receipt/navigation metadata is unavailable. |
| `GET /api/courier/earnings/summary` and `GET /api/courier/earnings/history` | `CourierEarningsService.php:119` omits `accrued_unpaid` and `paid`; its history method at line 166 omits each row's `payout_status`. The mobile model reads these in `lib/models/earnings.dart:100` and `:127`. | Saved earnings can load, but paid/unpaid totals and payment status remain unavailable. |

The local repository does not contain the money ledger, handover, payout, or
stored money-notification implementation needed for these features. Adding route
declarations alone would not supply that functionality. This backend difference
is also documented in `docs/rider-realtime.md:125` and
`docs/rider-money-integration.md`.

**The app's source defaults to a different backend.**

`lib/core/services/api_config.dart:10` configures
`https://shopleap.shop/api`. An `API_BASE_URL` build override can select the local
backend instead. Editing this workspace's `routes/api.php` affects this Laravel
application when it is running; it does not update the deployed API or rebuild
the installed app.

Read-only GET requests to the configured deployed API returned:

| Deployed path after `/api` | HTTP status without a token |
| --- | --- |
| `/courier/me` | 401 |
| `/courier/cash/summary` | 401 |
| `/courier/cash/history` | 401 |
| `/courier/earnings/summary` | 401 |
| `/courier/earnings/history` | 401 |
| `/courier/notifications` | 401 |
| `/courier/receipts/cash-handovers/__route_audit__` | 401 |
| `/courier/receipts/rider-payouts/__route_audit__` | 401 |

These responses show that the server rejects unauthenticated requests. They do
not verify signed-in responses, balances, receipt ownership, or successful
receipt rendering. The receipt checks used placeholder references. No deployed
POST/PUT requests were sent.

An Android CPH2819 phone was connected. This audit did not inspect its installed
build's effective API URL or capture authenticated requests from the phone, so
the local missing routes are not proof that the installed app is receiving the
same failures.

**Verification:** Laravel registered all existing API controller actions with
valid methods. Authentication, order/pickup/delivery actions, dashboard, scanner,
history, navigation, tracking, chat, profile, and password route variants used by
the app matched locally; matching alone does not verify their runtime responses.
The existing backend suite passed with **76 tests and 1,029 assertions** using:

```powershell
php vendor/phpunit/phpunit/phpunit --colors=never --do-not-cache-result
```

No application source, configuration, installed app, or financial records were
changed. This report is the only added source file.
