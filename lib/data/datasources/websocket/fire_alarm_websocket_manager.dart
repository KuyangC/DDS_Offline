import 'dart:async';
import 'package:flutter/material.dart';
import 'websocket_service.dart';
import '../../services/logger.dart';
import '../../services/unified_ip_service.dart';
import '../../../presentation/providers/fire_alarm_data_provider.dart';
import '../../../core/config/dependency_injection.dart';
import '../../services/auto_refresh_service.dart';

/// WebSocket Manager untuk FireAlarmData
///
/// Menangani koneksi WebSocket ke ESP32 tanpa mengubah FireAlarmData class.
/// Bertanggung jawab atas:asdasd
/// - Membuat dan memutus koneksi WebSocket
/// - Memproses pesan dari ESP32
/// - Mengatur status koneksi di FireAlarmData
/// - Mengelola auto-reconnect
class FireAlarmWebSocketManager extends ChangeNotifier {
  // Dependencies
  final FireAlarmData _fireAlarmData;
  final WebSocketService _webSocketService = WebSocketService();

  // Stream subscriptionsww
  StreamSubscription<WebSocketMessage>? _messageSubscription;
  StreamSubscription<WebSocketStatus>? _statusSubscription;

  // Constant
  static const int _minIPParts = 4;
  static const int _maxOctetValue = 255;
  static const int _shortMessageThreshold = 4;
  static const int _reasonableDataLength = 8;
  static const int _longDataThreshold = 20;
  static const int _fallbackDataThreshold = 5;

  FireAlarmWebSocketManager(this._fireAlarmData);

  // Getters - WebSocket service status
  bool get isConnected => _webSocketService.isConnected;
  bool get isConnecting => _webSocketService.isConnecting;
  String get currentURL => _webSocketService.currentURL;
  int get reconnectAttempts => _webSocketService.reconnectAttempts;
  WebSocketErrorType? get lastErrorType => _webSocketService.lastErrorType;
  WebSocketService get webSocketService => _webSocketService;

  /// Connect ke ESP32 via WebSocket dengan IP Configuration Service
  Future<bool> connectToESP32(String? esp32IP) async {
    _logConnectionStart(esp32IP);

    try {
      final targetIP = await _getTargetIP(esp32IP);
      await _testConnectivity(targetIP);
      final url = UnifiedIPService.getWebSocketURLWithIP(targetIP);

      _logConnectionURL(url);

      final success = await _webSocketService.connectWithHealthCheck(url, autoReconnect: true);

      if (success) {
        await _handleSuccessfulConnection(targetIP);
      } else {
        _logConnectionFailed();
      }

      _logConnectionEnd();
      return success;
    } catch (e) {
      _logConnectionError(e);
      return false;
    }
  }

  /// Get target IP address from parameter or saved configuration
  Future<String> _getTargetIP(String? esp32IP) async {
    final targetIP = esp32IP ?? await UnifiedIPService.getESP32IP();
    AppLogger.info('Target IP: $targetIP', tag: 'FIRE_ALARM_WS');
    return targetIP;
  }

  /// Test connectivity to target IP
  Future<void> _testConnectivity(String targetIP) async {
    final connectivityTest = await UnifiedIPService.testConnectivity(targetIP);
    if (!connectivityTest) {
      AppLogger.warning('Connectivity test FAILED, continuing anyway', tag: 'FIRE_ALARM_WS');
    } else {
      AppLogger.info('Connectivity test PASSED', tag: 'FIRE_ALARM_WS');
    }
  }

  /// Log WebSocket URL for connection
  void _logConnectionURL(String url) {
    AppLogger.info('WebSocket URL: $url', tag: 'FIRE_ALARM_WS');
    AppLogger.info('Calling webSocketService.connectWithHealthCheck()...', tag: 'FIRE_ALARM_WS');
  }

  /// Handle successful WebSocket connection
  Future<void> _handleSuccessfulConnection(String targetIP) async {
    AppLogger.info('WebSocket connected SUCCESSFULLY', tag: 'FIRE_ALARM_WS');
    AppLogger.info('Service.isConnected: ${_webSocketService.isConnected}', tag: 'FIRE_ALARM_WS');

    _setupWebSocketListeners();
    await UnifiedIPService.saveLastConnectedIP(targetIP);
    await _updateAutoRefreshService();
    _updateFireAlarmConnectionStatus();
    notifyListeners();
  }

