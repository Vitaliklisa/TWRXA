# TWRXA store setup

The storefront reads its catalog and signed-in cart from Firestore. Checkout,
Stripe webhooks, Printify fulfillment, order tracking, and catalog sync run in
Vercel Serverless Functions; Firebase Cloud Functions are not used.

Follow [Backend deployment](./BACKEND_DEPLOYMENT.md) to configure the Vercel
environment, provider webhooks, product sync, and Firestore rules/indexes.
Use [Cloudflare Workers migration notes](./CLOUDFLARE_WORKERS_MIGRATION.md) only
if the backend is intentionally moved off Vercel later.

The Public Offer page contains business, returns, contact, and governing-law
text that must be completed and reviewed before accepting live orders. Sample
prices, shipping defaults, seller details, and policy copy are not production
configuration.
