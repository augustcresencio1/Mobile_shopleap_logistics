# Rider realtime refresh implementation and write audit

The backend sends a timestamp-only Supabase HTTP Broadcast to
`rider:{courier_profiles.id}`, event `refresh`. Flutter fetches the authorized
Laravel APIs after the signal. No schema changes or `postgres_changes`
subscriptions are needed. The backend service key stays in the backend's own
environment. The existing Flutter publishable key remains the client key.

## Files changed or created

Backend/configuration:

- `.env.example` — empty Supabase placeholders only.
- `config/services.php` — Supabase environment bindings.
- `app/Services/RiderRealtime.php` — shared HTTP transport, missing-config warning,
  HTTP exception reporting, accepted-status debug log, unchanged notify signatures.
- `app/Services/RiderRefresh.php` — recipient resolution and `DB::afterCommit`.
- `app/Models/Order.php` — model for the existing orders table.
- `app/Models/Message.php` — model for the existing messages table.
- `app/Models/OrderEvent.php` — model for the notification source table.
- `app/Observers/OrderObserver.php` — current/original pickup, delivery and earning riders.
- `app/Observers/MessageObserver.php` — current/original conversation participants.
- `app/Observers/OrderEventObserver.php` — current/original order owners.
- `app/Providers/AppServiceProvider.php` — observer registrations.
- `app/Http/Controllers/Api/CourierDeliveryController.php` — direct refresh for
  atomic order/event writes and chat read markers; message creation uses its model.
- `app/Http/Controllers/Api/RiderNavigationController.php` — observed arrival event.
- `app/Console/Commands/RiderRealtimeTest.php` — status-only diagnostic command.

Flutter files below are relative to `frontend/mobileshopleap_logistic_app/`:

- `lib/core/services/live_refresh.dart`
- `lib/screens/home/main_shell.dart`
- `lib/screens/chat/chat_list_screen.dart`
- `lib/screens/chat/chat_room_screen.dart`
- `lib/screens/dashboard/courier_dashboard_screen.dart`
- `lib/screens/dashboard/pickup_dashboard_screen.dart`
- `lib/screens/dashboard/delivery_dashboard_screen.dart`
- `lib/screens/money/cash_screen.dart`
- `lib/screens/profit/profit_screen.dart`

Tests/documentation:

- `tests/TestCase.php` — disables real Supabase credentials and stray HTTP in tests.
- `tests/Feature/RiderRealtimeTest.php`
- `tests/Feature/CourierEarningsTest.php`
- `tests/Feature/CourierChatTest.php`
- `frontend/mobileshopleap_logistic_app/test/live_refresh_test.dart`
- `frontend/mobileshopleap_logistic_app/test/cash_screen_test.dart`
- `frontend/mobileshopleap_logistic_app/test/profit_screen_test.dart`
- `frontend/mobileshopleap_logistic_app/test/chat_notifications_test.dart`
- `frontend/mobileshopleap_logistic_app/test/money_notification_test.dart`
- `docs/rider-realtime.md`

The notification test's existing Cash label assertion now matches the existing
`Cash on Hand` UI text. Production labels were not changed.

## Event coverage and rider identifiers

All paths below end in `RiderRefresh::riders()` -> `DB::afterCommit()` ->
`RiderRealtime::notifyMany()` -> `notify()`. Outside a transaction, afterCommit
runs immediately because the SQL write is already committed. Recipient IDs are
captured before Eloquent resets originals. Rollbacks discard scheduled pushes.

| Event | Existing table / model | Rider identifier | Refresh trigger |
| --- | --- | --- | --- |
| Order creation; pickup/delivery assignment and reassignment | `orders` / `Order` | `pickup_rider_id`, `delivery_rider_id`, plus `earning_courier_id` | Registered `OrderObserver::saved/deleted`; both current and original values. No order creation/assignment endpoint exists in this checkout. |
| Pickup acceptance/decline | `orders` and `order_events` | Both order rider columns, plus saved earning owner | `acceptPickup/declinePickup` -> `logEvent` -> direct `RiderRefresh::orders`. |
| Pickup confirmation; start delivery; failed delivery | `orders`, `order_events`, optional `parcel_events` | Both order riders, plus earning owner | `pickup/startDelivery/failDelivery` -> atomic `transition` -> `logEvent` -> direct refresh. |
| Delivered, COD collected, saved rider earnings, delivery proof | `orders`, `order_delivery_proofs`, event tables | Both order riders and `earning_courier_id`; proof's `courier_id` is also a profile ID | `recordDelivery` -> `logEvent` -> direct refresh inside the delivery transaction, sent after commit. Already-recorded retries do not write or send another backend event. |
| Chat creation/edit/delete | `messages` / `Message` | `conversation_participants.user_id` mapped through `courier_profiles.user_id` to its `id` | `sendMessage` uses `Message::create`; `MessageObserver::saved/deleted` resolves participants in both current and original conversations, including hub conversations with no order. |
| Chat read/unread change | `conversation_participants` | Its `user_id` mapped to profile ID | `markChatRead` calls `RiderRefresh::users` only when its monotonic SQL update actually changes a marker. |
| Notification/event created/edited/deleted | `order_events` / `OrderEvent` | `order_id` -> assigned order riders and earning owner | SQL `logEvent` explicitly refreshes the order. Arrival uses `OrderEvent::create`. Registered `OrderEventObserver` covers other model saves/deletes, including original/current `order_id`. |
| Cash handover, payout, transaction or balance ledger | No implementation/model/writer present | Must use actual record owner profile; resolve a `user_id` first if necessary | External backend integration required; see below. COD and order earnings in this checkout are covered above. |

