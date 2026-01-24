import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import '../../data/services/enhanced_zone_parser.dart';
import '../../data/services/bell_manager.dart';
import '../../data/datasources/local/zone_name_local_storage.dart';
import '../../data/services/logger.dart';
import '../../data/services/websocket_mode_manager.dart';
import '../../data/services/unified_fire_alarm_parser.dart';
import '../../data/services/activity_log_repository.dart';
import '../../data/models/zone_status_model.dart';

/// Offline Fire Alarm Data Manager
///
/// Central state management untuk fire alarm monitoring system.
/// Bertanggung jawab atas:
/// - Menyimpan dan mengelola zone status
/// - Memproses data dari WebSocket
/// - Mengelola system status LEDs
/// - Tracking bells, alarms, dan troubles
/// - Mengelola activity logs
class FireAlarmData extends ChangeNotifier {
  // Constants
  static const String _defaultProjectName = '---PROJECT ID---';
  static const String _defaultPanelType = '--- PANEL TYPE ---';
  static const int _defaultModuleCount = 63;
  static const int _defaultZoneCount = 315;
  static const double _logoWidth = 160.0;
  static const double _logoHeight = 40.0;
  static const double _logoLeftPadding = 50.0;
  static const double _logoTopPadding = 10.0;
  static const String _logoAssetPath = 'assets/data/images/LOGO.png';

  // Lifecycle management
  bool _mounted = true;

  // Service dependencies
  late final BellManager _bellManager;
  late final ZoneNameLocalStorage _zoneNameStorage;
  late final EnhancedZoneParser _zoneParser;
  late final WebSocketModeManager _wsModeManager;
  late final ActivityLogRepository _activityLogRepository;

  // Zone data storage
  final Map<int, ZoneStatus> _zoneStatus = {};

  // System status LEDs
  bool _alarmLED = false;
  bool _troubleLED = false;
  bool _supervisoryLED = false;
  bool _normalLED = false;

  // WebSocket connection state
  bool _hasWebSocketData = false;
  bool _isWebSocketMode = false;
  bool _isWebSocketConnected = false;

  // Pending WebSocket data (buffer)
  final List<String> _pendingWebSocketData = [];

  // Project information
  String projectName = _defaultProjectName;
  String panelType = _defaultPanelType;
  int numberOfModules = _defaultModuleCount;
  int numberOfZones = _defaultZoneCount;
  String activeZone = '';

  // Activity tracking
  String recentActivity = '';
  DateTime lastUpdateTime = DateTime.now();
  List<Map<String, dynamic>> activityLogs = [];
  List<Map<String, dynamic>> _localActivityLogs = [];

  // System reset tracking
  bool _isResetting = false;

  // Zone accumulation for alarms/troubles
  final Set<int> _accumulatedAlarmZones = {};
  final Set<int> _accumulatedTroubleZones = {};

  // New alarm stream for auto-opening zone detail dialog
  final StreamController<int> _newAlarmController = StreamController<int>.broadcast();
  Stream<int> get newAlarmStream => _newAlarmController.stream;

  // Loading states
  bool _isInitiallyLoading = false;
  bool _isAccumulationMode = false;

  // Getters - System state
  bool get isResetting => _isResetting;
  bool get isInitiallyLoading => _isInitiallyLoading;
  bool get isAccumulationMode => _isAccumulationMode;

  // Getters - LED status
  bool get alarmLED => _alarmLED;
  bool get troubleLED => _troubleLED;
  bool get supervisoryLED => _supervisoryLED;
  bool get normalLED => _normalLED;

  // Getters - WebSocket state
  bool get hasWebSocketData => _hasWebSocketData;
  bool get isWebSocketMode => _isWebSocketMode;
  bool get isWebSocketConnected => _isWebSocketConnected;

  /// Send notification (offline mode - no-op)
  void sendNotification({
    required String title,
    required String body,
  }) {
    AppLogger.info('sendNotification called (offline mode - no-op)', tag: 'FIRE_ALARM_DATA');
  }

  @override
  void notifyListeners() {
    if (_mounted) {
      super.notifyListeners();
    }
  }

