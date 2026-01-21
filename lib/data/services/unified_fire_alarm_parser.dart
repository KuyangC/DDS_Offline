import 'package:flutter/material.dart';
import '../models/zone_status_model.dart';

// ==================== UNIFIED DATA MODELS ====================

/// Unified zone status for all zones (1-315)
class UnifiedZoneStatus {
  final int zoneNumber;
  final String status; // 'Alarm', 'Trouble', 'Active', 'Normal', 'Offline'
  final String description;
  final Color color;
  final String deviceAddress;
  final int deviceNumber;
  final int zoneInDevice; // 1-5 dalam device
  final DateTime timestamp;
  final bool isOffline;
  final bool hasPower;
  final bool hasBellActive; // Bell activation status from device bell bit (0x20)
  final String? rawData; // Raw data untuk debugging

  UnifiedZoneStatus({
    required this.zoneNumber,
    required this.status,
    required this.description,
    required this.color,
    required this.deviceAddress,
    required this.deviceNumber,
    required this.zoneInDevice,
    required this.timestamp,
    this.isOffline = false,
    this.hasPower = true,
    this.hasBellActive = false,
    this.rawData,
  });
}

/// Unified system status for the entire system
class UnifiedSystemStatus {
  final bool hasAlarm;
  final bool hasTrouble;
  final bool hasPower;
  final bool isSilenced;
  final bool isDrill;
  final bool isDisabled;
  final bool isSystemOffline;
  final int connectedDevices;
  final int disconnectedDevices;
  final int totalAlarmZones;
  final int totalTroubleZones;
  final int totalActiveZones;
  final String systemContext;
  final DateTime timestamp;
  final List<String> activeEvents;

  UnifiedSystemStatus({
    required this.hasAlarm,
    required this.hasTrouble,
    required this.hasPower,
    required this.isSilenced,
    required this.isDrill,
    required this.isDisabled,
    required this.isSystemOffline,
    required this.connectedDevices,
    required this.disconnectedDevices,
    required this.totalAlarmZones,
    required this.totalTroubleZones,
    required this.totalActiveZones,
    required this.systemContext,
    required this.timestamp,
    required this.activeEvents,
  });
}

/// Complete parsing result
class UnifiedParsingResult {
  final Map<int, UnifiedZoneStatus> zones;
  final UnifiedSystemStatus systemStatus;
  final String parsingSource;
  final bool hasError;
  final String? errorMessage;
  final DateTime timestamp;
  final String? rawData;

  UnifiedParsingResult({
    required this.zones,
    required this.systemStatus,
    required this.parsingSource,
    this.hasError = false,
    this.errorMessage,
    required this.timestamp,
    this.rawData,
  });

  factory UnifiedParsingResult.error(String errorMessage, String source) {
    return UnifiedParsingResult(
      zones: {},
      systemStatus: UnifiedSystemStatus(
        hasAlarm: false,
        hasTrouble: false,
        hasPower: false,
        isSilenced: false,
        isDrill: false,
        isDisabled: false,
        isSystemOffline: true,
        connectedDevices: 0,
        disconnectedDevices: 63,
        totalAlarmZones: 0,
        totalTroubleZones: 0,
        totalActiveZones: 0,
        systemContext: 'SYSTEM ERROR',
        timestamp: DateTime.now(),
        activeEvents: ['PARSING ERROR: $errorMessage'],
      ),
      parsingSource: source,
      hasError: true,
      errorMessage: errorMessage,
      timestamp: DateTime.now(),
    );
  }
}

// ==================== PARSING STRATEGIES ====================

abstract class ParsingStrategy {
  Future<UnifiedParsingResult> parseData(String rawData, Map<String, dynamic>? context);
  String get strategyName;
}

class EnhancedZoneParsingStrategy implements ParsingStrategy {
  static const int totalDevices = 63;
  static const int zonesPerDevice = 5;

  @override
  String get strategyName => 'enhanced_zone_parser';