## SQL writes that bypass observers

The production PHP audit covers `app/`, `routes/`, `database/`, `resources/`
and `public/`, excluding dependencies, generated build output and inactive backups.

| Location | Query-builder write | How it is covered |
| --- | --- | --- |
| `CourierDeliveryController::transition` | `orders` conditional `update`, including the failure attempt increment expression | All successful writes call `logEvent`, which explicitly resolves and refreshes every order rider after commit. |
| `CourierDeliveryController::acceptPickup` | `orders` conditional `update` | Same shared `logEvent` hook after the successful update. |
| `CourierDeliveryController::declinePickup` | `orders` conditional `update` | Same shared hook. |
| `CourierDeliveryController::recordDelivery` | `order_delivery_proofs` `insert`; `orders` `update` of status, COD and earnings snapshot | Same shared hook after proof, order and event writes inside the transaction. Failed/rolled-back writes do not push. |
| `CourierDeliveryController::logEvent` | `order_events` `insert`; conditional `parcel_events` `insert` | Direct `RiderRefresh::orders` after all event inserts; no duplicate model observer broadcast for the same SQL event. |
| `CourierDeliveryController::sendMessage` | `conversations` `insertGetId`; `conversation_participants` `insert`; `conversations` `update` of `last_message_at` | The associated `Message::create` observer captures recipients after participants exist, and broadcasts after the whole transaction, including the conversation update, commits. |
| `CourierDeliveryController::markChatRead` | `conversation_participants` conditional `update` of `last_read_at` | Direct `RiderRefresh::users` when affected rows > 0. The monotonic guard prevents repeated GET/push loops. |
| Former `CourierDeliveryController::sendMessage` message insert | Previously `messages` `insertGetId` | Refactored to `Message::create`, so the observer fires. |
| Former `RiderNavigationController::arrived` event insert | Previously `order_events` `insert` | Refactored to `OrderEvent::create`, so the observer fires. |

No other production order/chat/notification/financial SQL writes were found.
Authentication token deletes and user/courier profile updates are account/auth
operations, with no cash/balance fields. Rider tracking writes a cache, not the
financial/order tables. `rider_rates` is read here; its writer is external.

## Flutter behavior

- `Courier.fromJson` takes the ID from `courier.id`, never `user.id`.
  MainShell starts/restarts LiveRefresh when this profile ID becomes available.
- LiveRefresh subscribes only to `rider:<profile ID>` and broadcast `refresh`.
  It debounces pushes for 300 ms, invalidates HTTP caches, sets `lastPush` and
  emits `tick`. Fallback polling invalidates caches too, at 5 seconds while
  disconnected and 60 seconds while subscribed.
- Cash, Profit, pickup, delivery and courier dashboards refresh when visible on
  a tick. Chat list listens directly and receives the shell's shared thread
  updates; the chat room listens while it is the current resumed route.
- Cash and Profit apply the 30 second throttle only to fallback polling. A
  new push bypasses it and supersedes an older in-flight request immediately.
  Generations discard older responses; failed refreshes clear stale balances.
  Inactive money pages reload on entry, using existing navigation ticks.
- Dashboards retain a pending push during a load and fetch again immediately
  after that request completes, rather than waiting for the next poll.
- The bell's stored-notification request bypasses its 60 second throttle on a
  push and supersedes an older request. Chat list/unread and bell order sections
  already had shell tick listeners; they remain in place. Separate chat and bell
  timers are 60 second backups. The chat room's separate timer is also 60 seconds;
  disconnected LiveRefresh ticks still refresh it every 5 seconds.
- Screen tick listeners are removed in dispose. Stop cancels fallback/debounce
  timers and removes the channel from the Supabase client. Generation checks
  discard callbacks from old subscriptions. Removal finishes before a topic is
  reused, and a profile change cannot restart realtime while the app is paused.

## External backend work still required

This repository does not contain seller/admin order creation or assignment,
seller/buyer/hub incoming-message writers, `rider_rates` writers, cash ledger,
handover, payout, transaction or stored money-notification models/controllers.
An observer registered in this PHP application cannot observe another process
writing the same database. Install the corresponding observer/service integration
in each application that owns those writes, or make that application send the
same HTTP Broadcast after its transaction commits.

