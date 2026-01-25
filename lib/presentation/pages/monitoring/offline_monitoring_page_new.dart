// ignore_for_file: use_build_context_synchronously, library_private_types_in_public_api

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/services/logger.dart';
import '../../../data/services/websocket_mode_manager.dart';
import '../../../data/datasources/websocket/websocket_service.dart';
import '../../../data/services/unified_ip_service.dart';
import '../../../data/datasources/local/offline_settings_service.dart';
import '../../../data/services/offline_performance_manager.dart';
import '../../../data/datasources/websocket/fire_alarm_websocket_manager.dart';
import '../../../data/datasources/local/zone_name_local_storage.dart';
import '../../../data/datasources/local/exit_password_service.dart';
import '../../../data/datasources/local/zone_mapping_service.dart';
import '../../../data/services/auto_refresh_service.dart';
import '../../../data/services/bell_manager.dart';
import '../../services/alarm_queue_manager.dart';
import '../../providers/fire_alarm_data_provider.dart';
import '../../../data/models/zone_status_model.dart';
import '../../widgets/blinking_tab_header.dart';
import '../../widgets/zone_detail_dialog.dart';
import '../../widgets/exit_password_dialog.dart';
import '../auth/login_page.dart';
import '../../../main.dart';

/// Module status based on zone states within the module
enum ModuleStatus {
  normal,
  trouble,
  alarm,
}

class OfflineMonitoringPage extends StatefulWidget {
  final String ip;
  final int port;
  final String projectName;
  final int moduleCount;

  const OfflineMonitoringPage({
    super.key,
    required this.ip,
    required this.port,
    required this.projectName,
    required this.moduleCount,
  });

  @override
  State<OfflineMonitoringPage> createState() => _OfflineMonitoringPageState();
}

class _OfflineMonitoringPageState extends State<OfflineMonitoringPage> with WidgetsBindingObserver {
  
  
  int _displayModules = 63; // Default display all modules (matches tab_monitoring.dart)

  // Auto-hide timer state
  bool _showModuleControls = true;
  Timer? _hideControlsTimer;
  static const Duration _autoHideDuration = Duration(seconds: 15);

  // Tab section state
  String _selectedTab = 'recent';
  List<String> _availableDates = [];
  String _selectedDate = '';
  final List<Map<String, dynamic>> _localActivityLogs = [];
    static const int _maxActivityLogs = 100; // Maximum logs to store

  // Performance manager
  late final OfflinePerformanceManager _performanceManager;

  // WebSocket manager removed - using global WebSocketModeManager instead
  // This prevents race conditions and multiple manager conflicts

  // 🔥 NEW: Disconnect status untuk offline mode
  bool _isDisconnected = false;
  StreamSubscription? _autoRefreshStatusSubscription;

  // New alarm subscription for auto-opening zone detail dialog
  StreamSubscription<int>? _newAlarmSubscription;

  // Initialization flag for lifecycle management
  bool _isInitialized = false;

  // WebSocket initialization flag to prevent duplicate calls
  bool _isWebSocketInitializing = false;

  // Zone names map for custom zone naming
  Map<int, String> _zoneNames = {};

  // Loading state to prevent race conditions during zone name loading
  bool _isZoneNamesLoading = false;

  // Password protection state
  bool _isPasswordDialogShowing = false;

  // Navigation safety flags
  bool _isNavigating = false;
  bool _isDialogClosing = false;
  bool _disposed = false;
  
  // Multi-alarm queue management
  final AlarmQueueManager _alarmQueueManager = AlarmQueueManager();
  bool _isAlarmDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    AppLogger.info('🚀 OFFLINE MONITORING PAGE INITIALIZED', tag: 'OFFLINE_MONITORING');

    // Initialize performance manager
    _performanceManager = OfflinePerformanceManager.instance;

    // WebSocket manager will be initialized in didChangeDependencies()
    // to avoid MediaQuery lifecycle errors

    // 🚀 Enable focused performance mode for maximum responsiveness
    _enableFocusedPerformanceMode();

    // ❌ REMOVED: _initializeWebSocketMode() - Moved to didChangeDependencies()
    // to avoid "Bad State" error from accessing Provider before context is ready

    _displayModules = widget.moduleCount; // Start with configured modules

    // Start auto-hide timer for module controls
    _startHideControlsTimer();

    // Initialize tab section with sample data
    _initializeTabSection();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Prevent duplicate initialization
    if (_isInitialized) return;
    _isInitialized = true;

    // Force landscape mode regardless of screen size
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // ✅ SAFE: Provider access di didChangeDependencies
    final fireAlarmData = Provider.of<FireAlarmData>(context, listen: false);
    // WebSocket manager removed - using global WebSocketModeManager instead

    // Load project-specific zone names
    _loadZoneNames();

    // Listen to activity logs changes
    fireAlarmData.addListener(_onActivityLogsChanged);

    // Listen to new alarm stream for auto-opening zone detail dialog
    _newAlarmSubscription = fireAlarmData.newAlarmStream.listen((zoneNumber) {
      if (mounted && !_disposed) {
        // Add alarm to queue
        _alarmQueueManager.addAlarm(zoneNumber);
        
        // Only show dialog if none is currently open
        if (!_isAlarmDialogOpen) {
          _isAlarmDialogOpen = true;
          AppLogger.info('Opening multi-alarm dialog for Zone $zoneNumber', tag: 'AUTO_ALARM_DIALOG');
          _showMultiAlarmDialog(context, fireAlarmData);
        } else {
          AppLogger.info('Dialog already open, Zone $zoneNumber added to queue', tag: 'AUTO_ALARM_DIALOG');
        }
      }
    });
    AppLogger.info('Multi-alarm stream listener started', tag: 'AUTO_ALARM_DIALOG');

