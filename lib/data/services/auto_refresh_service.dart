// ignore_for_file: prefer_final_fields, avoid_print

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'logger.dart';
import 'websocket_mode_manager.dart';
import '../datasources/websocket/websocket_service.dart';
import '../../presentation/providers/fire_alarm_data_provider.dart';

/// Auto Refresh Service untuk menghandle data update saat WebSocket/ESP32 mati
/// Memberikan fallback mechanism untuk mode offline dan auto-retry logic
class AutoRefreshService {
  static const String _tag = 'AUTO_REFRESH_SERVICE';
  static AutoRefreshService? _instance;

  /// Get singleton instance
  static AutoRefreshService get instance {
    _instance ??= AutoRefreshService._();
    return _instance!;
  }

  AutoRefreshService._() {
    // 🔥 ENHANCED: Constructor logging v2
    // ignore: avoid_print
    print('========================================');
    // ignore: avoid_print
    print('🏗️🏗️🏗️ AUTO_REFRESH_SERVICE CONSTRUCTOR CALLED v2 🏗️🏗️🏗️');
    print('========================================');
    _initialize();
  }

  // Timer untuk periodic refresh
  Timer? _refreshTimer;
  Timer? _connectionCheckTimer;
  Timer? _retryTimer;
  Timer? _disconnectCheckTimer;
  Timer? _hotReloadTimer;

  // Settings
  Duration _refreshInterval = const Duration(seconds: 5); // Default 5 detik
  Duration _connectionCheckInterval = const Duration(seconds: 3); // Check setiap 3 detik
  Duration _retryDelay = const Duration(seconds: 10); // Retry setelah 10 detik
  Duration _disconnectTimeout = const Duration(seconds: 30); // Disconnect setelah 30 detik tanpa data (OFFLINE MODE ONLY)
  Duration _postRestartGracePeriod = const Duration(seconds: 15); // 🔥 NEW: Grace period setelah restart (15 detik)

  // State tracking
  bool _isAutoRefreshEnabled = true;
  bool _isConnectionLost = false;
  bool _isDisconnected = false; // 🔥 NEW: Disconnect status untuk offline mode
  bool _hasReceivedDataAfterRestart = false; // 🔥 NEW: Track apakah sudah ada data setelah restart
  int _retryAttempts = 0;
  int _maxRetryAttempts = 5;
  DateTime? _lastSuccessfulUpdate;
  DateTime? _lastConnectionCheck;
  DateTime? _lastDataReceivedTime; // 🔥 NEW: Last time WebSocket data received (offline mode)
  DateTime? _lastRestartTime; // 🔥 NEW: Waktu terakhir aplikasi restart

  // Services
  FireAlarmData? _fireAlarmData;
  WebSocketModeManager? _webSocketModeManager;
  WebSocketService? _webSocketService;
  StreamSubscription<WebSocketStatus>? _webSocketStatusSubscription; // Track subscription to prevent duplicates

  // Controllers
  final StreamController<AutoRefreshStatus> _statusController =
      StreamController<AutoRefreshStatus>.broadcast();
  final StreamController<DateTime> _refreshController =
      StreamController<DateTime>.broadcast();
  final StreamController<void> _hotReloadTriggerController =
      StreamController<void>.broadcast(); // 🔥 NEW: Hot reload trigger stream

  // Public streams
  Stream<AutoRefreshStatus> get statusStream => _statusController.stream;
  Stream<DateTime> get refreshStream => _refreshController.stream;
  Stream<void> get hotReloadTriggerStream => _hotReloadTriggerController.stream; // 🔥 NEW: Expose hot reload stream

  // Getters
  bool get isAutoRefreshEnabled => _isAutoRefreshEnabled;
  bool get isConnectionLost => _isConnectionLost;
  bool get isDisconnected => _isDisconnected; // 🔥 NEW: Disconnect status untuk offline mode
  int get retryAttempts => _retryAttempts;
  DateTime? get lastSuccessfulUpdate => _lastSuccessfulUpdate;
  DateTime? get lastDataReceivedTime => _lastDataReceivedTime; // 🔥 NEW: Last data received time
  Duration get refreshInterval => _refreshInterval;

