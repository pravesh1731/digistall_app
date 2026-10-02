// Server-side notification implementation example
// This code should be implemented in your Node.js backend (functions/index.js)

const admin = require('firebase-admin');
const functions = require('firebase-functions');

// Initialize Firebase Admin SDK (add this to your functions/index.js)
if (!admin.apps.length) {
  admin.initializeApp();
}

// Function to send notification when new order is created
async function sendNewOrderNotification(shopId, orderData) {
  try {
    const message = {
      notification: {
        title: '🛍️ New Order Received!',
        body: `Order from ${orderData.customerName}\n${orderData.productName} - ₹${orderData.amount}`,
      },
      data: {
        type: 'new_order',
        orderId: orderData.orderId,
        shopId: shopId,
        customerName: orderData.customerName,
        productName: orderData.productName,
        amount: orderData.amount.toString(),
      },
      topic: `shop_${shopId}`, // Send to all devices subscribed to this shop
    };

    const response = await admin.messaging().send(message);
    console.log('✅ Notification sent successfully:', response);
    return response;
  } catch (error) {
    console.error('❌ Error sending notification:', error);
    throw error;
  }
}

// Function to send notification to specific FCM token
async function sendNotificationToToken(fcmToken, orderData) {
  try {
    const message = {
      notification: {
        title: '🛍️ New Order Received!',
        body: `Order from ${orderData.customerName}\n${orderData.productName} - ₹${orderData.amount}`,
      },
      data: {
        type: 'new_order',
        orderId: orderData.orderId,
        customerName: orderData.customerName,
        productName: orderData.productName,
        amount: orderData.amount.toString(),
      },
      token: fcmToken,
    };

    const response = await admin.messaging().send(message);
    console.log('✅ Notification sent to token:', response);
    return response;
  } catch (error) {
    console.error('❌ Error sending notification to token:', error);
    throw error;
  }
}

// Cloud Function to handle FCM token registration
exports.registerFCMToken = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).send('Method Not Allowed');
    return;
  }

  try {
    const { shopId, userId, fcmToken } = req.body;

    if (!shopId || !userId || !fcmToken) {
      res.status(400).json({ error: 'Missing required fields' });
      return;
    }

    // Store FCM token in Firestore or your database
    const db = admin.firestore();
    await db.collection('fcm_tokens').doc(userId).set({
      shopId,
      userId,
      fcmToken,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`✅ FCM token registered for user ${userId}, shop ${shopId}`);
    res.status(200).json({ message: 'FCM token registered successfully' });
  } catch (error) {
    console.error('❌ Error registering FCM token:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Example: Trigger notification when new order is created
// Call this function in your order creation endpoint
exports.onOrderCreated = functions.firestore
  .document('orders/{orderId}')
  .onCreate(async (snap, context) => {
    try {
      const orderData = snap.data();
      const shopId = orderData.shopId;

      // Send notification to shop topic
      await sendNewOrderNotification(shopId, {
        orderId: context.params.orderId,
        customerName: orderData.customerName,
        productName: orderData.productName,
        amount: orderData.totalAmount,
      });

      console.log('✅ New order notification triggered');
    } catch (error) {
      console.error('❌ Error triggering order notification:', error);
    }
  });

// Export functions for use in your existing backend
module.exports = {
  sendNewOrderNotification,
  sendNotificationToToken,
};

/* 
INTEGRATION STEPS FOR YOUR BACKEND:

1. Install firebase-admin in your functions folder:
   npm install firebase-admin

2. Add this code to your functions/index.js

3. In your existing order creation endpoint, add:
   const { sendNewOrderNotification } = require('./path-to-this-file');
   
   // After successfully creating order
   await sendNewOrderNotification(shopId, {
     orderId: newOrder._id,
     customerName: orderData.customerName,
     productName: orderData.productName,
     amount: orderData.totalAmount,
   });

4. Add the FCM token registration endpoint to your existing API:
   app.post('/user/register-fcm-token', async (req, res) => {
     const { shopId, userId, fcmToken } = req.body;
     
     // Store in your database
     // Example for MongoDB:
     await User.findByIdAndUpdate(userId, { 
       fcmToken, 
       shopId,
       updatedAt: new Date() 
     });
     
     res.json({ message: 'FCM token registered successfully' });
   });

5. Make sure your Firebase project has the correct service account key
*/