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

  /// Max consecutive empty/invalid data before reconnect
  static const int maxConsecutiveEmptyData = 5;

  /// Max consecutive ping timeouts before reconnect (to avoid false positive)
  static const int maxConsecutivePingTimeouts = 3;
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

  /// Last valid data reception timestamp
  DateTime? _lastValidDataTime;

  /// Consecutive empty/invalid data counter
  int _consecutiveEmptyDataCount = 0;

  /// Consecutive ping timeout counter
  int _consecutivePingTimeouts = 0;

  /// Flag to prevent multiple reconnect attempts
  bool _isReconnectScheduled = false;

  /// Controller for status updates (UI can listen to this)
  final _statusController = StreamController<AutoReconnectStatus>.broadcast();
  Stream<AutoReconnectStatus> get statusStream => _statusController.stream;

  /// Controller for retry countdown (UI can show "Reconnecting in Xs...")
  final _countdownController = StreamController<int>.broadcast();
  Stream<int> get countdownStream => _countdownController.stream;

  /// Controller for data validation issues (UI can show warnings)
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

    AppLogger.info('Starting auto-reconnect monitoring', tag: 'AUTO_RECONNECT');

    _webSocketManager = webSocketManager;
    _esp32IP = esp32IP;
    _isMonitoring = true;
    _retryCount = 0;
    _isReconnectScheduled = false;
    _consecutiveEmptyDataCount = 0;
    _consecutivePingTimeouts = 0;
    _lastValidDataTime = DateTime.now();

    // Listen to WebSocket status changes ONLY
    _setupStatusListener();

    // Listen to WebSocket messages (for pong response & data validation)
    _setupMessageListener();

    // Start health check
    _startHealthCheck();

    _updateStatus(AutoReconnectStatus.connected);
  }

  /// Stop monitoring
  void stopMonitoring() {
    if (!_isMonitoring) return;

    AppLogger.info('Stopping auto-reconnect monitoring', tag: 'AUTO_RECONNECT');

    _isMonitoring = false;
    _isReconnectScheduled = false;

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
    _consecutiveEmptyDataCount = 0;
    _consecutivePingTimeouts = 0;
    _lastValidDataTime = null;

    _updateStatus(AutoReconnectStatus.idle);
  }

  /// Force manual reconnect (reset retry counter)
  Future<bool> forceReconnect() async {
    AppLogger.info('Manual reconnect requested', tag: 'AUTO_RECONNECT');

    // Reset retry counter
    _retryCount = 0;
    _isReconnectScheduled = false;

    // Cancel any pending retry
    _retryTimer?.cancel();
    _retryTimer = null;

    // Schedule immediate reconnect
    return await _scheduleReconnect(immediate: true);
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
      AppLogger.debug('WebSocket status: $status', tag: 'AUTO_RECONNECT');

      if (status == WebSocketStatus.disconnected) {
        // Connection lost, trigger reconnect
        if (_isMonitoring && !_isReconnectScheduled) {
          AppLogger.warning('Connection lost! Triggering reconnect...', tag: 'AUTO_RECONNECT');
          _scheduleReconnect();
        }
      } else if (status == WebSocketStatus.connected) {
        // Connected successfully
        AppLogger.info('WebSocket connected event received', tag: 'AUTO_RECONNECT');

        if (_isReconnecting) {
          _onReconnectSuccess();
        } else {
          _updateStatus(AutoReconnectStatus.connected);
        }
      }
    });

    AppLogger.info('WebSocket status listener setup complete', tag: 'AUTO_RECONNECT');
  }

  /// Setup WebSocket message listener (for pong response & data validation)
  void _setupMessageListener() {
    if (_webSocketManager == null) return;

    _messageSubscription = _webSocketManager!.webSocketService.messageStream.listen((message) {
      // Check for pong response (case-insensitive)
      final lowerCaseData = message.data.toLowerCase();
      if (lowerCaseData.contains('pong') || lowerCaseData.contains('ping')) {
        AppLogger.debug('Pong received: ${message.data}', tag: 'AUTO_RECONNECT');
        _lastPingTime = null; // Reset ping timeout
        _consecutivePingTimeouts = 0; // Reset consecutive timeout counter
        return;
      }

      // Validate incoming data (detect empty/invalid data)
      _validateIncomingData(message.data);
    });

    AppLogger.info('WebSocket message listener setup complete with data validation', tag: 'AUTO_RECONNECT');
  }

  /// Validate incoming data to detect empty/invalid data
  void _validateIncomingData(String data) {
    // Skip validation jika sedang reconnecting
    if (_isReconnecting) return;

    final trimmedData = data.trim();

    // 1. Check jika data kosong atau hanya whitespace
    if (trimmedData.isEmpty) {
      _consecutiveEmptyDataCount++;

      AppLogger.warning(
        'Empty data received (count: $_consecutiveEmptyDataCount/$AutoReconnectConfig.maxConsecutiveEmptyData)',
        tag: 'DATA_VALIDATION',
      );

      // Notify UI
      _dataValidationController.add('Empty data received ($_consecutiveEmptyDataCount/$AutoReconnectConfig.maxConsecutiveEmptyData)');

      // Trigger reconnect jika terlalu banyak empty data berturut-turut
      if (_consecutiveEmptyDataCount >= AutoReconnectConfig.maxConsecutiveEmptyData) {
        AppLogger.error(
          'Too many consecutive empty data ($_consecutiveEmptyDataCount). Triggering reconnect.',
          tag: 'DATA_VALIDATION',
        );

        // Notify UI about critical issue
        _dataValidationController.add('CRITICAL: Host not sending data! Reconnecting...');

        // Trigger reconnect via status stream (disconnect first)
        // This will be caught by status listener
      }
      return;
    }

    // 2. Check jika data adalah JSON kosong {} atau []
    if (trimmedData == '{}' || trimmedData == '[]' || trimmedData == '\"\"') {
      _consecutiveEmptyDataCount++;

      AppLogger.warning(
        'Empty JSON received: "$trimmedData" (count: $_consecutiveEmptyDataCount/$AutoReconnectConfig.maxConsecutiveEmptyData)',
        tag: 'DATA_VALIDATION',
      );

      _dataValidationController.add('Empty JSON: $trimmedData ($_consecutiveEmptyDataCount/$AutoReconnectConfig.maxConsecutiveEmptyData)');

      if (_consecutiveEmptyDataCount >= AutoReconnectConfig.maxConsecutiveEmptyData) {
        AppLogger.error(
          'Too many consecutive empty JSON ($_consecutiveEmptyDataCount). Triggering reconnect.',
          tag: 'DATA_VALIDATION',
        );

        _dataValidationController.add('CRITICAL: Host sending empty JSON! Reconnecting...');
      }
      return;
    }

    // 3. Data valid! Reset counter dan update timestamp
    _consecutiveEmptyDataCount = 0;
    _lastValidDataTime = DateTime.now();

    AppLogger.debug(
      'Valid data received (${trimmedData.length} chars)',
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

    AppLogger.info('Health check started (interval: ${AutoReconnectConfig.healthCheckInterval.inSeconds}s)', tag: 'AUTO_RECONNECT');
  }

  /// Send ping to ESP32
  void _sendPing() {
    // Skip ping jika sedang reconnecting
    if (_webSocketManager == null || _isReconnecting) return;

    AppLogger.debug('Sending ping...', tag: 'AUTO_RECONNECT');

    // Store ping timestamp
    _lastPingTime = DateTime.now();

    // Send ping message
    try {
      _webSocketManager!.webSocketService.sendMessage('{"type":"ping"}');

      // Check for timeout - HANYA jika tidak sedang reconnecting
      Future.delayed(AutoReconnectConfig.pingTimeout, () {
        // Check jika masih monitoring, ping masih pending (belum di-reset oleh pong), dan tidak sedang reconnecting
        if (_lastPingTime != null && _isMonitoring && !_isReconnecting) {
          // Ping timeout detected
          _consecutivePingTimeouts++;

          AppLogger.warning(
            'Ping timeout detected ($_consecutivePingTimeouts/${AutoReconnectConfig.maxConsecutivePingTimeouts}). No pong response received.',
            tag: 'AUTO_RECONNECT',
          );

          // Only trigger reconnect jika multiple timeouts berturut-turut (to avoid false positive)
          if (_consecutivePingTimeouts >= AutoReconnectConfig.maxConsecutivePingTimeouts) {
            AppLogger.error(
              'Too many consecutive ping timeouts ($_consecutivePingTimeouts). Connection might be dead. Triggering reconnect.',
              tag: 'AUTO_RECONNECT',
            );

            // Trigger reconnect by disconnecting first
            // This will trigger status listener which will call _scheduleReconnect
            _webSocketManager?.webSocketService.disconnect();
          }
        }
      });
    } catch (e) {
      AppLogger.error('Failed to send ping: $e', tag: 'AUTO_RECONNECT');
      _lastPingTime = null;
    }
  }

  /// Schedule reconnect with exponential backoff
  Future<bool> _scheduleReconnect({bool immediate = false}) async {
    // Prevent double scheduling
    if (_isReconnectScheduled) {
      AppLogger.warning('Reconnect already scheduled, skipping', tag: 'AUTO_RECONNECT');
      return false;
    }

    // Check max retry
    if (_retryCount >= AutoReconnectConfig.maxRetry) {
      AppLogger.error('Max retry reached (${AutoReconnectConfig.maxRetry}). Stopping auto-reconnect.', tag: 'AUTO_RECONNECT');
      _updateStatus(AutoReconnectStatus.failed);
      _isReconnectScheduled = false;
      return false;
    }

    _isReconnectScheduled = true;
    _updateStatus(AutoReconnectStatus.waiting);

    // Calculate delay
    final delay = immediate ? Duration.zero : _getRetryDelay();
    final delaySeconds = delay.inSeconds;

    if (!immediate) {
      AppLogger.info('Scheduling retry in ${delaySeconds}s (attempt ${_retryCount + 1}/${AutoReconnectConfig.maxRetry})', tag: 'AUTO_RECONNECT');

      // Countdown for UI
      if (delaySeconds > 0) {
        int countdown = delaySeconds;
        _countdownController.add(countdown);

        final countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          countdown--;
          _countdownController.add(countdown);

          if (countdown <= 0) {
            timer.cancel();
          }
        });

        // Store countdown timer to cancel it when reconnect starts
        _retryTimer = countdownTimer;
      }
    }

    // Schedule reconnect
    _retryTimer = Timer(delay, () async {
      _isReconnectScheduled = false;
      await _attemptReconnect();
    });

    return true;
  }

  /// Get retry delay based on retry count (exponential backoff)
  Duration _getRetryDelay() {
    final index = _retryCount.clamp(0, AutoReconnectConfig.retryDelays.length - 1);
    return AutoReconnectConfig.retryDelays[index];
  }

  /// Attempt reconnect to ESP32
  Future<bool> _attemptReconnect() async {
    if (_webSocketManager == null || _esp32IP == null) {
      AppLogger.error('WebSocket manager or ESP32 IP is null', tag: 'AUTO_RECONNECT');
      return false;
    }

    AppLogger.info('Attempting to reconnect to $_esp32IP... (attempt ${_retryCount + 1}/${AutoReconnectConfig.maxRetry})', tag: 'AUTO_RECONNECT');
    _updateStatus(AutoReconnectStatus.reconnecting);
    _isReconnecting = true;

    try {
      // Attempt connection
      final success = await _webSocketManager!.connectToESP32(_esp32IP!);

      if (success) {
        // DO NOT reset state here! Let status listener handle it
        // Status listener will call _onReconnectSuccess when it receives connected event
        AppLogger.info('Reconnect initiated, waiting for status listener confirmation...', tag: 'AUTO_RECONNECT');

        // Wait for status listener to confirm (with timeout)
        await Future.delayed(const Duration(seconds: 3));

        if (_isReconnecting) {
          // Status listener didn't confirm, assume success anyway
          AppLogger.warning('Status listener timeout, assuming success', tag: 'AUTO_RECONNECT');
          _onReconnectSuccess();
        }

        return success;
      } else {
        // Failed
        AppLogger.warning('Reconnect attempt failed (success=false)', tag: 'AUTO_RECONNECT');
        _onReconnectFailed();
        return false;
      }
    } catch (e) {
      AppLogger.error('Reconnect error: $e', tag: 'AUTO_RECONNECT');
      _onReconnectFailed();
      return false;
    }
  }

  /// Handle reconnect success
  void _onReconnectSuccess() {
    if (!_isReconnecting) return; // Already handled

    AppLogger.info('Reconnect successful!', tag: 'AUTO_RECONNECT');

    // Reset state
    _retryCount = 0;
    _isReconnecting = false;
    _isReconnectScheduled = false;

    // Reset data validation counters
    _consecutiveEmptyDataCount = 0;
    _consecutivePingTimeouts = 0;
    _lastValidDataTime = DateTime.now();

    AppLogger.info('Data validation counters reset', tag: 'AUTO_RECONNECT');

    _updateStatus(AutoReconnectStatus.connected);

    // Notify UI
    _dataValidationController.add('Reconnected successfully!');
  }

  /// Handle reconnect failed
  void _onReconnectFailed() {
    AppLogger.warning('Reconnect failed', tag: 'AUTO_RECONNECT');

    _isReconnecting = false;
    _isReconnectScheduled = false;
    _retryCount++;

    // Schedule next retry
    _scheduleReconnect();
  }

  /// Update reconnect status
  void _updateStatus(AutoReconnectStatus status) {
    if (_currentStatus != status) {
      _currentStatus = status;
      _statusController.add(status);
      AppLogger.debug('Status updated: $status', tag: 'AUTO_RECONNECT');
    }
  }

  // ==================== DISPOSE ====================
  void dispose() {
    AppLogger.info('Disposing auto-reconnect service', tag: 'AUTO_RECONNECT');

    stopMonitoring();

    _statusController.close();
    _countdownController.close();
    _dataValidationController.close();
  }
}
