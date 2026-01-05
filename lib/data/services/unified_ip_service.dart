import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'logger.dart';

/// Unified IP Service for centralized IP management across the application
/// Provides single source of truth for ESP32 connection settings
class UnifiedIPService {
  static final UnifiedIPService _instance = UnifiedIPService._internal();
  factory UnifiedIPService() => _instance;
  UnifiedIPService._internal();

  static const String _ipKey = 'unified_esp32_ip';
  static const String _portKey = 'unified_esp32_port';
  static const String _projectNameKey = 'unified_project_name';
  static const String _moduleCountKey = 'unified_module_count';
  static const String _lastSavedKey = 'unified_last_saved';
  static const String _isConfiguredKey = 'unified_is_configured';

  // Default values
  static const String _defaultIP = '192.168.1.100';
  static const int _defaultPort = 81; // Unified with IPConfigurationService
  static const String _defaultProjectName = 'Fire Alarm System';
  static const int _defaultModuleCount = 1;

  // Static getter for defaultIP (IPConfigurationService compatibility)
  static String get defaultIP => _defaultIP;

  // In-memory cache for performance
  String? _cachedIP;
  int? _cachedPort;
  String? _cachedProjectName;
  int? _cachedModuleCount;
  DateTime? _cachedLastSaved;
  bool? _cachedIsConfigured;

