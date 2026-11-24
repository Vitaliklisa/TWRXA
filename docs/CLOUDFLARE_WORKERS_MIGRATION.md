# Cloudflare Workers commerce API

The Cloudflare Worker implementation lives in `worker/` and is intended to
serve commerce endpoints on `api.twrxa.khomenko.de`. This repository change
adds the implementation alongside the existing Vercel handlers; it does not
deploy the Worker, change DNS, configure provider dashboards, or move webhook
destinations. Until the Worker is deployed and verified, keep the current
provider webhook destinations unchanged.

## Architecture

- Flutter sends commerce API requests to the Worker API hostname. The web
  build can override this with `API_BASE_URL`.
- Vercel forwards legacy `/api/*` requests to the Worker using HTTP 308, which
  preserves webhook POST methods and bodies.
- Firebase Authentication and Firestore remain the identity and data systems.
  The Worker verifies Firebase ID tokens and uses Firestore REST with a short
  lived Google OAuth access token signed using Web Crypto.
- Stripe Checkout uses Connect destination charges. Stripe webhooks are
  signature-verified against the original request bytes before processing.
- Printify API calls and webhooks handle catalog sync, fulfillment, and
  tracking. Printify webhooks are also verified against their original bytes.
- A daily Worker cron runs the catalog sync. Signed Printify product webhooks
  provide the near-real-time sync path.

## Configuration and deployment

See [BACKEND_DEPLOYMENT.md](./BACKEND_DEPLOYMENT.md) for the Worker variables
and secret names, Firebase permissions, commands, and staged rollout checklist.
The API hostname is configured as a Cloudflare Custom Domain in `wrangler.toml`;
Cloudflare manages its DNS record and certificate. Do not add a competing
`workers.dev` CNAME.

Deployment must be staged: deploy and configure the Worker, test checkout in
Stripe test mode and a Printify draft/test order, confirm tracking and retries,
then switch webhook destinations. Never configure Vercel and the Worker to
process the same provider events concurrently because that can duplicate
fulfillment.

## Validation

Run the local checks before deployment:

```powershell
npm run typecheck
npm run worker:test
npx wrangler deploy --dry-run --outdir dist
```

The dry run only builds the Worker bundle; `npm run worker:deploy` performs an
actual deployment and is intentionally not part of local validation.