  /// Set resetting state
  set isResetting(bool value) {
    _isResetting = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _mounted = false;
    _newAlarmController.close();
    super.dispose();
  }

  /// Initialize services
  Future<void> initialize() async {
    try {
      _bellManager = GetIt.instance<BellManager>();
      _zoneNameStorage = GetIt.instance<ZoneNameLocalStorage>();
      _zoneParser = GetIt.instance<EnhancedZoneParser>();
      _wsModeManager = GetIt.instance<WebSocketModeManager>();
      _activityLogRepository = GetIt.instance<ActivityLogRepository>();

      // Load existing logs from database
      await _loadLogsFromDatabase();

      AppLogger.info('✅ FireAlarmData initialized successfully');
    } catch (e) {
      AppLogger.error('❌ Error initializing FireAlarmData', error: e);
      rethrow;
    }
  }

  /// Load existing logs from database
  Future<void> _loadLogsFromDatabase() async {
    try {
      if (!_activityLogRepository.isInitialized) {
        AppLogger.warning('ActivityLogRepository not initialized, skipping log load', tag: 'FIRE_ALARM_DATA');
        return;
      }

      final dbLogs = await _activityLogRepository.getAllLogs();

      if (dbLogs.isNotEmpty) {
        activityLogs.clear();
        activityLogs.addAll(dbLogs);
        AppLogger.info('Loaded ${dbLogs.length} logs from database', tag: 'FIRE_ALARM_DATA');
      }
    } catch (e) {
      AppLogger.error('Error loading logs from database', tag: 'FIRE_ALARM_DATA', error: e);
    }
  }

  /// Get zone status by global zone number
  ZoneStatus? getZoneStatus(int globalZoneNumber) {
    return _zoneStatus[globalZoneNumber];
  }

  /// Get all zone statuses
  List<ZoneStatus> getAllZones() {
    return _zoneStatus.values.toList();
  }

  /// Get active alarm zones
  List<ZoneStatus> getAlarmZones() {
    return _zoneStatus.values.where((zone) => zone.hasAlarm).toList();
  }

  /// Get active trouble zones
  List<ZoneStatus> getTroubleZones() {
    return _zoneStatus.values.where((zone) => zone.hasTrouble).toList();
  }

  /// Check if zone is accumulated alarm
  bool isZoneAccumulatedAlarm(int zoneNumber) {
    return _accumulatedAlarmZones.contains(zoneNumber);
  }

  /// Check if zone is accumulated trouble
  bool isZoneAccumulatedTrouble(int zoneNumber) {
    return _accumulatedTroubleZones.contains(zoneNumber);
  }

  /// Get individual zone status for UI
  Map<String, dynamic> getIndividualZoneStatus(int zoneNumber) {
    final zone = _zoneStatus[zoneNumber];
    if (zone == null) {
      return {
        'zoneNumber': zoneNumber,
        'isActive': false,
        'isOffline': true,
        'status': 'Offline',
        'color': Colors.grey,
      };
    }

    // 🔥 FIX: Return 'Offline' status ketika zone tidak aktif
    if (!zone.isActive) {
      return {
        'zoneNumber': zoneNumber,
        'isActive': false,
        'isOffline': true,
        'status': 'Offline',
        'color': Colors.grey.shade300,
        'hasAlarm': false,
        'hasTrouble': false,
        'hasBellActive': false,
      };
    }

    return {
      'zoneNumber': zoneNumber,
      'isActive': zone.isActive,
      'isOffline': false,
      'status': zone.statusText,
      'color': zone.currentStatus == ZoneStatusType.alarm
          ? Colors.red
          : zone.currentStatus == ZoneStatusType.trouble
              ? Colors.orange
              : zone.currentStatus == ZoneStatusType.supervisory
                  ? Colors.yellow
                  : Colors.white,
      'hasAlarm': zone.hasAlarm,
      'hasTrouble': zone.hasTrouble,
      'hasBellActive': zone.hasBellActive,
    };
  }

