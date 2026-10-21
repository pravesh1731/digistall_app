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
- **New orders arrive `CONFIRMED`** (backend default since Oct 2026); there is no accept step. Legacy `PENDING` rows are treated the same (`OrderGroup.status` = `accepted`, `isNew`). Tabs: Orders / Shipped / Delivered / Cancelled. From there: either `user/selfdeliver` (status `SHIPPED`, mode `SELF`, emails the customer a 4-digit OTP; finish with `user/verifydeliveryotp`), or "Send with rider" (`CONFIRMED` again plus a `deliveryOtp` note, then gotan `api/digiorder/confirmToRider`; rider info comes from gotan `getDigiOrder?orderId=`), or `SHIPPED`. After that comes `DELIVERED`. `CANCEL` is also possible. Gotan rider status does not update the hri order; the seller marks it delivered.
- `userStatus` steps: `DOMAIN` → `BUSSINESS` (sic) → `FIRSTPRODUCT` → `COMPLETED`. Like the website, the app's onboarding creates the subdomain and the shop in one go (`validTill: "Lifetime"`) and sets `COMPLETED`. A user who already has a shop but isn't `COMPLETED` is promoted to `COMPLETED` on login.
- After onboarding the app calls gotan `api/digi/subdomainmail` and `api/digi/welcomeemail`.
- Website sellers who used the backend OTP fallback have the userId `seller_<phone>`. After Firebase verifies that phone, the app links to that account (`auth_screen.dart`). The app deliberately does **not** use `customer/sendphoneotp` / `verifyphoneotp`: they send no SMS and accept master codes.
- The storefront offers cash on delivery unless `shop.cod == false`, and the schema defaults `cod` to false, so new shops are created with `cod: true` and Profile has a COD switch (saved via `shop/updatepayment`).
- Gotan marketplace categories ("store formats", `core/store_formats.dart`, generated from the website) are saved to `shopFormats`, `formats` and `settings.shopFormats`, then synced best-effort to gotan `PUT api/shop/editshop`.
- Low stock = `productUnits < 5` (website rule); `low_stock_screen.dart` restocks via `shop/updateproduct`.
- If a gotan rider cancels, `getDigiOrder` shows `riderStatus: Cancelled` (+ `cancelReason`); the order card offers "Resend to rider".
- Languages: `core/languages_data.dart` is generated from the website's `utils/indianLanguages.js` (23 languages, store-setup strings only, read with `st(key)`). Everywhere else, like the website, text is Hindi when `lang == 'hi'` and English otherwise (`tr`).

## Notifications

Seller alerts follow the reference doc "Gotan Order Notifications" (seller app S1–S5 + section 5); kinds are `SellerAlert` in `lib/core/inbox.dart`:
- **S1 new order**: push on channel `orders_loud` (sound `res/raw/new_order_alert.wav`, alarm audio usage, `FLAG_INSISTENT` so it rings until opened), big text with items / total / payment / delivery area, VIEW ORDER action. Stopped when the order is opened or leaves "new".
- **S2 rider on the way**, **S5 delivered**, customer cancelled, rider dropped out, rider delay (10 min): push on `order_updates`.
- **S3 collected**, **S4 out for delivery**, still looking for a rider (3 min): in-app only (silent banner from `MainShell`).
- Every alert is saved to `Inbox` (per shop, SharedPreferences) and shown in `notifications_screen.dart` (bell on Home). That screen can fire test alerts for checking against S1–S5.

Neither backend pushes these events to sellers (hri-backend's new-order push uses the token the storefront sends; gotanbackend sends nothing on rider updates). So `NotificationService` polls every 10 s while the app is alive: `user/getuser` for orders and gotan `api/digiorder/shopdigiorder` for rider trips (`RiderTrip`, `lib/core/rider.dart`). `detect()` diffs against `notif_state_<shopId>` and raises each event once. Order changes made on this device are excluded via `markLocalChange`. Rider stages come from `riderStatus` ("En Route" + `riderAccepted`, "PICKED_UP", out for delivery / in transit, "Delivered", "Cancelled"), and `Session.stageOf` moves orders between tabs the same way the website does.

FCM data messages with `type` = `new_order`, `rider_assigned`, `order_picked`, `out_for_delivery`, `order_delivered`, `order_cancelled`, `rider_changed` (+ `orderId`) are shown with the same styles, including from the background handler in `main.dart`, and aren't repeated by polling (`notif_shown`). So closed-app alerts work once a backend sends those to `Shop.deviceToken` (saved via `user/setDeviceToken`; topic `shop_<shopId>`). Tapping any alert calls `AppNav.openOrders(orderId)`. `NOTIFICATIONS.md` and the related docs describe the old app.

## Firebase

Project `humans-of-rural-india-d2b22`. Config files: `lib/firebase_options.dart` (Android and iOS), `android/app/google-services.json`, `firebase.json`. Images upload to Storage folders `products/`, `storefront/`, `shop-qr/` (same as the website). Regenerate config with `flutterfire configure`.
