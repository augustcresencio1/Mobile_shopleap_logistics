Rider navigation opens external Google Maps directions URLs. No embedded map,
Google API key, geocoding API, or Google distance/ETA service is used.

The assigned courier hub is the final station. Stops keep their server order;
routes are not automatically optimized. Long routes are split into sections of
at most three waypoints plus a destination so mobile browser fallback also works.
All stops remain in the plan. Links use a valid saved pin when available and the
address alone otherwise; names, order numbers, and pickup schedules are excluded.

GET /api/courier/navigation/route?role=pickup|delivery returns assigned active
stops and the assigned hub. Call and Text open the phone dialer and SMS composer.

The rider explicitly starts a live trip on an order screen. Location sharing
continues while using Maps or when the phone is locked, until the trip ends or
the rider stops it. See rider-live-tracking.md for the authenticated upload and
hub polling contract and device limitations. Straight-line distance uses the
destination pin; approximate ETA uses GPS speed, or 20 km/h when stationary.
These estimates do not include roads or traffic. Google Maps uses its own phone
location while the rider navigates in that app.

POST /api/courier/orders/{id}/arrived accepts role, latitude, longitude, accuracy,
and recorded_at. The server checks assignment, trip stage, fresh GPS (within two
minutes), and the saved destination pin. It records an order event without
changing pickup/delivery status. The default 150 m check returns a warning.
Set PICKRUSH_ENFORCE_ARRIVAL_RADIUS=true and refresh Laravel configuration to
require a pin, an in-radius location, and GPS accuracy of 150 m or better.

Current address tables have no coordinate columns. Delivery pins can be read
from orders.shipping_address as latitude/longitude, lat/lng, or nested location
or pin objects. The pin must be captured by the ordering/admin flow; it is never
inferred from a name or address. Seller/hub latitude and longitude are used if
those fields are supplied by the backend later. Without a pin, address navigation
works and arrival verification reports that distance could not be checked.

Android requests coarse and precise location access at runtime. iOS declares
NSLocationWhenInUseUsageDescription, Always permission, and background location
for live trips. Do not set BYPASS_PERMISSION_LOCATION_ALWAYS=1 for live tracking.
Adding the native GPS plugin requires a full app rebuild, not hot reload.

References:
- https://developers.google.com/maps/documentation/urls/get-started
- https://pub.dev/packages/geolocator
