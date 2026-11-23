# TWRXA Supply Co.

TWRXA is a responsive storefront demo built with Flutter for web, Android, and
iOS. Its visual identity pairs near-black surfaces with acid green, ultraviolet
purple, and hot-pink accents.

## Storefront

- Browse a sample apparel and accessories drop without signing in.
- Filter by category and search product names or descriptions.
- Open product details, choose a size, and add items to the bag.
- Adjust quantities and review the subtotal in the bag.
- Use the responsive layout on desktop and mobile screens.

The catalog, prices, and product artwork are demo content. The bag is held in
memory for the current session. Checkout is intentionally a notice-only demo:
there is no payment processing, order submission, or customer data collection.

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

The current app launch is a public shop experience and does not require
Firebase configuration or an account.

Regenerate the shared artwork and platform assets with:

```bash
node scripts/generate-flutter-icons.mjs
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```
