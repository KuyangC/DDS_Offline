import 'dart:async';
import '../../data/services/logger.dart';

/// Singleton service for managing alarm queue
/// Handles multiple concurrent zone alarms with queue management
class AlarmQueueManager {
  // Singleton pattern
  static final AlarmQueueManager _instance = AlarmQueueManager._internal();
  factory AlarmQueueManager() => _instance;
  AlarmQueueManager._internal();

  // Alarm queue: list of zone numbers in alarm state
  final List<int> _alarmQueue = [];
  
  // Stream controller for queue updates
  final StreamController<List<int>> _queueController = 
    StreamController<List<int>>.broadcast();

  /// Stream of alarm queue updates
  Stream<List<int>> get queueStream => _queueController.stream;
  
  /// Get current alarm queue (immutable copy)
  List<int> get currentQueue => List.unmodifiable(_alarmQueue);
  
  /// Get number of alarms in queue
  int get queueLength => _alarmQueue.length;
  
  /// Check if there are any alarms in queue
  bool get hasAlarms => _alarmQueue.isNotEmpty;

  /// Add alarm to queue (avoid duplicates)
  void addAlarm(int zoneNumber) {
    if (!_alarmQueue.contains(zoneNumber)) {
      _alarmQueue.add(zoneNumber);
      _queueController.add(_alarmQueue);
      AppLogger.info(
        '🔔 Alarm added to queue: Zone $zoneNumber (Total: ${_alarmQueue.length})', 
        tag: 'ALARM_QUEUE'
      );
    } else {
      AppLogger.debug(
        'Zone $zoneNumber already in alarm queue, skipping duplicate', 
        tag: 'ALARM_QUEUE'
      );
    }
  }

  /// Remove specific alarm from queue
  void removeAlarm(int zoneNumber) {
    final removed = _alarmQueue.remove(zoneNumber);
    if (removed) {
      _queueController.add(_alarmQueue);
      AppLogger.info(
        '✅ Alarm removed from queue: Zone $zoneNumber (Remaining: ${_alarmQueue.length})', 
        tag: 'ALARM_QUEUE'
      );
    }
  }

  /// Clear entire alarm queue
  void clearQueue() {
    if (_alarmQueue.isNotEmpty) {
      final count = _alarmQueue.length;
      _alarmQueue.clear();
      _queueController.add(_alarmQueue);
      AppLogger.info(
        '🗑️ Alarm queue cleared ($count alarms removed)', 
        tag: 'ALARM_QUEUE'
      );
    }
  }

  /// Get zone number at specific index
  int? getZoneAt(int index) {
    if (index >= 0 && index < _alarmQueue.length) {
      return _alarmQueue[index];
    }
    return null;
  }

  /// Get index of specific zone in queue
  /// Returns -1 if zone not in queue
  int getIndexOf(int zoneNumber) {
    return _alarmQueue.indexOf(zoneNumber);
  }

  /// Check if specific zone is in queue
  bool containsZone(int zoneNumber) {
    return _alarmQueue.contains(zoneNumber);
  }

  /// Get queue statistics for debugging
  Map<String, dynamic> getQueueStats() {
    return {
      'queueLength': _alarmQueue.length,
      'zones': _alarmQueue,
      'hasAlarms': hasAlarms,
    };
  }

  /// Dispose resources
  void dispose() {
    _queueController.close();
    _alarmQueue.clear();
    AppLogger.info('AlarmQueueManager disposed', tag: 'ALARM_QUEUE');
  }
}
