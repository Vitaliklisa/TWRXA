# TWRXA commerce backend

TWRXA keeps Firebase Authentication and Firestore for identity, carts, product
catalog, and owner-scoped order records. The storefront remains hosted on
Vercel; the Cloudflare Worker in `worker/` serves commerce APIs on
`api.twrxa.khomenko.de`. The existing Vercel handlers remain in the repository
for rollback, but `vercel.json` forwards `/api/*` requests to the Worker. To
route traffic back to Vercel handlers, revert that redirect. No Firebase Cloud
Functions deployment is required.

## Before enabling checkout

1. Link the `Vitaliklisa/TWRXA` GitHub repository to the intended Vercel
   project and use the repository's existing `vercel.json` build settings.
   The build sends `API_BASE_URL` to Flutter; it defaults to the Worker
   subdomain.
2. Select Firebase project `twrxa-shop`. Enable Firebase Authentication Email
   and Password, Google, and Anonymous providers as appropriate. Add the
   deployed Vercel hostname (and the custom hostname only after it points to
   this Vercel project) to Firebase Authentication's authorized domains.
3. Create a service account with only the Firestore and Firebase Authentication
   user-lookup permissions needed by the Worker. Store its JSON key as the
   Cloudflare secret `GOOGLE_SERVICE_ACCOUNT_JSON`. Never put the key in
   Flutter, `VITE_*`, `NEXT_PUBLIC_*`, source control, or a chat message.
4. Configure Stripe Connect and Printify credentials as Cloudflare Worker
   secrets. Use Stripe test-mode keys and a test connected account until a
   separate live-mode approval is given.
5. Deploy Firestore security rules and indexes separately. This is safe on the
   Firebase Spark plan:

   ```powershell
   firebase deploy --only firestore:rules,firestore:indexes --project twrxa-shop
   ```

The repository does not verify the current Vercel Git connection, domain,
Firebase dashboard settings, provider credentials, or live webhook
registration. Confirm those settings in the respective dashboards before
enabling checkout.

## Vercel environment variables

Set these for the Vercel **server runtime** (Production and Preview as
appropriate), then redeploy. Values are intentionally not included here.

| Variable                       | Required | Purpose                                                                         |
| ------------------------------ | -------- | ------------------------------------------------------------------------------- |
| `FIREBASE_ADMIN_PROJECT_ID`    | Yes      | Must be `twrxa-shop`.                                                           |
| `FIREBASE_ADMIN_CLIENT_EMAIL`  | Yes      | Firebase Admin service-account email.                                           |
| `FIREBASE_ADMIN_PRIVATE_KEY`   | Yes      | Firebase Admin private key; preserve its newlines.                              |
| `STRIPE_SECRET_KEY`            | Yes      | Stripe secret API key. Start with a test-mode key.                              |
| `STRIPE_WEBHOOK_SECRET`        | Yes      | Signing secret for `/api/stripe-webhook`.                                       |
| `STRIPE_CONNECT_ACCOUNT_ID`    | Yes      | Destination account ID beginning `acct_`.                                       |
| `PRINTIFY_API_TOKEN`           | Yes      | Server-only Printify API token.                                                 |
| `PRINTIFY_WEBHOOK_SECRET`      | Yes      | HMAC secret configured for Printify webhooks.                                   |
| `PRINTIFY_SHOP_ID`             | Yes      | Numeric Printify shop ID.                                                       |
| `APP_BASE_URL`                 | Yes      | HTTPS storefront base URL used for checkout returns.                            |
| `CRON_SECRET`                  | Yes      | Random bearer secret for scheduled/manual catalog sync.                         |
| `PRODUCT_CURRENCY`             | No       | Three-letter currency; defaults to `USD`.                                       |
| `CHECKOUT_ALLOWED_COUNTRIES`   | No       | Comma-separated ISO country codes; defaults to `US,CA`.                         |
| `FLAT_SHIPPING_AMOUNT_CENTS`   | No       | Flat shipping amount in minor units; defaults to `0`.                           |
| `STRIPE_APPLICATION_FEE_BPS`   | No       | Platform fee in basis points; defaults to `0`.                                  |
| `FIREBASE_AUTH_DOMAIN`         | No       | Web build auth domain; defaults to `twrxa-shop.firebaseapp.com`.                |
| `VERCEL_DEPLOYMENT_CREATED_AT` | No       | Optional timestamp supplied by your deployment automation for health reporting. |

