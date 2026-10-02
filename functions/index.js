const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

// Example Cloud Function: send FCM when a new order is created in Firestore
// Adjust the path and payload according to your database schema.
exports.notifyShopOnNewOrder = functions.firestore
  .document("orders/{orderId}")
  .onCreate(async (snap, context) => {
    const order = snap.data();
    const orderId = context.params.orderId;
    const customerName = order.customerName || order.email || "";

    // Example: fetch tokens for the shop (replace with your storage)
    const shopId = order.shopId;
    if (!shopId) return null;

    const tokensDoc = await admin
      .firestore()
      .collection("shopTokens")
      .doc(shopId)
      .get();
    if (!tokensDoc.exists) return null;
    const tokens = tokensDoc.data().tokens || [];

    if (!tokens.length) return null;

    const payloadData = {
      type: "new_order",
      orderDetails: { orderId, customerName },
      orderIds: [orderId],
    };

    const message = {
      tokens,
      priority: "high",
      notification: {
        title: "New Order Received",
        body: `Order #${orderId}${customerName ? " from " + customerName : ""}`,
      },
      data: {
        payload: JSON.stringify(payloadData),
      },
      android: {
        priority: "high",
      },
      apns: {
        headers: {
          "apns-priority": "10",
        },
        payload: {
          aps: {
            alert: {
              title: "New Order Received",
              body: `Order #${orderId}${
                customerName ? " from " + customerName : ""
              }`,
            },
            sound: "default",
          },
        },
      },
    };

    try {
      const response = await admin.messaging().sendMulticast(message);
      console.log("FCM response:", response);
    } catch (err) {
      console.error("Error sending FCM:", err);
    }

    return null;
  });
