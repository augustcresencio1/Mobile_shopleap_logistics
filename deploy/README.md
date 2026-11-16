# Rider backend on Render Free

Create a Docker web service from `augustcresencio1/Mobile_shopleap_logistics`, branch `main`. Select **Free** and **Singapore**. Leave Root Directory empty. Use Dockerfile Path `./Dockerfile`, Docker Build Context `.`, and Health Check Path `/up`. Automatic deploys stay off. The Docker build context contains backend source only.

Inject the existing local configuration as environment variables. Never commit it, generate a different APP_KEY, run migrations, seed the shared database, or upload local storage contents.

Required names: `APP_KEY`, `APP_URL`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT`, `R2_PRIVATE_BUCKET`, `R2_PUBLIC_BUCKET`, `R2_PUBLIC_URL`.

The image sets production mode, debug off, PostgreSQL with required TLS, private R2 uploads, file cache/sessions, synchronous queues, trusted ingress proxies, and CA bundle paths. Public `/up` does not query application tables. Apache binds to Render's `PORT`; access logs omit query strings, credentials, and request bodies. No migrations or seeders are copied into the runtime image.

## Cutover is a separate step

The current published APK continues to use `https://shopleap.shop/api`. Do not switch it to this local backend until the documented API differences and phone checks are resolved. See `docs/mobile-api-route-audit.md` and `docs/rider-money-integration.md`: this local backend is missing cash/receipt and notification read routes and some response fields. Completing those features was deferred by the owner.

Render Free blocks outbound SMTP ports. The existing Gmail SMTP configuration alone cannot deliver OTP here. An HTTPS email relay/provider must be configured and tested before using this backend for registration or password reset. Startup prints that limitation without printing any email content or credentials. No OTP delivery is claimed by a passing health check.

`SUPABASE_URL` and `SUPABASE_SERVICE_KEY` enable this backend's realtime broadcasts. They are absent from the current local environment; the existing app and web backend retain their current realtime behavior while the APK stays on the web API.

Warm up a Free service by opening its `/up` URL a few minutes before the presentation. It can sleep after 15 idle minutes. Test with mobile data and the development PC turned off before switching the APK to the new API.