  /// Save module name using ZoneNameLocalStorage
  Future<void> saveModuleName(int moduleNumber, String moduleName) async {
    try {
      // Load existing zone names
      final data = await ZoneNameLocalStorage.loadZoneNames();
      final zones = ZoneNameLocalStorage.parseZoneData(data);

      // Update or add module name (using negative module number for modules)
      zones[-moduleNumber] = moduleName;

      // Save back
      final formatted = ZoneNameLocalStorage.formatZoneNames(zones);
      await ZoneNameLocalStorage.saveZoneNames(formatted);

      notifyListeners();
    } catch (e) {
      print('Error saving module name: $e');
      rethrow;
    }
  }

  /// Get module name by number using ZoneNameLocalStorage
  String getModuleNameByNumber(int moduleNumber) {
    try {
      // Module names stored with negative numbers
      return _cachedModuleNames[moduleNumber] ?? 'Module $moduleNumber';
    } catch (e) {
      print('Error getting module name: $e');
      return 'Module $moduleNumber';
    }
  }

  /// Get zone name by absolute number (for individual zones)
  String getZoneNameByAbsoluteNumber(int zoneNumber) {
    try {
      return _cachedZoneNames[zoneNumber] ?? 'Zone $zoneNumber';
    } catch (e) {
      print('Error getting zone name: $e');
      return 'Zone $zoneNumber';
    }
  }

  /// Get zone status by absolute number
  Map<String, dynamic>? getZoneStatusByAbsoluteNumber(int zoneNumber) {
    final zone = _zoneStatus[zoneNumber];
    if (zone == null) return null;

    return {
      'zoneNumber': zone.zoneNumber,
      'zoneName': _cachedZoneNames[zoneNumber] ?? 'Zone $zoneNumber',
      'isActive': zone.isActive,
      'status': zone.statusText,
      'hasAlarm': zone.hasAlarm,
      'hasTrouble': zone.hasTrouble,
      'hasBellActive': zone.hasBellActive,
    };
  }

  // Cached names for quick access
  final Map<int, String> _cachedZoneNames = {};
  final Map<int, String> _cachedModuleNames = {};

  /// Additional getters
  bool get hasValidZoneData => _zoneStatus.isNotEmpty;
  bool get isMounted => _mounted;
  List<String> get pendingWebSocketData => List.unmodifiable(_pendingWebSocketData);

  /// Get active alarm zone numbers
  List<int> get activeAlarmZones {
    final alarmZones = _zoneStatus.values
        .where((zone) => zone.hasAlarm)
        .map((zone) => zone.globalZoneNumber)
        .toList();

    return alarmZones;
  }

  /// Get active trouble zone numbers
  List<int> get activeTroubleZones {
    final troubleZones = _zoneStatus.values
        .where((zone) => zone.hasTrouble)
        .map((zone) => zone.globalZoneNumber)
        .toList();

    return troubleZones;
  }

  /// Get system status for UI
  String getSystemStatus(String statusType) {
    switch (statusType) {
      case 'Alarm':
        return _alarmLED ? 'active' : 'inactive';
      case 'Trouble':
        return _troubleLED ? 'active' : 'inactive';
      case 'Supervisory':
        return _supervisoryLED ? 'active' : 'inactive';
      case 'Normal':
        return _normalLED ? 'active' : 'inactive';
      default:
        return 'inactive';
    }
  }

  /// Get zone count by status
  int getZoneCount(String status) {
    switch (status) {
      case 'Alarm':
        return getAlarmZones().length;
      case 'Trouble':
        return getTroubleZones().length;
      case 'Supervisory':
        return _zoneStatus.values.where((z) => z.hasSupervisory).length;
      case 'Normal':
        return _zoneStatus.values.where((z) => !z.hasAlarm && !z.hasTrouble && !z.hasSupervisory && z.isActive).length;
      default:
        return 0;
    }
  }

  /// Get LED color for status
  Color getEnhancedLEDColor(String statusType) {
    switch (statusType) {
      case 'Alarm':
        return _alarmLED ? Colors.red : Colors.grey;
      case 'Trouble':
        return _troubleLED ? Colors.orange : Colors.grey;
      case 'Supervisory':
        return _supervisoryLED ? Colors.yellow : Colors.grey;
      case 'Normal':
        return _normalLED ? Colors.white : Colors.grey;
      default:
        return Colors.grey;
    }
  }