  /// Initialize auto refresh service - Updated to force recompile
  Future<void> _initialize() async {
    try {
      print('========================================');
      print('🏗️ AUTO_REFRESH_SERVICE: _initialize() STARTED');
      print('========================================');

      // Get service instances
      _webSocketModeManager = WebSocketModeManager.instance;
      print('✅ WebSocketModeManager obtained: ${_webSocketModeManager != null ? "OK" : "NULL"}');

      // Listen to WebSocket mode changes
      _webSocketModeManager?.addListener(_onWebSocketModeChanged);
      print('✅ WebSocket mode change listener ATTACHED');

      // Start connection monitoring
      _startConnectionMonitoring();
      print('✅ Connection monitoring STARTED');

      // 🔥 NEW: Start disconnect detection untuk offline mode
      print('🔍 About to call _startDisconnectDetection()...');
      _startDisconnectDetection();
      print('✅ _startDisconnectDetection() COMPLETED');

      print('========================================');
      print('✅ AUTO REFRESH SERVICE INITIALIZED');
      print('========================================');

    } catch (e, stackTrace) {
      print('❌❌❌ ERROR initializing Auto Refresh Service ❌❌❌');
      print('   Error: $e');
      print('   StackTrace: $stackTrace');
    }
  }

  /// Set FireAlarmData instance
  void setFireAlarmData(FireAlarmData fireAlarmData) {
    _fireAlarmData = fireAlarmData;

    // 🔥 DEBUG: Log when FireAlarmData is set
    AppLogger.info('========================================', tag: _tag);
    AppLogger.info('🔧 setFireAlarmData() CALLED', tag: _tag);
    AppLogger.info('   FireAlarmData: ${fireAlarmData != null ? "SET" : "NULL"}', tag: _tag);
    AppLogger.info('========================================', tag: _tag);
    AppLogger.info('✅ FireAlarmData set successfully', tag: _tag);
  }

  /// Set WebSocket service instance
  void setWebSocketService(WebSocketService webSocketService) {
    _webSocketService = webSocketService;

    // 🔥 DEBUG: Log when WebSocketService is set
    AppLogger.info('========================================', tag: _tag);
    AppLogger.info('🔧 setWebSocketService() CALLED', tag: _tag);
    AppLogger.info('   WebSocketService: ${webSocketService != null ? "SET" : "NULL"}', tag: _tag);
    AppLogger.info('========================================', tag: _tag);

    // 🔥 CRITICAL FIX: Cancel old subscription to prevent multiple listeners
    _webSocketStatusSubscription?.cancel();
    _webSocketStatusSubscription = null;

    // Listen to WebSocket status changes
    try {
      _webSocketStatusSubscription = _webSocketService?.statusStream.listen(
        _onWebSocketStatusChanged,
        onError: (error) {
          AppLogger.error('WebSocket status stream error: $error', tag: _tag);
        },
      );
      AppLogger.info('✅ WebSocket status stream listener ATTACHED', tag: _tag);
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error setting up WebSocket status stream listener',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
    }

    AppLogger.info('✅ WebSocketService set successfully', tag: _tag);
  }

  /// Start auto refresh
  void startAutoRefresh({Duration? interval}) {
    if (!_isAutoRefreshEnabled) {
      AppLogger.warning('Auto refresh is disabled', tag: _tag);
      return;
    }

    if (interval != null) {
      _refreshInterval = interval;
    }

    stopAutoRefresh(); // Stop existing timer first

    AppLogger.info(
      'Starting auto refresh with interval: ${_refreshInterval.inSeconds}s',
      tag: _tag,
    );

    _refreshTimer = Timer.periodic(_refreshInterval, (timer) {
      _performAutoRefresh();
    });

    _emitStatus(AutoRefreshStatus.active);
  }

  /// Stop auto refresh
  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;

