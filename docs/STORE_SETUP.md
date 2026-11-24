# TWRXA store integrations

The storefront now supports local catalog sorting, guest cart cookies on web,
Firebase Functions checkout/tracking, Stripe Connect destination charges, and
Printify order fulfillment. Before checkout can accept real orders, complete
the configuration below using the actual Stripe, Printify, and seller data.

## 1. Firebase

- Select the `twrxa-shop` Firebase project.
- Enable **Anonymous** sign-in in Firebase Authentication. Checkout creates a
  Firebase anonymous account for guests so an order is tied to a verified
  Firebase UID rather than a client-supplied identity.
- Cloud Functions require the Firebase Blaze billing plan.
- Configure Firebase options for every target you ship. The Web options point
  to `twrxa-shop`; the checked-in Android and iOS Firebase options still point
  to the older `datedawn` project and must be replaced with TWRXA app options
  before a native build can use these functions.

## 2. Server-side product catalog

Create one `products/{productId}` document for each sellable item in Firestore.
The document ID must match the Flutter cart's product ID. For example, the
`heavy-tee` document needs these fields:

```json
{
  "active": true,
  "name": "Heavyweight Tee",
  "price": 4800,
  "currency": "usd",
  "createdAt": "Firestore Timestamp",
  "printifyProductId": "YOUR_PRINTIFY_SHOP_PRODUCT_ID",
  "printifyVariants": {
    "S": 111111,
    "M": 222222,
    "L": 333333,
    "XL": 444444
  }
}
```

`price` is an integer in the currency's smallest unit (for example, 4800 is
USD 48.00). Accessories without selectable variants use a `default` entry in
`printifyVariants`. Use actual product and variant IDs from the connected
Printify shop; the function rejects missing or inactive catalog entries. The
Flutter catalog is currently sample content and does not contain real Printify
IDs.

Product documents are publicly readable and server-managed. Firestore rules
deny client writes to products and orders. Deploy the rules and product indexes
after adding the catalog.

## 3. Function parameters and secrets

Deploying prompts for these non-secret Firebase Functions parameters:

- `STRIPE_CONNECT_ACCOUNT_ID`: the connected Stripe account receiving the
  destination transfer (`acct_...`).
- `PRINTIFY_SHOP_ID`: numeric shop ID from the Printify API.
- `APP_BASE_URL`: the public HTTPS storefront URL. Defaults to
  `https://twrxa-shop.web.app`.
- `CHECKOUT_ALLOWED_COUNTRIES`: comma-separated ISO-3166-1 alpha-2 country
  codes. Defaults to `US,CA`.
- `FLAT_SHIPPING_AMOUNT_CENTS`: one flat checkout shipping rate in cents.
  Defaults to `0` (free shipping).
- `STRIPE_APPLICATION_FEE_BPS`: optional platform fee in basis points.
  Defaults to `0`; Stripe fees are charged to the platform for destination
  charges.

Set API credentials as Firebase secrets; never add them to Flutter, source
control, or Vercel client variables:

```powershell
firebase functions:secrets:set STRIPE_SECRET_KEY --project twrxa-shop
firebase functions:secrets:set STRIPE_WEBHOOK_SECRET --project twrxa-shop
firebase functions:secrets:set PRINTIFY_API_TOKEN --project twrxa-shop
firebase functions:secrets:set PRINTIFY_WEBHOOK_SECRET --project twrxa-shop
```

Deploy with:

```powershell
firebase deploy --only functions,firestore:rules,firestore:indexes --project twrxa-shop
```

The callable `createCheckoutSession` reads product prices and Printify variant
IDs from Firestore; cart-supplied prices are never used. It creates a Stripe
Checkout Session with `payment_intent_data.transfer_data.destination`. The
`fulfillOrder` webhook validates Stripe's signature and sends paid orders to
Printify's order endpoint and then its `send_to_production` endpoint. Stripe
webhook events to register: `checkout.session.completed`,
`checkout.session.async_payment_succeeded`,
`checkout.session.async_payment_failed`, and `checkout.session.expired`.
Use the URL printed for `fulfillOrder` after deployment.

For shipping/tracking synchronization, configure Printify webhooks for
`order:updated`, `order:shipment:created`, and `order:shipment:delivered` using
the deployed `printifyWebhook` URL and the same
`PRINTIFY_WEBHOOK_SECRET`. Printify signs the raw JSON body with
`X-Pfy-Signature: sha256=<HMAC-SHA256>`.

The order lookup callable checks the authenticated Firebase UID before
returning a tracking summary. Customers must use the same browser session or
Firebase account used at checkout. Tracking data is refreshed by Printify
webhook events.

## 4. Local checks

```powershell
npm --prefix functions run check
flutter test test/product_sort_test.dart
flutter test test/cart_repository_test.dart
flutter test test/twrxa_shop_test.dart
flutter analyze lib test
```

The Public Offer page intentionally identifies business, returns, contact, and
governing-law text that must be completed and reviewed before taking live
orders. The sample products, prices, shipping defaults, seller details, and
policy copy are not production configuration.