  /// Get LED status
  bool getEnhancedLEDStatus(String statusType) {
    switch (statusType) {
      case 'Alarm':
        return _alarmLED;
      case 'Trouble':
        return _troubleLED;
      case 'Supervisory':
        return _supervisoryLED;
      case 'Normal':
        return _normalLED;
      default:
        return false;
    }
  }

  /// Get inactive color
  Color getInactiveColor() {
    return Colors.grey;
  }

  /// Get simple system status with detection
  String getSimpleSystemStatusWithDetection(String statusType) {
    // Check if we have any active alarms or troubles
    final hasAlarms = getAlarmZones().isNotEmpty;
    final hasTroubles = getTroubleZones().isNotEmpty;

    switch (statusType) {
      case 'Alarm':
        return hasAlarms ? 'active' : 'inactive';
      case 'Trouble':
        return hasTroubles ? 'active' : 'inactive';
      case 'Supervisory':
        return 'inactive'; // Not implemented for offline mode
      case 'Normal':
        return (!hasAlarms && !hasTroubles) ? 'active' : 'inactive';
      default:
        return 'inactive';
    }
  }

  /// Check if has trouble zones
  bool getSimpleHasTroubleZones() {
    return getTroubleZones().isNotEmpty;
  }

  /// Clear accumulated zones
  void clearAccumulatedZones() {
    _accumulatedAlarmZones.clear();
    _accumulatedTroubleZones.clear();
    notifyListeners();
  }

  /// Update recent activity
  void updateRecentActivity(String activity, {String? user}) {
    final now = DateTime.now();
    recentActivity = activity;
    lastUpdateTime = now;
    notifyListeners();
  }

  // Activity logging configuration
  static const int _maxActivityLogs = 200; // Maximum logs to store
  final Set<int> _loggedAlarmZones = {}; // Track logged alarm zones to prevent duplicates
  final Set<int> _loggedTroubleZones = {}; // Track logged trouble zones to prevent duplicates
  bool _wasConnected = false; // Track previous connection state for logging
  
  // Connection status tracking with debouncing
  DateTime? _lastConnectionStatusChange;
  static const Duration _connectionStatusDebounce = Duration(milliseconds: 500);

  /// Add activity log entry
  /// This method adds a new activity log entry with timestamp and maintains max log limit
  /// Also saves to database for persistent storage
  /// Add activity log entry
  /// This method adds a new activity log entry with timestamp and maintains max log limit
  /// Also saves to database for persistent storage
  /// [notify] - Whether to notify listeners (set to false for batch updates)
  void addActivityLog(String activity, {String? zoneName, String? type, bool notify = true}) {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    final timeStr = DateFormat('HH:mm:ss').format(now);

    final logEntry = {
      'timestamp': now,
      'date': dateStr,
      'time': timeStr,
      'activity': activity,
      if (zoneName != null) 'zoneName': zoneName,
      if (type != null) 'type': type,
    };

    // Add to beginning of list (newest first)
    activityLogs.insert(0, logEntry);

    // Maintain max log limit
    if (activityLogs.length > _maxActivityLogs) {
      activityLogs.removeLast();
    }

    // Save to database asynchronously (non-blocking)
    _saveLogToDatabase(logEntry);

    AppLogger.debug('Activity log added: $activity', tag: 'ACTIVITY_LOG');
    
    // Only notify if requested (performance optimization for loops)
    if (notify) {
      notifyListeners();
    }
  }

  /// Save log to database asynchronously
  Future<void> _saveLogToDatabase(Map<String, dynamic> log) async {
    try {
      if (_activityLogRepository.isInitialized) {
        await _activityLogRepository.saveLog(log);
      }
    } catch (e) {
      AppLogger.error('Failed to save log to database', tag: 'ACTIVITY_LOG', error: e);
    }
  }

  /// Clear activity logs
  void clearActivityLogs() {
    activityLogs.clear();
    _loggedAlarmZones.clear();
    _loggedTroubleZones.clear();
    notifyListeners();
  }