`GET /api/health` returns HTTP 200 with the deployment timestamp (or `null`),
latest product sync timestamp (or `null`), and `secretNamesPresent`, a boolean
array in the required-variable table order. `ok` is false when configuration or
Firestore connectivity is missing. It never returns any variable value,
Firebase project/account ID, or service-account data.

## API endpoints

- `POST /api/checkout-session` — requires a Firebase ID token. Reads product
  prices and Printify variant IDs from Firestore; ignores client-supplied
  prices and user IDs; creates a Stripe Checkout Session with a Connect
  destination charge.
- `POST /api/stripe-webhook` — verifies the raw request body against
  `STRIPE_WEBHOOK_SECRET`; on paid checkout events creates a Printify order
  with the verified shipping address and mapped product/variant/quantity,
  then sends it to production. Register `checkout.session.completed`,
  `checkout.session.async_payment_succeeded`,
  `checkout.session.async_payment_failed`, and `checkout.session.expired`.
- `POST /api/printify-webhook` — validates `X-Pfy-Signature`, fetches the
  signed order's latest Printify status, and updates its tracking data in
  Firestore. Configure the available order update/shipment topics in
  Printify.
- `GET /api/order-tracking?orderId=...` — requires the same Firebase account
  used for checkout and only returns that owner's order.
- `POST /api/sync-products` — accepts signed Printify product webhooks. It
  fetches all pages from the configured shop and upserts mapped products.
- `GET /api/sync-products` — runs a full sync only with
  `Authorization: Bearer <CRON_SECRET>`. Vercel Cron is configured for one
  daily run at 09:00 UTC, compatible with Hobby's daily schedule limit. Product
  webhooks are the near-real-time path; on plans without usable product
  webhooks, daily sync cannot guarantee an update within 60 minutes.
- `GET /api/health` — reports configuration booleans and sync/deployment
  timestamps, never secret values.

The Worker is on a dedicated API subdomain, so it allows browser requests only
from `APP_BASE_URL`; it does not enable wildcard CORS. Webhook routes verify
provider signatures over raw request bytes. Customer routes verify Firebase
ID tokens server-side, including revoked-token checks; Firestore rules remain
the authority for client-side reads and writes.

## Product and variant sync

The importer maps the available Printify variants into `variantMatrix` records
containing color, size, Printify variant ID, and server-side unit amount.
Color/size combinations are active only when each combination maps to one
unique Printify variant. Products with other ambiguous option dimensions
remain inactive rather than risking the wrong fulfillment item. Legacy
`printifyVariants` and `printifyVariantPrices` fields are also written for
compatibility.

After setting environment variables and deploying, run a sync in a protected
terminal:

```powershell
$env:CRON_SECRET = Read-Host "Vercel CRON_SECRET"
curl.exe -H "Authorization: Bearer $env:CRON_SECRET" `
  https://twrxa.vercel.app/api/sync-products