  @override
  Future<UnifiedParsingResult> parseData(String rawData, Map<String, dynamic>? context) async {
    try {
      List<String> deviceModules = [];
      if (rawData.contains('<STX>')) {
        final firstSTXIndex = rawData.indexOf('<STX>');
        if (firstSTXIndex != -1) {
            String dataSection = rawData.substring(firstSTXIndex);
            deviceModules = dataSection.split('<STX>').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
        }
      } else {
        deviceModules = [rawData];
      }

      final Map<int, UnifiedZoneStatus> zones = {};
      int connectedDevices = 0;
      int alarmZones = 0;
      int troubleZones = 0;

      for (final deviceModule in deviceModules) {
        if (deviceModule.startsWith('\$')) continue; // Skip confirmation codes

        final slaveAddress = _extractSlaveAddress(deviceModule);
        if (slaveAddress == null) continue;

        final deviceNumber = int.parse(slaveAddress);
        final deviceZones = _parseDeviceZones(deviceModule, deviceNumber, slaveAddress);

        for (final zone in deviceZones) {
          final globalZoneNumber = (deviceNumber - 1) * zonesPerDevice + zone.zoneInDevice;
          zones[globalZoneNumber] = zone;
          if (zone.status == 'Alarm') alarmZones++;
          if (zone.status == 'Trouble') troubleZones++;
        }
        if (deviceZones.any((zone) => !zone.isOffline)) {
          connectedDevices++;
        }
      }

      final systemStatus = UnifiedSystemStatus(
        hasAlarm: alarmZones > 0,
        hasTrouble: troubleZones > 0,
        hasPower: connectedDevices > 0,
        isSilenced: false,
        isDrill: false,
        isDisabled: false,
        isSystemOffline: connectedDevices == 0,
        connectedDevices: connectedDevices,
        disconnectedDevices: totalDevices - connectedDevices,
        totalAlarmZones: alarmZones,
        totalTroubleZones: troubleZones,
        totalActiveZones: zones.values.where((z) => !z.isOffline).length,
        systemContext: _determineSystemContext(alarmZones, troubleZones, connectedDevices),
        timestamp: DateTime.now(),
        activeEvents: [
          if (alarmZones > 0) '$alarmZones ALARM ZONES',
          if (troubleZones > 0) '$troubleZones TROUBLE ZONES',
          if (connectedDevices < totalDevices) '${totalDevices - connectedDevices} DEVICES OFFLINE',
        ],
      );

      return UnifiedParsingResult(
        zones: zones,
        systemStatus: systemStatus,
        parsingSource: strategyName,
        timestamp: DateTime.now(),
        rawData: rawData,
      );
    } catch (e) {
      return UnifiedParsingResult.error('Enhanced Zone Parser failed: $e', strategyName);
    }
  }

  List<UnifiedZoneStatus> _parseDeviceZones(String deviceData, int deviceNumber, String deviceAddress) {
    final List<UnifiedZoneStatus> zones = [];
    if (deviceData.length < 2) return zones;

    final statusDataSegment = deviceData.substring(2); // Get "BBCC" part
    
    if (statusDataSegment.length < 4) { // If trouble/alarm bytes are missing, treat as offline
        for (int i = 1; i <= zonesPerDevice; i++) {
            final globalZoneNumber = (deviceNumber - 1) * zonesPerDevice + i;
            zones.add(UnifiedZoneStatus(
                zoneNumber: globalZoneNumber,
                status: 'Offline',
                description: 'Zone $i - Offline',
                color: Colors.grey.shade300,
                deviceAddress: deviceAddress,
                deviceNumber: deviceNumber,
                zoneInDevice: i,
                timestamp: DateTime.now(),
                isOffline: true,
                hasPower: false,
            ));
        }
        return zones;
    }
    
    final troubleValue = int.parse(statusDataSegment.substring(0, 2), radix: 16);
    final alarmValue = int.parse(statusDataSegment.substring(2, 4), radix: 16);

    for (int i = 1; i <= zonesPerDevice; i++) {
      final zoneResult = _mapZoneStatusFromBytes(troubleValue, alarmValue, i - 1); // Pass 0-indexed zone
      final globalZoneNumber = (deviceNumber - 1) * zonesPerDevice + i;
      zones.add(UnifiedZoneStatus(
          zoneNumber: globalZoneNumber,
          status: zoneResult['status'],
          description: zoneResult['description'],
          color: zoneResult['color'],
          deviceAddress: deviceAddress,
          deviceNumber: deviceNumber,
          zoneInDevice: i,
          timestamp: DateTime.now(),
          isOffline: zoneResult['isOffline'] ?? false,
          hasPower: zoneResult['hasPower'] ?? true,
          hasBellActive: zoneResult['hasBell'] ?? false,
          rawData: deviceData,
      ));
    }
    return zones;
  }

