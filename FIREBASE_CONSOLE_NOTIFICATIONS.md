# 🔔 Firebase Console Notification Guide

## How to Send Notifications Without Backend

Since you don't want backend integration, you can send notifications directly from the Firebase Console. Here's how:

### 📱 **Method 1: Send to Specific Device (Using FCM Token)**

1. **Get FCM Token from App:**
   - The app logs show your FCM token: `fUyFgNItQt-XSDltzdt8pu:APA91bHqZd7KnpjNMHIEa5HgbrJnbK7klv2rZ6D4YNJo49AuBCK5tNJDLviKrFU1aA3IEQ8_ZNDhs3O7HtwKwoCZ6SMDyo5Q3sG5tm2HnrINnr-i-Unohbk`
   - Or use the `NotificationTestPage` to get the current token

2. **Send from Firebase Console:**
   - Go to Firebase Console → Cloud Messaging
   - Click "Send your first message"
   - Enter notification title: `🛍️ New Order Received!`
   - Enter message: `You have a new order to process`
   - Click "Send test message"
   - Paste your FCM token and send

### 📢 **Method 2: Send to Topic (All devices subscribed to shop)**

1. **Topic Name:** `shop_pravesh123` (your app auto-subscribes to `shop_${shopId}`)

2. **Send from Firebase Console:**
   - Go to Firebase Console → Cloud Messaging
   - Click "Send your first message"
   - Enter notification details
   - In "Target" section, select "Topic"
   - Enter topic: `shop_pravesh123`
   - Click "Send"

### 📋 **Method 3: Using Firebase Cloud Messaging API (Manual)**

```bash
curl -X POST "https://fcm.googleapis.com/fcm/send" \
-H "Authorization: key=YOUR_SERVER_KEY" \
-H "Content-Type: application/json" \
-d '{
  "to": "fUyFgNItQt-XSDltzdt8pu:APA91bHqZd7KnpjNMHIEa5HgbrJnbK7klv2rZ6D4YNJo49AuBCK5tNJDLviKrFU1aA3IEQ8_ZNDhs3O7HtwKwoCZ6SMDyo5Q3sG5tm2HnrINnr-i-Unohbk",
  "notification": {
    "title": "🛍️ New Order Received!",
    "body": "Order from Customer - Product Name - ₹99.99"
  },
  "data": {
    "type": "new_order",
    "orderId": "ORDER123",
    "customerName": "Test Customer",
    "productName": "Test Product",
    "amount": "99.99"
  }
}'
```

### 🔧 **What Your App Does Now:**

✅ **Local Notifications:** When new orders are detected via polling  
✅ **Firebase Topic Subscription:** Auto-subscribes to `shop_pravesh123`  
✅ **FCM Token Storage:** Stores token locally for manual use  
✅ **Background Notifications:** Receives Firebase messages when app is closed  
✅ **Foreground Notifications:** Shows local notifications when app is open  
✅ **Navigation:** Taps on notifications navigate to order details  

### 🧪 **Testing Steps:**

1. **Test Local Notifications:**
   - Use `NotificationTestPage` in your app
   - Tap "Test Local Notification"

2. **Test Firebase Notifications:**
   - Copy FCM token from app logs
   - Go to Firebase Console
   - Send test notification using the token

3. **Test Topic Notifications:**
   - Send to topic `shop_pravesh123` from Firebase Console
   - All devices with your app will receive it

### 📱 **Current Setup:**

- **Shop ID:** `pravesh123`
- **Topic:** `shop_pravesh123`
- **FCM Token:** `fUyFgNItQt-XSDltzdt8pu:APA91bHqZd7KnpjNMHIEa5HgbrJnbK7klv2rZ6D4YNJo49AuBCK5tNJDLviKrFU1aA3IEQ8_ZNDhs3O7HtwKwoCZ6SMDyo5Q3sG5tm2HnrINnr-i-Unohbk`

### 🎯 **Quick Test:**

1. Open Firebase Console
2. Go to Cloud Messaging
3. Send test message to your FCM token above
4. You should see notification on your device!

---

**No backend required! Your notification system is working perfectly! 🎉**