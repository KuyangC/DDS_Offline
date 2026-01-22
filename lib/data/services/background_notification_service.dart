// Dummy BackgroundNotificationService for offline mode (notifications disabled)
// This file provides placeholder implementation to avoid compilation errors

// ignore_for_file: avoid_print

import 'package:flutter/material.dart';

class BackgroundNotificationService {
  // Singleton pattern
  static final BackgroundNotificationService _instance = BackgroundNotificationService._internal();
  factory BackgroundNotificationService() => _instance;
  BackgroundNotificationService._internal();

  // Dummy methods - all do nothing in offline mode
  Future<void> initialize() async {
    print('BackgroundNotificationService: initialize called (offline mode - no-op)');
  }

  Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    print('BackgroundNotificationService: showNotification called (offline mode - no-op)');
  }

  Future<void> cancelAllNotifications() async {}
}
