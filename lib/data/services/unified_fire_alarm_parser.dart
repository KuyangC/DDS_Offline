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
      // 🔥 CRITICAL: Extract master data BEFORE first STX
      String? masterData;
      bool hasMasterAlarm = false;
      bool hasMasterSilenced = false;
      bool hasMasterTrouble = false;
      
      List<String> deviceModules = [];
      if (rawData.contains('<STX>')) {
        final firstSTXIndex = rawData.indexOf('<STX>');
        if (firstSTXIndex != -1) {
            // 🔥 NEW: Extract data BEFORE STX = master data (e.g., "54CD")
            if (firstSTXIndex > 0) {
              masterData = rawData.substring(0, firstSTXIndex).trim();
              
              // Parse master status byte (4 chars: header + status byte)
              if (masterData.length >= 4) {
                final statusByte = masterData.substring(2); // Last 2 chars = "CD"
                final statusValue = int.parse(statusByte, radix: 16); // CD = 205
                
                // Bit 4 (0x10 = 16) = ALARM LED (inverted: 0=ON, 1=OFF)
                hasMasterAlarm = (statusValue & 0x10) == 0;
                
                // 🔥 Bit 3 (0x08 = 8) = TROUBLE LED (inverted: 0=ON, 1=OFF)
                hasMasterTrouble = (statusValue & 0x08) == 0;
                
                // 🔥 Bit 1 (0x02 = 2) = SILENCED (inverted: 0=ON, 1=OFF)
                hasMasterSilenced = (statusValue & 0x02) == 0;
                
                print('🔥 MASTER DATA: $masterData, StatusByte: $statusByte (0x${statusValue.toRadixString(16)}), ALARM: $hasMasterAlarm, TROUBLE: $hasMasterTrouble, SILENCED: $hasMasterSilenced');
              }
            }
            
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

      // 🔥 USE MASTER DATA if available, otherwise fall back to zone count
      final systemStatus = UnifiedSystemStatus(
        hasAlarm: masterData != null ? hasMasterAlarm : (alarmZones > 0),
        hasTrouble: masterData != null ? hasMasterTrouble : (troubleZones > 0),
        hasPower: connectedDevices > 0,
        isSilenced: masterData != null ? hasMasterSilenced : false,
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
          if (masterData != null && hasMasterAlarm) 'MASTER LED ALARM ON',
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

    // 🔥 CRITICAL FIX: Remove STX control character (0x02) if present at beginning
    // The split by <STX> leaves the actual STX byte at start of each segment
    String cleanData = deviceData;
    if (cleanData.isNotEmpty && cleanData.codeUnitAt(0) == 2) {
      cleanData = cleanData.substring(1); // Remove STX byte
    }

    // Now extract status data (skip 2-digit device address)
    if (cleanData.length < 2) return zones;
    
    final statusData = cleanData.substring(2);
    if (statusData.length < 4) { // Assumes offline if no trouble/alarm bytes
        if (deviceNumber <= 5) {
           print('🔍 DEV=$deviceNumber: OFFLINE DETECTED. StatusData="$statusData"');
        }
        for (int i = 1; i <= zonesPerDevice; i++) {
            zones.add(_createZoneStatus(deviceNumber, i, deviceAddress, 'Offline', 0, 0, cleanData));
        }
        return zones;
    }
    
    final troubleValue = int.parse(statusData.substring(0, 2), radix: 16);
    final alarmValue = int.parse(statusData.substring(2, 4), radix: 16);

    for (int i = 1; i <= zonesPerDevice; i++) {
      zones.add(_createZoneStatus(deviceNumber, i, deviceAddress, statusData, troubleValue, alarmValue, cleanData));
    }
    return zones;
  }

  UnifiedZoneStatus _createZoneStatus(int deviceNumber, int zoneInDevice, String deviceAddress, String statusData, int troubleValue, int alarmValue, String rawDeviceData) {
      final int bitPosition = zoneInDevice - 1;
      final bool hasAlarm = (alarmValue & (1 << bitPosition)) != 0;
      final bool hasTrouble = (troubleValue & (1 << bitPosition)) != 0;
      final bool hasBellActive = (alarmValue & 0x20) != 0;
      
      String status = 'Normal';
      Color color = Colors.white;

      if (statusData == 'Offline') {
          status = 'Offline';
          color = Colors.grey;
      } else if (hasAlarm) {
          status = 'Alarm';
          color = Colors.red;
      } else if (hasTrouble) {
          status = 'Trouble';
          color = Colors.orange;
      }

      return UnifiedZoneStatus(
        zoneNumber: (deviceNumber - 1) * zonesPerDevice + zoneInDevice,
        status: status,
        description: 'Zone $zoneInDevice',
        color: color,
        deviceAddress: deviceAddress,
        deviceNumber: deviceNumber,
        zoneInDevice: zoneInDevice,
        timestamp: DateTime.now(),
        hasBellActive: hasBellActive,
        rawData: rawDeviceData,
      );
  }

  String _determineSystemContext(int alarmZones, int troubleZones, int connectedDevices) {
    if (connectedDevices == 0) return 'SYSTEM OFFLINE';
    if (alarmZones > 0) return 'ALARM ACTIVE';
    if (troubleZones > 0) return 'TROUBLE CONDITION';
    return 'SYSTEM NORMAL';
  }

  String? _extractSlaveAddress(String segment) {
    if (segment.isEmpty) return null;
    
    String cleanSegment = segment;
    // Check for STX (0x02) at start and remove it
    if (cleanSegment.codeUnitAt(0) == 2) {
      if (cleanSegment.length < 2) return null;
      cleanSegment = cleanSegment.substring(1);
    }
    
    if (cleanSegment.length < 2) return null;
    
    final address = cleanSegment.substring(0, 2);
    final addressNum = int.tryParse(address);
    if (addressNum != null && addressNum >= 1 && addressNum <= totalDevices) {
      return address;
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
