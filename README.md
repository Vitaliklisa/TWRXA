# TWRXA Supply Co.

TWRXA is a responsive storefront demo built with Flutter for web, Android, and
iOS. Its visual identity pairs near-black surfaces with acid green, ultraviolet
purple, and hot-pink accents.

## Storefront

- Browse a sample apparel and accessories drop without signing in.
- Filter by category and search product names or descriptions.
- Sort the current catalog by newest, oldest, and price in either direction.
- Open product details, choose a size, and add items to the bag.
- Persist guest carts in browser cookies or native SharedPreferences; signed-in
  carts are synchronized to Firestore.
- Adjust quantities, review the subtotal, and open secure Stripe Checkout.
- Track owner-scoped Printify orders, browse the FAQ, and read the Public Offer.
- Use the responsive layout on desktop and mobile screens.

The local catalog, prices, and product artwork are sample content. Secure
checkout requires the Vercel backend environment, server-side
product/Printify mappings, Stripe Connect account, and provider webhooks
described in [docs/BACKEND_DEPLOYMENT.md](docs/BACKEND_DEPLOYMENT.md). Firebase
Auth and Firestore remain the identity and catalog/order store; checkout and
fulfillment run on Vercel. Do not accept live orders until the Public Offer
placeholders are completed and reviewed.

## Run locally

```bash
flutter pub get
flutter run -d chrome
```

For a browser-accessible local preview with hot reload:

```bash
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080
```

Build the web app with:

```bash
flutter build web --release
```

## App identity

- Storefront UI: `lib/screens/twrxa_shop_screen.dart`
- Colors and shared Material styling: `lib/core/theme.dart`
- Web title, icon, and install metadata: `web/index.html` and `web/manifest.json`
- Shared icon/splash source: `scripts/generate-flutter-icons.mjs`

Browsing does not require an account. Checkout creates a Firebase anonymous
session and requires the TWRXA Firebase configuration and Vercel server setup
in [docs/BACKEND_DEPLOYMENT.md](docs/BACKEND_DEPLOYMENT.md). The checked-in
Android and iOS Firebase app options still target the prior `datedawn`
project.

Regenerate the shared artwork and platform assets with:

```bash
node scripts/generate-flutter-icons.mjs
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```
