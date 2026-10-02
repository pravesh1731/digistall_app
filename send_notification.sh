#!/bin/bash

# Firebase Notification Sender Script
# Usage: ./send_notification.sh "Order Title" "Order Message" "ORDER_ID"

# Your Firebase Server Key (get this from Firebase Console → Project Settings → Cloud Messaging)
# Replace with your actual server key
SERVER_KEY="YOUR_FIREBASE_SERVER_KEY_HERE"

# Your FCM Token (from app logs)
FCM_TOKEN="fUyFgNItQt-XSDltzdt8pu:APA91bHqZd7KnpjNMHIEa5HgbrJnbK7klv2rZ6D4YNJo49AuBCK5tNJDLviKrFU1aA3IEQ8_ZNDhs3O7HtwKwoCZ6SMDyo5Q3sG5tm2HnrINnr-i-Unohbk"

# Your Shop Topic
SHOP_TOPIC="shop_pravesh123"

# Default values if not provided
TITLE=${1:-"🛍️ New Order Received!"}
MESSAGE=${2:-"You have a new order to process"}
ORDER_ID=${3:-"ORDER_$(date +%s)"}

echo "Sending notification..."
echo "Title: $TITLE"
echo "Message: $MESSAGE"
echo "Order ID: $ORDER_ID"

# Method 1: Send to specific device (FCM Token)
echo "Sending to specific device..."
curl -X POST "https://fcm.googleapis.com/fcm/send" \
-H "Authorization: key=$SERVER_KEY" \
-H "Content-Type: application/json" \
-d '{
  "to": "'$FCM_TOKEN'",
  "notification": {
    "title": "'$TITLE'",
    "body": "'$MESSAGE'"
  },
  "data": {
    "type": "new_order",
    "orderId": "'$ORDER_ID'",
    "customerName": "Test Customer",
    "productName": "Test Product",
    "amount": "99.99"
  }
}'

echo -e "\n\n"

# Method 2: Send to topic (all devices subscribed to shop)
echo "Sending to topic: $SHOP_TOPIC..."
curl -X POST "https://fcm.googleapis.com/fcm/send" \
-H "Authorization: key=$SERVER_KEY" \
-H "Content-Type: application/json" \
-d '{
  "to": "/topics/'$SHOP_TOPIC'",
  "notification": {
    "title": "'$TITLE'",
    "body": "'$MESSAGE'"
  },
  "data": {
    "type": "new_order",
    "orderId": "'$ORDER_ID'",
    "customerName": "Test Customer",
    "productName": "Test Product",
    "amount": "99.99"
  }
}'

echo -e "\n\nNotification sent!"