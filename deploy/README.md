# Rider backend on Render Free

Deployment is Live at https://shopleap-rider-api-august.onrender.com. See `docs/RENDER_DEPLOYMENT_2026-11-16.md` for the verified results, current APK URL, and remaining cutover work.

Create a Docker web service from `augustcresencio1/Mobile_shopleap_logistics`, branch `main`. Select **Free** and **Singapore**. Leave Root Directory empty. Use Dockerfile Path `./Dockerfile`, Docker Build Context `.`, and Health Check Path `/up`. Automatic deploys stay off. The Docker build context contains backend source only.

Inject the existing local configuration as environment variables. Never commit it, generate a different APP_KEY, run migrations, seed the shared database, or upload local storage contents.

Required names: `APP_KEY`, `APP_URL`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT`, `R2_PRIVATE_BUCKET`, `R2_PUBLIC_BUCKET`, `R2_PUBLIC_URL`.

The image sets production mode, debug off, PostgreSQL with required TLS, private R2 uploads, file cache/sessions, synchronous queues, trusted ingress proxies, and CA bundle paths. Public `/up` does not query application tables. Apache binds to Render's `PORT`; access logs omit query strings, credentials, and request bodies. No migrations or seeders are copied into the runtime image.

## Current rider APK and deferred features

The owner requested a separate rider APK connected directly to this service while deferring missing backend features. The current build `20261117` uses `https://shopleap-rider-api-august.onrender.com/api`; see `docs/RIDER_RENDER_APK_2026-11-16.md` for its link and checks. See `docs/mobile-api-route-audit.md`, `docs/mobile-account-integration.md`, and `docs/rider-money-integration.md` for the missing cash/receipt, account and notification route/response details. Those features are not represented as working in this release.

Render Free blocks outbound SMTP ports. The existing Gmail SMTP configuration alone cannot deliver OTP here. An HTTPS email relay/provider must be configured and tested before using this backend for registration or password reset. Startup prints that limitation without printing any email content or credentials. No OTP delivery is claimed by a passing health check.

`SUPABASE_URL` and `SUPABASE_SERVICE_KEY` enable this backend's realtime broadcasts. They are absent from the current local environment. Configuring this service's realtime broadcasts remains pending; the existing web backend is unchanged.

Warm up a Free service by opening its `/up` URL a few minutes before the presentation. It can sleep after 15 idle minutes. Rehearse this APK with mobile data and the development PC turned off before the presentation.