  /// Update AutoRefreshService with WebSocket service
  Future<void> _updateAutoRefreshService() async {
    try {
      final autoRefreshService = getIt<AutoRefreshService>();
      autoRefreshService.setWebSocketService(_webSocketService);
      AppLogger.info('AutoRefreshService updated', tag: 'FIRE_ALARM_WS');
    } catch (e) {
      AppLogger.error('Failed to set AutoRefreshService', error: e, tag: 'FIRE_ALARM_WS');
    }
  }

  /// Update FireAlarmData connection status
  void _updateFireAlarmConnectionStatus() {
    _fireAlarmData.setWebSocketConnectionStatus(true);
    AppLogger.info('FireAlarmData status set to: CONNECTED', tag: 'FIRE_ALARM_WS');
    AppLogger.info('isWebSocketConnected: ${_fireAlarmData.isWebSocketConnected}', tag: 'FIRE_ALARM_WS');
  }

  /// Log connection start
  void _logConnectionStart(String? esp32IP) {
    AppLogger.info('═══════════════════════════════════════════════════════════════', tag: 'FIRE_ALARM_WS');
    AppLogger.info('WEBSOCKET: CONNECTING TO ESP32', tag: 'FIRE_ALARM_WS');
    AppLogger.info('IP Parameter: $esp32IP', tag: 'FIRE_ALARM_WS');
  }

  /// Log connection failed
  void _logConnectionFailed() {
    AppLogger.error('WebSocket connection FAILED', tag: 'FIRE_ALARM_WS');
  }

  /// Log connection end
  void _logConnectionEnd() {
    AppLogger.info('═══════════════════════════════════════════════════════════════', tag: 'FIRE_ALARM_WS');
  }

  /// Log connection error
  void _logConnectionError(dynamic e) {
    AppLogger.error('EXCEPTION: $e', tag: 'FIRE_ALARM_WS');
    AppLogger.info('═══════════════════════════════════════════════════════════════', tag: 'FIRE_ALARM_WS');
  }

  /// Connect ke ESP32 menggunakan konfigurasi tersimpan
  Future<bool> connectToESP32WithSavedConfig() async {
    return await connectToESP32(null); // null akan gunakan saved config
  }

  /// Update dan connect dengan IP baru
  Future<bool> updateAndConnect(String newIP) async {
    // Validasi IP terlebih dahulu
    if (!_isValidIP(newIP)) {
      AppLogger.error('Invalid IP format: $newIP', tag: 'FIRE_ALARM_WS');
      return false;
    }

    // Disconnect dulu jika sudah connected
    if (isConnected) {
      await disconnectFromESP32();
    }

    // Save IP baru
    final saveSuccess = await UnifiedIPService.saveESP32IP(newIP);
    if (!saveSuccess) {
      AppLogger.warning('Failed to save new IP: $newIP', tag: 'FIRE_ALARM_WS');
      // Continue dengan connection attempt meskipun save gagal
    }

    // Connect dengan IP baru
    return await connectToESP32(newIP);
  }

