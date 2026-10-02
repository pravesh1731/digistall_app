# Cloud Function sample: notifyShopOnNewOrder

This folder contains a simple Firebase Cloud Function that sends an FCM notification when a new order document is created in Firestore.

How it works

- Trigger: Firestore document `orders/{orderId}` onCreate.
- Fetches device tokens from `shopTokens/{shopId}` (adapt this to your storage).
- Sends a multicast FCM with both `notification` and `data.payload` (JSON string) which the app expects.

Deploy

1. Install Firebase CLI and login:
   ```bash
   npm install -g firebase-tools
   firebase login
   ```
2. From this `functions/` folder run:
   ```bash
   cd functions
   npm install
   firebase deploy --only functions:notifyShopOnNewOrder
   ```

Adaptations

- Change the Firestore paths and token storage to match your project's schema.
- Ensure you have set up FCM/APNs in the Firebase Console for iOS.
- Store shop tokens in `shopTokens/{shopId}` as `{ tokens: ['token1', 'token2'] }` or alter code accordingly.

Security

- Do not store server keys in the mobile app. Use server-side functions or trusted servers to send FCM.
