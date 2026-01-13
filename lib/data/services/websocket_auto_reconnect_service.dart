import 'dart:async';
import 'package:flutter/foundation.dart';
import '../datasources/websocket/websocket_service.dart';
import '../datasources/websocket/fire_alarm_websocket_manager.dart';
import 'logger.dart';

/// Auto-reconnect configuration
class AutoReconnectConfig {
  /// Maximum retry attempts before giving up
  static const int maxRetry = 10;

  /// Retry delays with exponential backoff
  static const List<Duration> retryDelays = [
    Duration.zero,           // Immediate retry
    Duration(seconds: 2),    // Wait 2s
    Duration(seconds: 5),    // Wait 5s
    Duration(seconds: 10),   // Wait 10s
    Duration(seconds: 30),   // Max delay 30s
  ];

  /// Health check interval (ping/pong)
  static const Duration healthCheckInterval = Duration(seconds: 30);

  /// Ping timeout
  static const Duration pingTimeout = Duration(seconds: 5);

  /// ⭐ NEW: Max consecutive empty/invalid data before reconnect
  static const int maxConsecutiveEmptyData = 5;
}

/// Auto-reconnect status for UI
enum AutoReconnectStatus {
  /// Not monitoring
  idle,
  /// Currently reconnecting
  reconnecting,
  /// Connection failed, waiting to retry
  waiting,
  /// Max retry reached, stopped
  failed,
  /// Successfully connected
  connected,
}

/// WebSocket Auto-Reconnect Service
///
/// Handles automatic reconnection with exponential backoff,
/// health check (ping/pong), and user notifications.
class WebSocketAutoReconnectService {
  // ==================== SINGLETON ====================
  WebSocketAutoReconnectService._internal();
  static final WebSocketAutoReconnectService _instance = WebSocketAutoReconnectService._internal();
  static WebSocketAutoReconnectService get instance => _instance;

  // ==================== STATE ====================
  /// Current retry count
  int _retryCount = 0;

  /// Is monitoring active?
  bool _isMonitoring = false;

  /// Is currently reconnecting?
  bool _isReconnecting = false;

  /// Timer for retry delay
  Timer? _retryTimer;

  /// Timer for health check (ping/pong)
  Timer? _healthCheckTimer;

  /// Subscription to WebSocket status stream
  StreamSubscription<WebSocketStatus>? _statusSubscription;

  /// Subscription to WebSocket message stream (for pong response)
  StreamSubscription<WebSocketMessage>? _messageSubscription;

  /// Last ping timestamp (for timeout detection)
  DateTime? _lastPingTime;

  /// ⭐ NEW: Last valid data reception timestamp
  DateTime? _lastValidDataTime;

  /// ⭐ NEW: Consecutive empty/invalid data counter
  int _consecutiveEmptyDataCount = 0;

  /// Controller for status updates (UI can listen to this)
  final _statusController = StreamController<AutoReconnectStatus>.broadcast();
  Stream<AutoReconnectStatus> get statusStream => _statusController.stream;

  /// Controller for retry countdown (UI can show "Reconnecting in Xs...")
  final _countdownController = StreamController<int>.broadcast();
  Stream<int> get countdownStream => _countdownController.stream;

  /// ⭐ NEW: Controller for data validation issues (UI can show warnings)
  final _dataValidationController = StreamController<String>.broadcast();
  Stream<String> get dataValidationStream => _dataValidationController.stream;

  /// Current reconnect status
  AutoReconnectStatus _currentStatus = AutoReconnectStatus.idle;
  AutoReconnectStatus get currentStatus => _currentStatus;

  /// WebSocket manager reference
  FireAlarmWebSocketManager? _webSocketManager;

  /// Stored ESP32 IP for reconnect
  String? _esp32IP;

  // ==================== PUBLIC METHODS ====================

