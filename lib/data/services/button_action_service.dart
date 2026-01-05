import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../presentation/providers/fire_alarm_data_provider.dart';
import '../../core/config/dependency_injection.dart';
import 'bell_manager.dart';

/// Service terpusat untuk mengelola aksi button pada Control Page dan Full Monitoring Page
/// Offline mode: Only WebSocket mode supported
class ButtonActionService {
  static final ButtonActionService _instance = ButtonActionService._internal();
  factory ButtonActionService() => _instance;
  ButtonActionService._internal();

  // Button action codes
  static const String drillCode = 'd';
  static const String systemResetCode = 'r';
  static const String acknowledgeCode = 'a';
  static const String silenceCode = 's';

  // Track last sent data to prevent duplicates
  String? _lastSentData;
  DateTime? _lastSentTime;

  /// Mengirim data button action via WebSocket (Offline mode - WebSocket only)
  Future<bool> sendButtonAction(String actionCode, {required BuildContext context}) async {
    try {
      final fireAlarmData = context.read<FireAlarmData>();

      // Offline mode: Only WebSocket supported
      return await _sendToESP32(actionCode, context, fireAlarmData);
    } catch (e) {
      if (context.mounted) {
        _showErrorNotification(context, 'Failed to send command');
      }
      return false;
    }
  }

  /// Kirim command ke ESP32 via WebSocket
  Future<bool> _sendToESP32(String actionCode, BuildContext context, dynamic fireAlarmData) async {
    try {
      // Cek koneksi WebSocket
      final modeManager = fireAlarmData.modeManager;
      if (!modeManager.isWebSocketMode || !modeManager.isConnected) {
        if (context.mounted) {
          _showESPDisconnectedNotification(context);
        }
        return false;
      }

      // Cegah pengiriman data yang sama dalam waktu 1 detik
      if (_lastSentData == actionCode && _lastSentTime != null) {
        final timeDiff = DateTime.now().difference(_lastSentTime!);
        if (timeDiff.inMilliseconds < 1000) {
          return false;
        }
      }

      // Kirim command via WebSocket manager
      final webSocketManager = modeManager.webSocketManager;
      if (webSocketManager == null) {
        return false;
      }

      final commandData = {
        'command': actionCode,
        'type': 'control_command',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'user': 'Unknown',
        'action': _getActionName(actionCode),
      };

      final success = await webSocketManager.sendToESP32(commandData);

      if (success) {
        // 🔔 BELL MANAGER INTEGRATION: Process bell-related commands
        if (context.mounted) {
          await _processBellCommand(actionCode, context);
        }

        // Update tracking
        _lastSentData = actionCode;
        _lastSentTime = DateTime.now();

        return true;
      } else {
        if (context.mounted) {
          _showErrorNotification(context, 'Failed to send command to ESP32');
        }
        return false;
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorNotification(context, 'Failed to send command to ESP32');
      }
      return false;
    }
  }

  /// Handler untuk System Reset
  Future<bool> handleSystemReset({required BuildContext context}) async {
    // Show confirmation dialog
    final confirmed = await _showConfirmationDialog(
      context,
      'SYSTEM RESET',
      'Are you sure you want to reset the entire fire alarm system?',
      'RESET',
    );

    if (!confirmed) return false;

    final success = await sendButtonAction(systemResetCode, context: context);

    if (success && context.mounted) {
      final fireAlarmData = context.read<FireAlarmData>();
      fireAlarmData.isResetting = true;
      fireAlarmData.updateRecentActivity('SYSTEM RESET', user: 'Unknown');

      // Clear resetting flag after delay
      Future.delayed(const Duration(seconds: 3), () {
        if (fireAlarmData.isResetting) {
          fireAlarmData.isResetting = false;
        }
      });
    }

    return success;
  }

  /// Handler untuk Drill (toggle)
  Future<bool> handleDrill({required BuildContext context}) async {
    // Show confirmation dialog
    final confirmed = await _showConfirmationDialog(
      context,
      'DRILL MODE',
      'Are you sure you want to activate drill mode?',
      'ACTIVATE',
    );

    if (!confirmed) return false;

    final success = await sendButtonAction(drillCode, context: context);

    if (success && context.mounted) {
      final fireAlarmData = context.read<FireAlarmData>();
      fireAlarmData.updateRecentActivity('DRILL', user: 'Unknown');
    }

    return success;
  }

  /// Handler untuk Acknowledge (toggle)
  Future<bool> handleAcknowledge({required BuildContext context, bool? currentState}) async {
    final success = await sendButtonAction(acknowledgeCode, context: context);

    if (success && context.mounted) {
      final fireAlarmData = context.read<FireAlarmData>();
      fireAlarmData.updateRecentActivity('ACKNOWLEDGE', user: 'Unknown');
    }

    return success;
  }

  /// Handler untuk Silence (toggle)
  Future<bool> handleSilence({required BuildContext context}) async {
    final success = await sendButtonAction(silenceCode, context: context);

    if (success && context.mounted) {
      final fireAlarmData = context.read<FireAlarmData>();
      fireAlarmData.updateRecentActivity('SILENCED', user: 'Unknown');
    }

    return success;
  }

  /// Mendapatkan nama action dari code
  String _getActionName(String actionCode) {
    switch (actionCode) {
      case drillCode:
        return 'DRILL';
      case systemResetCode:
        return 'SYSTEM_RESET';
      case acknowledgeCode:
        return 'ACKNOWLEDGE';
      case silenceCode:
        return 'SILENCE';
      default:
        return 'UNKNOWN';
    }
  }

  /// Menampilkan dialog konfirmasi
  Future<bool> _showConfirmationDialog(
    BuildContext context,
    String title,
    String message,
    String action,
  ) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('CANCEL'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: Text(action),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  /// Menampilkan notifikasi ESP32 disconnected
  void _showESPDisconnectedNotification(BuildContext context) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ESP32 not connected - Check WebSocket connection',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// Menampilkan notifikasi error
  void _showErrorNotification(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Show success notification
  void _showSuccessNotification(BuildContext context, String message) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// 🔔 Process bell-related commands with Bell Manager integration
  Future<void> _processBellCommand(String actionCode, BuildContext context) async {
    try {
      if (!getIt.isRegistered<BellManager>()) {
        return;
      }

      final bellManager = getIt<BellManager>();

      switch (actionCode) {
        case silenceCode:
          await bellManager.toggleSystemMute();

          if (context.mounted) {
            final isMuted = bellManager.isSystemMuted;
            _showSuccessNotification(
              context,
              isMuted ? '🔇 System bell muted' : '🔔 System bell unmuted'
            );
          }
          break;

        case systemResetCode:
          // Bell manager will automatically reset through normal processing
          break;

        case acknowledgeCode:
        case drillCode:
          // These commands don't directly affect bell state
          break;

        default:
      }
    } catch (e) {
      // Ignore bell processing errors
    }
  }

  /// Reset tracking data (untuk testing purposes)
  void resetTracking() {
    _lastSentData = null;
    _lastSentTime = null;
  }
}
