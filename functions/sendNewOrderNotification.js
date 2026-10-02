// Node.js Firebase Admin SDK example for sending new order notification
const admin = require("firebase-admin");
admin.initializeApp();

/**
 * Send a new order notification to a device
 * @param {string} fcmToken - The FCM token of the device
 * @param {string} orderId - The order ID
 * @param {string} customerName - The customer name
 */
async function sendNewOrderNotification(fcmToken, orderId, customerName) {
  await admin.messaging().send({
    token: fcmToken,
    data: {
      type: "new_order",
      orderId: orderId,
      title: "New Order Received",
      body: `Order #${orderId} from ${customerName}`,
    },
  });
  console.log("Notification sent to", fcmToken);
}

// Example usage (replace with your actual values):
// sendNewOrderNotification('<FCM_TOKEN>', '12345', 'John Doe');

// --- Test invocation for your device ---
// Replace with the path to your service account key JSON if not already initialized above
// const admin = require('firebase-admin');
// admin.initializeApp({
//   credential: admin.credential.cert(require('./path/to/serviceAccountKey.json'))
// });

const fcmToken =
  "dWAbwGFMTiiQA1BgZo7AoA:APA91bHCwIyaaT6fGzOckRrY-8aAcSBxWKAwIcHrOoQZKz1S5lRD3a565pF0nE3gFYnSqRLEQRDH7tmHyS7YZtwogP6gpu9tYJOKaiOJdawAZ-Nhy7bUIQk";
const orderId = "12345";
const customerName = "John Doe";

sendNewOrderNotification(fcmToken, orderId, customerName)
  .then(() => console.log("Notification sent!"))
  .catch((err) => console.error("Error sending notification:", err));

module.exports = { sendNewOrderNotification };