  /// Start monitoring WebSocket connection
  void startMonitoring({
    required FireAlarmWebSocketManager webSocketManager,
    required String esp32IP,
  }) {
    if (_isMonitoring) {
      AppLogger.warning('Auto-reconnect already monitoring', tag: 'AUTO_RECONNECT');
      return;
    }

    AppLogger.info('🚀 Starting auto-reconnect monitoring', tag: 'AUTO_RECONNECT');

    _webSocketManager = webSocketManager;
    _esp32IP = esp32IP;
    _isMonitoring = true;
    _retryCount = 0;

    // Listen to WebSocket status changes
    _setupStatusListener();

    // Listen to WebSocket messages (for pong response)
    _setupMessageListener();

    // Start health check
    _startHealthCheck();

    _updateStatus(AutoReconnectStatus.connected);
  }

  /// Stop monitoring
  void stopMonitoring() {
    if (!_isMonitoring) return;

    AppLogger.info('🛑 Stopping auto-reconnect monitoring', tag: 'AUTO_RECONNECT');

    _isMonitoring = false;

    // Cancel all timers
    _retryTimer?.cancel();
    _retryTimer = null;
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;

    // Cancel subscriptions
    _statusSubscription?.cancel();
    _statusSubscription = null;
    _messageSubscription?.cancel();
    _messageSubscription = null;

    // Reset state
    _retryCount = 0;
    _isReconnecting = false;

    // ⭐ NEW: Reset data validation counters
    _consecutiveEmptyDataCount = 0;
    _lastValidDataTime = null;

    _updateStatus(AutoReconnectStatus.idle);
  }

  /// Force manual reconnect (reset retry counter)
  Future<bool> forceReconnect() async {
    AppLogger.info('🔄 Manual reconnect requested', tag: 'AUTO_RECONNECT');

    // Reset retry counter
    _retryCount = 0;

    // Cancel any pending retry
    _retryTimer?.cancel();
    _retryTimer = null;

    // Attempt reconnect immediately
    return await _attemptReconnect();
  }

  /// Get current retry status for UI
  Map<String, dynamic> getRetryStatus() {
    return {
      'retryCount': _retryCount,
      'maxRetry': AutoReconnectConfig.maxRetry,
      'status': _currentStatus.toString(),
      'isMonitoring': _isMonitoring,
      'isReconnecting': _isReconnecting,
    };
  }

  // ==================== PRIVATE METHODS ====================

  /// Setup WebSocket status listener
  void _setupStatusListener() {
    if (_webSocketManager == null) return;

    _statusSubscription = _webSocketManager!.webSocketService.statusStream.listen((status) {
      AppLogger.debug('📡 WebSocket status: $status', tag: 'AUTO_RECONNECT');

      if (status == WebSocketStatus.disconnected) {
        // Connection lost, trigger reconnect
        if (_isMonitoring && !_isReconnecting) {
          AppLogger.warning('🔌 Connection lost! Triggering reconnect...', tag: 'AUTO_RECONNECT');
          _scheduleRetry();
        }
      } else if (status == WebSocketStatus.connected) {
        // Connected successfully
        if (_isReconnecting) {
          _onReconnectSuccess();
        } else {
          _updateStatus(AutoReconnectStatus.connected);
        }
      }
    });

    AppLogger.info('✅ WebSocket status listener setup complete', tag: 'AUTO_RECONNECT');
  }

  /// Setup WebSocket message listener (for pong response & data validation)
  void _setupMessageListener() {
    if (_webSocketManager == null) return;

    _messageSubscription = _webSocketManager!.webSocketService.messageStream.listen((message) {
      // Check for pong response
      if (message.data.contains('pong') || message.data.contains('PONG')) {
        AppLogger.debug('🏓 Pong received', tag: 'AUTO_RECONNECT');
        _lastPingTime = null; // Reset ping timeout
        return;
      }

      // ⭐ NEW: Validate incoming data (detect empty/invalid data)
      _validateIncomingData(message.data);
    });

    AppLogger.info('✅ WebSocket message listener setup complete with data validation', tag: 'AUTO_RECONNECT');
  }

