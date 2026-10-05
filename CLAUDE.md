# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

DigiStall seller app (Flutter, Android first; iOS config exists but has no `GoogleService-Info.plist`). It is the mobile version of the seller admin website admin.digistall.in (repo `Siyag-Rural-Market-Private-Limited/new-web`). It follows that site's mobile design (`src/new_theme.css` and the `New*` components) and its API calls. A seller signs in, claims `<subdomain>.digistall.in`, and then manages orders, catalogue, storefront look, bills and business cards. Customers use the storefront (repo `new-tem`). Package `digistall`; Android applicationId `com.digistall.digistall`.

## Commands

```bash
flutter pub get
flutter run                       # debug on a connected device (no emulator is set up on this machine)
flutter analyze
flutter test                      # unit + backend-contract + screen smoke tests
flutter test test/api_test.dart --plain-name "<name>"
SCREENSHOT_DIR=/some/dir flutter test test/screens_smoke_test.dart   # also writes phone-size PNGs of every screen
flutter build appbundle           # release, signed with android/app/keystore/release_key.jks
dart run flutter_launcher_icons   # icons from assets/images/app_icon.png
```

## Layout

- `lib/core/api.dart` is the only place that talks to the backends; screens call `Api.*`.
- `lib/core/session.dart` holds the `Session` singleton (`ChangeNotifier`): `userId`, the `user` doc, the `shop` (as `Shop`), and `lang` (`en`/`hi`). It also defines `tr(en, hi)`, used for every user-visible string. Screens mix in `SessionAware` (in `widgets/ds.dart`) to rebuild on changes. The session persists in SharedPreferences (`userId`, `lang`, `cache_user`, `cache_shop`).
- `lib/core/models.dart` contains read-only views over backend JSON: `Shop`, `Product`, `OrderGroup`, `BillGroup`, and formatting (`inr`, dates). The backend has several spellings for some fields; these getters decide which one wins.
- `lib/core/theme.dart` holds the `DS` colour tokens and text styles. The fonts are `Bricolage` (headings) and `Hind` (body, covers Hindi). `lib/widgets/ds.dart` is the widget kit (awning stripes, `DsButton`, `DsCard`, `DsField`, sheets, `DsThumb`, `EmptyStall`, `toast`, `confirmDialog`).
- `lib/screens/`:
  - `gate.dart`: start-up routing and `continueAfterLogin`.
  - `auth_screen.dart`: Firebase phone OTP and Google sign-in.
  - `onboarding_screen.dart`: subdomain, business details and map pin, all on one page.
  - `main_shell.dart`: bottom nav with Home / Orders / (+) / Catalog / Tools.
  - Then home, orders, catalog, product_form, tools, billbook, store_editor, business_cards, profile, and location_picker (OpenStreetMap via `flutter_map`).
- `lib/services/notification_service.dart` handles new-order alerts. `lib/services/invoice_pdf.dart` builds the order and bill PDFs.

## Backend contracts (hri-backend = `Api.base`, gotanbackend = `Api.gotan`)

- Nearly everything is `POST` with JSON, reads included, e.g. `POST shop {shopId}` and `POST user/getuser {userId}`. Payloads come back as `{"response": ...}`. `user/getuser` answers **210** with a string when the user doesn't exist.
- **shopId == subdomain.** Orders live inside the user doc (`user.orders`). Each row is one product, and rows share an `orderId`; `OrderGroup.fromRaw` groups them. Walk-in bills are in `user.Bills` (written by `user/generatebill`, which also decrements stock for real catalog productIds and returns `{response:false}` when stock is short).
- The order address string is `"name, phone, line, city, state, pin"` (storefront format). Customer name and phone are parsed from it.
- `shop/updateshop` `$set`s the fields it is given. Send only the changed fields plus `shopId`, never the whole shop: a stale full copy would overwrite stock changed by new orders. `settings` is sent whole (merged from the cached copy).
- `settings.gallery` is `[String]` in the schema, so store image URLs only.
- Order flow: `CONFIRMED` (accept), then either `user/selfdeliver` (status `SHIPPED`, mode `SELF`, emails the customer a 4-digit OTP; finish with `user/verifydeliveryotp`), or "Send with rider" (`CONFIRMED` again plus a `deliveryOtp` note, then gotan `api/digiorder/confirmToRider`; rider info comes from gotan `getDigiOrder?orderId=`), or `SHIPPED`. After that comes `DELIVERED`. `CANCEL` is also possible. Gotan rider status does not update the hri order; the seller marks it delivered.
- `userStatus` steps: `DOMAIN` → `BUSSINESS` (sic) → `FIRSTPRODUCT` → `COMPLETED`. Like the website, the app's onboarding creates the subdomain and the shop in one go (`validTill: "Lifetime"`) and sets `COMPLETED`. A user who already has a shop but isn't `COMPLETED` is promoted to `COMPLETED` on login.
- After onboarding the app calls gotan `api/digi/subdomainmail` and `api/digi/welcomeemail`.
- Website sellers who used the backend OTP fallback have the userId `seller_<phone>`. After Firebase verifies that phone, the app links to that account (`auth_screen.dart`). The app deliberately does **not** use `customer/sendphoneotp` / `verifyphoneotp`: they send no SMS and accept master codes.
- The storefront always offers cash on delivery and ignores `shop.cod`, so the app doesn't expose a COD toggle.

## Notifications

The backend's new-order push goes to the token the *storefront* sends, which is usually none, so it rarely reaches sellers. The app therefore polls `user/getuser` every 10 s while it is alive. It diffs order IDs against `seen_orders_<shopId>` in prefs and shows a local notification per new pending order. It also saves the FCM token with `user/setDeviceToken` and subscribes to the topic `shop_<shopId>`. `main.dart`'s background handler shows data-only `type:new_order` messages. Tapping any notification calls `AppNav.openOrders(orderId)`, which switches to the Orders tab and scrolls to that order. `NOTIFICATIONS.md` and the related docs describe the old app; `send_notification.sh` uses the shut-down legacy FCM API.

## Firebase

Project `humans-of-rural-india-d2b22`. Config files: `lib/firebase_options.dart` (Android and iOS), `android/app/google-services.json`, `firebase.json`. Images upload to Storage folders `products/`, `storefront/`, `shop-qr/` (same as the website). Regenerate config with `flutterfire configure`.
