import 'package:flutter/material.dart';

ValueNotifier<int> selectedPageNotifier = ValueNotifier(0);
ValueNotifier<bool> isDarkModeNotifier = ValueNotifier(true);
ValueNotifier<bool> isTargetNotifier = ValueNotifier(false);
ValueNotifier<dynamic> isValue = ValueNotifier('');
// notif_notifier.dart
final ValueNotifier<Map<String, String>?> incomingNotifNotifier = ValueNotifier(
  null,
);