  /// ⭐ NEW: Validate incoming data to detect empty/invalid data
  void _validateIncomingData(String data) {
    // Skip validation jika sedang reconnecting
    if (_isReconnecting) return;

    final trimmedData = data.trim();

    // 1. Check jika data kosong atau hanya whitespace
    if (trimmedData.isEmpty) {
      _consecutiveEmptyDataCount++;

      AppLogger.warning(
        '⚠️ Empty data received (count: $_consecutiveEmptyDataCount/$AutoReconnectConfig.maxConsecutiveEmptyData)',
        tag: 'DATA_VALIDATION',
      );

      // Notify UI
      _dataValidationController.add('Empty data received ($_consecutiveEmptyDataCount/$AutoReconnectConfig.maxConsecutiveEmptyData)');

      // Trigger reconnect jika terlalu banyak empty data berturut-turut
      if (_consecutiveEmptyDataCount >= AutoReconnectConfig.maxConsecutiveEmptyData) {
        AppLogger.error(
          '❌ Too many consecutive empty data ($_consecutiveEmptyDataCount). ESP32 might be dead!',
          tag: 'DATA_VALIDATION',
        );

        // Notify UI about critical issue
        _dataValidationController.add('CRITICAL: ESP32 not sending data! Reconnecting...');

        // Trigger reconnect
        if (!_isReconnecting) {
          _scheduleRetry();
        }
      }
      return;
    }

    // 2. Check jika data adalah JSON kosong {} atau []
    if (trimmedData == '{}' || trimmedData == '[]' || trimmedData == '""') {
      _consecutiveEmptyDataCount++;

      AppLogger.warning(
        '⚠️ Empty JSON received: "$trimmedData" (count: $_consecutiveEmptyDataCount/$AutoReconnectConfig.maxConsecutiveEmptyData)',
        tag: 'DATA_VALIDATION',
      );

      _dataValidationController.add('Empty JSON: $trimmedData ($_consecutiveEmptyDataCount/$AutoReconnectConfig.maxConsecutiveEmptyData)');

      if (_consecutiveEmptyDataCount >= AutoReconnectConfig.maxConsecutiveEmptyData) {
        AppLogger.error(
          '❌ Too many consecutive empty JSON ($_consecutiveEmptyDataCount). ESP32 might be dead!',
          tag: 'DATA_VALIDATION',
        );

        _dataValidationController.add('CRITICAL: ESP32 sending empty JSON! Reconnecting...');

        if (!_isReconnecting) {
          _scheduleRetry();
        }
      }
      return;
    }

    // 3. Data valid! Reset counter dan update timestamp
    _consecutiveEmptyDataCount = 0;
    _lastValidDataTime = DateTime.now();

    AppLogger.debug(
      '✅ Valid data received (${trimmedData.length} chars)',
      tag: 'DATA_VALIDATION',
    );
  }

  /// Start health check (ping/pong)
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();

    _healthCheckTimer = Timer.periodic(AutoReconnectConfig.healthCheckInterval, (_) {
      if (_isMonitoring && _currentStatus == AutoReconnectStatus.connected) {
        _sendPing();
      }
    });

