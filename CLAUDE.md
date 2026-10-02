# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Digistall is a Flutter app for shop owners (Android, plus iOS config). A seller signs in, claims a subdomain (their storefront on digistall.in), sets up shop details and payments, manages a product catalogue, and handles incoming orders. Package name `digistall`; Android applicationId `com.digistall.digistall`.

## Commands

```bash
flutter pub get
flutter run                       # debug on connected device
flutter run --release             # needed to test background/terminated push notifications
flutter analyze                   # lints from package:flutter_lints (analysis_options.yaml)
flutter test                      # all tests
flutter test test/widget_test.dart --plain-name "<test name>"   # single test
flutter build appbundle           # release build, signed by android/app/build.gradle.kts using android/app/keystore/release_key.jks
dart run flutter_launcher_icons   # regenerate icons from assets/images/app_icon.png
```

`test/widget_test.dart` is still the stock Flutter counter test. It does not match the app and will fail: `MyApp` needs Firebase initialized and has no counter.

## Architecture

**No state management library, no repository/service layer for the API.** Each page is a `StatefulWidget` that calls the backend directly with `package:http` (`import 'package:http/http.dart' as http;`). Note that `http` is only a *transitive* dependency in `pubspec.lock`. Add it to `pubspec.yaml` if you touch dependencies. Pages keep state with `setState`, and shared identifiers are passed down through constructors.

**Backend.** The base URLs live in `lib/global/Common.dart`:
- `Common.baseUrl` (`https://backend.digistall.in/`) is the main API. Almost every call is a `POST` with a JSON body, including reads (e.g. `POST shop {shopId}`, `POST user/getuser {userId}`). Responses wrap the payload in `{"response": ...}`. Orders come back nested in the user record: `response.orders`.
- `Common.gotanBaseUrl` is a separate rider/delivery backend (`api/digiorder/confirmToRider`, used in `HomePage`).

`Common` also holds the theme palette and font sizes (`background`, `primary`, `secondary`, `h1`–`h4`). Use these rather than hard-coded colors. The fonts are `bevan` (default, OrelegaOne) and `bold` (PTSerif-Bold), declared in `pubspec.yaml`.

**shopId == subdomain.** The backend's `shopId` is the shop's subdomain string. After login, `SignInAndUp` stores it under both the `domain` and `shopId` SharedPreferences keys. `NavMain` passes `_domain` as the `shopId` argument to every tab.

**Session/persistence is SharedPreferences only.** Firebase Auth handles sign-in (Google sign-in in `SignInAndUp`, phone OTP in `PhoneInputPage`/`OTPVerificationPage`). After that, the app identifies the user purely by the `userId`/`domain`/`email` etc. it saved to SharedPreferences, and API calls send no auth header. Logout in `ProfilePage` clears prefs and returns to `SignInAndUp`.

**Onboarding state machine.** It is driven by the backend `userStatus` field, read in `SignInAndUp._callYourApi`:
- `DOMAIN` → `SubdomainPage`: check and create the subdomain, then set the status to `BUSSINESS` (sic, misspelled in the backend contract; keep it).
- `BUSSINESS` → `ShopDetailsPage` (`shop/createshop`).
- `FIRSTPRODUCT` → `ShopAdditionalDetailsPage` (payment/UPI QR, welcome emails).
- `COMPLETED` → `NavMain`. `main.dart` checks the stored `userStatus` at startup to skip straight here.

**Main shell.** `lib/NavMain.dart` is a bottom-nav with 5 tabs: `HomePage` (orders, status changes, PDF invoices via `pdf`/`printing`), `CataloguePage` (categories/products, plus `pages/AddEditProductPage`), `EditorTemplateWithStyle` (storefront editor, `lib/editor/`), `ToolsPage` (business card templates), and `ProfilePage` (with `PaymentPage`).

**Images** are uploaded to Firebase Storage (e.g. `shop-qr/`, `profile/`). The resulting download URL is then sent to the backend.

## Notifications (spans several files)

- `lib/services/notification_service.dart` contains the singleton `NotificationService`: local notifications, FCM listeners, topic subscription `shop_<domain>`, and FCM token saved to prefs.
- **New-order alerts come mainly from polling, not push.** `NavMain` calls `NotificationService().startOrderMonitoring(...)`, which polls `user/getuser` every 3s. It diffs the order IDs against `last_order_ids_<shopId>` in prefs and fires a local notification for each new ID. When that happens, `HomePage` re-fetches its order list (`fetchOrders(silent: true)`).
- The FCM background handler is the top-level `_firebaseMessagingBackgroundHandler` in `main.dart`. It expects **flat** data fields: `type: "new_order"`, `orderId`, `customerName`, `productName`, `amount`. The sample Cloud Function in `functions/index.js` sends a different shape (a JSON string under `data.payload`), so the two don't match. `functions/` isn't wired into `firebase.json` either; treat it as reference only.
- Tapping a notification navigates through the global `navigatorKey` (`lib/global/navigator_key.dart`) to the named route `/order-detail` (the only named route, defined in `main.dart`). If the navigator isn't ready yet, the order ID is saved to prefs. It is replayed by `handlePendingNavigation()` after the first frame.
- `lib/services/notification_config.dart` and `lib/utils/notification_config.dart` are disabled stubs. `lib/utils/order_watcher.dart` is empty.
- `NOTIFICATIONS.md`, `NOTIFICATION_IMPLEMENTATION.md` and `FIREBASE_CONSOLE_NOTIFICATIONS.md` describe how to test pushes from the Firebase console. `send_notification.sh` uses the legacy FCM HTTP API, which Google has shut down.

## Firebase

Project `humans-of-rural-india-d2b22`. Config files: `lib/firebase_options.dart` (FlutterFire-generated, Android + iOS only), `android/app/google-services.json`, and `firebase.json`. If you regenerate them, use `flutterfire configure`.

## Debug/test-only code

`lib/testing/` (`ImageUploader`, `NotificationTestPage`) and `lib/pages/NotificationDebugPage.dart` are dev scaffolding, not part of the user flow. `OrderDetailPage` is a placeholder that only shows the order ID. `NotificationOrdersPage.dart` is a broken fragment (a `build` method with no enclosing class). Nothing imports it, but `flutter analyze` reports it.
