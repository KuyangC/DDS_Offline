import 'dart:async';
import 'package:flutter/material.dart';

/// Simplified Local Audio Manager
/// Stub implementation for offline mode
class LocalAudioManager {
  bool _isNotificationMuted = false;
  bool _isSoundMuted = false;
  bool _isBellMuted = false;

  final StreamController<Map<String, bool>> _audioStatusController =
      StreamController<Map<String, bool>>.broadcast();

  Stream<Map<String, bool>> get audioStatusStream => _audioStatusController.stream;

  bool get isNotificationMuted => _isNotificationMuted;
  bool get isSoundMuted => _isSoundMuted;
  bool get isBellMuted => _isBellMuted;

  Future<void> initialize() async {
    // No initialization needed for stub
  }

  void toggleNotificationMute() {
    _isNotificationMuted = !_isNotificationMuted;
    _emitStatus();
  }

  void toggleSoundMute() {
    _isSoundMuted = !_isSoundMuted;
    _emitStatus();
  }

  void toggleBellMute() {
    _isBellMuted = !_isBellMuted;
    _emitStatus();
  }

  void updateAudioStatusFromButtons({
    required bool isDrillActive,
    required bool isAlarmActive,
    required bool isTroubleActive,
    required bool isSilencedActive,
  }) {
    // Update audio status based on button states
    // Stub implementation - no actual audio control
  }

  void _emitStatus() {
    _audioStatusController.add({
      'notificationMuted': _isNotificationMuted,
      'soundMuted': _isSoundMuted,
      'bellMuted': _isBellMuted,
    });
  }

  void stopAllAudioImmediately() {
    // Stop all audio immediately
    // Stub implementation for offline mode
  }

  void dispose() {
    _audioStatusController.close();
  }
}
