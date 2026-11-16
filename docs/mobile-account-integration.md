# Mobile account integration, part 1

Updated 16 November 2026. Flutter targets `https://shopleap.shop/api` by
default. `API_BASE_URL` overrides are normalized to end in `/api` once; the
logistics portal host is rejected. All paths below are relative to that base.

## Requests

| Method | Public path |
| --- | --- |
| GET | `/hubs` |
| GET | `/hubs/{hub}/barangays` |
| POST | `/courier/register` |
| POST | `/courier/verify-otp` |
| POST | `/courier/resend-otp` |
| POST | `/courier/login` |
| POST | `/courier/forgot-password` |
| POST | `/courier/reset-password` |

Registration sends multipart `or_cr_upload` and `license_upload`, plus the
registration fields including `hub_id`. Password reset submits `email`, `otp`,
`password`, and `password_confirmation` to `/courier/reset-password`; there is
no separate password-code verification API request. Hub-list failures are shown
in the registration UI instead of silently becoming empty dropdowns.

| Method | Authenticated path |
| --- | --- |
| GET | `/courier/me` |
| POST | `/courier/logout` |
| POST | `/courier/reapply` |
| POST | `/courier/account/profile` |
| POST | `/courier/account/password` |
| POST | `/courier/account/avatar` |
| DELETE | `/courier/account/avatar` |

Authenticated requests use `Authorization: Bearer <token>`. Pending and rejected
couriers can open Account settings; rejected couriers can submit reapplication.
The app does not gate these account requests on courier approval.

Account save sends `first_name`, `last_name`, `email`, `contact_no`,
`vehicle_type`, `plate_number`, `province`, `municipality`, `barangay`, and
`street_address`. Province and municipality are stored separately from the
combined City / Province label and prefilled from `/courier/me`. Account entry
and pull-to-refresh request fresh profile data. Password change sends
`current_password`, `password`, and `password_confirmation`.

Avatar upload displays the returned `avatar_url`, `photo_url`, or
`profile_photo_url` from the courier, top level, or user payload. A response
containing only the avatar URL preserves the existing account fields. Successful
removal also accepts an empty 204 response and clears the avatar; failed removal
retains the saved image.

## Production validation still needs confirmation

This workspace's Laravel application differs from the supplied production
contract. `routes/api.php` currently has `/courier/account/photo`, not the avatar
routes, and `CourierProfileController::uploadPhoto` validates multipart field
`photo`. Flutter now uses the requested avatar route and retains this **locally
verified `photo` field**. The production avatar controller is needed to confirm
its exact multipart field; renaming it to `avatar` solely because of the URL
would be a guess.

The local profile-update rules also omit province and municipality, whereas the
reported production validation requires them. Flutter sends those exact keys
using the existing values in `/courier/me`. Local Laravel account routes still
sit inside the approval middleware group, and local reapply and hub-barangay
routes are absent. These backend differences were not changed or deployed.

## Error handling

`ApiClient` handles JSON, multipart, DELETE, and receipt errors centrally:

- Authenticated 401 clears the token and response cache and notifies the app to
  navigate to login. Missing tokens fail locally. A delayed 401 from a previous
  session cannot clear a new session. Public login failures preserve any existing
  session.
- 403 preserves authentication and surfaces the server message. Startup displays
  an error with retry/logout rather than silently discarding the session.
- 404 surfaces the server message or a resource-not-found fallback.
- 422 retains the validation map and joins its field messages for display.
- 429 returns a consistent message and parses `Retry-After` seconds or HTTP dates,
  including on public requests. Authenticated retries honor the existing shared
  cooldown.

Regression tests in `account_photo_test.dart` and
`account_auth_contract_test.dart` use synthetic tokens and mocked responses.
They verify requests, address preservation, avatar display/removal, pending and
rejected account access, login navigation, and error handling. They do not
verify production validation, storage access, or a live authenticated upload.

Verification: all **30 targeted account/authentication, deployed-API, and cache
tests pass**. Dart analysis of `lib` reports no errors or warnings (existing
informational lint/deprecation notices remain). The full Flutter suite reports
**183 passed / 6 failed**. The failures concern UI expectations in untouched
screens: the cash label is `Cash on Hand` while its test expects `Cash on hand`;
four pickup tests expect an `OutlinedButton` while the screen uses a
`GradientFilledButton`; and one GPS test expects a permission request after a
single tap without dismissing the current location/battery explanation flow.