    AppLogger.info('✅ Health check started (interval: ${AutoReconnectConfig.healthCheckInterval.inSeconds}s)', tag: 'AUTO_RECONNECT');
  }

  /// Send ping to ESP32
  void _sendPing() {
    if (_webSocketManager == null) return;

    AppLogger.debug('🏓 Sending ping...', tag: 'AUTO_RECONNECT');

    // Store ping timestamp
    _lastPingTime = DateTime.now();

    // Send ping message
    try {
      _webSocketManager!.webSocketService.sendMessage('{"type":"ping"}');

      // Check for timeout
      Future.delayed(AutoReconnectConfig.pingTimeout, () {
        if (_lastPingTime != null && _isMonitoring) {
          // Ping timeout - connection might be dead
          AppLogger.warning('⏰ Ping timeout! Connection might be dead.', tag: 'AUTO_RECONNECT');

          // Trigger reconnect
          if (!_isReconnecting) {
            _scheduleRetry();
          }
        }
      });
    } catch (e) {
      AppLogger.error('❌ Failed to send ping: $e', tag: 'AUTO_RECONNECT');
      _lastPingTime = null;
    }
  }

  /// Schedule retry with exponential backoff
  void _scheduleRetry() {
    // Check max retry
    if (_retryCount >= AutoReconnectConfig.maxRetry) {
      AppLogger.error('❌ Max retry reached (${AutoReconnectConfig.maxRetry}). Stopping auto-reconnect.', tag: 'AUTO_RECONNECT');
      _updateStatus(AutoReconnectStatus.failed);
      return;
    }

    // Calculate delay
    final delay = _getRetryDelay();
    final delaySeconds = delay.inSeconds;

    AppLogger.info('⏰ Scheduling retry in ${delaySeconds}s (attempt ${_retryCount + 1}/${AutoReconnectConfig.maxRetry})', tag: 'AUTO_RECONNECT');

    _updateStatus(AutoReconnectStatus.waiting);

    // Countdown for UI
    if (delaySeconds > 0) {
      int countdown = delaySeconds;
      _countdownController.add(countdown);

      _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        countdown--;
        _countdownController.add(countdown);

        if (countdown <= 0) {
          timer.cancel();
        }
      });
    }

    // Schedule reconnect
    _retryTimer = Timer(delay, () async {
      await _attemptReconnect();
    });
  }

  /// Get retry delay based on retry count (exponential backoff)
  Duration _getRetryDelay() {
    final index = _retryCount.clamp(0, AutoReconnectConfig.retryDelays.length - 1);
    return AutoReconnectConfig.retryDelays[index];
  }

  /// Attempt reconnect to ESP32
  Future<bool> _attemptReconnect() async {
    if (_webSocketManager == null || _esp32IP == null) {
      AppLogger.error('❌ WebSocket manager or ESP32 IP is null', tag: 'AUTO_RECONNECT');
      return false;
    }

    AppLogger.info('🔄 Attempting to reconnect to $_esp32IP...', tag: 'AUTO_RECONNECT');
    _updateStatus(AutoReconnectStatus.reconnecting);
    _isReconnecting = true;

    try {
      // Attempt connection
      final success = await _webSocketManager!.connectToESP32(_esp32IP!);

      if (success) {
        // Success (will be confirmed by status listener)
        AppLogger.info('✅ Reconnect attempt successful', tag: 'AUTO_RECONNECT');
        return true;
      } else {
        // Failed
        _onReconnectFailed();
        return false;
      }
    } catch (e) {
      AppLogger.error('❌ Reconnect error: $e', tag: 'AUTO_RECONNECT');
      _onReconnectFailed();
      return false;
    }
  }

  /// Handle reconnect success
  void _onReconnectSuccess() {
    AppLogger.info('✅ Reconnect successful!', tag: 'AUTO_RECONNECT');

    // Reset state
    _retryCount = 0;
    _isReconnecting = false;
    _retryTimer?.cancel();
    _retryTimer = null;

    // ⭐ NEW: Reset data validation counters
    _consecutiveEmptyDataCount = 0;
    _lastValidDataTime = DateTime.now();

    AppLogger.info('✅ Data validation counters reset', tag: 'AUTO_RECONNECT');

    _updateStatus(AutoReconnectStatus.connected);

    // Notify UI
    _dataValidationController.add('Reconnected successfully!');
  }

  /// Handle reconnect failed
  void _onReconnectFailed() {
    AppLogger.warning('⚠️ Reconnect failed', tag: 'AUTO_RECONNECT');

    _isReconnecting = false;
    _retryCount++;

    // Schedule next retry
    _scheduleRetry();
  }

  /// Update reconnect status
  void _updateStatus(AutoReconnectStatus status) {
    if (_currentStatus != status) {
      _currentStatus = status;
      _statusController.add(status);
      AppLogger.debug('📊 Status updated: $status', tag: 'AUTO_RECONNECT');
    }
  }

  // ==================== DISPOSE ====================
  void dispose() {
    AppLogger.info('🗑️ Disposing auto-reconnect service', tag: 'AUTO_RECONNECT');

    stopMonitoring();

    _statusController.close();
    _countdownController.close();
    _dataValidationController.close(); // ⭐ NEW: Close data validation controller
  }
}