Remove-Item Env:CRON_SECRET
```

The scheduled sync uses that same bearer secret. Signed Printify product
webhooks use `PRINTIFY_WEBHOOK_SECRET`; request bodies from other sources are
rejected unless they carry the cron bearer secret. Removed products are marked
inactive when a signed delete webhook identifies them. Syncs never delete
Firestore documents.

Firestore creates the `products` collection on the first write. The
`variantMatrix` is read by the product detail UI, which submits the exact
Printify variant ID in checkout. Order and product client writes remain
denied by `firestore.rules`.

## Stripe and live-order safety

Use the Stripe Dashboard to create the webhook and copy its signing secret to
Vercel. The route uses Stripe Checkout, shipping-address collection, and
`payment_intent_data.transfer_data.destination`. Do not use live-mode keys
until the seller, fee, shipping, tax, refund, and Public Offer settings have
been verified and live processing is explicitly approved. This PR does not
deploy, change dashboard settings, or access Stripe.

The Printify create-order and send-to-production calls are protected by
Firestore fulfillment leases and stored order IDs. Because an external API
call and a Firestore write cannot share one transaction, review failed or
interrupted Printify submissions in provider dashboards before manually
retrying them.

## Cloudflare Workers path

The Worker uses Firestore REST with a short-lived Google OAuth token signed
using Web Crypto. It does not use `firebase-admin`, gRPC, or Node crypto.
`wrangler.toml` declares `api.twrxa.khomenko.de` as a Cloudflare Custom
Domain. Cloudflare creates the DNS record and certificate for a Custom Domain;
do not also create a CNAME to `workers.dev`, because an existing CNAME blocks
Custom Domain creation. The domain must be in an active Cloudflare zone.

Set these **secrets** after the Worker has been deployed once. The service
account JSON replaces the three `FIREBASE_ADMIN_*` Vercel variables; the
connected account and cron secret are additional secrets needed by the Worker:

| Secret                        | Purpose                                                           |
| ----------------------------- | ----------------------------------------------------------------- |
| `GOOGLE_SERVICE_ACCOUNT_JSON` | Service account JSON for Firestore and Firebase Auth user lookup. |
| `STRIPE_SECRET_KEY`           | Stripe secret API key. Use test mode first.                       |
| `STRIPE_WEBHOOK_SECRET`       | Stripe webhook signing secret.                                    |
| `STRIPE_CONNECT_ACCOUNT_ID`   | Destination account ID beginning `acct_`.                         |
| `PRINTIFY_API_TOKEN`          | Server-only Printify API token.                                   |
| `PRINTIFY_WEBHOOK_SECRET`     | Printify webhook HMAC secret.                                     |
| `PRINTIFY_SHOP_ID`            | Numeric Printify shop ID.                                         |
| `CRON_SECRET`                 | Bearer secret for scheduled/manual product sync.                  |

`APP_BASE_URL`, `APP_ALLOWED_ORIGINS`, `PRODUCT_CURRENCY`, `CHECKOUT_ALLOWED_COUNTRIES`,
`FLAT_SHIPPING_AMOUNT_CENTS`, and `STRIPE_APPLICATION_FEE_BPS` are ordinary
Worker variables in `wrangler.toml`. The production storefront origin must
match `APP_BASE_URL` or be listed exactly in `APP_ALLOWED_ORIGINS` for browser
CORS. Add any preview origin explicitly; wildcard origins are not accepted.
The Vercel web build accepts `API_BASE_URL` to override the default API
hostname for preview environments.

After review and merge, the operator can deploy from the repository root:

```powershell
npm run worker:dev
npx wrangler deploy --dry-run --outdir dist
npm run worker:deploy
```

The first real deploy creates the Worker. Then set each secret without putting
its value in source control or chat, and deploy again to activate them:

```powershell
npx wrangler secret put GOOGLE_SERVICE_ACCOUNT_JSON
npx wrangler secret put STRIPE_SECRET_KEY
npx wrangler secret put STRIPE_WEBHOOK_SECRET
npx wrangler secret put STRIPE_CONNECT_ACCOUNT_ID
npx wrangler secret put PRINTIFY_API_TOKEN
npx wrangler secret put PRINTIFY_WEBHOOK_SECRET
npx wrangler secret put PRINTIFY_SHOP_ID
npx wrangler secret put CRON_SECRET
npm run worker:deploy
```

The configured Custom Domain is created by Wrangler on deployment. If
attaching it in the dashboard instead, use **Workers & Pages → twrxa-api →
Settings → Domains & Routes → Add → Custom Domain** and enter
`api.twrxa.khomenko.de`; do not add a separate `workers.dev` CNAME.

Wrangler also configures a daily product sync at 09:00 UTC. Signed Printify
product webhooks remain the near-real-time path.

Repoint Stripe and Printify webhooks directly to the Worker once it has passed
test-mode verification. Do not have both Vercel and the Worker process the
same provider events. Vercel forwards old `/api/*` callers with HTTP 308
rather than 301 so POST methods and webhook bodies are preserved.

## Local checks

```powershell
npm run worker:test
npx wrangler deploy --dry-run --outdir dist
npm run test:commerce
npm run typecheck
flutter test
flutter analyze lib test
npm run build
```