    // ✅ FIXED: Delay WebSocket initialization until after first frame
    // This ensures GetIt services are fully registered before access
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeWebSocketMode();
      }
    });

    // Start auto-save timer for activity logs
    fireAlarmData.startActivityLogAutoSave();
    AppLogger.info('Activity log auto-save timer started', tag: 'OFFLINE_MONITORING');

    // 🔥 NEW: Log user entry to monitoring system
    fireAlarmData.addActivityLog(
      'User Return Monitoring System',
      type: 'lifecycle',
    );
    AppLogger.info('User entered monitoring page', tag: 'LIFECYCLE');
  }

  Future<void> _loadZoneNames() async {
    if (mounted) {
      setState(() {
        _isZoneNamesLoading = true;
      });
    }

    try {
      _zoneNames = await ZoneNameLocalStorage.loadZoneNamesForProject(widget.projectName);
      AppLogger.info('Loaded ${_zoneNames.length} custom zone names for project: ${widget.projectName}', tag: 'OFFLINE_MONITORING');
    } catch (e) {
      AppLogger.error('Error loading zone names for project: ${widget.projectName}', tag: 'OFFLINE_MONITORING', error: e);
      _zoneNames = {};
    } finally {
      if (mounted) {
        setState(() {
          _isZoneNamesLoading = false;
        });

        // Debug: Log successful loading
        AppLogger.debug('Zone names loaded and UI rebuilt. Zone count: ${_zoneNames.length}', tag: 'OFFLINE_MONITORING');
        if (_zoneNames.isNotEmpty) {
          final sampleNames = _zoneNames.keys.take(3).map((k) => '$k:"${_zoneNames[k]}"').join(', ');
          AppLogger.debug('Sample zone names: $sampleNames', tag: 'OFFLINE_MONITORING');
        }
      }
    }
  }

  void _initializeWebSocketMode() async {
    // Prevent duplicate initialization
    if (_isWebSocketInitializing) {
      AppLogger.debug('WebSocket initialization already in progress, skipping', tag: 'OFFLINE_MONITORING');
      return;
    }

    _isWebSocketInitializing = true;

    try {
      // ✅ SAFETY CHECK: Ensure context is still mounted before accessing Provider
      if (!mounted || !context.mounted) {
        AppLogger.warning('Context not mounted, skipping WebSocket initialization', tag: 'OFFLINE_MONITORING');
        return;
      }

      // ✅ SAFETY CHECK: Ensure GetIt services are registered
      if (!GetIt.instance.isRegistered<FireAlarmData>()) {
        AppLogger.warning('FireAlarmData not registered in GetIt yet, will retry', tag: 'OFFLINE_MONITORING');
        // Retry after a short delay
        await Future.delayed(const Duration(milliseconds: 100));
        _isWebSocketInitializing = false; // Reset flag before retry
        if (mounted && GetIt.instance.isRegistered<FireAlarmData>()) {
          _initializeWebSocketMode();
        }
        return;
      }

      // 🔥 OPTIMIZED: WebSocketModeManager should already be initialized from OfflineConfig
      // This ensures the "Case 1 GAGAL" bug is fixed
      final wsManager = WebSocketModeManager.instance;
      final fireAlarmData = Provider.of<FireAlarmData>(context, listen: false);
      final unifiedIPService = UnifiedIPService();

      // 🔥 BIDIRECTIONAL SYNC: Ensure IP settings are consistent
      // Update UnifiedIPService with current navigation parameters
      await unifiedIPService.setIP(widget.ip);
      await unifiedIPService.setPort(widget.port);
      await unifiedIPService.setProjectName(widget.projectName);
      await unifiedIPService.setModuleCount(widget.moduleCount);

      // Configure offline mode settings for backward compatibility
      await OfflineSettingsService.saveIndividualSettings(
        ip: widget.ip,
        port: widget.port,
        projectName: widget.projectName,
        moduleCount: widget.moduleCount,
        isConfigured: true,
      );

      // Initialize manager if needed
      await wsManager.initializeManager(fireAlarmData);

      // 🔥 CRITICAL FIX: Set WebSocket mode FIRST, then update IP
      // This is the correct order to ensure proper connection
      if (!wsManager.isWebSocketMode) {
        AppLogger.info('🔄 Switching to WebSocket mode...', tag: 'OFFLINE_MONITORING');
        await wsManager.toggleMode(); // This will set _isWebSocketMode = true
      }

      // 🔥 CRITICAL: Update ESP32 IP AFTER setting WebSocket mode
      // This ensures the reconnect happens in updateESP32IP (line 287 of websocket_mode_manager.dart)
      AppLogger.info('📡 Updating ESP32 IP to: ${widget.ip}', tag: 'OFFLINE_MONITORING');
      await wsManager.updateESP32IP(widget.ip);

      // Connect to ESP32 using provided IP and port with global manager
      final webSocketManager = wsManager.webSocketManager;
      AppLogger.info('🔍 webSocketManager is null: ${webSocketManager == null}', tag: 'OFFLINE_MONITORING');
      AppLogger.info('🔍 widget.ip: ${widget.ip}', tag: 'OFFLINE_MONITORING');

      final success = webSocketManager != null ? await webSocketManager.connectToESP32(widget.ip) : false;

      AppLogger.info('🔍 connectToESP32() returned: $success', tag: 'OFFLINE_MONITORING');

      if (success) {
        AppLogger.info('✅ WebSocket connected using unified global manager', tag: 'OFFLINE_MONITORING');
      } else {
        AppLogger.warning('⚠️ WebSocket connection failed', tag: 'OFFLINE_MONITORING');
      }

      // Set project name in FireAlarmData
      if (mounted) {
        fireAlarmData.projectName = widget.projectName;
      }

      AppLogger.info('WebSocket mode optimized and initialized for ${widget.ip}:${widget.port}');
      AppLogger.info('UnifiedIPService synchronized with monitoring page parameters');
    } catch (e) {
      AppLogger.error('Failed to initialize WebSocket mode', error: e);
      if (mounted) {
        // WebSocket connection failed - handled by WebSocket manager
      }
    } finally {
      _isWebSocketInitializing = false;
    }
  }

  /// Initialize tab section with data from FireAlarmData
  void _initializeTabSection() {
    // Initialize dates from FireAlarmData activity logs
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDates();
    });
  }

  void _initializeDates() {
    // 🔥 TRIPLE SAFETY CHECK: mounted, _disposed, dan context.mounted
    if (!mounted || _disposed) {
      AppLogger.debug('Skipping _initializeDates - widget disposed or not mounted', tag: 'OFFLINE_MONITORING');
      return;
    }

    try {
      // Check context ALSO (not just widget)
      if (!context.mounted) {
        AppLogger.warning('Context not mounted in _initializeDates, skipping Provider access', tag: 'OFFLINE_MONITORING');
        return;
      }

      final fireAlarmData = Provider.of<FireAlarmData>(context, listen: false);
      final availableDates = fireAlarmData.getAvailableDatesFromActivityLogs();

      // Final check before setState
      if (!mounted || _disposed) {
        AppLogger.debug('Skipping setState - widget disposed during _initializeDates', tag: 'OFFLINE_MONITORING');
        return;
      }

      setState(() {
        _availableDates = availableDates;
        if (_selectedDate.isEmpty && _availableDates.isNotEmpty) {
          _selectedDate = _availableDates.first;
        }
      });

      AppLogger.info('Tab section initialized with ${availableDates.length} available dates');
    } catch (e) {
      // Catch any errors during context access
      AppLogger.error('Error in _initializeDates: $e', tag: 'OFFLINE_MONITORING');
    }
  }

  void _onActivityLogsChanged() {
    // Only skip if widget is truly disposed
    if (_disposed || !mounted) {
      AppLogger.debug('Skipping _onActivityLogsChanged - widget disposed', tag: 'OFFLINE_MONITORING');
      return;
    }

    // Update UI with latest activity logs
    _initializeDates();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        // When app is resumed, ensure landscape mode for offline monitoring
        if (mounted) {
          
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
          // Also ensure immersive mode
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        }
        break;

      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // Don't restore orientations here - keep landscape until user manually leaves
        
        break;

      case AppLifecycleState.hidden:
        // App is hidden but not destroyed
        
        break;
    }
  }

  /// Reset all navigation state flags to prevent contamination between flows
  void _resetNavigationState() {
    // Direct reset without setState() for safe disposal
    _isNavigating = false;
    _isDialogClosing = false;
    _isPasswordDialogShowing = false;

    // Only call setState if widget is still mounted and not in disposal
    if (mounted) {
      setState(() {
        // No state variables to change here since we reset them directly
      });
    }
  }

  /// Safe operation wrapper for async operations with error handling
  Future<T?> _safeOperation<T>(
    Future<T> Function() operation, {
    String? operationName,
    T? fallbackValue,
  }) async {
    try {
      return await operation();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error in ${operationName ?? "operation"}',
        error: e,
        stackTrace: stackTrace,
        tag: 'SAFE_OP',
      );

      // Reset state on error
      _resetNavigationState();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Operation failed: ${operationName ?? "unknown error"}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      return fallbackValue;
    }
  }

  /// Handle navigation errors gracefully with state reset
  void _handleNavigationError(Object error) {
    AppLogger.error('Navigation error occurred', error: error, tag: 'EXIT');

    // Reset state on error to prevent getting stuck
    _resetNavigationState();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Navigation error. Please try again.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void dispose() {
    // 🔥 NEW: Log user exit FIRST before any cleanup
    try {
      final fireAlarmData = Provider.of<FireAlarmData>(context, listen: false);
      fireAlarmData.addActivityLog(
        'User Left Monitoring System',
        type: 'lifecycle',
      );
      AppLogger.info('User exited monitoring page', tag: 'LIFECYCLE');
    } catch (e) {
      AppLogger.warning('Could not log user exit: $e', tag: 'LIFECYCLE');
    }

    // 🔥 CRITICAL FIX: Remove listener FIRST before any other dispose operations
    // This prevents notifyListeners() from being called during dispose
    try {
      final fireAlarmData = Provider.of<FireAlarmData>(context, listen: false);
      fireAlarmData.removeListener(_onActivityLogsChanged);
      AppLogger.debug('Activity log listener removed successfully', tag: 'OFFLINE_MONITORING');
    } catch (e) {
      AppLogger.warning('Error removing activity log listener: $e', tag: 'OFFLINE_MONITORING');
    }

    // ✅ Reset all navigation flags first (without setState)
    _isNavigating = false;
    _isDialogClosing = false;
    _isPasswordDialogShowing = false;

    // Prevent navigation after dispose
    _isNavigating = true;

    // Mark as disposed to prevent periodic timer Provider access
    _disposed = true;

    WidgetsBinding.instance.removeObserver(this);

    // Restore user preferred orientations when leaving the page
    _restoreUserPreferredOrientations();

    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // 🚀 Dispose performance manager
    _performanceManager.dispose();

    // 🔥 CRITICAL FIX: JANGAN dispose singleton WebSocketModeManager!
    // Ini digunakan seluruh app, jika di-dispose akan mematikan WebSocket connection
    // dan mencegah auto-reconnect bekerja.
    // Hanya cancel subscriptions, jangan dispose manager itself.
    // WebSocketModeManager.instance.dispose(); // ❌ REMOVED - Ini penyebab tidak bisa auto-reconnect

    // 🔥 NEW: Cancel AutoRefreshService status subscription
    _autoRefreshStatusSubscription?.cancel();

    // Cancel new alarm subscription
    _newAlarmSubscription?.cancel();
    AppLogger.debug('New alarm subscription cancelled', tag: 'AUTO_ALARM_DIALOG');

    // Stop activity log auto-save timer
    try {
      final fireAlarmData = Provider.of<FireAlarmData>(context, listen: false);
      fireAlarmData.stopActivityLogAutoSave();
      AppLogger.info('Activity log auto-save timer stopped', tag: 'OFFLINE_MONITORING');
    } catch (e) {
      // Provider might not be available during dispose
      AppLogger.debug('Could not stop auto-save timer: $e', tag: 'OFFLINE_MONITORING');
    }

    // Cancel auto-hide timer to prevent memory leaks
    _hideControlsTimer?.cancel();

    super.dispose();
  }

  
  void _incrementModules() {
    setState(() {
      if (_displayModules < 63) {
        _displayModules++;
      }
    });
  }

  void _decrementModules() {
    setState(() {
      if (_displayModules > 1) {
        _displayModules--;
      }
    });
  }

  /// Auto-hide controls timer methods
  void _startHideControlsTimer() {
    _hideControlsTimer = Timer(_autoHideDuration, () {
      if (mounted) {
        _hideControls();
      }
    });
  }

  void _hideControls() {
    setState(() {
      _showModuleControls = false;
    });
  }

  /// Parse WebSocket data to activity log format
  Map<String, dynamic> _parseWebSocketToActivityLog(dynamic data, String eventType) {
    final now = DateTime.now();
    final dateStr = DateFormat('dd/MM/yyyy').format(now);
    final timeStr = DateFormat('HH:mm:ss').format(now);

    String activity;
    switch (eventType) {
      case 'zone_update':
        activity = 'Zone ${data['zone'] ?? 'Unknown'} status changed to ${data['status'] ?? 'Unknown'}';
        break;
      case 'system_status':
        activity = 'System status: ${data['status'] ?? 'Unknown'}';
        break;
      case 'connection':
        activity = 'Connection: ${data['status'] ?? 'Unknown'}';
        break;
      case 'module_update':
        activity = 'Module ${data['module'] ?? 'Unknown'} updated';
        break;
      default:
        activity = 'System event: $eventType';
    }

    return {
      'date': dateStr,
      'time': timeStr,
      'activity': activity,
      'timestamp': now.millisecondsSinceEpoch.toString(),
      'type': eventType,
      'data': data,
    };
  }

  /// Extract active alarm zones from FireAlarmData
  List<Map<String, dynamic>> _extractAlarmZones() {
    final List<Map<String, dynamic>> alarmZones = [];

    // Get zone status from fireAlarmData
    final fireAlarmData = Provider.of<FireAlarmData>(context, listen: false);

    // Get zones with actual alarm status from zone data (like trouble zones)
    final alarmZoneNumbers = fireAlarmData.activeAlarmZones;

    if (alarmZoneNumbers.isNotEmpty) {
      for (final zoneNumber in alarmZoneNumbers) {
        // Skip zones outside display range
        if (zoneNumber > _displayModules * 5) continue;

        final zoneStatus = fireAlarmData.getIndividualZoneStatus(zoneNumber);

        // Calculate module and zone in module numbers
        final moduleNumber = ((zoneNumber - 1) / 5).floor() + 1;
        final zoneInModule = ((zoneNumber - 1) % 5) + 1;
        // Get custom zone name or use default format
        final customZoneName = _zoneNames[zoneNumber];
        final areaName = customZoneName ??
                       'Module ${moduleNumber.toString().padLeft(2, '0')} - Zone $zoneInModule';

        alarmZones.add({
          'zoneNumber': zoneNumber,
          'moduleNumber': moduleNumber,
          'zoneInModule': zoneInModule,
          'area': areaName,
          'status': zoneStatus?['status'] ?? 'Alarm',
          'timestamp': zoneStatus?['timestamp']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
          'bellType': fireAlarmData.getSystemStatus('Alarm'),
        });
      }
    }

    return alarmZones;
  }

  /// Extract active trouble zones from FireAlarmData
  List<Map<String, dynamic>> _extractTroubleZones() {
    final List<Map<String, dynamic>> troubleZones = [];

    // Get zone status from fireAlarmData
    final fireAlarmData = Provider.of<FireAlarmData>(context, listen: false);

    // Get zones with actual trouble status from zone data (not LED status)
    final troubleZoneNumbers = fireAlarmData.activeTroubleZones;

    if (troubleZoneNumbers.isNotEmpty) {
      for (final zoneNumber in troubleZoneNumbers) {
        // Skip zones outside display range
        if (zoneNumber > _displayModules * 5) continue;

        final zoneStatus = fireAlarmData.getIndividualZoneStatus(zoneNumber);

        // Calculate module and zone in module numbers
        final moduleNumber = ((zoneNumber - 1) / 5).floor() + 1;
        final zoneInModule = ((zoneNumber - 1) % 5) + 1;

        // Get custom zone name or use default format (same as Fire Alarm tab)
        final customZoneName = _zoneNames[zoneNumber];
        final areaName = customZoneName ??
                       'Module ${moduleNumber.toString().padLeft(2, '0')} - Zone $zoneInModule';

        troubleZones.add({
          'zoneNumber': zoneNumber,
          'moduleNumber': moduleNumber,
          'zoneInModule': zoneInModule,
          'area': areaName,
          'status': zoneStatus?['status'] ?? 'Trouble',
          'timestamp': zoneStatus?['timestamp']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
          'bellType': false, // Trouble zones don't typically have bell activation
        });
      }
    }

    return troubleZones;
  }

  /// Add activity log to buffer with size limit
  void _addActivityLog(Map<String, dynamic> log) {
    setState(() {
      _localActivityLogs.insert(0, log);
      if (_localActivityLogs.length > _maxActivityLogs) {
        _localActivityLogs.removeLast();
      }
      _updateAvailableDates();
    });
  }

  /// Update available dates from activity logs
  void _updateAvailableDates() {
    final Set<String> dates = _localActivityLogs
        .map((log) => log['date'] as String)
        .toSet();

    setState(() {
      _availableDates = dates.toList()..sort((a, b) => _compareDates(b, a));
      if (_selectedDate.isEmpty && _availableDates.isNotEmpty) {
        _selectedDate = _availableDates.first;
      }
    });
  }

  /// Compare dates in dd/MM/yyyy format
  int _compareDates(String date1, String date2) {
    try {
      final parts1 = date1.split('/');
      final parts2 = date2.split('/');

      final day1 = int.parse(parts1[0]);
      final month1 = int.parse(parts1[1]);
      final year1 = int.parse(parts1[2]);

      final day2 = int.parse(parts2[0]);
      final month2 = int.parse(parts2[1]);
      final year2 = int.parse(parts2[2]);

      final dateTime1 = DateTime(year1, month1, day1);
      final dateTime2 = DateTime(year2, month2, day2);

      return dateTime1.compareTo(dateTime2);
    } catch (e) {
      return 0;
    }
  }

  /// Enable focused performance mode for optimal WebSocket responsiveness
  Future<void> _enableFocusedPerformanceMode() async {
    try {
      await _performanceManager.initialize();
      await _performanceManager.setPerformanceMode(OfflinePerformanceMode.focused);

      AppLogger.info('✅ Focused performance mode enabled - WebSocket priority activated');
    } catch (e) {
      AppLogger.error('Failed to enable focused performance mode', error: e);
    }
  }

  void _restoreUserPreferredOrientations() {
    

    // Restore to flexible orientations, allowing the system to decide based on device orientation.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Also restore system UI to normal mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // 🔄 Restore normal performance mode when leaving
    _restoreNormalPerformanceMode();

    // Force a short delay to ensure orientation change takes effect
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        
      }
    });
  }

  /// Restore normal performance mode when exiting offline monitoring
  Future<void> _restoreNormalPerformanceMode() async {
    try {
      await _performanceManager.setPerformanceMode(OfflinePerformanceMode.normal);
      AppLogger.info('✅ Normal performance mode restored');
    } catch (e) {
      AppLogger.error('Failed to restore normal performance mode', error: e);
    }
  }

  /// Show exit password dialog for password protection
  void _showExitPasswordDialog() {
    if (_isPasswordDialogShowing || _isNavigating || !mounted) return; // Enhanced safety checks

    setState(() {
      _isPasswordDialogShowing = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false, // Must enter password to dismiss
      builder: (BuildContext dialogContext) {
        return ExitPasswordDialog(
          onResult: (success) {
            setState(() {
              _isPasswordDialogShowing = false;
            });

            if (success && mounted) {
              _performActualExit(dialogContext);
            }
          },
        );
      },
    ).then((_) {
      // Additional safety reset in case dialog is dismissed unexpectedly
      if (mounted) {
        setState(() {
          _isPasswordDialogShowing = false;
        });
      }
    });
  }

  /// Determine if navigation should go to LoginPage or MainNavigation
  Future<bool> _shouldNavigateToLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if user has valid local session (came from login flow)
      final userId = prefs.getString('user_id');
      final username = prefs.getString('username');
      final configDone = prefs.getBool('config_done') ?? false;
      final settingsDone = prefs.getBool('settings_done') ?? false;

      // 🔥 NEW: Disable auto-redirect flag since user is manually exiting
      await prefs.setBool('auto_redirect_to_offline', false);

      // Set offline mode flag for MainNavigation bypass
      await prefs.setBool('coming_from_offline_mode', true);

      AppLogger.info('🚪 Manual exit detected - auto-redirect disabled, offline bypass enabled', tag: 'EXIT');
      AppLogger.info('Navigation decision - userId: $userId, configDone: $configDone, settingsDone: $settingsDone', tag: 'EXIT');

      // If has valid session, go to MainNavigation, else go to LoginPage
      final hasValidSession = userId != null &&
                             username != null &&
                             configDone &&
                             settingsDone;

      return !hasValidSession; // Return true if should navigate to Login

    } catch (e) {
      AppLogger.error('Error checking navigation target', error: e, tag: 'EXIT');
      // Default to LoginPage on error for safety
      return true;
    }
  }

  /// Perform the actual exit after successful password validation
  Future<void> _performActualExit(BuildContext dialogContext) async {
    if (_isNavigating) return; // Prevent multiple calls

    setState(() {
      _isNavigating = true;
    });

    try {
      // Close the dialog first
      if (!_isDialogClosing) {
        setState(() {
          _isDialogClosing = true;
        });

        Navigator.of(dialogContext).pop();
        await Future.delayed(const Duration(milliseconds: 150));
      }

      // Perform normal exit operations
      _restoreUserPreferredOrientations();
      await _cleanupMonitoringState();

      // Check mounted before navigation
      if (!mounted) return;

      // ✅ INTELLIGENT NAVIGATION: Determine correct navigation target
      final shouldNavigateToLogin = await _shouldNavigateToLogin();

      if (shouldNavigateToLogin) {
        // Navigate to LoginPage (for password entry flow)
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const Login_page()),
          (Route<dynamic> route) => false,
        );
        AppLogger.info('Successfully navigated to LoginPage', tag: 'EXIT');
      } else {
        // Navigate to Login_page as default
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const Login_page()),
          (Route<dynamic> route) => false,
        );
        AppLogger.info('Successfully navigated to Login_page', tag: 'EXIT');
      }

    } catch (e) {
      // Reset state and handle error gracefully
      _handleNavigationError(e);

      // Fallback navigation if primary fails
      if (mounted) {
        try {
          // Try simple pop as fallback
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        } catch (fallbackError) {
          AppLogger.error('Fallback navigation failed', error: fallbackError);
        }
      }
    } finally {
      // Reset navigation state
      if (mounted) {
        setState(() {
          _isNavigating = false;
          _isDialogClosing = false;
          _isPasswordDialogShowing = false;
        });
      }
    }
  }

  /// Clean up monitoring state before navigation
  Future<void> _cleanupMonitoringState() async {
    try {
      _hideControlsTimer?.cancel();
      // Disconnect using global WebSocket manager
      final wsManager = WebSocketModeManager.instance;
      final webSocketManager = wsManager.webSocketManager;
      if (webSocketManager != null) {
        await webSocketManager.disconnectFromESP32();
      }
      _localActivityLogs.clear();
      AppLogger.info('Monitoring state cleaned up successfully', tag: 'EXIT');
    } catch (e) {
      AppLogger.error('Error during monitoring state cleanup', error: e);
    }
  }




  // 🎯 UPDATED: Helper methods untuk responsive design - lebih konservatif untuk mencegah overflow
  int _calculateCrossAxisCount(double screenWidth) {
    // Enhanced responsive calculation for better device coverage
    // Using breakpoint-based design for optimal user experience
    if (screenWidth < 360) {
      return 2; // Small phones (iPhone SE, etc.) - minimal density
    } else if (screenWidth < 480) {
      return 3; // Regular phones - balanced density
    } else if (screenWidth < 600) {
      return 4; // Large phones - good density
    } else if (screenWidth < 768) {
      return 5; // Small tablets/landscape phones - moderate density
    } else if (screenWidth < 900) {
      return 6; // Tablets - good balance
    } else if (screenWidth < 1024) {
      return 7; // Large tablets - high density
    } else if (screenWidth < 1200) {
      return 8; // Small desktop - very good density
    } else if (screenWidth < 1600) {
      return 10; // Standard desktop - maximum density
    } else {
      return 12; // Large desktop/4K - ultra high density
    }
  }

  
  
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _isNavigating || _isDialogClosing) return; // Enhanced safety
        if (_isPasswordDialogShowing) return; // Already showing dialog

        // Show password dialog for exit protection
        _showExitPasswordDialog();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Consumer<FireAlarmData>(
            builder: (context, fireAlarmData, child) {
              // Calculate total configured zones count (5 zones per module)
              final totalConfiguredZones = widget.moduleCount * 5;

              return Container(
                width: double.infinity,
                padding: _getResponsivePadding(context),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
  
                            // Header info (Project info dengan offline-specific controls)
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(
                                horizontal: _getContainerPadding(context),
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: Column(
                                children: [
                                  // First row: Back button, module controls, and project info
                                  Row(
                                    children: [
                                      // Back Button (dipindahkan dari container atas)
                                      IconButton(
                                        onPressed: _showExitPasswordDialog,
                                        icon: const Icon(
                                          Icons.arrow_back_ios_new,
                                          color: Colors.black87,
                                          size: 22,
                                        ),
                                        padding: const EdgeInsets.all(10),
                                        constraints: const BoxConstraints(
                                          minWidth: 45,
                                          minHeight: 45,
                                        ),
                                      ),

                                      // Spacer
                                      const SizedBox(width: 15),

                                      // Module Controls (dipindahkan dari baris 2)
                                      AnimatedOpacity(
                                        opacity: _showModuleControls ? 1.0 : 0.0,
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeInOut,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            border: Border.all(color: Colors.grey.shade400),
                                            borderRadius: BorderRadius.circular(8),
                                            color: Colors.white,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Decrease button
                                              InkWell(
                                                onTap: _decrementModules,
                                                child: Container(
                                                  width: 28,
                                                  height: 28,
                                                  decoration: BoxDecoration(
                                                    color: _displayModules > 1 ? Colors.red.shade100 : Colors.grey.shade200,
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Icon(
                                                    Icons.remove,
                                                    size: 18,
                                                    color: _displayModules > 1 ? Colors.red : Colors.grey,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    'MODULES',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.grey.shade600,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                  Text(
                                                    '$_displayModules',
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.black,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(width: 12),
                                              // Increase button
                                              InkWell(
                                                onTap: _incrementModules,
                                                child: Container(
                                                  width: 28,
                                                  height: 28,
                                                  decoration: BoxDecoration(
                                                    color: _displayModules < 63 ? Colors.green.shade100 : Colors.grey.shade200,
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Icon(
                                                    Icons.add,
                                                    size: 18,
                                                    color: _displayModules < 63 ? Colors.green : Colors.grey,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),

                                      // Spacer antara module controls dan project info
                                      const SizedBox(width: 20),

                                      // Project Info di dalam Expanded
                                      Expanded(
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                                          children: [
                                            Column(
                                              children: [
                                                const Text(
                                                  'PROJECT',
                                                  style: TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                const SizedBox(height: 5),
                                                Text(
                                                  widget.projectName,
                                                  style: const TextStyle(
                                                    color: Colors.black87,
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Column(
                                              children: [
                                                const Text(
                                                  'STATUS',
                                                  style: TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                const SizedBox(height: 5),
                                                Text(
                                                  // 🔥 FIX: Gunakan logika status yang benar
                                                  _isDisconnected
                                                      ? 'DISCONNECTED'
                                                      : _getSystemStatusText(fireAlarmData),
                                                  style: TextStyle(
                                                    // 🔥 FIX: Gunakan warna yang sesuai status
                                                    color: _isDisconnected
                                                        ? Colors.red
                                                        : _getSystemStatusColor(fireAlarmData),
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Column(
                                              children: [
                                                const Text(
                                                  'ACTIVE ZONES',
                                                  style: TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                const SizedBox(height: 5),
                                                Text(
                                                  '$totalConfiguredZones',
                                                  style: const TextStyle(
                                                    color: Colors.black87,
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  ],
                              ),
                            ),

                            const SizedBox(height: 10),

                            // Modules container
                            Flexible(
                              child: Container(
                                width: double.infinity,
                                padding: EdgeInsets.all(_getContainerPadding(context)),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: _buildDynamicGrid(
                                  context,
                                  BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width - (_getContainerPadding(context) * 2) - 40,
                                    maxHeight: 400,
                                  ),
                                  fireAlarmData,
                                ),
                              ),
                            ),

                            const SizedBox(height: 10),

                            // 🎯 TAB SECTION (Activity Logs & Status)
                            _buildTabSection(),

                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Helper: Get system status text based on LED states (from master data)
  String _getSystemStatusText(FireAlarmData fireAlarmData) {
    // 🔥 USE LED FLAGS from master data, NOT zone counts!
    if (fireAlarmData.alarmLED) {
      return 'ALARM';
    }
    if (fireAlarmData.troubleLED) {
      return 'TROUBLE';
    }
    return 'NORMAL';
  }

  /// Helper: Get system status color based on LED states (from master data)
  Color _getSystemStatusColor(FireAlarmData fireAlarmData) {
    // 🔥 USE LED FLAGS from master data, NOT zone counts!
    if (fireAlarmData.alarmLED) {
      return Colors.red;  // ALARM = Merah
    }
    if (fireAlarmData.troubleLED) {
      return Colors.yellow.shade700;  // TROUBLE = KUNING
    }
    return Colors.green;  // NORMAL = Hijau
  }

  Widget _buildDynamicGrid(BuildContext context, BoxConstraints constraints, FireAlarmData fireAlarmData) {
    final crossAxisCount = _calculateCrossAxisCount(constraints.maxWidth);
    final spacing = _getGridSpacing(context);
    final moduleWidth = (constraints.maxWidth - (crossAxisCount - 1) * spacing) / crossAxisCount;

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: spacing,
      runSpacing: spacing,
      children: List.generate(_displayModules, (index) {
        final moduleNumber = index + 1;

        // 🔥 CRITICAL FIX: Bungkus dengan Consumer supaya rebuild saat FireAlarmData berubah
        return SizedBox(
          width: moduleWidth,
          child: Consumer<FireAlarmData>(
            builder: (context, fireAlarmData, child) {
              return IndividualModuleContainer(
                key: ValueKey('module_$moduleNumber'), // Tambah key untuk memastikan rebuild
                moduleNumber: moduleNumber,
                fireAlarmData: fireAlarmData,
                zoneNames: _zoneNames,
                onZoneTap: (zoneNumber) => _showZoneDetailDialog(context, zoneNumber, fireAlarmData),
                onModuleTap: (moduleNumber) => _showModuleDetailDialog(context, moduleNumber, fireAlarmData),
              );
            },
          ),
        );
      }),
    );
  }

  
  
  
  
  /// Build tab section with headers and content
  Widget _buildTabSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTabHeaders(),
          const SizedBox(height: 16),
          _buildTabContent(),
        ],
      ),
    );
  }

  /// Check if alarm icon should be shown based on active alarm zones or bell status
  bool _shouldShowAlarmIcon(FireAlarmData fireAlarmData) {
    // ✅ FIXED: Use BellManager instead of FireAlarmData for bell status
    final bellManager = GetIt.instance<BellManager>();
    final hasActiveBells = bellManager != null && bellManager.currentStatus.activeBells > 0;

    return fireAlarmData.activeAlarmZones.isNotEmpty ||
           fireAlarmData.alarmLED ||
           hasActiveBells;
  }

  /// Check if trouble icon should be shown based on active trouble zones
  bool _shouldShowTroubleIcon(FireAlarmData fireAlarmData) {
    return fireAlarmData.activeTroubleZones.isNotEmpty;
  }

  /// Build tab headers (Recent Status, Fire Alarm)
  Widget _buildTabHeaders() {
    return Consumer<FireAlarmData>(
      builder: (context, fireAlarmData, child) {
        return Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Row(
            children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedTab = 'recent';
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _selectedTab == 'recent'
                      ? const Color.fromARGB(255, 19, 137, 47) // Green theme
                      : Colors.transparent,
                  border: Border(
                    bottom: BorderSide(
                      color: _selectedTab == 'recent'
                          ? const Color.fromARGB(255, 19, 137, 47)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  'RECENT STATUS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _selectedTab == 'recent'
                        ? Colors.white
                        : Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedTab = 'fire_alarm';
                  // Alarm zones are extracted directly in _buildFireAlarmTab() when needed
                });
              },
              child: BlinkingTabHeader(
                shouldBlink: _shouldShowAlarmIcon(fireAlarmData),
                blinkColor: Colors.red,
                enableGlow: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _selectedTab == 'fire_alarm'
                        ? Colors.red.shade600
                        : Colors.transparent,
                    border: Border(
                      bottom: BorderSide(
                        color: _selectedTab == 'fire_alarm'
                            ? Colors.red.shade600
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_shouldShowAlarmIcon(fireAlarmData)) ...[
                        Icon(
                          Icons.local_fire_department,
                          size: 16,
                          color: _selectedTab == 'fire_alarm'
                              ? Colors.white
                              : Colors.grey.shade700,
                        ),
                        const SizedBox(width: 4),
                      ],
                      // ✅ FIXED: Use BellManager directly instead of FireAlarmData
                      // BellManager uses 0x20 bit correctly, not LED status
                      if ((GetIt.instance<BellManager>()?.currentStatus.activeBells ?? 0) > 0) ...[
                        Icon(
                          Icons.notifications_active,
                          size: 16,
                          color: _selectedTab == 'fire_alarm'
                              ? Colors.white
                              : Colors.orange,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        'FIRE ALARM',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _selectedTab == 'fire_alarm'
                              ? Colors.white
                              : Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedTab = 'trouble';
                  // Trouble zones are extracted directly in _buildTroubleTab() when needed
                });
              },
              child: BlinkingTabHeader(
                shouldBlink: _shouldShowTroubleIcon(fireAlarmData),
                blinkColor: Colors.yellow.shade700,  // TROUBLE = KUNING
                enableGlow: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _selectedTab == 'trouble'
                        ? Colors.yellow.shade700  // TROUBLE = KUNING
                        : Colors.transparent,
                    border: Border(
                      bottom: BorderSide(
                        color: _selectedTab == 'trouble'
                            ? Colors.yellow.shade700  // TROUBLE = KUNING
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_shouldShowTroubleIcon(fireAlarmData)) ...[
                        Icon(
                          Icons.warning,
                          size: 16,
                          color: _selectedTab == 'trouble'
                              ? Colors.white
                              : Colors.grey.shade700,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        'TROUBLE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _selectedTab == 'trouble'
                              ? Colors.white
                              : Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
          ),
        );
      },
    );
  }

  /// Build tab content based on selected tab
  Widget _buildTabContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate dynamic height based on available screen space
        final screenHeight = MediaQuery.of(context).size.height;
        final availableHeight = screenHeight - 300; // Account for header, status bar, and other UI elements
        final dynamicHeight = (availableHeight * 0.6).clamp(300.0, 600.0); // Min 300px, max 600px

        return SizedBox(
          height: dynamicHeight,
          child: _selectedTab == 'recent'
              ? _buildRecentStatusTab()
              : _selectedTab == 'fire_alarm'
                  ? _buildFireAlarmTab()
                  : _buildTroubleTab(),
        );
      },
    );
  }

  /// Build Recent Status tab content
  Widget _buildRecentStatusTab() {
    return Consumer<FireAlarmData>(
      builder: (context, fireAlarmData, child) {
        final activityLogs = fireAlarmData.activityLogs;
        final hasLogs = activityLogs.isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date picker
            _buildDateTabs(fireAlarmData),
            const SizedBox(height: 8),
            // Event count header
            _buildEventCountHeader(fireAlarmData),
            const SizedBox(height: 8),
            // Activity logs
            Expanded(
              child: !hasLogs
                  ? _buildNoDataWidget('No recent activities available')
                  : _buildActivityLogs(fireAlarmData),
            ),
          ],
        );
      },
    );
  }

  /// Build event count header
  Widget _buildEventCountHeader(FireAlarmData fireAlarmData) {
    if (_selectedDate.isEmpty) return const SizedBox.shrink();

    final dateLogs = fireAlarmData.getActivityLogsByDate(_selectedDate);

    // Format date for display (convert yyyy-MM-dd to dd/MM/yyyy)
    String displayDate = _selectedDate;
    try {
      final parts = _selectedDate.split('-');
      if (parts.length == 3) {
        displayDate = '${parts[2]}/${parts[1]}/${parts[0]}'; // dd/MM/yyyy
      }
    } catch (e) {
      // Keep original if parsing fails
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          Icon(
            Icons.calendar_today,
            color: Colors.green.shade600,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            '$displayDate: ${dateLogs.length} event${dateLogs.length != 1 ? 's' : ''}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }

  /// Build date tabs for activity log filtering
  Widget _buildDateTabs(FireAlarmData fireAlarmData) {
    // Get available dates (will include today if empty)
    final availableDates = fireAlarmData.getAvailableDatesFromActivityLogs();

    // Always show date selection area with enhanced styling
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: availableDates.length,
        itemBuilder: (context, index) {
          final date = availableDates[index];
          final isSelected = date == _selectedDate;

          // Format date for display (convert yyyy-MM-dd to dd/MM/yyyy)
          String displayDate = date;
          try {
            final parts = date.split('-');
            if (parts.length == 3) {
              displayDate = '${parts[2]}/${parts[1]}/${parts[0]}'; // dd/MM/yyyy
            }
          } catch (e) {
            // Keep original if parsing fails
          }

          // Calculate responsive width
          final screenWidth = MediaQuery.of(context).size.width;
          double itemWidth = screenWidth <= 412 ? 100.0 : 110.0;

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedDate = date;
              });
            },
            child: Container(
              width: itemWidth,
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.green.shade100
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected
                      ? Colors.green.shade300
                      : Colors.green.shade200,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Center(
                child: Text(
                  displayDate,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? Colors.green.shade800
                        : Colors.green.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Build activity logs display from FireAlarmData
  Widget _buildActivityLogs(FireAlarmData fireAlarmData) {
    final dateLogs = fireAlarmData.getActivityLogsByDate(_selectedDate);

    if (dateLogs.isEmpty) {
      return _buildNoDataWidget('No activities for selected date');
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      itemCount: dateLogs.length,
      itemBuilder: (context, index) {
        final log = dateLogs[index];
        final logType = log['type'] as String?;

        // Tentukan warna border berdasarkan type
        Color borderColor;
        double borderWidth;

        switch (logType) {
          case 'alarm':
          case 'DISCONNECT_WARNING':
            borderColor = Colors.red.shade400; // Merah untuk alarm/warning
            borderWidth = 2.0;
            break;
          case 'trouble':
            borderColor = Colors.orange.shade400; // Kuning/oranye untuk trouble
            borderWidth = 2.0;
            break;
          case 'normal':
          case 'RECONNECTED':
            borderColor = Colors.green.shade400; // Hijau untuk normal/reconnect
            borderWidth = 2.0;
            break;
          case 'connection':
            borderColor = Colors.blue.shade400; // Biru untuk connection info
            borderWidth = 1.5;
            break;
          default:
            borderColor = Colors.grey.shade200; // Default grey
            borderWidth = 1.0;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: borderColor,
              width: borderWidth,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.03),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 14,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    log['time'] ?? '',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                log['activity'] ?? '',
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Build Fire Alarm tab content
  Widget _buildFireAlarmTab() {
    return Consumer<FireAlarmData>(
      builder: (context, fireAlarmData, child) {
        final alarmZones = _extractAlarmZones();
        final hasActiveAlarm = alarmZones.isNotEmpty;

        // 🔥 Get silenced status from fireAlarmData
        final isSilenced = fireAlarmData.isSilenced;

        // 🔔 FIXED: Use BellManager for accurate bell status (not FireAlarmData)
        // BellManager uses 0x20 bit correctly, doesn't depend on LED status
        final bellManager = GetIt.instance<BellManager>();
        final hasActiveBells = bellManager != null && bellManager.currentStatus.activeBells > 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with alarm and bell count
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                // 🔥 Show warning colors if silenced OR has active alarm/bells
                color: (hasActiveAlarm || hasActiveBells || isSilenced) ? Colors.red.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (hasActiveAlarm || hasActiveBells || isSilenced) ? Colors.red.shade200 : Colors.green.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    // 🔥 Show warning icon if silenced OR has active alarm/bells
                    (hasActiveAlarm || hasActiveBells || isSilenced) ? Icons.warning : Icons.check_circle,
                    color: (hasActiveAlarm || hasActiveBells || isSilenced) ? Colors.red.shade600 : Colors.green.shade600,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          // 🔥 Show "Bells Area SILENCED" if master silenced ON
                          isSilenced
                              ? 'Bells Area SILENCED'
                              : (hasActiveAlarm || hasActiveBells)
                                  ? 'Active Bell Area'
                                  : 'No Active Alarms',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            // 🔥 Red color if silenced OR active alarms
                            color: (hasActiveAlarm || hasActiveBells || isSilenced) ? Colors.red.shade700 : Colors.green.shade700,
                          ),
                        ),
                        if (hasActiveAlarm && hasActiveBells) ...[
                          Text(
                            '${alarmZones.length} zone(s) in alarm state • ${bellManager?.currentStatus.activeBells ?? 0} bell(s) ringing',
                            style: TextStyle(
                              fontSize: 14,
                              color: (hasActiveAlarm || hasActiveBells) ? Colors.red.shade600 : Colors.green.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // 🔔 Display module addresses with active bells
                          _buildActiveBellModules(bellManager),
                        ] else if (hasActiveAlarm) ...[
                          Text(
                            '${alarmZones.length} zone(s) in alarm state',
                            style: TextStyle(
                              fontSize: 14,
                              color: (hasActiveAlarm || hasActiveBells) ? Colors.red.shade600 : Colors.green.shade600,
                            ),
                          ),
                        ] else if (hasActiveBells) ...[
                          const SizedBox(height: 4),
                          // Display module addresses with active bells
                          _buildActiveBellModules(bellManager),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
        const SizedBox(height: 12),
        // Alarm zones list
        Expanded(
          child: !hasActiveAlarm
              ? _buildNoDataWidget('No active alarm zones')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: alarmZones.length,
                  itemBuilder: (context, index) {
                    final zone = alarmZones[index];
                    return InkWell(
                      onTap: () => _showZoneDetailDialog(context, zone['zoneNumber'], fireAlarmData),
                      child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.red.shade200,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.08),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade600,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  'Zone ${zone['zoneNumber']}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (zone['bellType'] == true) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.notifications_active,
                                  color: Colors.red.shade600,
                                  size: 14,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            zone['area'] ?? '',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            zone['status'] ?? '',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
      },
    );
  }

  /// Build Trouble tab content
  Widget _buildTroubleTab() {
    return Consumer<FireAlarmData>(
      builder: (context, fireAlarmData, child) {
        final troubleZones = _extractTroubleZones();
        final hasActiveTrouble = troubleZones.isNotEmpty;

        return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with trouble count
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: hasActiveTrouble ? Colors.yellow.shade50 : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasActiveTrouble ? Colors.yellow.shade300 : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.warning,
                color: hasActiveTrouble ? Colors.yellow.shade700 : Colors.grey.shade600,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasActiveTrouble
                          ? '${troubleZones.length} Active Trouble Zone${troubleZones.length != 1 ? 's' : ''}'
                          : 'No Active Trouble',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: hasActiveTrouble ? Colors.yellow.shade800 : Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      hasActiveTrouble ? 'System requires attention' : 'All systems operational',
                      style: TextStyle(
                        fontSize: 12,
                        color: hasActiveTrouble ? Colors.yellow.shade900 : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Trouble zones list
        Expanded(
          child: !hasActiveTrouble
              ? _buildNoDataWidget('No active trouble zones')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: troubleZones.length,
                  itemBuilder: (context, index) {
                    final zone = troubleZones[index];
                    return InkWell(
                      onTap: () => _showZoneDetailDialog(context, zone['zoneNumber'], fireAlarmData),
                      borderRadius: BorderRadius.circular(6),
                      splashColor: Colors.yellow.withValues(alpha: 0.1),
                      highlightColor: Colors.yellow.withValues(alpha: 0.05),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.yellow.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.yellow.shade300,
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.yellow.withValues(alpha: 0.08),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.yellow.shade700,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    'Zone ${zone['zoneNumber']}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.warning,
                                  color: Colors.yellow.shade700,
                                  size: 14,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              zone['area'] ?? '',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              zone['status'] ?? '',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.yellow.shade900,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
      },
    );
  }

  /// Build no data widget
  Widget _buildNoDataWidget(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'System events will appear here automatically',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  // Get responsive padding for main container
  EdgeInsets _getResponsivePadding(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    // Enhanced responsive padding based on screen size
    double horizontalPadding;
    double verticalPadding;

    if (screenWidth < 360) {
      horizontalPadding = 8.0;  // Small phones
      verticalPadding = 6.0;
    } else if (screenWidth < 480) {
      horizontalPadding = 10.0; // Regular phones
      verticalPadding = 8.0;
    } else if (screenWidth < 768) {
      horizontalPadding = 12.0; // Large phones
      verticalPadding = 10.0;
    } else if (screenWidth < 1024) {
      horizontalPadding = 16.0; // Tablets
      verticalPadding = 12.0;
    } else if (screenWidth < 1200) {
      horizontalPadding = 20.0; // Small desktop
      verticalPadding = 15.0;
    } else {
      horizontalPadding = 25.0; // Large desktop
      verticalPadding = 20.0;
    }

    return EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding);
  }

  // Get responsive padding for individual containers
  double _getContainerPadding(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    if (screenWidth < 360) {
      return 6.0;  // Small phones
    } else if (screenWidth < 480) {
      return 8.0;  // Regular phones
    } else if (screenWidth < 768) {
      return 10.0; // Large phones
    } else if (screenWidth < 1024) {
      return 12.0; // Tablets
    } else if (screenWidth < 1200) {
      return 16.0; // Small desktop
    } else {
      return 20.0; // Large desktop
    }
  }

  // Enhanced responsive spacing for grid
  double _getGridSpacing(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    if (screenWidth < 480) {
      return 4.0;  // Phones - compact spacing
    } else if (screenWidth < 768) {
      return 6.0;  // Large phones
    } else if (screenWidth < 1024) {
      return 8.0;  // Tablets
    } else if (screenWidth < 1200) {
      return 10.0; // Small desktop
    } else {
      return 12.0; // Large desktop
    }
  }

  // Calculate responsive font size based on screen diagonal
  double _calculateResponsiveFontSize(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final screenWidth = size.width;
    final diagonal = math.sqrt(size.width * size.width + size.height * size.height);
    double baseSize;

    if (screenWidth < 360) {
      baseSize = diagonal / 120; // Small phones - smaller font
    } else if (screenWidth < 480) {
      baseSize = diagonal / 110; // Regular phones
    } else if (screenWidth < 768) {
      baseSize = diagonal / 100; // Large phones
    } else if (screenWidth < 1024) {
      baseSize = diagonal / 90;  // Tablets
    } else if (screenWidth < 1200) {
      baseSize = diagonal / 80;  // Small desktop
    } else {
      baseSize = diagonal / 70;  // Large desktop - larger font
    }

    return baseSize.clamp(10.0, 18.0); // Wider range for better visibility
  }

  // Get responsive header font size
  double _getHeaderFontSize(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    if (screenWidth < 360) {
      return 12.0; // Small phones
    } else if (screenWidth < 480) {
      return 13.0; // Regular phones
    } else if (screenWidth < 768) {
      return 14.0; // Large phones
    } else if (screenWidth < 1024) {
      return 15.0; // Tablets
    } else if (screenWidth < 1200) {
      return 16.0; // Small desktop
    } else {
      return 18.0; // Large desktop
    }
  }

  // Get responsive title font size
  double _getTitleFontSize(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    if (screenWidth < 360) {
      return 14.0; // Small phones
    } else if (screenWidth < 480) {
      return 16.0; // Regular phones
    } else if (screenWidth < 768) {
      return 18.0; // Large phones
    } else if (screenWidth < 1024) {
      return 20.0; // Tablets
    } else if (screenWidth < 1200) {
      return 22.0; // Small desktop
    } else {
      return 24.0; // Large desktop
    }
  }

  
  /// Show zone detail dialog
  void _showZoneDetailDialog(BuildContext context, int zoneNumber, FireAlarmData fireAlarmData) async {
    // 🔥 FIX: Reload zone names sebelum menampilkan dialog
    final updatedZoneNames = await ZoneNameLocalStorage.loadZoneNamesForProject(widget.projectName);

    // Update _zoneNames yang utama juga
    if (mounted) {
      setState(() {
        _zoneNames = updatedZoneNames;
      });
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (BuildContext context) {
        return ZoneDetailDialog(
          zoneNumber: zoneNumber,
          fireAlarmData: fireAlarmData,
          zoneNames: updatedZoneNames,
        );
      },
    );
  }

  /// Show multi-alarm dialog with queue navigation
  void _showMultiAlarmDialog(BuildContext context, FireAlarmData fireAlarmData) async {
    // Reload zone names
    final updatedZoneNames = await ZoneNameLocalStorage.loadZoneNamesForProject(widget.projectName);

    // Update _zoneNames
    if (mounted) {
      setState(() {
        _zoneNames = updatedZoneNames;
      });
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (BuildContext context) {
        return ZoneDetailDialog(
          alarmQueue: _alarmQueueManager.currentQueue,
          initialIndex: 0,  // Start at first alarm
          fireAlarmData: fireAlarmData,
          zoneNames: updatedZoneNames,
          onClose: () {
            // Clear queue and reset flag when dialog closes
            _alarmQueueManager.clearQueue();
            _isAlarmDialogOpen = false;
          },
        );
      },
    ).then((_) {
      // Ensure flag is reset if dialog closed unexpectedly
      _isAlarmDialogOpen = false;
      _alarmQueueManager.clearQueue();
    });
  }

  /// Show module detail dialog
  void _showModuleDetailDialog(BuildContext context, int moduleNumber, FireAlarmData fireAlarmData) async {
    // 🔥 FIX: Reload zone names sebelum menampilkan dialog
    final updatedZoneNames = await ZoneNameLocalStorage.loadZoneNamesForProject(widget.projectName);

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (BuildContext context) {
        return ModuleDetailDialog(
          moduleNumber: moduleNumber,
          fireAlarmData: fireAlarmData,
          zoneNames: updatedZoneNames,
        );
      },
    );
  }

  /// Build widget showing module addresses with active bells
  /// Format: "MODULE ADDRESS: #01, #02, #03"
  Widget _buildActiveBellModules(BellManager? bellManager) {
    if (bellManager == null) return const SizedBox.shrink();
    
    final bellStatus = bellManager.currentStatus;
    if (bellStatus.activeBells == 0) return const SizedBox.shrink();
    
    // Extract device addresses with active bells
    final activeModules = bellStatus.deviceBellStatus.entries
      .where((entry) => entry.value.isActive)
      .map((entry) => entry.value.deviceAddress)
      .toList()
      ..sort();  // Sort numerically
    
    if (activeModules.isEmpty) return const SizedBox.shrink();
    
    // Format: #01, #02, #03
    final moduleAddresses = activeModules
      .map((addr) => '#${addr.toString().padLeft(2, '0')}')
      .join(', ');
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.red.shade200,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.notifications_active,
            size: 18,
            color: Colors.red.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade800,
                ),
                children: [
                  TextSpan(
                    text: 'MODULE ADDRESS: ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade800,
                    ),
                  ),
                  TextSpan(
                    text: moduleAddresses,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Individual Module Container - Container untuk setiap module (same as tab_monitoring.dart)
class IndividualModuleContainer extends StatefulWidget {
  final int moduleNumber;
  final FireAlarmData fireAlarmData;
  final Map<int, String> zoneNames;
  final Function(int)? onZoneTap;
  final Function(int)? onModuleTap;

  const IndividualModuleContainer({
    super.key,
    required this.moduleNumber,
    required this.fireAlarmData,
    required this.zoneNames,
    this.onZoneTap,
    this.onModuleTap,
  });

  @override
  _IndividualModuleContainerState createState() => _IndividualModuleContainerState();
}

class _IndividualModuleContainerState extends State<IndividualModuleContainer> {
  // Cache zone colors to detect changes and avoid unnecessary rebuilds
  late Map<int, Color> _lastZoneColors;
  late ModuleStatus _lastModuleStatus;

  @override
  void initState() {
    super.initState();
    _lastModuleStatus = _getModuleStatus();
    _initializeColorCache();
  }

  void _initializeColorCache() {
    _lastZoneColors = {};

    // Initialize cache with current colors
    for (int ledIndex = 1; ledIndex <= 5; ledIndex++) {
      final zoneNumber = ZoneStatusUtils.calculateGlobalZoneNumber(widget.moduleNumber, ledIndex);
      _lastZoneColors[zoneNumber] = _getZoneColorFromSystem(zoneNumber);
    }
  }

  @override
  void didUpdateWidget(IndividualModuleContainer oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Check if any zone colors have changed
    bool colorsChanged = false;

    // Check module status first
    final currentModuleStatus = _getModuleStatus();
    if (_lastModuleStatus != currentModuleStatus) {
      _lastModuleStatus = currentModuleStatus;
      colorsChanged = true;
    }

    // Check zone colors
    for (int ledIndex = 1; ledIndex <= 5; ledIndex++) {
      final zoneNumber = ZoneStatusUtils.calculateGlobalZoneNumber(widget.moduleNumber, ledIndex);
      final currentColor = _getZoneColorFromSystem(zoneNumber);
      if (_lastZoneColors[zoneNumber] != currentColor) {
        _lastZoneColors[zoneNumber] = currentColor;
        colorsChanged = true;
      }
    }

    // Only trigger rebuild if colors actually changed
    if (colorsChanged) {
      setState(() {});
    }
  }

  /// Determine module status based on all 5 zones
  /// Priority: Alarm > Trouble > Normal
  ModuleStatus _getModuleStatus() {
    bool hasAlarm = false;
    bool hasTrouble = false;
    
    // Check all 5 zones in this module
    for (int ledIndex = 1; ledIndex <= 5; ledIndex++) {
      final zoneNumber = ZoneStatusUtils.calculateGlobalZoneNumber(
        widget.moduleNumber, 
        ledIndex
      );
      final zoneStatus = widget.fireAlarmData.getZoneStatus(zoneNumber);
      
      if (zoneStatus?.hasAlarm == true) {
        hasAlarm = true;
        break; // Alarm has highest priority, stop checking
      }
      if (zoneStatus?.hasTrouble == true) {
        hasTrouble = true;
      }
    }
    
    if (hasAlarm) return ModuleStatus.alarm;
    if (hasTrouble) return ModuleStatus.trouble;
    return ModuleStatus.normal;
  }

  /// Get container decoration based on module status
  BoxDecoration _getModuleDecoration(ModuleStatus status) {
    Color bgColor;
    Color borderColor;
    
    switch (status) {
      case ModuleStatus.alarm:
        bgColor = Colors.red.shade50;
        borderColor = Colors.red.shade400;
        break;
      case ModuleStatus.trouble:
        bgColor = Colors.yellow.shade50;
        borderColor = Colors.yellow.shade600;
        break;
      case ModuleStatus.normal:
        bgColor = Colors.grey.shade50;
        borderColor = Colors.grey.shade300;
        break;
    }
    
    return BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: borderColor, width: 2),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 2,
          spreadRadius: 1,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onModuleTap != null ? () => widget.onModuleTap!(widget.moduleNumber) : null,
      child: Container(
        decoration: _getModuleDecoration(_getModuleStatus()),
        child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Module number
          Text(
            '#${widget.moduleNumber.toString().padLeft(2, '0')}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // 🎯 HORIZONTAL LAYOUT: Container untuk 6 LEDs dalam 1 baris dengan responsive spacing
          LayoutBuilder(
            builder: (context, ledConstraints) {
              // Calculate responsive spacing based on available container width
              final totalAvailableWidth = ledConstraints.maxWidth - 12.0; // minus horizontal padding
              final baseSpacing = (totalAvailableWidth * 0.01).clamp(0.5, 1.5); // 1% of width, min 0.5, max 1.5
              final bellSpacing = (totalAvailableWidth * 0.02).clamp(1.0, 2.0); // 2% of width, min 1, max 2

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300, width: 0.5),
                ),
                child: Row(
                  children: [
                    Expanded(child: _buildLED(1, Colors.red)), // Zone 1
                    SizedBox(width: baseSpacing * 0.3),
                    Expanded(child: _buildLED(2, Colors.red)), // Zone 2
                    SizedBox(width: baseSpacing * 0.3),
                    Expanded(child: _buildLED(3, Colors.red)), // Zone 3
                    SizedBox(width: baseSpacing * 0.3),
                    Expanded(child: _buildLED(4, Colors.red)), // Zone 4
                    SizedBox(width: baseSpacing * 0.3),
                    Expanded(child: _buildLED(5, Colors.red)), // Zone 5
                  ],
                ),
              );
            },
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildLED(int ledIndex, Color activeColor) {
    // Calculate zone number for this zone LED
    final zoneNumber = ZoneStatusUtils.calculateGlobalZoneNumber(widget.moduleNumber, ledIndex);
    // Use custom zone name, fallback to default if not available
    final label = widget.zoneNames[zoneNumber] ?? ZoneNameLocalStorage.getDefaultZoneName(zoneNumber);

    // Determine LED color based on zone status
    Color ledColor = _getZoneColorFromSystem(zoneNumber);

    final isActive = ledColor != Colors.grey.shade300 && ledColor != Colors.white;

      // 🔥 NEW: Calculate responsive LED size to prevent overflow
    // Use LayoutBuilder to get container constraints
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate available width for all 6 LEDs
        double totalAvailableWidth = constraints.maxWidth - 13.5; // Account for padding

        // Calculate optimal LED size with minimum and maximum constraints
        double maxLEDSize = 12.0;  // Reduced to fit zone numbers
        double minLEDSize = 8.0;   // Minimum readable size for zone numbers
        double spacingBudget = totalAvailableWidth / 6.0;

        // Use 70% of available space for LED, but clamp between min and max
        double responsiveLEDSize = (spacingBudget * 0.7).clamp(minLEDSize, maxLEDSize);

        // Calculate font size based on LED size
        double fontSize = (responsiveLEDSize * 0.4).clamp(6.0, 8.0);

        // Debug information for responsive sizing
        if (totalAvailableWidth < 90) {

        }

        return Padding(
          padding: const EdgeInsets.only(right: 1.5),
          child: GestureDetector(
            onTap: ledIndex <= 5 && widget.onZoneTap != null ? () => widget.onZoneTap!(zoneNumber) : null,
            child: Container(
              width: responsiveLEDSize,
              height: responsiveLEDSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ledColor,
                border: Border.all(
                  color: Colors.black54,
                  width: 0.5,
                ),
                boxShadow: isActive ? [
                  BoxShadow(
                    color: ledColor.withValues(alpha: 0.4),
                    blurRadius: 2,
                    spreadRadius: 0.5,
                  ),
                ] : null,
              ),
            ),
          ),
        );
      },
    );
  }

  // Get zone color based on complete system status
  Color _getZoneColorFromSystem(int zoneNumber) {
    // 🔥 FIX: Direct check dari activeAlarmZones dan activeTroubleZones
    final alarmZones = widget.fireAlarmData.activeAlarmZones;
    final troubleZones = widget.fireAlarmData.activeTroubleZones;

    // Cek langsung dari list (paling cepat dan akurat)
    if (alarmZones.contains(zoneNumber)) {
      return Colors.red;  // ALARM = MERAH
    }
    if (troubleZones.contains(zoneNumber)) {
      return Colors.yellow.shade700;  // TROUBLE = KUNING
    }

    // Check accumulation mode
    if (widget.fireAlarmData.isAccumulationMode) {
      if (widget.fireAlarmData.isZoneAccumulatedAlarm(zoneNumber)) {
        return Colors.red;
      }
      if (widget.fireAlarmData.isZoneAccumulatedTrouble(zoneNumber)) {
        return Colors.yellow.shade700;
      }
    }

    // Check individual zone status
    final zoneStatus = widget.fireAlarmData.getIndividualZoneStatus(zoneNumber);
    if (zoneStatus != null) {
      final status = zoneStatus['status'] as String?;

      // Cek OFFLINE status dulu sebelum cek alarm/trouble
      if (zoneStatus['isOffline'] == true || status == 'Offline') {
        return Colors.grey.shade300;  // OFFLINE = Abu-abu
      }

      if (status == 'Alarm') return Colors.red;
      if (status == 'Trouble') return Colors.yellow.shade700;
    }

    // Jika tidak ada data zone sama sekali → OFFLINE
    if (zoneStatus == null) {
      return Colors.grey.shade300;  // NO DATA = Abu-abu (Offline)
    }

    // Default: NORMAL/ACTIVE = HIJAU (hanya jika ada data dan tidak offline)
    return Colors.green;
  }
}


// Module Detail Dialog Widget
class ModuleDetailDialog extends StatelessWidget {
  final int moduleNumber;
  final FireAlarmData fireAlarmData;
  final Map<int, String> zoneNames;

  const ModuleDetailDialog({
    super.key,
    required this.moduleNumber,
    required this.fireAlarmData,
    required this.zoneNames,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate module zones (1-5 per module)
    final startZone = ((moduleNumber - 1) * 5) + 1;
    final endZone = startZone + 4;

    // Count active zones in this module
    int activeZones = 0;
    int alarmZones = 0;
    int troubleZones = 0;
    int normalZones = 0;

    for (int zoneNum = startZone; zoneNum <= endZone; zoneNum++) {
      final zoneStatus = fireAlarmData.getIndividualZoneStatus(zoneNum);
      if (zoneStatus != null) {
        final status = zoneStatus['status'] as String?;
        activeZones++;
        switch (status) {
          case 'Alarm':
            alarmZones++;
            break;
          case 'Trouble':
            troubleZones++;
            break;
          case 'Normal':
            normalZones++;
            break;
        }
      } else {
        normalZones++;
      }
    }

    // Determine overall module status
    Color moduleStatusColor;
    String moduleStatusText;
    if (alarmZones > 0) {
      moduleStatusColor = Colors.red;
      moduleStatusText = 'ALARM';
    } else if (troubleZones > 0) {
      moduleStatusColor = Colors.yellow.shade700;  // TROUBLE = KUNING
      moduleStatusText = 'TROUBLE';
    } else if (activeZones > 0) {
      moduleStatusColor = Colors.green;  // ACTIVE = HIJAU
      moduleStatusText = 'NORMAL';
    } else {
      moduleStatusColor = Colors.green;
      moduleStatusText = 'NORMAL';
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header with module status
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: moduleStatusColor.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                border: Border(
                  bottom: BorderSide(
                    color: moduleStatusColor.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'MODULE #$moduleNumber',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: moduleStatusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      
                      const SizedBox(width: 8),
                      Text(
                        'Device Address: $moduleNumber',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Module Statistics
                    
                    const SizedBox(height: 16),

                    // Zone List
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Zones in this Module',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...List.generate(5, (index) {
                            final zoneNum = startZone + index;
                            final zoneStatus = fireAlarmData.getIndividualZoneStatus(zoneNum);

                            // ADD: NO DATA validation for zones in module
                            String status;
                            if (!fireAlarmData.hasValidZoneData || fireAlarmData.isInitiallyLoading) {
                              status = 'Offline';
                            } else {
                              status = zoneStatus?['status'] as String? ?? 'Offline';
                            }

                            final statusColor = _getStatusColor(status);
                            final zoneName = zoneNames[zoneNum] ?? ZoneNameLocalStorage.getDefaultZoneName(zoneNum);

                            return GestureDetector(
                              onTap: () {
                                // Navigate to zone detail dialog
                                Navigator.of(context).pop(); // Close module dialog first
                                // Show zone detail dialog after a short delay to allow the previous dialog to close
                                Future.delayed(const Duration(milliseconds: 100), () {
                                  showDialog(
                                    context: context,
                                    barrierDismissible: true,
                                    barrierColor: Colors.black.withValues(alpha: 0.5),
                                    builder: (BuildContext context) {
                                      return ZoneDetailDialog(
                                        zoneNumber: zoneNum,
                                        fireAlarmData: fireAlarmData,
                                        zoneNames: zoneNames,
                                      );
                                    },
                                  );
                                });
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),  // Background ikut warna status
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: statusColor,
                                    width: 2,  // Border lebih tebal dan ikut warna status
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: statusColor.withValues(alpha: 0.15),  // Shadow ikut warna status
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: statusColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            zoneName,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                              color: statusColor,  // Text ikut warna status
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: statusColor,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: statusColor, width: 1),
                                          ),
                                          child: Text(
                                            status.toUpperCase(),
                                            style: TextStyle(
                                              color: Colors.white,  // Teks putih di atas warna status
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    // Show additional info if zone has data
                                    if (zoneStatus != null && status != 'Offline') ...[
                                      const SizedBox(height: 8),
                                      Padding(
                                        padding: const EdgeInsets.only(left: 24),
                                        child: Text(
                                          'Zone #$zoneNum',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: statusColor.withValues(alpha: 0.7),  // Ikut warna status
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // Close button
            Container(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: moduleStatusColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    // 🔥 FIX: Case insensitive - convert to uppercase
    final statusUpper = status.toUpperCase();
    switch (statusUpper) {
      case 'ALARM':
        return Colors.red;
      case 'TROUBLE':
        return Colors.yellow.shade700;  // TROUBLE = KUNING
      case 'NORMAL':
        return Colors.green;  // NORMAL = HIJAU
      case 'OFFLINE':
      case 'INACTIVE':
        return Colors.grey.shade300;  // OFFLINE = ABU-ABU
      default:
        return Colors.grey.shade300;
    }
  }
}