  /// Start auto-save timer (periodically saves logs to database)
  void startActivityLogAutoSave() {
    if (_activityLogRepository.isInitialized) {
      _activityLogRepository.startAutoSave(() => activityLogs);
      AppLogger.info('Activity log auto-save timer started', tag: 'FIRE_ALARM_DATA');
    }
  }

  /// Stop auto-save timer
  void stopActivityLogAutoSave() {
    _activityLogRepository.stopAutoSave();
    AppLogger.info('Activity log auto-save timer stopped', tag: 'FIRE_ALARM_DATA');
  }

  /// Manually save all current logs to database
  Future<void> saveAllLogsToDatabase() async {
    try {
      if (_activityLogRepository.isInitialized) {
        await _activityLogRepository.saveLogs(activityLogs);
        AppLogger.info('Saved ${activityLogs.length} logs to database', tag: 'FIRE_ALARM_DATA');
      }
    } catch (e) {
      AppLogger.error('Failed to save all logs to database', tag: 'FIRE_ALARM_DATA', error: e);
    }
  }

  /// Clear database logs
  Future<void> clearDatabaseLogs() async {
    try {
      if (_activityLogRepository.isInitialized) {
        await _activityLogRepository.clearAllLogs();
        AppLogger.info('Database logs cleared', tag: 'FIRE_ALARM_DATA');
      }
    } catch (e) {
      AppLogger.error('Failed to clear database logs', tag: 'FIRE_ALARM_DATA', error: e);
    }
  }

  /// Get modules list (placeholder for compatibility)
  List<Map<String, dynamic>> get modules {
    // Return empty list for offline mode
    return [];
  }

  /// Reset state
  void reset() {
    _zoneStatus.clear();
    _accumulatedAlarmZones.clear();
    _accumulatedTroubleZones.clear();
    _loggedAlarmZones.clear();
    _loggedTroubleZones.clear();
    _alarmLED = false;
    _troubleLED = false;
    _supervisoryLED = false;
    _normalLED = false;
    _hasWebSocketData = false;
    notifyListeners();
  }

  /// Invalidate zone cache
  Future<void> invalidateZoneCache() async {
    reset();
  }

  /// Set WebSocket mode
  void setWebSocketMode(bool isWebSocketMode) {
    _isWebSocketMode = isWebSocketMode;
    AppLogger.info('WebSocket mode set to: $isWebSocketMode', tag: 'FIRE_ALARM_DATA');
    notifyListeners();
  }

  /// Set WebSocket connection status
  void setWebSocketConnectionStatus(bool isConnected) {
    AppLogger.debug('setWebSocketConnectionStatus($isConnected), current: $_isWebSocketConnected', tag: 'CONNECTION');

    // Early return if status hasn't actually changed
    if (_isWebSocketConnected == isConnected) {
      return;
    }

    // Debounce: Prevent rapid status changes within 2 seconds
    final now = DateTime.now();
    if (_lastConnectionStatusChange != null) {
      final timeSinceLastChange = now.difference(_lastConnectionStatusChange!);
      // 🔥 CRITICAL: Extended debounce (2 seconds) to handle page lifecycle transitions
      // This prevents spam during dispose→init cycles when user navigates in/out of monitoring page
      final debounceThreshold = Duration(seconds: 2);
      
      if (timeSinceLastChange < debounceThreshold) {
        AppLogger.debug('Connection status change debounced (${timeSinceLastChange.inMilliseconds}ms since last)', tag: 'CONNECTION');
        // Still update the internal state but don't log or notify
        _isWebSocketConnected = isConnected;
        return;
      }
    }

    // Update timestamp
    _lastConnectionStatusChange = now;

    // Log connection state changes (only on actual state change)
    if (_wasConnected != isConnected) {
      if (isConnected) {
        addActivityLog(
          'System: Communication established to Host',
          type: 'connection',
        );
      } else {
        addActivityLog(
          'System: Communication lost to Host',
          type: 'connection',
        );
      }
      _wasConnected = isConnected;
    }

    _isWebSocketConnected = isConnected;
    notifyListeners();
    AppLogger.debug('Connection status updated to: $isConnected', tag: 'CONNECTION');
  }