  /// Get the current ESP32 IP address
  Future<String> getIP() async {
    if (_cachedIP != null) return _cachedIP!;

    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedIP = prefs.getString(_ipKey) ?? _defaultIP;
      return _cachedIP!;
    } catch (e) {
      AppLogger.error('Failed to get IP from storage', error: e);
      _cachedIP = _defaultIP;
      return _defaultIP;
    }
  }

  /// Set the ESP32 IP address
  Future<void> setIP(String ip) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_ipKey, ip);
      _cachedIP = ip;
      _cacheLastSaved();
      AppLogger.info('IP address updated to: $ip');
    } catch (e) {
      AppLogger.error('Failed to set IP address', error: e);
      throw Exception('Failed to save IP address: $e');
    }
  }

  /// Get the current ESP32 port
  Future<int> getPort() async {
    if (_cachedPort != null) return _cachedPort!;

    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedPort = prefs.getInt(_portKey) ?? _defaultPort;
      return _cachedPort!;
    } catch (e) {
      AppLogger.error('Failed to get port from storage', error: e);
      _cachedPort = _defaultPort;
      return _defaultPort;
    }
  }

  /// Set the ESP32 port
  Future<void> setPort(int port) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_portKey, port);
      _cachedPort = port;
      _cacheLastSaved();
      AppLogger.info('Port updated to: $port');
    } catch (e) {
      AppLogger.error('Failed to set port', error: e);
      throw Exception('Failed to save port: $e');
    }
  }

  /// Get the current project name
  Future<String> getProjectName() async {
    if (_cachedProjectName != null) return _cachedProjectName!;

    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedProjectName = prefs.getString(_projectNameKey) ?? _defaultProjectName;
      return _cachedProjectName!;
    } catch (e) {
      AppLogger.error('Failed to get project name from storage', error: e);
      _cachedProjectName = _defaultProjectName;
      return _defaultProjectName;
    }
  }

  /// Set the project name
  Future<void> setProjectName(String projectName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_projectNameKey, projectName);
      _cachedProjectName = projectName;
      _cacheLastSaved();
      AppLogger.info('Project name updated to: $projectName');
    } catch (e) {
      AppLogger.error('Failed to set project name', error: e);
      throw Exception('Failed to save project name: $e');
    }
  }

  /// Get the current module count
  Future<int> getModuleCount() async {
    if (_cachedModuleCount != null) return _cachedModuleCount!;

    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedModuleCount = prefs.getInt(_moduleCountKey) ?? _defaultModuleCount;
      return _cachedModuleCount!;
    } catch (e) {
      AppLogger.error('Failed to get module count from storage', error: e);
      _cachedModuleCount = _defaultModuleCount;
      return _defaultModuleCount;
    }
  }

  /// Set the module count
  Future<void> setModuleCount(int moduleCount) async {
    try {
      if (moduleCount < 1 || moduleCount > 63) {
        throw ArgumentError('Module count must be between 1 and 63');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_moduleCountKey, moduleCount);
      _cachedModuleCount = moduleCount;
      _cacheLastSaved();
      AppLogger.info('Module count updated to: $moduleCount');
    } catch (e) {
      AppLogger.error('Failed to set module count', error: e);
      throw Exception('Failed to save module count: $e');
    }
  }

  /// Get the last saved timestamp
  Future<DateTime?> getLastSaved() async {
    if (_cachedLastSaved != null) return _cachedLastSaved;

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedString = prefs.getString(_lastSavedKey);
      if (savedString != null) {
        _cachedLastSaved = DateTime.parse(savedString);
        return _cachedLastSaved;
      }
      return null;
    } catch (e) {
      AppLogger.error('Failed to get last saved timestamp', error: e);
      return null;
    }
  }

  /// Check if the system is configured
  Future<bool> isConfigured() async {
    if (_cachedIsConfigured != null) return _cachedIsConfigured!;

    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedIsConfigured = prefs.getBool(_isConfiguredKey) ?? false;
      return _cachedIsConfigured!;
    } catch (e) {
      AppLogger.error('Failed to get configuration status', error: e);
      _cachedIsConfigured = false;
      return false;
    }
  }

  /// Mark the system as configured
  Future<void> markConfigured({bool configured = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_isConfiguredKey, configured);
      _cachedIsConfigured = configured;
      AppLogger.info('System configuration status marked as: $configured');
    } catch (e) {
      AppLogger.error('Failed to set configuration status', error: e);
      throw Exception('Failed to save configuration status: $e');
    }
  }

  /// Get complete configuration as a map
  Future<Map<String, dynamic>> getConfiguration() async {
    return {
      'ip': await getIP(),
      'port': await getPort(),
      'projectName': await getProjectName(),
      'moduleCount': await getModuleCount(),
      'isConfigured': await isConfigured(),
      'lastSaved': await getLastSaved(),
    };
  }

  /// Set complete configuration from a map
  Future<void> setConfiguration(Map<String, dynamic> config) async {
    try {
      if (config.containsKey('ip')) {
        await setIP(config['ip'] as String);
      }
      if (config.containsKey('port')) {
        await setPort(config['port'] as int);
      }
      if (config.containsKey('projectName')) {
        await setProjectName(config['projectName'] as String);
      }
      if (config.containsKey('moduleCount')) {
        await setModuleCount(config['moduleCount'] as int);
      }
      if (config.containsKey('isConfigured')) {
        await markConfigured(configured: config['isConfigured'] as bool);
      }

      AppLogger.info('Complete configuration updated successfully');
    } catch (e) {
      AppLogger.error('Failed to set complete configuration', error: e);
      throw Exception('Failed to save configuration: $e');
    }
  }

  /// Sync from legacy OfflineConfig storage
  Future<void> syncFromOfflineConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Get legacy keys
      final legacyIP = prefs.getString('offline_ip');
      final legacyPort = prefs.getInt('offline_port');
      final legacyProjectName = prefs.getString('offline_project_name');
      final legacyModuleCount = prefs.getInt('offline_module_count');
      final legacyConfigured = prefs.getBool('offline_configured');

      // Update if legacy values exist
      if (legacyIP != null && legacyIP.isNotEmpty) {
        await setIP(legacyIP);
      }
      if (legacyPort != null && legacyPort != 0) {
        await setPort(legacyPort);
      }
      if (legacyProjectName != null && legacyProjectName.isNotEmpty) {
        await setProjectName(legacyProjectName);
      }
      if (legacyModuleCount != null && legacyModuleCount != 0) {
        await setModuleCount(legacyModuleCount);
      }
      if (legacyConfigured != null) {
        await markConfigured(configured: legacyConfigured);
      }

      AppLogger.info('Synced configuration from legacy OfflineConfig storage');
    } catch (e) {
      AppLogger.error('Failed to sync from OfflineConfig', error: e);
      // Don't throw error here as this is a sync operation
    }
  }

  /// Sync from home.dart WebSocketSettings storage
  Future<void> syncFromHomeSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Get home.dart keys
      final homeIP = prefs.getString('esp32_ip');
      final homePort = prefs.getInt('esp32_port');

      // Update if home.dart values exist
      if (homeIP != null && homeIP.isNotEmpty) {
        await setIP(homeIP);
      }
      if (homePort != null && homePort != 0) {
        await setPort(homePort);
      }

      AppLogger.info('Synced configuration from home.dart WebSocketSettings');
    } catch (e) {
      AppLogger.error('Failed to sync from home.dart settings', error: e);
      // Don't throw error here as this is a sync operation
    }
  }

  /// Sync to legacy OfflineConfig storage for backward compatibility
  Future<void> syncToOfflineConfig() async {
    try {
      final config = await getConfiguration();
      final prefs = await SharedPreferences.getInstance();

      // Update legacy keys
      await prefs.setString('offline_ip', config['ip'] as String);
      await prefs.setInt('offline_port', config['port'] as int);
      await prefs.setString('offline_project_name', config['projectName'] as String);
      await prefs.setInt('offline_module_count', config['moduleCount'] as int);
      await prefs.setBool('offline_configured', config['isConfigured'] as bool);

      AppLogger.info('Synced configuration to legacy OfflineConfig storage');
    } catch (e) {
      AppLogger.error('Failed to sync to OfflineConfig', error: e);
      // Don't throw error here as this is a sync operation
    }
  }

  /// Sync to home.dart WebSocketSettings storage for backward compatibility
  Future<void> syncToHomeSettings() async {
    try {
      final config = await getConfiguration();
      final prefs = await SharedPreferences.getInstance();

      // Update home.dart keys
      await prefs.setString('esp32_ip', config['ip'] as String);
      await prefs.setInt('esp32_port', config['port'] as int);

      AppLogger.info('Synced configuration to home.dart WebSocketSettings');
    } catch (e) {
      AppLogger.error('Failed to sync to home.dart settings', error: e);
      // Don't throw error here as this is a sync operation
    }
  }

  /// Clear all cached data
  void clearCache() {
    _cachedIP = null;
    _cachedPort = null;
    _cachedProjectName = null;
    _cachedModuleCount = null;
    _cachedLastSaved = null;
    _cachedIsConfigured = null;
  }

  /// Reset to default values
  Future<void> resetToDefaults() async {
    try {
      await setIP(_defaultIP);
      await setPort(_defaultPort);
      await setProjectName(_defaultProjectName);
      await setModuleCount(_defaultModuleCount);
      await markConfigured(configured: false);

      AppLogger.info('Configuration reset to default values');
    } catch (e) {
      AppLogger.error('Failed to reset to defaults', error: e);
      throw Exception('Failed to reset configuration: $e');
    }
  }

  /// Export configuration to JSON string
  Future<String> exportToJSON() async {
    final config = await getConfiguration();
    return config.map((key, value) => MapEntry(key, value?.toString())).toString();
  }

  /// Import configuration from JSON string
  Future<void> importFromJSON(String jsonString) async {
    try {
      // Note: This is a simplified import. In production, you'd want proper JSON parsing
      // This is a basic implementation for demonstration
      final config = <String, dynamic>{};

      // Simple parsing (you might want to use dart:convert for proper JSON parsing)
      if (jsonString.contains('"ip":')) {
        final ipMatch = RegExp(r'"ip":\s*"([^"]+)"').firstMatch(jsonString);
        if (ipMatch != null) config['ip'] = ipMatch.group(1);
      }

      if (jsonString.contains('"port":')) {
        final portMatch = RegExp(r'"port":\s*(\d+)').firstMatch(jsonString);
        if (portMatch != null && portMatch.group(1) != null) config['port'] = int.parse(portMatch.group(1)!);
      }

      if (jsonString.contains('"projectName":')) {
        final nameMatch = RegExp(r'"projectName":\s*"([^"]+)"').firstMatch(jsonString);
        if (nameMatch != null) config['projectName'] = nameMatch.group(1);
      }

      if (jsonString.contains('"moduleCount":')) {
        final moduleMatch = RegExp(r'"moduleCount":\s*(\d+)').firstMatch(jsonString);
        if (moduleMatch != null && moduleMatch.group(1) != null) config['moduleCount'] = int.parse(moduleMatch.group(1)!);
      }

      await setConfiguration(config);
      AppLogger.info('Configuration imported from JSON');
    } catch (e) {
      AppLogger.error('Failed to import configuration from JSON', error: e);
      throw Exception('Failed to import configuration: $e');
    }
  }

  /// Cache the last saved timestamp
  void _cacheLastSaved() {
    _cachedLastSaved = DateTime.now();
    // Persist to storage asynchronously
    _persistLastSaved();
  }

  /// Persist the last saved timestamp to storage
  Future<void> _persistLastSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastSavedKey, _cachedLastSaved!.toIso8601String());
    } catch (e) {
      AppLogger.error('Failed to persist last saved timestamp', error: e);
    }
  }

  // ============ IPConfigurationService COMPATIBILITY METHODS ============

  /// Get ESP32 IP address (IPConfigurationService compatibility)
  static Future<String> getESP32IP() async {
    final service = UnifiedIPService();
    return await service.getIP();
  }

  /// Save ESP32 IP address (IPConfigurationService compatibility)
  static Future<bool> saveESP32IP(String ip) async {
    try {
      final service = UnifiedIPService();
      await service.setIP(ip);
      return true;
    } catch (e) {
      AppLogger.error('Failed to save ESP32 IP', error: e);
      return false;
    }
  }

  /// Get WebSocket URL with IP (IPConfigurationService compatibility)
  static String getWebSocketURLWithIP(String ip) {
    return 'ws://$ip:81';
  }

  /// Save last connected IP (IPConfigurationService compatibility)
  static Future<void> saveLastConnectedIP(String ip) async {
    try {
      final service = UnifiedIPService();
      await service.setIP(ip);
      AppLogger.info('Last connected IP saved: $ip');
    } catch (e) {
      AppLogger.error('Failed to save last connected IP', error: e);
    }
  }

  /// Test connectivity to IP address (IPConfigurationService compatibility)
  static Future<bool> testConnectivity(String ip, {int port = 81, Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: timeout);
      socket.destroy();
      AppLogger.info('Connectivity test PASSED for $ip:$port');
      return true;
    } catch (e) {
      AppLogger.warning('Connectivity test FAILED for $ip:$port - $e');
      return false;
    }
  }
}