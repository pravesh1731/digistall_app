import 'package:flutter/material.dart';
import '../services/notification_service.dart';

class NotificationTestPage extends StatelessWidget {
  final String shopId;
  
  const NotificationTestPage({super.key, required this.shopId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Notification Testing',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            
            ElevatedButton(
              onPressed: () async {
                await NotificationService().showNewOrderNotification(
                  orderId: 'TEST001',
                  customerName: 'Test Customer',
                  productName: 'Test Product',
                  amount: 99.99,
                );
              },
              child: const Text('Test Local Notification'),
            ),
            
            const SizedBox(height: 16),
            
            ElevatedButton(
              onPressed: () async {
                final token = NotificationService().fcmToken;
                if (token != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('FCM Token: $token'),
                      duration: const Duration(seconds: 5),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('FCM Token not available'),
                    ),
                  );
                }
              },
              child: const Text('Show FCM Token'),
            ),
            
            const SizedBox(height: 16),
            
            ElevatedButton(
              onPressed: () async {
                await NotificationService().subscribeToShopTopic(shopId);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Subscribed to shop_$shopId topic'),
                  ),
                );
              },
              child: const Text('Subscribe to Shop Topic'),
            ),
            
            const SizedBox(height: 16),
            
            ElevatedButton(
              onPressed: () async {
                await NotificationService().clearAllNotifications();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('All notifications cleared'),
                  ),
                );
              },
              child: const Text('Clear All Notifications'),
            ),
            
            const SizedBox(height: 20),
            
            const Text(
              'Instructions:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '1. Test Local Notification - Shows a sample notification\n'
              '2. Show FCM Token - Displays your device token\n'
              '3. Subscribe to Topic - Subscribes to shop notifications\n'
              '4. Clear Notifications - Removes all notifications\n\n'
              'FCM Token should be sent to your backend for push notifications.',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}