For a query-builder reassignment in that other application, capture all old
profile IDs before the update, combine them with all new profile IDs, and pass
the captured values to `DB::afterCommit(fn () => RiderRealtime::notifyMany($ids))`.
For a user-owned financial/notification record, resolve both old/new user IDs
through CourierProfile first. For chat, resolve courier participants rather than
using `sender_id` as a channel ID. For a hub rate change, refresh the affected
hub's courier profile IDs after commit; historical saved pay should stay fixed.

The local routes also lack `/courier/cash/summary`, `/courier/cash/history`,
notification read/read-all endpoints and money receipt endpoints expected by
Flutter. Local `/courier/notifications` returns legacy order events, without
stored money notification metadata or unread pagination. Use the money backend
described in `docs/rider-money-integration.md` for those features, and install
the refresh hooks there. No replacement schema or financial records were created.

## Manual test steps (requires your environment)

1. In your own backend `.env`, set `SUPABASE_URL` to the Supabase Project URL
   matching the Flutter project's URL. Set `SUPABASE_SERVICE_KEY` to that
   project's backend-only **service_role JWT** API key. Do not put that key in
   Dart, Git, screenshots or command output. Keep the Flutter publishable key.
2. From the repository root, run `php artisan config:clear`.
3. Start the Laravel backend you intend to test. Point Flutter's existing API
   configuration at it. For Cash/payout testing, use the money backend with the
   external hooks above installed.
4. From `frontend/mobileshopleap_logistic_app`, run `flutter run`, sign in to an
   approved rider and keep the app in the foreground. Read the profile ID from
   the `courier.id` response or the `LiveRefresh: subscribing to rider:<id>` log.
5. Wait for `LiveRefresh: status=RealtimeSubscribeStatus.subscribed`.
6. While Flutter is running, in a second terminal at the backend root run
   `php artisan rider:realtime-test <courierProfileId>` using that numeric profile
   ID. HTTP **200/202** means the broadcast was accepted; **401/403** means the
   key/project authorization was rejected. No credentials or response body are
   printed. A missing URL/key reports missing configuration, and connection
   failures report that no HTTP response arrived.
7. Look for `LiveRefresh: PUSH received` in Flutter, followed by immediate visible
   screen API reads (after the 300 ms debounce). In Cash/Profit look for
   `Cash reload: tick` / `Profit reload: tick` even within 30 seconds of a load.
   The bell must refetch within its usual 60 second interval too.
8. In Laravel logs (`storage/logs/laravel.log` with the default single-file log
   channel), look for `RiderRealtime: broadcast accepted.` and its numeric
   `courier_profile_id` / `status` when debug logging is enabled. Missing config
   logs `RiderRealtime: Supabase URL or service key is missing.`. HTTP/network
   failures reach Laravel's exception reporter without failing the original action.
9. Exercise pickup accept/decline/confirm, start/fail/deliver and chat send/read.
   Verify dashboard, chat and bell updates with no manual refresh. Using an
   integrated seller/admin backend, reassign a parcel between two signed-in
   riders and verify both refresh. Test confirmed/short handovers and paid
   payouts only against the actual financial backend.
10. Pause/resume and sign out/in several times. Confirm a single active rider
    subscription and no callbacks from the prior rider. Disconnect the socket:
    ordinary screens should refresh via the 5 second fallback; money screens
    keep their 30 second polling throttle. Reconnect restores the 60 second backup.

Live endpoint verification is deliberately left to these steps: automated tests
use fake HTTP, an in-memory SQLite database and synthetic credentials, without
needing or printing your secrets. Flutter verification runs in a temporary copy
to preserve this checkout's build directory.

## Verification results

- Backend: `php vendor/phpunit/phpunit/phpunit --no-progress --do-not-cache-result`
  passed all **69 tests / 512 assertions**, including reassignment, nested rollback,
  old/new message and notification ownership, read markers, SQL order/COD writes,
  401/403/server/network failures and status-only diagnostic output.
- Flutter: **50 tests passed** across `cash_screen_test.dart`,
  `profit_screen_test.dart`, `chat_notifications_test.dart`,
  `money_notification_test.dart`, `notification_bell_test.dart`,
  `courier_home_api_test.dart` and `live_refresh_test.dart`.
- Dart analysis of the changed service, screens and tests passed with no issues.
- PHP Pint checks passed for the service, observers, models, provider, command,
  navigation controller and new realtime test infrastructure.
- No real Supabase broadcast, secret-dependent API check or device run was performed.

The transport and cleanup follow the primary documentation for
[Supabase Broadcast](https://supabase.com/docs/guides/realtime/broadcast) and
[Flutter channel removal](https://supabase.com/docs/reference/dart/removechannel).
