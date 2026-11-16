# Rider Render deployment — November 16, 2026

The existing local Laravel rider backend is deployed and **Live** on Render Free in Singapore, in August Kristopher M. Cresencio's separate account (`augustcresencio022@gmail.com`). Source: `augustcresencio1/Mobile_shopleap_logistics`, branch `main`, deployed commit `989c651829cb9330e1395d13bb4941cade5593ab`.

- API base: https://shopleap-rider-api-august.onrender.com/api
- Health: https://shopleap-rider-api-august.onrender.com/up
- Dashboard: https://dashboard.render.com/web/srv-dbtej0s9v7es73add8cg
- First successful deployment: `dep-dbtej1k9v7es73addah0`, completed November 16 at 7:33 PM Singapore/Manila time.
- Service: `srv-dbtej0s9v7es73add8cg`; plan Free; automatic deploys off.

The existing APP_KEY, shared PostgreSQL and R2 settings are injected as runtime environment variables. They were not committed or printed. No migrations, seeders, schema changes, order actions, or upload writes ran during deployment.

## Verified against the deployed service

| Check | Result | Response time |
| --- | --- | --- |
| `GET /up` | HTTP 200 | 0.240 s |
| `GET /api/hubs` | HTTP 200 JSON; real database read | 0.525 s |
| Empty `POST /api/courier/login` | HTTP 422 JSON validation | 0.638 s |
| Unsigned `GET /api/courier/me` | HTTP 401 JSON | 0.121 s |

The isolated package check also passed package discovery, config/route/view caching, health/auth/validation responses, and HTTPS proxy handling with **zero database queries, emails, or R2 writes**.

## Current APK and remaining work

The owner subsequently requested an APK connected directly to this rider Render service while deferring the missing backend features. The new [Render-connected rider APK](https://pub-08abb33dded04b0daaa0e3029235c29c.r2.dev/mobile-demo/2026-11-17/Shopleap-Rider-Render-c858c09df3ce.apk) is build `20261117` and uses `https://shopleap-rider-api-august.onrender.com/api`. See `RIDER_RENDER_APK_2026-11-16.md` for installation and compatible APK updates. The earlier build `20261116` used the web API.

Remaining backend work and phone verification:

1. Complete or integrate the missing cash, receipt, notification-read, account and other route/response differences described in `mobile-api-route-audit.md`, `mobile-account-integration.md`, and `rider-money-integration.md`. Do not manufacture financial records or apply shared-database migrations.
2. Configure and test an HTTPS OTP mail relay. This service currently preserves the local SMTP configuration, but SMTP cannot deliver from Render Free. Registration and password-reset mail are **not verified or ready** on this service.
3. Configure `SUPABASE_URL` and `SUPABASE_SERVICE_KEY` if this backend must broadcast rider updates; the current local environment did not include them. Preserve the existing online app's behavior while cutover is pending.
4. Rehearse approved rider login, home, pickup/delivery, proof upload, camera/GPS, chat, financial reads and receipt ownership on the new backend. The public checks above do not prove signed-in behavior.
5. Future Flutter changes require another APK with the same package and signing key and a build number higher than `20261117`. Compatible backend fixes can be deployed at the same API URL without rebuilding the app.

Open `/up` a few minutes before a demo to wake a sleeping Free service, then wait for the health response and sign in. Keep mobile data available and test with the development PC turned off.
