import 'package:flutter/material.dart';

class OrderDetailPage extends StatelessWidget {
  final String orderId;
  const OrderDetailPage({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order Detail')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Order ID', style: Theme.of(context).textTheme.titleLarge ?? const TextStyle(fontSize: 20)),
            const SizedBox(height: 8),
            Text(orderId, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 24),
            const Text('This is a placeholder order detail page.\nImplement fetching and display of full order information here.'),
          ],
        ),
      ),
    );
  }
}
