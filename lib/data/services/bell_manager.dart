import 'dart:async';
import 'package:flutter/material.dart';
import 'logger.dart';
import '../models/zone_status_model.dart';

class BellManager extends ChangeNotifier {
  static const String _tag = 'BELL_MANAGER';

  bool _mounted = true;

  final Map<String, BellStatus> _deviceBellStatus = {};
  int _activeBells = 0;
  DateTime _lastBellActivity = DateTime.now();

  bool _isSystemMuted = false;
  bool _isBellPaused = false;
  
  final StreamController<BellSystemStatus> _bellStatusController =
      StreamController<BellSystemStatus>.broadcast();

  Timer? _statusUpdateTimer;

  BellManager() {
    _initializeStatusMonitoring();
  }

  BellSystemStatus get currentStatus => _calculateSystemBellStatus();
  Stream<BellSystemStatus> get bellStatusStream => _bellStatusController.stream;
  bool get isSystemMuted => _isSystemMuted;

  BellStatus? getBellStatusForDevice(int deviceAddress) {
    final deviceId = 'device_${deviceAddress.toString().padLeft(2, '0')}';
    return _deviceBellStatus[deviceId];
  }

  void processZoneData(Map<int, ZoneStatus> zones) {
    try {
      final Map<int, List<ZoneStatus>> deviceZonesMap = {};
      zones.forEach((key, zone) {
        (deviceZonesMap[zone.deviceAddress] ??= []).add(zone);
      });

      final Set<String> processedDeviceIds = {};
      _activeBells = 0;

      for (final entry in deviceZonesMap.entries) {
        final deviceAddr = entry.key;
        final deviceZones = entry.value;
        final deviceId = 'device_${deviceAddr.toString().padLeft(2, '0')}';
        processedDeviceIds.add(deviceId);

        final hasDeviceBellActive = deviceZones.any((zone) => zone.hasBellActive);
        final isActive = hasDeviceBellActive && !_isSystemMuted && !_isBellPaused;

        final previousStatus = _deviceBellStatus[deviceId];
        final currentStatus = BellStatus(
          deviceId: deviceId,
          deviceAddress: deviceAddr,
          isActive: isActive,
          isMuted: _isSystemMuted,
          hasAlarm: deviceZones.any((zone) => zone.hasAlarm),
          hasBellActive: hasDeviceBellActive,
          lastActivation: isActive ? (previousStatus?.lastActivation ?? DateTime.now()) : previousStatus?.lastActivation,
          totalActivations: (previousStatus?.totalActivations ?? 0) + (isActive && !(previousStatus?.isActive ?? false) ? 1 : 0),
        );

        _deviceBellStatus[deviceId] = currentStatus;
        if (isActive) {
          _activeBells++;
          _lastBellActivity = DateTime.now();
        }
      }

      _deviceBellStatus.keys
          .where((deviceId) => !processedDeviceIds.contains(deviceId))
          .toList()
          .forEach((deviceId) {
        final oldStatus = _deviceBellStatus[deviceId];
        if (oldStatus != null && oldStatus.isActive) {
          _deviceBellStatus[deviceId] = oldStatus.copyWith(isActive: false);
        }
      });
      
      _notifyStatusChange();
    } catch (e, stackTrace) {
      AppLogger.error('Error processing zone data for bell status', tag: _tag, error: e, stackTrace: stackTrace);
    }
  }

  Future<void> toggleSystemMute() async {
    _isSystemMuted = !_isSystemMuted;
    AppLogger.info('System bell mute ${ _isSystemMuted ? "activated" : "deactivated" }', tag: _tag);
    _recalculateAllDeviceStatus();
    _notifyStatusChange();
  }

  void _recalculateAllDeviceStatus(){
     _deviceBellStatus.forEach((deviceId, status) {
        _deviceBellStatus[deviceId] = status.copyWith(
          isMuted: _isSystemMuted,
          isActive: status.hasBellActive && !_isSystemMuted && !_isBellPaused,
        );
      });
      _recalculateActiveBells();
  }

  BellSystemStatus _calculateSystemBellStatus() {
    return BellSystemStatus(
      activeBells: _activeBells,
      isSystemMuted: _isSystemMuted,
      isBellPaused: _isBellPaused,
      lastBellActivity: _lastBellActivity,
      deviceBellStatus: Map.unmodifiable(_deviceBellStatus),
    );
  }

  void _initializeStatusMonitoring() {
    _statusUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _notifyStatusChange();
    });
  }

  void _recalculateActiveBells() {
    _activeBells = _deviceBellStatus.values.where((s) => s.isActive).length;
  }

  void _notifyStatusChange() {
    if (_mounted) {
      _bellStatusController.add(currentStatus);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _mounted = false;
    _statusUpdateTimer?.cancel();
    _bellStatusController.close();
    super.dispose();
  }
}

class BellSystemStatus {
  final int activeBells;
  final bool isSystemMuted;
  final bool isBellPaused;
  final DateTime lastBellActivity;
  final Map<String, BellStatus> deviceBellStatus;

  const BellSystemStatus({
    required this.activeBells,
    required this.isSystemMuted,
    required this.isBellPaused,
    required this.lastBellActivity,
    required this.deviceBellStatus,
  });
}

class BellStatus {
  final String deviceId;
  final int deviceAddress;
  final bool isActive;
  final bool isMuted;
  final bool hasAlarm;
  final bool hasBellActive;
  final DateTime? lastActivation;
  final int totalActivations;

  const BellStatus({
    required this.deviceId,
    required this.deviceAddress,
    required this.isActive,
    required this.isMuted,
    required this.hasAlarm,
    required this.hasBellActive,
    this.lastActivation,
    this.totalActivations = 0,
  });

  BellStatus copyWith({
    bool? isActive,
    bool? isMuted,
  }) {
    return BellStatus(
      deviceId: deviceId,
      deviceAddress: deviceAddress,
      isActive: isActive ?? this.isActive,
      isMuted: isMuted ?? this.isMuted,
      hasAlarm: hasAlarm,
      hasBellActive: hasBellActive,
      lastActivation: lastActivation,
      totalActivations: totalActivations,
    );
  }
}