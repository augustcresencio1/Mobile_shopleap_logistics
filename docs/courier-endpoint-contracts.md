# Courier endpoint contract audit (2026-11-16)

Checked against `routes/api.php`, `CourierDeliveryController`,
`CourierEarningsController`, `CourierDeliveryProofService`, and
`CourierEarningsService`, and the Flutter services, models, and callers.
This is source and automated-test verification; no live courier orders were changed.

All paths below are relative to `/api`. Requests use the authenticated bearer
token and `Accept: application/json`. Access requires an active courier user,
an approved, active courier profile, an approved hub, and an active hub owner.
Every `{order}` is the exact stored `order_number`, never the internal `id` or
the waybill code. Legacy `/orders/{id}/...` backend routes remain available.

| Method and path | Request | Response consumed by Flutter |
| --- | --- | --- |
| `GET /courier/pickups` | No body; `filter=awaiting_accept` for requests, no filter for accepted pickups | `data` list; `order_number`, `waybill_code`, `buyer_name`, seller/shipping fields, status, pickup status and items |
| `POST /courier/pickups/{order}/accept` | No fields | Success message; errors propagate |
| `POST /courier/pickups/{order}/decline` | JSON `reason`, required string, max 500 | Success message; errors propagate |
| `POST /courier/pickups/{order}/confirm` | JSON `scan` containing the original scanned/manual text; controller validates it when present, max 256 | Success message and `status: PICKED_UP`; errors propagate |
| `GET /courier/deliveries` | No body | `data` list of assigned/out-for-delivery orders, parsed using the same order mapper |
| `POST /courier/deliveries/{order}/out` | No fields | Success message and `status: OUT_FOR_DELIVERY` |
| `POST /courier/deliveries/{order}/delivered` | Multipart `amount` and `proof_image`; optional `captured_at`, `latitude`, `longitude`, `notes` | Requires HTTP 200 and `proof.uploaded: true`; parses nullable `earning` and proof metadata |
| `POST /courier/deliveries/{order}/failed` | JSON `reason`, required string, max 500; no `note` field | Success message and `status: DELIVERY_FAILED` |
| `GET /courier/dashboard` | No body | Root pickup/delivery count maps, `delivered_today`, `earned_today`, `currency` |
| `GET /courier/history` | `page`, optional `from`, `to`, `status=delivered\|returned` | `data` and `meta`; public reference, customer/address, outcome, COD, earning and proof metadata |
| `GET /courier/earnings` | Earnings filters below | Same root summary as `/earnings/summary` |
| `GET /courier/earnings/summary` | Earnings filters below | Root totals and daily entries; nullable money stays unavailable and valid zero stays zero |
| `GET /courier/earnings/rate` | No body | Root nullable `amount`, `currency`, `effective_from` |
| `GET /courier/earnings/history` | Same earnings filters, plus `page` | `data` and `meta`; public reference, nullable amount/timestamps and proof metadata |

Earnings filters are `period=today|week|month|all|7d|30d|custom`, or
`preset=today|7d|30d|custom` (preset takes precedence). A custom range requires
`from` and `to` as `YYYY-MM-DD`, spanning 1–366 inclusive calendar days in
Asia/Manila. Existing earnings/history parsing already matches these contracts.

Delivery proof is JPEG, PNG, or WebP, at most 5 MiB, each side at least 640 px,
and at most 40 MP. `amount` is nonnegative COD with at most two decimal places;
notes allow at most 255 characters. Retries send the same saved photo and fields.

The scanner UI and manual entry share the same lookup: match the waybill/public
reference from the assigned pickups list, falling through to deliveries for a
delivery scan. QR wrappers, tracking URLs and legacy numeric labels are resolved
without calling `/courier/orders/scan/{code}`. Pickup confirmation then posts to
the resolved public order number with `{"scan":"original scanned text"}`.

The recipient key is **`data[].buyer_name`**, selected explicitly by
`CourierDeliveryController::orderSelect()`. Flutter prioritizes this key even
when a nested `buyer` object lacks a name; the pickup detail reads the resulting
`Order.recipientName`. No recipient name is synthesized.