  /// Get available dates from activity logs
  List<String> getAvailableDatesFromActivityLogs() {
    final dates = activityLogs
        .map((log) {
          final timestamp = log['timestamp'] as DateTime?;
          if (timestamp != null) {
            return DateFormat('yyyy-MM-dd').format(timestamp);
          }
          return null;
        })
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
    return dates.reversed.toList();
  }

  /// Get activity logs by date
  List<Map<String, dynamic>> getActivityLogsByDate(String date) {
    return activityLogs.where((log) {
      final timestamp = log['timestamp'] as DateTime?;
      if (timestamp != null) {
        final logDate = DateFormat('yyyy-MM-dd').format(timestamp);
        return logDate == date;
      }
      return false;
    }).toList();
  }

  /// Get system status with trouble detection
  String getSystemStatusWithTroubleDetection(String statusType) {
    return getSimpleSystemStatusWithDetection(statusType);
  }

  /// Get system status color with trouble detection
  Color getSystemStatusColorWithTroubleDetection(String statusType) {
    switch (statusType) {
      case 'Alarm':
        return _alarmLED ? Colors.red : Colors.grey;
      case 'Trouble':
        return _troubleLED ? Colors.orange : Colors.grey;
      case 'Supervisory':
        return _supervisoryLED ? Colors.yellow : Colors.grey;
      case 'Normal':
        return _normalLED ? Colors.white : Colors.grey;
      default:
        return Colors.grey;
    }
  }

  /// Clear pending WebSocket data
  void clearPendingWebSocketData() {
    _pendingWebSocketData.clear();
    AppLogger.info('Pending WebSocket data cleared', tag: 'FIRE_ALARM_DATA');
  }

  /// 🔥 Force process pending WebSocket data after reconnect
  Future<void> forceProcessPendingData() async {
    try {
      AppLogger.info('🔄 Force processing pending WebSocket data', tag: 'FIRE_ALARM_DATA');

      // Process pending data with force processing
      if (_pendingWebSocketData.isNotEmpty) {
        final pendingData = List<String>.from(_pendingWebSocketData);
        _pendingWebSocketData.clear();

        AppLogger.info('Processing ${pendingData.length} pending data items', tag: 'FIRE_ALARM_DATA');

        for (final data in pendingData) {
          try {
            await processWebSocketData(data, forceProcess: true);
          } catch (e) {
            AppLogger.warning('⚠️ Error force processing pending data: $e', tag: 'FIRE_ALARM_DATA');
          }
        }
      } else {
        AppLogger.info('No pending data to process', tag: 'FIRE_ALARM_DATA');
      }

      // Force UI refresh
      notifyListeners();
      AppLogger.info('✅ Force data processing complete', tag: 'FIRE_ALARM_DATA');

    } catch (e, stackTrace) {
      AppLogger.error('❌ Error during force processing', tag: 'FIRE_ALARM_DATA', error: e, stackTrace: stackTrace);
    }
  }

  /// Helper method untuk convert status string ke ZoneType
  ZoneType _getZoneTypeFromStatus(String status) {
    switch (status) {
      case 'Alarm':
        return ZoneType.smoke; // Use smoke as default for alarm
      case 'Trouble':
        return ZoneType.trouble;
      case 'Active':
        return ZoneType.input; // Use input for active zones
      case 'Normal':
        return ZoneType.supervisory; // Use supervisory for normal zones
      case 'Offline':
        return ZoneType.inactive;
      default:
        return ZoneType.unknown;
    }
  }