  /// Disconnect dari ESP32 WebSocket
  Future<void> disconnectFromESP32() async {
    try {
      AppLogger.info('Disconnecting from ESP32 WebSocket', tag: 'FIRE_ALARM_WS');

      // Cancel subscriptions
      await _messageSubscription?.cancel();
      _messageSubscription = null;
      await _statusSubscription?.cancel();
      _statusSubscription = null;

      // Disconnect WebSocket service
      await _webSocketService.disconnect();

      AppLogger.info('WebSocket disconnected successfully', tag: 'FIRE_ALARM_WS');
      notifyListeners();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error disconnecting from ESP32',
        tag: 'FIRE_ALARM_WS',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Setup WebSocket message listeners
  void _setupWebSocketListeners() {
    // Cancel existing subscriptions
    _messageSubscription?.cancel();
    _statusSubscription?.cancel();

    // Listen untuk status changes
    _statusSubscription = _webSocketService.statusStream.listen((status) {
      AppLogger.info('📢 WebSocket STATUS stream received: $status', tag: 'FIRE_ALARM_WS');
      AppLogger.info('📢 Connected=${_webSocketService.isConnected}', tag: 'FIRE_ALARM_WS');

      // 🔥 CRITICAL: Update FireAlarmData connection status immediately
      if (_webSocketService.isConnected) {
        _fireAlarmData.setWebSocketConnectionStatus(true);
        AppLogger.info('✅ FireAlarmData status set to CONNECTED via listener', tag: 'FIRE_ALARM_WS');
      } else {
        _fireAlarmData.setWebSocketConnectionStatus(false);
        AppLogger.info('❌ FireAlarmData status set to DISCONNECTED via listener', tag: 'FIRE_ALARM_WS');
      }

      notifyListeners();
    });

    // Listen untuk incoming messages
    _messageSubscription = _webSocketService.messageStream.listen((message) {
      _handleWebSocketMessage(message);
    });

    AppLogger.info('✅ WebSocket listeners setup complete', tag: 'FIRE_ALARM_WS');
  }

  /// Handle incoming WebSocket message dari ESP32
  void _handleWebSocketMessage(WebSocketMessage message) {
    try {
      _logIncomingMessage(message);

      final esp32Data = _parseESP32Data(message.data);

      if (esp32Data != null) {
        _logMessageAccepted(esp32Data);

        // 🔥 CRITICAL FIX: If data received, ensure connection status is TRUE
        // This handles cases where WebSocketService reports disconnected but data is still flowing
        if (!_fireAlarmData.isWebSocketConnected) {
          print('🔄 Auto-set connection status to CONNECTED (data received)');
          _fireAlarmData.setWebSocketConnectionStatus(true);
          AppLogger.info('🔄 Auto-set connection status to CONNECTED (data received)', tag: 'FIRE_ALARM_WS');
        }

        _updateFireAlarmData(esp32Data);
      } else {
        _logMessageFiltered(message);
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error handling WebSocket message',
        tag: 'FIRE_ALARM_WS',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Log incoming WebSocket message
  void _logIncomingMessage(WebSocketMessage message) {
    final messagePreview = _truncateString(message.data.toString(), 100);
    AppLogger.info('WebSocket Raw Message (${message.data.runtimeType}): "$messagePreview"', tag: 'WS_FLOW');
  }

  /// Log message accepted for processing
  void _logMessageAccepted(Map<String, dynamic> esp32Data) {
    final rawData = esp32Data['raw'] as String? ?? 'no raw data';
    final rawDataPreview = _truncateString(rawData, 50);
    AppLogger.info('Message passed filtering: ${esp32Data.keys}, raw data: "$rawDataPreview"', tag: 'WS_FLOW');
  }

  /// Log message filtered out
  void _logMessageFiltered(WebSocketMessage message) {
    final messagePreview = _truncateString(message.data.toString(), 100);
    AppLogger.warning('Message filtered out: "$messagePreview"', tag: 'WS_FLOW');
  }

  /// Truncate string to specified length
  String _truncateString(String str, int maxLength) {
    return str.substring(0, str.length > maxLength ? maxLength : str.length);
  }

  /// Parse data dari ESP32 with message type filtering (synchronous)
  Map<String, dynamic>? _parseESP32Data(dynamic data) {
    try {
      // Handle different data formats from ESP32
      if (data is Map<String, dynamic>) {
        return _parseJSONData(data);
      } else if (data is String) {
        return _parseStringData(data);
      }

      AppLogger.warning('Unknown ESP32 data format: ${data.runtimeType}', tag: 'FIRE_ALARM_WS');
      return null;
    } catch (e, stackTrace) {
      AppLogger.error('Error parsing ESP32 data', tag: 'FIRE_ALARM_WS', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Parse JSON data from ESP32 - Intelligent zone data preservation
  Map<String, dynamic>? _parseJSONData(Map<String, dynamic> jsonData) {
    try {
      // Filter out pure system messages without zone data
      if (_shouldFilterSystemMessage(jsonData)) {
        return null;
      }

      // Check for non-zone message types
      final type = jsonData['type'] as String? ?? 'unknown';
      final command = jsonData['command'] as String?;
      if (_isNonZoneMessageType(type, command, jsonData)) {
        AppLogger.info('Filtering non-zone message: type=$type, command=$command', tag: 'FIRE_ALARM_WS');
        return null;
      }

      // Extract zone data from 'data' field
      final dataField = jsonData['data'] as String?;
      if (dataField != null) {
        return _extractZoneDataFromField(dataField);
      }

      // Fallback: Check for other zone data indicators
      if (!_hasZoneDataIndicators(jsonData)) {
        AppLogger.info('JSON message lacks zone data indicators, filtering out', tag: 'FIRE_ALARM_WS');
        return null;
      }

      AppLogger.info('Zone data detected in JSON message (legacy format), processing...', tag: 'FIRE_ALARM_WS');
      return jsonData;

    } catch (e, stackTrace) {
      AppLogger.error('Error parsing JSON data', tag: 'FIRE_ALARM_WS', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Check if system message should be filtered
  bool _shouldFilterSystemMessage(Map<String, dynamic> jsonData) {
    if (!jsonData.containsKey('messageType')) {
      return false;
    }

    final messageType = jsonData['messageType'] as String?;
    final isSystemMessage = messageType == 'systemStatus' || messageType == 'connectionStatus';
    final hasZoneData = _containsZoneData(jsonData);

    if (isSystemMessage && !hasZoneData) {
      AppLogger.info('Filtering pure system message: type=$messageType', tag: 'FIRE_ALARM_WS');
      return true;
    }
    return false;
  }

  /// Extract zone data from data field
  Map<String, dynamic> _extractZoneDataFromField(String dataField) {
    final preview = _truncateString(dataField, 100);
    AppLogger.info('Found data field: "$preview..."', tag: 'FIRE_ALARM_WS');
    AppLogger.info('Zone data extracted, will be processed by FireAlarmData.processWebSocketData()', tag: 'FIRE_ALARM_WS');

    return {
      'raw': dataField,
      'format': 'hex',
      'source': 'websocket_json',
      'dataField': dataField,
    };
  }

  /// Check if JSON has zone data indicators
  bool _hasZoneDataIndicators(Map<String, dynamic> jsonData) {
    return jsonData.containsKey('raw') ||
           jsonData.containsKey('zones') ||
           (jsonData.containsKey('address') && jsonData.containsKey('trouble'));
  }

  /// Parse string data from ESP32
  Map<String, dynamic>? _parseStringData(String stringData) {
    // Filter out control commands
    if (_isControlCommand(stringData)) {
      AppLogger.info('Filtering control command: $stringData', tag: 'FIRE_ALARM_WS');
      return null;
    }

    // Filter out short messages
    if (stringData.length < _shortMessageThreshold) {
      AppLogger.info('Filtering short message (${stringData.length} chars): $stringData', tag: 'FIRE_ALARM_WS');
      return null;
    }

    // 🔥 CRITICAL: Extract zone data from JSON if present
    String zoneData = stringData;
    
    if (stringData.contains('"data":"')) {
      try {
        // Find the start of the data field
        final dataStartMarker = '"data":"';
        final dataStart = stringData.indexOf(dataStartMarker);
        
        if (dataStart != -1) {
          final valueStart = dataStart + dataStartMarker.length;
          
          // Find the end - look for pipe | first (metadata separator), then closing quote
          String dataField;
          final pipePos =stringData.indexOf('|', valueStart);
          final quotePos = stringData.indexOf('","', valueStart); // Next JSON field
          final closingQuotePos = stringData.indexOf('"}', valueStart); // End of JSON
          
          // Take the earliest valid end position
          int endPos = stringData.length;
          if (pipePos > valueStart && pipePos < endPos) endPos = pipePos;
          if (quotePos > valueStart && quotePos < endPos) endPos = quotePos;
          if (closingQuotePos > valueStart && closingQuotePos < endPos) endPos = closingQuotePos;
          
          dataField = stringData.substring(valueStart, endPos);
          
          // Clean up the data - trim any trailing quotes or whitespace
          dataField = dataField.replaceAll(RegExp(r'["\s]+$'), '');
          
          if (dataField.isNotEmpty) {
            zoneData = dataField;
            AppLogger.info('📦 Extracted zone data: ${zoneData.substring(0, zoneData.length > 50 ? 50 : zoneData.length)}...', tag: 'FIRE_ALARM_WS');
          }
        }
      } catch (e) {
        AppLogger.warning('Failed to extract data field: $e', tag: 'FIRE_ALARM_WS');
      }
    }

    // Check if extracted data looks like zone data
    if (!_looksLikeZoneData(zoneData)) {
      AppLogger.info('String message doesn\'t match zone data patterns, filtering out', tag: 'FIRE_ALARM_WS');
      return null;
    }

    AppLogger.info('Zone data detected in string message, processing...', tag: 'FIRE_ALARM_WS');
    return {
      'raw': zoneData,  // Return extracted zone data, not full JSON
      'format': 'hex',
      'source': 'websocket_string',
    };
  }

  /// Check if message type is non-zone data - ENHANCED with zone data detection
  bool _isNonZoneMessageType(String type, String? command, Map<String, dynamic> jsonData) {
    final controlCommands = ['r', 'd', 's', 'a']; // reset, drill, silence, acknowledge
    final systemTypes = ['esp_command', 'control_signal', 'bell_confirmation'];

    // Allow messages with zone indicators even if they have control types
    if (command != null && controlCommands.contains(command.toLowerCase()) && _hasZoneIndicators(jsonData)) {
      return false; // Preserve - might contain zone updates
    }

    return systemTypes.contains(type);
  }

  /// Helper method to detect zone data in messages
  bool _containsZoneData(Map<String, dynamic> jsonData) {
    // Check for zone indicators in various fields
    final fieldsToCheck = ['data', 'zones', 'raw', 'payload'];

    for (final field in fieldsToCheck) {
      final value = jsonData[field];
      if (value != null && value.toString().length > 10) {
        // Look for zone patterns (device addresses, zone numbers)
        if (RegExp(r'[0-9A-Fa-f]{8,}').hasMatch(value.toString())) {
          return true; // Likely contains zone data
        }
      }
    }
    return false;
  }

  /// Check if JSON data has zone indicators
  bool _hasZoneIndicators(Map<String, dynamic> jsonData) {
    // Check for zone-related fields
    final zoneFields = ['zones', 'data', 'raw', 'zoneData', 'zone_status'];

    for (final field in zoneFields) {
      if (jsonData.containsKey(field) && jsonData[field] != null) {
        final value = jsonData[field].toString();
        // Look for hex patterns, zone numbers, or device addresses
        if (value.length > 5 && (RegExp(r'[0-9A-Fa-f]').hasMatch(value) || RegExp(r'\d+').hasMatch(value))) {
          return true;
        }
      }
    }

    return false;
  }

  /// Check if string is a control command
  bool _isControlCommand(String data) {
    final controlCommands = {'r', 'd', 's', 'a', 'reset', 'drill', 'silence', 'acknowledge'};
    final cleanData = data.toLowerCase().trim();

    return controlCommands.contains(cleanData) ||
           cleanData.startsWith('cmd:') ||
           cleanData.startsWith('ctrl:');
  }

  /// Check if string looks like zone data (very lenient like reference system)
  bool _looksLikeZoneData(String data) {
    // Check for STX/ETX markers (strong indicators of zone data)
    if (_hasStxEtxMarkers(data)) {
      return true;
    }

    // Check for user's specific data pattern
    if (_hasUserPattern(data)) {
      return true;
    }

    // Check for zone module patterns
    if (_hasZoneModulePattern(data)) {
      return true;
    }

    // Check for hex patterns with reasonable length
    if (_hasHexPatternWithLength(data)) {
      return true;
    }

    // Last resort: long data with hex-like content
    if (_hasLongHexContent(data)) {
      return true;
    }

    // Ultra permissive fallback
    return _hasAlphanumericContent(data);
  }

  /// Check for STX/ETX markers
  bool _hasStxEtxMarkers(String data) {
    return data.contains('<STX>') ||
           data.contains('<ETX>') ||
           data.contains(String.fromCharCode(0x02)) ||
           data.contains(String.fromCharCode(0x03));
  }

  /// Check for user's specific data pattern: "41DF <STX>012300..."
  bool _hasUserPattern(String data) {
    return RegExp(r'[0-9A-Fa-f]{4}\s*<STX>\d{6}').hasMatch(data);
  }

  /// Check for zone module patterns (01 23 45, 01ABCD, etc.)
  bool _hasZoneModulePattern(String data) {
    return RegExp(r'\b(0[1-9]|[1-5][0-9]|6[0-3])\s*[0-9A-Fa-f]{4}\b').hasMatch(data);
  }

  /// Check for hex patterns with reasonable length
  bool _hasHexPatternWithLength(String data) {
    final hexPattern = RegExp(r'[0-9A-Fa-f]{4,}');
    return hexPattern.hasMatch(data) && data.length >= _reasonableDataLength;
  }

  /// Check for long data with hex-like content
  bool _hasLongHexContent(String data) {
    return data.length >= _longDataThreshold && RegExp(r'[0-9A-Fa-f]').hasMatch(data);
  }

  /// Ultra permissive fallback - accept any alphanumeric data
  bool _hasAlphanumericContent(String data) {
    final hasContent = data.length >= _fallbackDataThreshold && RegExp(r'[a-zA-Z0-9]').hasMatch(data);
    if (hasContent) {
      AppLogger.info('ULTRA PERMISSIVE: Accepting data via fallback - data might be zone data', tag: 'FIRE_ALARM_WS');
    }
    return hasContent;
  }

  /// Update FireAlarmData dengan data dari ESP32
  Future<void> _updateFireAlarmData(Map<String, dynamic> esp32Data) async {
    try {
      AppLogger.info('ESP32 Data received: ${esp32Data.toString()}', tag: 'FIRE_ALARM_WS');

      final rawData = esp32Data['raw'] as String? ?? '';
      final format = esp32Data['format'] as String? ?? 'unknown';

      if (rawData.isNotEmpty) {
        await _processRawData(rawData, format);
      }

      notifyListeners();
    } catch (e, stackTrace) {
      AppLogger.error('Error updating FireAlarm data from WebSocket', tag: 'FIRE_ALARM_WS', error: e, stackTrace: stackTrace);
    }
  }

  /// Process raw data from WebSocket
  Future<void> _processRawData(String rawData, String format) async {
    AppLogger.info('Processing WebSocket data: format=$format, raw=$rawData', tag: 'FIRE_ALARM_WS');
    
    // 🔥 CRITICAL FIX: Always force process when data comes from active WebSocket connection
    // This ensures zones update regardless of _isWebSocketMode flag state
    await _fireAlarmData.processWebSocketData(rawData, forceProcess: true);
    
    AppLogger.info('WebSocket data processed successfully', tag: 'FIRE_ALARM_WS');
  }

  
  /// Get WebSocket connection diagnostics
  Map<String, dynamic> getDiagnostics() {
    final diagnostics = _webSocketService.getDiagnostics();
    diagnostics['manager'] = {
      'hasFireAlarmData': true, // FireAlarmData exists if manager is created
      'hasMessageSubscription': _messageSubscription != null,
      'hasStatusSubscription': _statusSubscription != null,
    };
    return diagnostics;
  }

  /// Reset WebSocket connection state
  void resetConnection() {
    _webSocketService.resetConnectionState();
    notifyListeners();
  }

  /// Send data ke ESP32 via WebSocket
  Future<bool> sendToESP32(Map<String, dynamic> data) async {
    try {
      return await _webSocketService.sendJSON(data);
    } catch (e, stackTrace) {
      AppLogger.error('Error sending data to ESP32', tag: 'FIRE_ALARM_WS', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Get recent WebSocket messages for debugging
  List<Map<String, dynamic>> getRecentMessages() {
    // This would be implemented with a message history buffer
    return [];
  }

  /// Validate IPv4 address format
  bool _isValidIP(String ip) {
    if (ip.isEmpty) {
      return false;
    }

    final parts = ip.split('.');
    if (parts.length != _minIPParts) {
      return false;
    }

    return parts.every(_isValidOctet);
  }

  /// Validate IP octet (0-255)
  bool _isValidOctet(String octet) {
    try {
      final value = int.parse(octet);
      return value >= 0 && value <= _maxOctetValue;
    } catch (e) {
      return false;
    }
  }

  @override
  void dispose() {
    AppLogger.info('Disposing FireAlarmWebSocketManager', tag: 'FIRE_ALARM_WS');

    _messageSubscription?.cancel();
    _statusSubscription?.cancel();
    _webSocketService.dispose();

    super.dispose();
  }
}