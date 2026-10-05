import 'package:flutter/material.dart';

/// Global navigator so notification taps can navigate without a context.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Bottom-navigation tabs of the main shell.
enum ShellTab { home, orders, catalog, tools }

class AppNav {
  AppNav._();

  /// The shell listens to this; anything can switch tabs by setting it.
  static final ValueNotifier<ShellTab> tab = ValueNotifier(ShellTab.home);

  /// Set when a notification asks to show a specific order.
  static final ValueNotifier<String?> focusOrderId = ValueNotifier(null);

  static void openOrders([String? orderId]) {
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    focusOrderId.value = orderId;
    tab.value = ShellTab.orders;
  }
}