    AppLogger.info('Auto refresh stopped', tag: _tag);
    _emitStatus(AutoRefreshStatus.stopped);
  }

  /// Enable/disable auto refresh
  void setAutoRefreshEnabled(bool enabled) {
    _isAutoRefreshEnabled = enabled;

    if (enabled) {
      startAutoRefresh();
    } else {
      stopAutoRefresh();
    }

    AppLogger.info('Auto refresh enabled: $enabled', tag: _tag);
  }

  /// Set refresh interval
  void setRefreshInterval(Duration interval) {
    _refreshInterval = interval;

    // Restart timer if currently active
    if (_refreshTimer != null) {
      startAutoRefresh();
    }

    AppLogger.info(
      'Refresh interval set to: ${interval.inSeconds}s',
      tag: _tag,
    );
  }

  /// Start connection monitoring
  void _startConnectionMonitoring() {
    _connectionCheckTimer?.cancel();

    _connectionCheckTimer = Timer.periodic(_connectionCheckInterval, (timer) {
      _checkConnectionStatus();
    });

    AppLogger.info('Connection monitoring started', tag: _tag);
  }

  /// Check connection status and handle connection loss
  void _checkConnectionStatus() {
    try {
      _lastConnectionCheck = DateTime.now();

      final isWebSocketMode = _webSocketModeManager?.isWebSocketMode ?? false;
      bool isConnectionHealthy = false;

      if (isWebSocketMode) {
        // Check WebSocket connection
        isConnectionHealthy = _webSocketService?.isConnected ?? false;
      } else {
        // Check Firebase connectivity (ping test)
        isConnectionHealthy = _checkFirebaseConnectivity();
      }

      final wasConnectionLost = _isConnectionLost;
      _isConnectionLost = !isConnectionHealthy;

      if (_isConnectionLost && !wasConnectionLost) {
        // Connection just lost
        AppLogger.warning('Connection lost detected', tag: _tag);
        _handleConnectionLoss();
      } else if (!_isConnectionLost && wasConnectionLost) {
        // Connection restored
        AppLogger.info('Connection restored', tag: _tag);
        _handleConnectionRestored();
      }

    } catch (e, stackTrace) {
      AppLogger.error(
        'Error checking connection status',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Check Firebase connectivity
  bool _checkFirebaseConnectivity() {
    // Simple connectivity check - in real implementation,
    // you might want to ping Firebase or check network status
    // For now, assume Firebase is always reachable in online mode
    return true;
  }

  /// Handle connection loss
  void _handleConnectionLoss() {
    _retryAttempts = 0;
    _emitStatus(AutoRefreshStatus.connectionLost);

    // Start auto refresh for offline mode
    if (_isAutoRefreshEnabled) {
      AppLogger.info('Starting offline auto refresh due to connection loss', tag: _tag);
      startAutoRefresh(interval: Duration(seconds: 3)); // Faster refresh when offline
    }

    // Schedule retry attempts
    _scheduleRetryAttempts();
  }

  /// Handle connection restored
  void _handleConnectionRestored() {
    _retryAttempts = 0;
    _emitStatus(AutoRefreshStatus.connected);

    // Stop retry timer
    _retryTimer?.cancel();
    _retryTimer = null;

    // Reset refresh interval to normal
    if (_refreshTimer != null) {
      startAutoRefresh(); // Restart with normal interval
    }

    AppLogger.info('Connection restored - auto refresh running normally', tag: _tag);
  }

  /// Schedule retry attempts
  void _scheduleRetryAttempts() {
    if (_retryAttempts >= _maxRetryAttempts) {
      AppLogger.warning('Max retry attempts reached, stopping auto retry', tag: _tag);
      _emitStatus(AutoRefreshStatus.maxRetriesReached);
      return;
    }

    _retryTimer = Timer(_retryDelay, () {
      _retryAttempts++;

      AppLogger.info(
        'Attempting connection retry #$_retryAttempts',
        tag: _tag,
      );

      _attemptReconnection();
    });
  }

  /// Attempt reconnection
  void _attemptReconnection() {
    try {
      final isWebSocketMode = _webSocketModeManager?.isWebSocketMode ?? false;

      if (isWebSocketMode) {
        // Attempt WebSocket reconnection
        final esp32IP = _webSocketModeManager?.esp32IP ?? '';
        if (esp32IP.isNotEmpty) {
          _webSocketService?.connectWithHealthCheck('ws://$esp32IP:81');
        }
      } else {
        // Firebase reconnection is automatic, just mark as restored
        _handleConnectionRestored();
      }

    } catch (e, stackTrace) {
      AppLogger.error(
        'Error during reconnection attempt',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );

      // Schedule next retry
      _scheduleRetryAttempts();
    }
  }

  // ============= DISCONNECT DETECTION (OFFLINE MODE) =============

  /// Start disconnect detection untuk offline mode (WebSocket)
  /// Mendeteksi jika 30 detik tidak ada data dari ESP32
  void _startDisconnectDetection() {
    _disconnectCheckTimer?.cancel();

    print('🔍🔍🔍 AUTO_REFRESH_SERVICE: _startDisconnectDetection() CALLED 🔍🔍🔍');
    print('         Check interval: Every 5 seconds');
    print('         Timeout: ${_disconnectTimeout.inSeconds} seconds');

    _disconnectCheckTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      // Silent timer tick - no need to spam logs every check
      _checkDisconnectStatus();
    });

    print('✅ AUTO_REFRESH_SERVICE: Disconnect detection timer STARTED (interval: ${_connectionCheckInterval.inSeconds}s)');
  }

  /// Check disconnect status untuk offline mode
  void _checkDisconnectStatus() {
    try {
      // 🔥 DEBUG: Log setiap kali check dipanggil
      final now = DateTime.now();
      final timeFormatted = '${now.hour}:${now.minute}:${now.second}';
      // 🔥 FIX: Jika belum pernah ada data dan belum ada data setelah restart, skip check
      // Tapi jika sudah pernah connect sebelumnya (lastDataReceivedTime != null), lanjutkan check
      if (_lastDataReceivedTime == null && !_hasReceivedDataAfterRestart) {
        // Skip disconnect check - silent skip, no need to spam logs every 3 seconds
        return;
      }

      // 🔥 FIX: Cek apakah WebSocketService terdaftar (ada indikasi mode offline)
      // Daripada bergantung pada isWebSocketMode flag yang mungkin incorrect
      final hasWebSocketService = _webSocketService != null;
      final isWebSocketMode = _webSocketModeManager?.isWebSocketMode ?? false;
      final isWSConnected = _webSocketService?.isConnected ?? false;

      print('⏰ AUTO_REFRESH: _checkDisconnectStatus() WS=$isWSConnected Mode=$isWebSocketMode');

      // 🔥 FIX: Gunakan logic baru - check jika WebSocketService exists dan sudah pernah ada data
      if (!hasWebSocketService) {
        print('   ❌ No WebSocketService - Firebase mode, skipping disconnect check');
        // Firebase mode - reset disconnect status
        if (_isDisconnected) {
          _isDisconnected = false;
          _emitStatus(AutoRefreshStatus.connected);
          print('   ✅ Firebase mode - disconnect status CLEARED');
        }
        return;
      }

      print('   ✅ WebSocket mode - proceeding with disconnect check');

      // 🔥 NEW: Check grace period setelah restart
      if (_lastRestartTime != null) {
        final timeSinceRestart = DateTime.now().difference(_lastRestartTime!);
        if (timeSinceRestart < _postRestartGracePeriod) {
          final remainingGrace = _postRestartGracePeriod - timeSinceRestart;
          print('   🛡️ GRACE PERIOD ACTIVE: ${remainingGrace.inSeconds}s remaining');
          print('   ℹ️ Skipping disconnect check - waiting for ESP32 to connect after restart');
          return; // Skip disconnect check selama grace period
        } else {
          print('   ✅ Grace period ended - normal disconnect detection resumed');
          _lastRestartTime = null; // Clear restart time setelah grace period berakhir
        }
      }

      // Hitung waktu sejak data terakhir
      final timeSinceLastData = DateTime.now().difference(_lastDataReceivedTime!);

      // 🔥 DEBUG: Log ALWAYS - bukan conditional
      print('   ⏱️⏱️⏱️ ${timeSinceLastData.inSeconds}s since last data (timeout: ${_disconnectTimeout.inSeconds}s) | isDisconnected: $_isDisconnected');

      // 🔥 NEW LOGIC:
      // 1. Setelah 3 detik tanpa data → Set isDisconnected = TRUE, tampil "DISCONNECTED"
      // 2. Setelah 30 detik → Hot reload aplikasi

      // Step 1: Set disconnect status setelah 3 detik
      if (timeSinceLastData > Duration(seconds: 3) && !_isDisconnected) {
        print('');
        print('   🚨🚨🚨 NO DATA DETECTED! (${timeSinceLastData.inSeconds}s > 3s) 🚨🚨🚨');

        _isDisconnected = true;
        print('   ⚠️⚠️⚠️ SETTING isDisconnected = TRUE ⚠️⚠️⚠️');
        print('   ⚠️ ESP32 DISCONNECTED - Tampilan akan menampilkan "DISCONNECTED"');

        // Emit disconnect status untuk UI
        _emitStatus(AutoRefreshStatus.disconnected);

        // 🔥 NEW: Add user-friendly log for data timeout
        if (_fireAlarmData != null && _fireAlarmData!.isMounted) {
          _fireAlarmData!.addActivityLog(
            'Host no Data Communication - Please Check Systems Settings',
            type: 'warning',
          );
          AppLogger.warning('No data from host, user notified via activity log', tag: 'DATA_TIMEOUT');
        }

        // 🔥 NEW: Add warning to Recent Status di FireAlarmData (backward compatibility)
        _addDisconnectWarningToRecentStatus(timeSinceLastData);

        // 🔥 NEW: Schedule hot reload setelah 30 detik
        _scheduleHotReload(timeSinceLastData);

      }
      // Step 2: Reconnect Attempt setelah 30 detik (Gantikan Hot Reload)
      else if (_isDisconnected && timeSinceLastData > _disconnectTimeout) {
        print('');
        print('   ⏰⏰⏰ 30 DETIK BERLALU - MENCOBA RECONNECT (SAFE) ⏰⏰⏰');
        
        // Coba reconnect tanpa reload aplikasi
        _attemptReconnection();
        
        // Reset timer disconnect untuk memberikan waktu bagi reconnect attempt
        _lastDataReceivedTime = DateTime.now().subtract(Duration(seconds: 5)); 
      }
    } catch (e, stackTrace) {
      print('❌ ERROR checking disconnect status: $e');
    }
  }

  /// Schedule reconnect attempt (Safe replacement for Hot Reload)
  void _scheduleHotReload(Duration timeSinceLastData) {
    // Deprecated: Using _scheduleSafeReconnect instead internally
    // Hitung sisa waktu sampai 30 detik
    final remainingTime = _disconnectTimeout - timeSinceLastData;

    print('   ⏳ Scheduling RECONNECT in ${remainingTime.inSeconds} seconds...');

    _hotReloadTimer?.cancel();
    _hotReloadTimer = Timer(remainingTime, () {
      print('');
      print('   ⏰⏰⏰ TIMEOUT EXPIRED - TRIGGERING SAFE RECONNECT ⏰⏰⏰');
      _attemptReconnection();
    });
  }

  /// Perform hot reload aplikasi - DEPRECATED / DISABLED
  void _performHotReload() {
     print('⚠️ Hot Reload logic has been disabled to prevent data loss.');
     _attemptReconnection();
  }

  /// Add disconnect warning to Recent Status
  void _addDisconnectWarningToRecentStatus(Duration timeSinceLastData) {
    try {
      // 🔥 SAFETY CHECK: Check if FireAlarmData exists and is mounted
      if (_fireAlarmData != null && _fireAlarmData!.isMounted) {
        final message = '⚠️ ESP32 Disconnect: No data for ${timeSinceLastData.inSeconds}s';

        // 🔥 DATA VALIDATION: Validate message before insert
        if (message.isEmpty) {
          AppLogger.warning('Empty disconnect warning message', tag: _tag);
          return;
        }

        // Validate timestamp
        final timestamp = DateTime.now().toIso8601String();
        if (timestamp.isEmpty) {
          AppLogger.error('Failed to generate timestamp', tag: _tag);
          return;
        }

        // Double-check FireAlarmData still mounted (could change between checks)
        if (!_fireAlarmData!.isMounted) {
          AppLogger.warning('FireAlarmData disposed, skipping activity log insert', tag: _tag);
          return;
        }

        // Now safe to insert
        _fireAlarmData!.activityLogs.insert(0, {
          'timestamp': timestamp,
          'type': 'DISCONNECT_WARNING',
          'message': message,
          'severity': 'warning',
        });

        // 🔥 SAFETY CHECK: Final mounted check before notify
        if (_fireAlarmData!.isMounted) {
          (_fireAlarmData as ChangeNotifier).notifyListeners();
        }

        AppLogger.info('📝 Disconnect warning added to Recent Status', tag: _tag);
      } else {
        AppLogger.debug('Skipped disconnect warning - FireAlarmData null or disposed', tag: _tag);
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error adding disconnect warning',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Add reconnect message to Recent Status
  void _addReconnectMessageToRecentStatus() {
    try {
      // 🔥 SAFETY CHECK: Check if FireAlarmData exists and is mounted
      if (_fireAlarmData != null && _fireAlarmData!.isMounted) {
        final message = '✅ ESP32 Reconnected: Data flow restored';

        // 🔥 DATA VALIDATION: Validate message before insert
        if (message.isEmpty) {
          AppLogger.warning('Empty reconnect message', tag: _tag);
          return;
        }

        // Validate timestamp
        final timestamp = DateTime.now().toIso8601String();
        if (timestamp.isEmpty) {
          AppLogger.error('Failed to generate timestamp', tag: _tag);
          return;
        }

        // Double-check FireAlarmData still mounted
        if (!_fireAlarmData!.isMounted) {
          AppLogger.warning('FireAlarmData disposed, skipping activity log insert', tag: _tag);
          return;
        }

        // Now safe to insert
        _fireAlarmData!.activityLogs.insert(0, {
          'timestamp': timestamp,
          'type': 'RECONNECTED',
          'message': message,
          'severity': 'info',
        });

        // 🔥 SAFETY CHECK: Final mounted check before notify
        if (_fireAlarmData!.isMounted) {
          (_fireAlarmData as ChangeNotifier).notifyListeners();
        }

        AppLogger.info('📝 Reconnect message added to Recent Status', tag: _tag);
      } else {
        AppLogger.debug('Skipped reconnect message - FireAlarmData null or disposed', tag: _tag);
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error adding reconnect message',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Attempt reconnect di offline mode menggunakan IP yang tersimpan
  void _attemptOfflineModeReconnect() async {
    try {
      print('');
      print('============================================================');
      print('🔄🔄🔄 AUTO-RECONNECT METHOD CALLED 🔄🔄🔄');
      print('============================================================');

      // 🔥 DEBUG: Log semua config yang tersedia
      final esp32IP = _webSocketModeManager?.esp32IP ?? '';
      final isWebSocketMode = _webSocketModeManager?.isWebSocketMode ?? false;

      print('🔍 STEP 1: Cek IP dari WebSocketModeManager');
      print('   WebSocketMode: $isWebSocketMode');
      print('   ESP32 IP dari WebSocketModeManager: "$esp32IP"');
      print('   WebSocketManager: ${_webSocketModeManager?.webSocketManager != null ? "TERDAFTAR" : "NULL"}');
      print('============================================================');

      if (esp32IP.isEmpty) {
        print('❌❌❌ IP dari WebSocketModeManager KOSONG! ❌❌❌');
        print('');
        print('🔍 STEP 2: Mencoba FALLBACK ke SharedPreferences...');

        // 🔥 TRY FALLBACK: Coba ambil dari SharedPreferences langsung
        try {
          final prefs = await SharedPreferences.getInstance();

          // Log semua available IP di SharedPreferences
          final ip1 = prefs.getString('websocket_esp32_ip');
          final ip2 = prefs.getString('esp32_ip');
          final ip3 = prefs.getString('offline_ip');
          final ip4 = prefs.getString('last_connected_esp32_ip');

          print('   📦 Available IPs in SharedPreferences:');
          print('      websocket_esp32_ip: "$ip1"');
          print('      esp32_ip: "$ip2"');
          print('      offline_ip: "$ip3"');
          print('      last_connected_esp32_ip: "$ip4"');

          final fallbackIP = ip1 ?? ip2 ?? ip3 ?? ip4 ?? '';

          print('   🔧 FALLBACK IP yang dipakai: "$fallbackIP"');
          print('============================================================');

          if (fallbackIP.isNotEmpty) {
            print('✅ Menggunakan FALLBACK IP untuk reconnect');
            await _performReconnect(fallbackIP);
          } else {
            print('❌❌❌ FALLBACK juga gagal - TIDAK ADA IP di SharedPreferences! ❌❌❌');
            print('   Solusi: Anda harus connect ke ESP32 minimal 1x agar IP tersimpan');
          }
        } catch (e) {
          print('   ❌ EXCEPTION saat fallback: $e');
        }
        return;
      }

      print('✅ Menggunakan IP dari WebSocketModeManager: "$esp32IP"');
      await _performReconnect(esp32IP);

    } catch (e, stackTrace) {
      print('❌❌❌ EXCEPTION attempting offline mode reconnect ❌❌❌');
      print('   Error: $e');
      print('   StackTrace: $stackTrace');
    }
  }

  /// Perform reconnect ke IP tertentu
  Future<void> _performReconnect(String esp32IP) async {
    try {
      // 🔥 FIX: Gunakan FireAlarmWebSocketManager untuk reconnect
      final webSocketManager = _webSocketModeManager?.webSocketManager;

      if (webSocketManager != null) {
        // 🔥 FIX: JANGAN reset lastDataReceivedTime di sini!
        // Biarkan timer mendeteksi jika reconnect berhasil tapi tidak ada data
        // Time hanya di-reset saat ADA DATA yang masuk (via onDataReceived())
        print('📡 Memanggil webSocketManager.connectToESP32("$esp32IP")...');
        print('   ⚠️ NOT resetting lastDataReceivedTime - menunggu data masuk...');

        // Attempt reconnect menggunakan FireAlarmWebSocketManager
        // Method ini akan menghandle port yang benar secara otomatis
        final success = await webSocketManager.connectToESP32(esp32IP);

        print('');
        print('============================================================');
        if (success) {
          print('✅✅✅ WebSocket Connection SUCCESSFUL ke ESP32: $esp32IP ✅✅✅');
          print('   ⏳ Menunggu data dari ESP32 untuk konfirmasi reconnect...');
          print('   ℹ️ Jika tidak ada data dalam 30 detik, reconnect akan dicoba lagi');

          // 🔥 CRITICAL: JANGAN reset disconnect status atau lastDataReceivedTime di sini!
          // Biarkan onDataReceived() yang meng-reset saat ada data yang masuk
          // Ini mencegah infinite loop jika reconnect berhasil tapi tidak ada data

        } else {
          print('❌❌❌ WebSocket Connection FAILED ke ESP32: $esp32IP ❌❌❌');
          print('   Will retry on next disconnect check (setiap 5 detik)');

          // 🔥 TRY ALTERNATIVE: Gunakan WebSocketService langsung
          print('   🔧 TRYING ALTERNATIVE: Gunakan WebSocketService langsung...');
          await _tryAlternativeReconnect(esp32IP);
        }
        print('============================================================');
        print('');
      } else {
        print('❌❌❌ GAGAL RECONNECT - WebSocketManager is NULL! ❌❌❌');
        print('   _webSocketModeManager = $_webSocketModeManager');

        // 🔥 TRY ALTERNATIVE: Gunakan WebSocketService langsung
        print('   🔧 TRYING ALTERNATIVE: Gunakan WebSocketService langsung...');
        await _tryAlternativeReconnect(esp32IP);
      }

    } catch (e, stackTrace) {
      print('❌❌❌ EXCEPTION di _performReconnect ❌❌❌');
      print('   Error: $e');
      print('   StackTrace: $stackTrace');
    }
  }

  /// Try alternative reconnect menggunakan WebSocketService langsung
  Future<void> _tryAlternativeReconnect(String esp32IP) async {
    try {
      print('   🔧 ALTERNATIVE RECONNECT: Gunakan WebSocketService langsung...');

      if (_webSocketService == null) {
        print('   ❌ WebSocketService is NULL!');
        return;
      }

      // Disconnect dulu jika masih connected
      if (_webSocketService!.isConnected) {
        print('   🔧 Disconnecting existing connection...');
        await _webSocketService!.disconnect();
      }

      // Generate WebSocket URL
      final url = 'ws://$esp32IP:81';
      print('   🔧 Connecting to: $url');

      final success = await _webSocketService!.connectWithHealthCheck(url, autoReconnect: true);

      if (success) {
        print('   ✅ ALTERNATIVE RECONNECT SUCCESSFUL!');
        if (_isDisconnected) {
          _isDisconnected = false;
          _emitStatus(AutoRefreshStatus.connected);
          print('   🔄 Disconnect status CLEARED after alternative reconnect');
        }
      } else {
        print('   ❌ ALTERNATIVE RECONNECT juga FAILED');
      }

    } catch (e, stackTrace) {
      print('   ❌ EXCEPTION di alternative reconnect: $e');
    }
  }

  /// 🔥 PUBLIC: Call this method when WebSocket data is received
  /// Ini akan update last data received time dan prevent disconnect
  void onDataReceived() {
    final wasDisconnected = _isDisconnected;
    _lastDataReceivedTime = DateTime.now();

    // 🔥 CRITICAL FIX: Cancel hot reload timer when data arrives
    _hotReloadTimer?.cancel();
    _hotReloadTimer = null;

    // 🔥 NEW: Set flag bahwa data sudah diterima setelah restart
    _hasReceivedDataAfterRestart = true;

    // 🔥 DEBUG: Log setiap kali data diterima dengan timestamp
    final now = DateTime.now();
    final timeFormatted = '${now.hour}:${now.minute}:${now.second}';

    print('📡📡📡 WebSocket DATA RECEIVED at $timeFormatted - lastDataReceivedTime UPDATED 📡📡📡');

    // 🔥 CRITICAL: Jika sebelumnya disconnected, sekarang RECONNECTED BERHASIL
    if (wasDisconnected) {
      _isDisconnected = false;
      print('');
      print('============================================================');
      print('✅✅✅ RECONNECT SUCCESSFUL - DATA MENGALIR KEMBALI! ✅✅✅');
      print('   Disconnect status CLEARED setelah data diterima');
      print('============================================================');
      print('');

      // Emit connected status
      _emitStatus(AutoRefreshStatus.connected);
    }
  }

  /// Perform auto refresh
  void _performAutoRefresh() {
    try {
      // Silent auto refresh - no need to log every refresh event

      // Emit refresh event
      _refreshController.add(DateTime.now());

      // Trigger data update in FireAlarmData
      if (_fireAlarmData != null) {
        _refreshFireAlarmData();
      }

      _lastSuccessfulUpdate = DateTime.now();
      _emitStatus(AutoRefreshStatus.refreshed);

    } catch (e, stackTrace) {
      AppLogger.error(
        'Error during auto refresh',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );

      _emitStatus(AutoRefreshStatus.error);
    }
  }

  /// Refresh FireAlarmData
  void _refreshFireAlarmData() {
    try {
      // Invalidate cache to force fresh data
      if (_fireAlarmData != null) {
        // Call notifyListeners to trigger UI update
        // This will force the UI to refresh with current data
        if (_fireAlarmData is ChangeNotifier) {
          (_fireAlarmData as ChangeNotifier).notifyListeners();
        }

        AppLogger.debug('FireAlarmData refreshed', tag: _tag);
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error refreshing FireAlarmData',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Handle WebSocket mode changes
  void _onWebSocketModeChanged() {
    AppLogger.info('WebSocket mode changed, restarting connection monitoring', tag: _tag);

    // Restart connection monitoring
    _startConnectionMonitoring();

    // Restart auto refresh with appropriate interval
    if (_isAutoRefreshEnabled) {
      startAutoRefresh();
    }
  }

  /// Handle WebSocket status changes
  void _onWebSocketStatusChanged(WebSocketStatus status) {
    AppLogger.info('🔄 WebSocket status changed: $status', tag: _tag);

    // 🔥 CRITICAL FIX: Reset disconnect detection when WebSocket RECONNECTS
    if (status == WebSocketStatus.connected) {
      final wasDisconnected = _isDisconnected;

      // Reset disconnect state and timer when WebSocket reconnects
      _isDisconnected = false;
      _lastDataReceivedTime = DateTime.now(); // Reset timer to NOW
      _hotReloadTimer?.cancel(); // Cancel any pending hot reload
      _hotReloadTimer = null;

      AppLogger.info('✅ WebSocket CONNECTED - Disconnect timer RESET', tag: _tag);
      _emitStatus(AutoRefreshStatus.connected);
    }
    // Connection status will be checked in the next cycle for other statuses
    // This ensures we have the most up-to-date status
  }

  /// Emit status change
  void _emitStatus(AutoRefreshStatus status) {
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  /// Force manual refresh
  void forceRefresh() {
    AppLogger.info('Force refresh triggered', tag: _tag);
    _performAutoRefresh();
  }

  /// Reset retry attempts
  void resetRetries() {
    _retryAttempts = 0;
    _retryTimer?.cancel();
    _retryTimer = null;

    AppLogger.info('Retry attempts reset', tag: _tag);
  }

  /// Get service diagnostics
  Map<String, dynamic> getDiagnostics() {
    return {
      'isAutoRefreshEnabled': _isAutoRefreshEnabled,
      'isConnectionLost': _isConnectionLost,
      'retryAttempts': _retryAttempts,
      'maxRetryAttempts': _maxRetryAttempts,
      'lastSuccessfulUpdate': _lastSuccessfulUpdate?.toIso8601String(),
      'lastConnectionCheck': _lastConnectionCheck?.toIso8601String(),
      'refreshInterval': _refreshInterval.inSeconds,
      'connectionCheckInterval': _connectionCheckInterval.inSeconds,
      'retryDelay': _retryDelay.inSeconds,
      'isTimerActive': _refreshTimer?.isActive ?? false,
      'isConnectionCheckActive': _connectionCheckTimer?.isActive ?? false,
      'isRetryTimerActive': _retryTimer?.isActive ?? false,
    };
  }

  /// 🔥 NEW: Reset service state (digunakan setelah hot restart)
  void reset() {
    print('');
    print('============================================================');
    print('🔄🔄🔄 RESETTING AUTO REFRESH SERVICE 🔄🔄🔄');
    print('============================================================');

    // Cancel semua timer
    _refreshTimer?.cancel();
    _connectionCheckTimer?.cancel();
    _retryTimer?.cancel();
    _disconnectCheckTimer?.cancel();
    _hotReloadTimer?.cancel();

    // Reset state variables (TAPI JANGAN reset lastDataReceivedTime)
    _isDisconnected = false;
    // _lastDataReceivedTime TIDAK di-reset - pertahankan untuk disconnect detection pasca-restart
    _isConnectionLost = false;
    _retryAttempts = 0;
    _lastSuccessfulUpdate = null;
    _lastConnectionCheck = null;
    _lastRestartTime = DateTime.now(); // Catat waktu restart
    _hasReceivedDataAfterRestart = false; // 🔥 NEW: Track apakah sudah ada data setelah restart

    print('   ✅ State reset completed');
    print('   ✅ Timers cancelled');
    print('   ✅ isDisconnected reset to false');
    print('   ✅ hasReceivedDataAfterRestart reset to false');
    print('   ✅ lastRestartTime set to now');
    print('   ⚠️ lastDataReceivedTime PRESERVED (${_lastDataReceivedTime != null ? "EXISTING data preserved" : "null - first run"})');
    print('   🛡️ Grace period: ${_postRestartGracePeriod.inSeconds} seconds');
    print('============================================================');
    print('');

    // Restart disconnect detection
    _startDisconnectDetection();
    print('✅ Disconnect detection restarted after reset');
  }

  /// Dispose resources
  void dispose() {
    AppLogger.info('Disposing Auto Refresh Service', tag: _tag);

    _refreshTimer?.cancel();
    _connectionCheckTimer?.cancel();
    _retryTimer?.cancel();
    _disconnectCheckTimer?.cancel(); // 🔥 NEW: Cancel disconnect check timer
    _hotReloadTimer?.cancel(); // 🔥 NEW: Cancel hot reload timer
    _webSocketStatusSubscription?.cancel(); // 🔥 FIX: Cancel status subscription

    _statusController.close();
    _refreshController.close();
    _hotReloadTriggerController.close(); // 🔥 NEW: Close hot reload controller

    _webSocketModeManager?.removeListener(_onWebSocketModeChanged);
  }
}

/// Auto refresh status enum
enum AutoRefreshStatus {
  stopped,
  active,
  connectionLost,
  connected,
  disconnected, // 🔥 NEW: ESP32 disconnect status untuk offline mode
  refreshed,
  error,
  maxRetriesReached,
}