  /// Process WebSocket data with optional force processing
  Future<void> processWebSocketData(String rawData, {bool forceProcess = false}) async {
    try {
      // DEBUG: Log current state
      AppLogger.info('🔍 DEBUG: _isWebSocketMode=$_isWebSocketMode, forceProcess=$forceProcess', tag: 'WEBSOCKET_DEBUG');

      // Store as pending if not in WebSocket mode
      if (!_shouldProcessWebSocketData(forceProcess)) {
        _storePendingData(rawData);
        AppLogger.warning('⚠️ Data stored as PENDING because not in WebSocket mode', tag: 'WEBSOCKET_DEBUG');
        return;
      }

      // 🔥 CRITICAL FIX: Extract zone data from JSON wrapper if needed
      String zoneData = rawData;
      try {
        // Check if rawData is JSON format from ESP32
        if (rawData.trim().startsWith('{')) {
          final jsonObj = jsonDecode(rawData) as Map<String, dynamic>;
          if (jsonObj.containsKey('data')) {
            // Extract the actual zone data from 'data' field
            String dataField = jsonObj['data'] as String;
            
            // Remove metadata suffix (|FB:SKIP|TS:...|MODE:...)
            final pipeIndex = dataField.indexOf('|');
            if (pipeIndex > 0) {
              dataField = dataField.substring(0, pipeIndex);
            }
            
            zoneData = dataField;
            AppLogger.info('📦 Extracted zone data from JSON: ${zoneData.substring(0, zoneData.length > 50 ? 50 : zoneData.length)}...', tag: 'WEBSOCKET');
          }
        }
      } catch (e) {
        // Not JSON or parsing failed, use rawData as-is
        AppLogger.info('📄 Using rawData as-is (not JSON format)', tag: 'WEBSOCKET');
      }

      AppLogger.info('✅ Processing zone data: ${zoneData.substring(0, zoneData.length > 100 ? 100 : zoneData.length)}...', tag: 'WEBSOCKET');

      // Parse data
      final parseResult = await UnifiedFireAlarmAPI.parse(zoneData);

      if (parseResult.zones.isEmpty) {
        AppLogger.warning('Parser returned empty result for: ${zoneData.substring(0, zoneData.length > 50 ? 50 : zoneData.length)}...', tag: 'WEBSOCKET');
        return;
      }

      AppLogger.info('✅ Parser returned ${parseResult.zones.length} zones', tag: 'WEBSOCKET');

      // Update zones
      await _updateZoneStatuses(parseResult);

      // Update system status
      _updateSystemLEDStatus(parseResult);

      // Mark as loaded and notify listeners
      _hasWebSocketData = true;
      _isInitiallyLoading = false;
      notifyListeners();

      AppLogger.info('WebSocket data processed successfully', tag: 'WEBSOCKET');
    } catch (e) {
      AppLogger.error('Error processing WebSocket data', error: e, tag: 'WEBSOCKET');
    }
  }

  /// Check if WebSocket data should be processed
  bool _shouldProcessWebSocketData(bool forceProcess) {
    return _isWebSocketMode || forceProcess;
  }

  /// Store data as pending
  void _storePendingData(String rawData) {
    _pendingWebSocketData.add(rawData);
    AppLogger.info('Data stored as pending (not in WebSocket mode)', tag: 'FIRE_ALARM_DATA');
  }

  /// Update zone statuses from parse result
  Future<void> _updateZoneStatuses(dynamic parseResult) async {
    int zoneCount = 0;
    int updatesCount = 0; // Track actual changes

    // Loop through all parsed zones
    for (final unifiedZone in parseResult.zones.values) {
      final zoneNumber = unifiedZone.zoneNumber;

      // Create new zone status object from parsed data
      final newZoneStatus = _createZoneStatus(unifiedZone);
      
      // OPTIMIZATION: Only update map if status actually changed
      // This preserves object references for UI Selectors to skip rebuilds
      final oldZoneStatus = _zoneStatus[zoneNumber];
      
      if (oldZoneStatus != newZoneStatus) {
        _zoneStatus[zoneNumber] = newZoneStatus;
        updatesCount++;
      }

      // Always update bell and accumulation tracking (logic handles duplicates)
      // Must be outside 'if' because accumulators might be cleared every frame
      _updateZoneTracking(unifiedZone);

      zoneCount++;
    }

    // FIX: Setelah semua zona diperbarui (atau tidak), tetap update BellManager
    // BellManager akan handle diff-ing internalnya sendiri
    _bellManager.processZoneData(_zoneStatus);

    print('Processed $zoneCount zones, $updatesCount actual updates');
  }

