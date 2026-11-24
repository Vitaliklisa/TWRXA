# Future Cloudflare Workers migration

This is a future option, not part of the current Vercel deployment. Firebase
Auth and Firestore remain the system of record.

If moving the commerce backend from Vercel to Workers:

1. Preserve the existing endpoint contracts used by Flutter:
   `/api/checkout-session`, `/api/stripe-webhook`,
   `/api/printify-webhook`, `/api/order-tracking`, `/api/sync-products`, and
   `/api/health`.
2. Replace Vercel request/response handlers with Worker `Request`/`Response`
   handlers and a scheduled Worker for product sync. Use Workers Secrets for
   Stripe, Printify, Firebase Admin, and cron credentials.
3. Re-implement Firebase ID-token verification and Firestore access using a
   supported server-side Firebase Admin runtime or the authenticated Firebase
   REST APIs. Verify token revocation and preserve owner-scoped order reads.
4. Verify Stripe signatures against `await request.arrayBuffer()` before
   parsing JSON, and verify Printify HMAC signatures against the original raw
   bytes. Never parse/reserialize webhook bodies before signature validation.
5. Retain the checkout invariants: prices and variant IDs come from Firestore,
   all cart lines are validated, destination charge metadata matches the
   stored order, and fulfillment is idempotent/reconcilable.
6. Recreate health reporting, catalog last-sync metadata, deployment
   configuration, and a daily-or-better schedule supported by the selected
   Cloudflare plan.
7. Test with Stripe test mode and a Printify test/draft order, then update the
   frontend API base only if the Worker is intentionally cross-origin. If it
   becomes cross-origin, use a strict allowlist for CORS and Firebase token
   forwarding.

Do not configure Vercel and Workers to process the same Stripe or Printify
webhooks simultaneously. Switch provider webhook destinations only after the
Worker has passed staging verification, otherwise an order could be fulfilled
twice.