  /// Map zone status from separate trouble and alarm bytes (6-char module format)
  Map<String, dynamic> _mapZoneStatusFromBytes(int troubleValue, int alarmValue, int zoneIndex) {
    String status = 'Normal';
    String description = 'Zone ${zoneIndex + 1} - Normal';
    Color color = Colors.white;

    final int bitPosition = zoneIndex; // Zone 0 = bit 0, Zone 1 = bit 1, etc.
    bool hasZoneAlarmBit = (alarmValue & (1 << bitPosition)) != 0; // Zone-specific alarm bit
    bool hasZoneTroubleBit = (troubleValue & (1 << bitPosition)) != 0; // Zone-specific trouble bit

    // Determine if the module-wide alarm condition is Pre-Alarm or Full Alarm based on the ALARM BYTE
    bool isPreAlarmCondition = (alarmValue >= 0x10 && alarmValue < 0x20); // 0x1X - e.g., 0x11, 0x14
    bool isFullAlarmCondition = (alarmValue >= 0x20); // 0x2X or higher - e.g., 0x21, 0x24, 0x3F

    if (hasZoneAlarmBit) { // If this specific zone's alarm bit is set
        if (isFullAlarmCondition) {
            status = 'Alarm';
            description = 'Zone ${zoneIndex + 1} - ALARM';
            color = Colors.red;
        } else if (isPreAlarmCondition) {
            status = 'Pre-Alarm';
            description = 'Zone ${zoneIndex + 1} - PRE-ALARM';
            color = Colors.orange; // As per user request, color Pre-Alarm like Trouble
        }
    } else if (hasZoneTroubleBit) { // If this specific zone's trouble bit is set
        status = 'Trouble';
        description = 'Zone ${zoneIndex + 1} - TROUBLE';
        color = Colors.orange;
    }

    return {
      'status': status,
      'description': description,
      'color': color,
      'isOffline': false, 
      'hasPower': true,   
      'hasBell': (alarmValue & 0x20) != 0, // This is the module-wide bell flag.
    };
  }

  String _determineSystemContext(int alarmZones, int troubleZones, int connectedDevices) {
    if (connectedDevices == 0) return 'SYSTEM OFFLINE';
    if (alarmZones > 0) return 'ALARM ACTIVE';
    if (troubleZones > 0) return 'TROUBLE CONDITION';
    return 'SYSTEM NORMAL';
  }

  String? _extractSlaveAddress(String segment) {
    if (segment.length >= 2) {
      final address = segment.substring(0, 2);
      final addressNum = int.tryParse(address);
      if (addressNum != null && addressNum >= 1 && addressNum <= totalDevices) {
        return address;
      }
    }
    return null;
  }
}

// ==================== PUBLIC API ====================

class UnifiedFireAlarmAPI {
  static Future<UnifiedParsingResult> parse(String rawData, { Map<String, dynamic>? context }) async {
    return await EnhancedZoneParsingStrategy().parseData(rawData, context);
  }
}
