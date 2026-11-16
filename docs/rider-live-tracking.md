# Live rider location integration

The rider explicitly selects **Start live trip** on an assigned pickup/delivery.
This starts one app-wide location stream and a session at the Laravel API.
The app uploads the latest GPS about every five seconds. Leaving the order page
does not end the trip. Android uses an ongoing location foreground service and
wake lock while Maps is open or the phone is locked. The rider grants location
and notification permissions before starting. iOS declares background location
and requires Always location permission. An OS force-stop, process termination,
disabled GPS, or loss of connectivity can interrupt updates; the web must show
last-known locations as stale rather than continuing to label them live.

Stop live trip, logout, authentication expiry, or loss of the active assignment
stops sharing. A successful delivery/failure also stops that delivery's stream.
Pickup tracking can continue in PICKED_UP on the way to the hub; it ends when
the hub changes the order out of the pickup stage or the rider selects Stop.
Starting another order closes the previous session first. Only one selected
trip is shared at a time; this is not route optimization or a location history.

## API contract

All routes use Laravel Sanctum bearer authentication. Courier requests require
an approved active rider and approved active assigned hub. Never use the
Supabase anonymous key as authorization for this API.

- `POST /api/courier/tracking/start`: `order_id`, `role` (`pickup` or `delivery`),
  `latitude`, `longitude`, `accuracy`, `recorded_at` (UTC ISO date), optional
  `speed` (m/s), `heading` (degrees). Returns `data.session_id` and first fix.
- `PUT /api/courier/tracking/location`: `session_id` plus the same GPS fields.
  A fresh fix is at most two minutes old or one minute ahead of server time.
  Delayed older fixes cannot replace newer ones. `409` means the session stopped,
  expired, or was superseded. `403` means the assignment/trip is no longer valid.
- `POST /api/courier/tracking/stop`: `session_id`. Safe to repeat. A stop for an
  older session cannot stop a newer session, and late updates cannot restart it.
- `GET /api/logistics/rider-locations?per_page=100&page=1`: authenticated approved
  hub owner (`role=logistics`). Returns only that hub's approved active riders.
  Do not accept a client-supplied hub ID to choose another hub's locations.

Example hub response:

```json
{
  "data": [{
    "courier_id": 100, "name": "Rider", "hub_id": 10,
    "order_id": 1000, "role": "delivery", "tracking": true, "status": "live",
    "location": {
      "latitude": 14.6, "longitude": 120.98, "accuracy": 8,
      "speed": 5, "heading": 90, "recorded_at": "2026-11-08T04:00:00+00:00"
    },
    "received_at": "2026-11-08T04:00:01+00:00"
  }],
  "meta": {"current_page": 1, "last_page": 1, "total": 1, "poll_after_seconds": 5},
  "server_time": "2026-11-08T04:00:02+00:00"
}
```

`status` is `live` only if both GPS and upload are within 30 seconds. Otherwise
it is `stale`, `stopped`, or `unavailable`. An unavailable entry has `location:null`.
After five minutes without an upload, the cached fix expires. Show stopped fixes
as last known, and remove/relabel markers when entries become unavailable.
Location responses use `Cache-Control: no-store, private`; do not persist them
in browser storage or forward coordinates onto public broadcast channels.

## Web dashboard wiring

The actual web dashboard is in a different project, which is not available here.
Deploy these Laravel endpoints to the backend used by both mobile and web first.
The local API at `127.0.0.1:8000` and the placeholder production URL are not a
deployed integration. Configure the mobile API URL and the web API URL to point
to that backend, and use the hub owner's Sanctum token from the web login flow.
This repo's courier login cannot issue a hub-owner token.

Copy `resources/js/rider-location-poller.js` into the web project's JavaScript:

```js
import { createRiderLocationPoller } from './rider-location-poller.js';

const locations = createRiderLocationPoller({
  apiBaseUrl: 'https://YOUR-BACKEND/api',
  getToken: () => auth.accessToken, // Existing hub-owner login, held by the web app.
  onUpdate: ({ data, server_time }) => {
    // Update the existing rider list/map markers by courier_id.
    // Use location.latitude/longitude, display accuracy and received_at,
    // and visibly distinguish live, stale, stopped, and unavailable entries.
    renderRiders(data, server_time);
  },
  onError: error => showTrackingError(error.message),
});
locations.start();
// Call locations.stop() on logout or dashboard/component disposal.
```

The adapter polls without overlapping requests, reads every page, pauses hidden
tabs, refreshes on return, cancels on disposal, and stops on 401/403. Network
errors relabel the last live fixes as stale. Upload plus polling means updates
normally arrive within about 5–10 seconds plus network/server time. No map SDK,
Google API key, or continuous location broadcast is added to the mobile app.

Latest locations use a Laravel cache store, not order_events or a new DB table.
`RIDER_TRACKING_CACHE_STORE=file` works on a single backend instance. Multiple
backend instances must share a cache store, e.g. `redis` or `database`, configured
by the server team. Do not use the `array` store in production. Configuration
changes require `php artisan config:clear` (or rebuild the config cache).

## Device verification

Rebuild/reinstall the native app. On Android grant location and notifications,
start an assigned trip, open Maps, lock the phone, and observe a moving/fresh
location through an authenticated hub session. Then test Stop, logout, delivery
completion, disabled GPS, airplane mode, and return to the app. Check stale
status after 30 seconds offline and isolation from another hub's account.
Windows cannot validate the iOS background runtime; test an iOS build on a device.
For iOS do not set `BYPASS_PERMISSION_LOCATION_ALWAYS=1` for live tracking.

References: [geolocator](https://pub.dev/packages/geolocator),
[Android location foreground services](https://developer.android.com/develop/background-work/services/fgs/service-types#location).