  /// Create ZoneStatus from UnifiedZoneStatus
  ZoneStatus _createZoneStatus(dynamic unifiedZone) {
    return ZoneStatus(
      globalZoneNumber: unifiedZone.zoneNumber,
      zoneInDevice: unifiedZone.zoneInDevice,
      deviceAddress: int.tryParse(unifiedZone.deviceAddress) ?? 1,
      isActive: unifiedZone.status != 'Offline',
      hasAlarm: unifiedZone.status == 'Alarm',
      hasTrouble: unifiedZone.status == 'Trouble',
      hasBellActive: unifiedZone.hasBellActive,
      description: unifiedZone.description,
      lastUpdate: unifiedZone.timestamp,
      zoneType: _getZoneTypeFromStatus(unifiedZone.status),
    );
  }

  /// Update bell and accumulation tracking for a zone
  void _updateZoneTracking(dynamic unifiedZone) {
    final zoneNumber = unifiedZone.zoneNumber;

    // Track accumulated zones and log new alarms/troubles
    if (unifiedZone.status == 'Alarm') {
      // Only log if this is a new alarm (not previously logged)
      if (!_loggedAlarmZones.contains(zoneNumber)) {
        _loggedAlarmZones.add(zoneNumber);
        // Remove from trouble logs if it was there
        _loggedTroubleZones.remove(zoneNumber);

        final zoneName = unifiedZone.description.isNotEmpty
            ? unifiedZone.description
            : 'Zone $zoneNumber';

        addActivityLog(
          '$zoneName - Fire Alarm detected',
          zoneName: zoneName,
          type: 'alarm',
          notify: false, // Suppress notification during loop
        );

        // Trigger new alarm stream for auto-opening zone detail dialog
        if (!_newAlarmController.isClosed) {
          _newAlarmController.add(zoneNumber);
          AppLogger.info('New alarm detected for Zone $zoneNumber - triggering auto-open dialog', tag: 'AUTO_ALARM_DIALOG');
        }
      }
      _accumulatedAlarmZones.add(zoneNumber);
    } else if (unifiedZone.status == 'Trouble') {
      // Only log if this is a new trouble (not previously logged and not an alarm)
      if (!_loggedTroubleZones.contains(zoneNumber) && !_loggedAlarmZones.contains(zoneNumber)) {
        _loggedTroubleZones.add(zoneNumber);

        final zoneName = unifiedZone.description.isNotEmpty
            ? unifiedZone.description
            : 'Zone $zoneNumber';

        addActivityLog(
          '$zoneName - Trouble condition detected',
          zoneName: zoneName,
          type: 'trouble',
          notify: false, // Suppress notification during loop
        );
      }
      _accumulatedTroubleZones.add(zoneNumber);
    } else if (unifiedZone.status == 'Normal') {
      // Clear from logged sets when returning to normal
      final wasAlarm = _loggedAlarmZones.contains(zoneNumber);
      final wasTrouble = _loggedTroubleZones.contains(zoneNumber);

      if (wasAlarm || wasTrouble) {
        _loggedAlarmZones.remove(zoneNumber);
        _loggedTroubleZones.remove(zoneNumber);

        final zoneName = unifiedZone.description.isNotEmpty
            ? unifiedZone.description
            : 'Zone $zoneNumber';

        addActivityLog(
          '$zoneName - Returned to Normal',
          zoneName: zoneName,
          type: 'normal',
        );
      }

      // Remove from accumulated sets
      _accumulatedAlarmZones.remove(zoneNumber);
      _accumulatedTroubleZones.remove(zoneNumber);
    }
  }

  /// Update system LED status from parse result
  void _updateSystemLEDStatus(dynamic parseResult) {
    final systemStatus = parseResult.systemStatus;
    _alarmLED = systemStatus.hasAlarm;
    _troubleLED = systemStatus.hasTrouble;
    _supervisoryLED = false; // Not available in UnifiedSystemStatus
    _normalLED = !systemStatus.hasAlarm && !systemStatus.hasTrouble;
  }
}
