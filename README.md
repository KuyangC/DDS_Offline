# DDS OfflineApp - Program Documentation

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [WebSocket Communication](#websocket-communication)
4. [Data Parsing System](#data-parsing-system)
5. [Data Models](#data-models)
6. [State Management](#state-management)
7. [Zone System](#zone-system)
8. [LED Status System](#led-status-system)
9. [Bell System](#bell-system)
10. [File Reference](#file-reference)

---

## Overview

**DDS OfflineApp** is a **Fire Alarm Monitoring System** for offline operation with real-time WebSocket communication to ESP32 fire alarm panels.

### System Specifications

| Specification | Value |
|---------------|-------|
| Total Devices | 63 devices |
| Zones per Device | 5 zones |
| Total Zones | 315 zones |
| Communication | WebSocket (ws://IP:PORT) |
| Framework | Flutter (Dart) |
| State Management | Provider |
| Platform | Android / Windows |

### Features

- Real-time zone status monitoring (315 zones)
- WebSocket auto-reconnect with exponential backoff
- LED status indicators (Alarm, Trouble, Normal, Supervisory)
- Bell activation tracking
- Zone naming and mapping
- Offline mode support
- Activity logging
- Password-protected system exit

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              DDS OFFLINE APP                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐    ┌──────────────────┐    ┌──────────────────────────┐  │
│  │   ESP32     │◄───┤ WebSocketService │◄───┤ FireAlarmWebSocket       │  │
│  │   Panel     │    │ (ws_service)     │    │ Manager                  │  │
│  └─────────────┘    └──────────────────┘    └──────────────────────────┘  │
│                            │                            │                   │
│                            ▼                            ▼                   │
│                   ┌──────────────────┐    ┌──────────────────────────┐     │
│                   │ Raw Hex Data     │    │ FireAlarmData            │     │
│                   │ (6 char/device)  │───▶│ (Provider)               │     │
│                   └──────────────────┘    └──────────────────────────┘     │
│                            │                            │                   │
│                            ▼                            ▼                   │
│                   ┌──────────────────┐    ┌──────────────────────────┐     │
│                   │ UnifiedFireAlarm │    │ ZoneStatus (315 zones)   │     │
│                   │ Parser           │    │ + LED Status             │     │
│                   └──────────────────┘    └──────────────────────────┘     │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         UI LAYER                                     │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │   │
│  │  │ Monitoring   │  │ Zone Config  │  │ Control      │              │   │
│  │  │ Page         │  │ Page         │  │ Page         │              │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Directory Structure

```
lib/
├── core/
│   ├── config/
│   │   └── dependency_injection.dart
│   ├── constants/
│   │   ├── animation_constants.dart
│   │   ├── app_constants.dart
│   │   ├── timing_constants.dart
│   │   └── ui_constants.dart
│   └── utils/
│       ├── background_parser.dart
│       ├── checksum_utils.dart
│       ├── file_permission_utils.dart
│       ├── memory_manager.dart
│       ├── tablet_responsive_helper.dart
│       └── validation_helpers.dart
│
├── data/
│   ├── datasources/
│   │   ├── local/
│   │   │   ├── exit_password_service.dart
│   │   │   ├── offline_settings_service.dart
│   │   │   ├── websocket_settings_service.dart
│   │   │   ├── zone_mapping_service.dart
│   │   │   └── zone_name_local_storage.dart
│   │   └── websocket/
│   │       ├── websocket_service.dart
│   │       └── fire_alarm_websocket_manager.dart
│   ├── models/
│   │   └── zone_status_model.dart
│   └── services/
│       ├── auto_refresh_service.dart
│       ├── background_app_service.dart
│       ├── background_notification_service.dart
│       ├── bell_manager.dart
│       ├── button_action_service.dart
│       ├── connection_health_service.dart
│       ├── enhanced_zone_parser.dart
│       ├── local_audio_manager.dart
│       ├── logger.dart
│       ├── offline_performance_manager.dart
│       ├── unified_fire_alarm_parser.dart
│       ├── unified_ip_service.dart
│       ├── websocket_mode_manager.dart
│       └── zone_data_parser.dart
│
├── presentation/
│   ├── pages/
│   │   ├── auth/
│   │   ├── connection/
│   │   ├── monitoring/
│   │   └── control/
│   ├── providers/
│   │   └── fire_alarm_data_provider.dart
│   └── widgets/
│
├── monitoring/
│   └── monitoring.dart
│
└── main.dart
```

---

## WebSocket Communication

### Connection Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         WEBSOCKET CONNECTION FLOW                            │
└─────────────────────────────────────────────────────────────────────────────┘

  User/App                         WebSocketService                     ESP32
     │                                  │                                 │
     │  connectToESP32(ip)              │                                 │
     ├─────────────────────────────────►│                                 │
     │                                  │                                 │
     │                                  │ 1. Health Check                 │
     │                                  │    ConnectionHealthService      │
     │                                  │    .testConnection(host, port)  │
     │                                  ├────────────────────────────────►│
     │                                  │◄────────────────────────────────┤
     │                                  │                                 │
     │                                  │ 2. Connect WebSocket             │
     │                                  │    WebSocketChannel.connect(uri) │
     │                                  ├────────────────────────────────►│
     │                                  │◄────────────────────────────────┤
     │                                  │                                 │
     │                                  │ 3. Setup Stream Listeners        │
     │                                  │    - messageStream               │
     │                                  │    - statusStream                │
     │                                  │                                 │
     │  Connected!                      │                                 │
     │◄─────────────────────────────────┤                                 │
     │                                  │                                 │
     │                                  │ 4. Listen for messages           │
     │                                  │◄────────────────────────────────┤
     │  Data received                   │  Raw hex data                    │
     │◄─────────────────────────────────┤                                 │
     │                                  │                                 │
     │  5. Auto-reconnect on disconnect (max 10 attempts, exponential backoff)
     │                                  │                                 │
```

### WebSocketService Features

| Feature | Description |
|---------|-------------|
| **Health Check** | Pre-connection test via `ConnectionHealthService` |
| **Auto-Reconnect** | Enabled by default with exponential backoff |
| **Connection Timeout** | 10 seconds |
| **Max Reconnect Attempts** | 10 attempts |
| **Reconnect Delay** | 2s → 4s → 8s → 16s → 30s (max) |
| **Jitter** | ±25% randomization to prevent thundering herd |

### Connection States

```dart
enum WebSocketStatus {
  disconnected,  // Not connected
  connecting,    // Connection in progress
  connected,     // Successfully connected
  error,         // Connection error
  reconnecting,  // Attempting to reconnect
}
```

### Error Types

```dart
enum WebSocketErrorType {
  none,              // No error
  timeout,           // Connection timeout
  connectionRefused, // ESP32 refused connection
  network,           // Network unreachable
  certificate,       // SSL/TLS certificate error
  unknown,           // Unknown error
}
```

### WebSocket URL Format

```
ws://[ESP32_IP]:[PORT]

Example:
ws://192.168.1.100:81
```

### Message Flow

```
ESP32 → WebSocket Channel → _handleMessage() → _messageController
                                                      │
                                                      ▼
                                         WebSocketMessage {
                                           type: data,
                                           data: "raw hex string",
                                           timestamp: DateTime
                                         }
                                                      │
                                                      ▼
                                    FireAlarmWebSocketManager
                                                      │
                                                      ▼
                                         _parseESP32Data() → Filter
                                                      │
                                                      ▼
                                    _updateFireAlarmData()
                                                      │
                                                      ▼
                                    FireAlarmData.processWebSocketData()
```

---

## Data Parsing System

### Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           DATA PARSING PIPELINE                              │
└─────────────────────────────────────────────────────────────────────────────┘

Raw WebSocket Data (e.g., "41DF<STX>010000<STX>020A00...")
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ UnifiedFireAlarmParser.parse()                                               │
│ • Select best parsing strategy based on data patterns                        │
│ • Cache result for quick access                                              │
└─────────────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ Strategy Selection (_selectBestStrategy)                                     │
│                                                                             │
│ 1. Check for <STX>/<ETX> markers + 6-char module → EnhancedZoneParser       │
│ 2. Check for $85/$84 codes → BellConfirmationParser                         │
│ 3. Check for control signals → ControlSignalParser                          │
│ 4. Default → EnhancedZoneParser                                             │
└─────────────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ EnhancedZoneParsingStrategy (Main Parser)                                    │
│                                                                             │
│ Parse format: "41DF<STX>010000<STX>020A00<STX>..."                          │
│                                                                             │
│ • Split by <STX> markers                                                    │
│ • Extract device modules (6 chars each)                                     │
│ • Parse each device into 5 zones                                           │
│ • Handle bell confirmation codes ($85/$84)                                  │
└─────────────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ _parseDeviceZones(deviceData, deviceNumber, deviceAddress)                  │
│                                                                             │
│ Device Format: [Address (2)][Trouble (2)][Alarm (2)] = 6 characters         │
│                                                                             │
│ Example: "010A00"                                                            │
│   Address: "01" (Device 1)                                                  │
│   Trouble: "0A" (hex = 10 decimal = 0000 1010 binary)                       │
│   Alarm:   "00" (hex = 00 decimal = 0000 0000 binary)                       │
└─────────────────────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ _mapZoneStatusFromBytes(troubleByte, alarmByte, zoneIndex)                  │
│                                                                             │
│ Bitwise Zone Decoding:                                                       │
│   Zone 1: Bit 0 (0x01) - Check both trouble & alarm bytes                   │
│   Zone 2: Bit 1 (0x02)                                                      │
│   Zone 3: Bit 2 (0x04)                                                      │
│   Zone 4: Bit 3 (0x08)                                                      │
│   Zone 5: Bit 4 (0x10)                                                      │
│   Bell:   Bit 5 (0x20) - Device-level bell status                           │
│                                                                             │
│ Status Priority: Alarm > Trouble > Normal                                   │
└─────────────────────────────────────────────────────────────────────────────┘
        │
        ▼
UnifiedZoneStatus {
  zoneNumber: 1-315,
  status: 'Alarm' | 'Trouble' | 'Normal' | 'Offline',
  color: Red | Orange | White | Grey,
  hasBellActive: bool,
  ...
}
        │
        ▼
FireAlarmData._zoneStatus[globalZoneNumber] = zoneStatus
        │
        ▼
UI Update (notifyListeners)
```

### ESP32 Data Format

#### Complete Data Stream Format

```
┌──────────┬──────────┬────────────┬────────────┬───────────┬──────────┐
│ Prefix   │ Checksum│   <STX>    │  Device 1  │  <STX>    │ Device 2 │
│ (4 hex)  │ (4 hex) │  Marker    │  (6 hex)   │  Marker   │ (6 hex)  │
├──────────┼──────────┼────────────┼────────────┼───────────┼──────────┤
│   41DF   │   40DF  │    0x02    │   010000   │   0x02    │  020A00  │
└──────────┴──────────┴────────────┴────────────┴───────────┴──────────┘
```

#### Single Device Module Format (6 hex characters)

```
┌────────────────────────────────────────────────────────────┐
│                    DEVICE MODULE (6 chars)                 │
├─────────────────────┬──────────────────┬───────────────────┤
│     Address         │    Trouble       │     Alarm         │
│     (2 hex)         │    (2 hex)       │     (2 hex)       │
├─────────────────────┼──────────────────┼───────────────────┤
│        01           │       0A         │       00          │
│  Device 1 (hex)    │  10 (decimal)   │  00 (decimal)     │
│                    │  0000 1010 (bin)│  0000 0000 (bin)  │
└─────────────────────┴──────────────────┴───────────────────┘

Breakdown:
  Address "01" = Device number 1
  Trouble "0A" = Zones 2 and 4 have trouble
  Alarm   "00" = No alarms
```

#### Bitwise Zone Mapping

```
Trouble Byte:  0x0A = 0000 1010
                          │  │  │  │
                          │  │  │  └── Zone 1: Normal (bit 0 = 0)
                          │  │  └───── Zone 2: Trouble (bit 1 = 1)
                          │  └──────── Zone 3: Normal (bit 2 = 0)
                          └─────────── Zone 4: Trouble (bit 3 = 1)
                                       └─────── Zone 5: Normal (bit 4 = 0)

Alarm Byte:    0x20 = 0010 0000
                          │  │  │  │  │  │
                          │  │  │  │  │  └── Zone 1-5: No alarm (bits 0-4 = 0)
                          │  │  │  │  └───── Zone 5: No alarm (bit 4 = 0)
                          │  │  │  └──────── Zone 4: No alarm (bit 3 = 0)
                          │  │  └─────────── Zone 3: No alarm (bit 2 = 0)
                          │  └────────────── Zone 2: No alarm (bit 1 = 0)
                          └───────────────── Zone 1: No alarm (bit 0 = 0)
                          │
                          └── BELL ACTIVE (bit 5 = 1)
```

#### Zone Status Examples

| Module | Address | Trouble | Alarm | Zone 1 | Zone 2 | Zone 3 | Zone 4 | Zone 5 | Bell |
|--------|---------|---------|-------|--------|--------|--------|--------|--------|------|
| `010000` | 01 | 00 | 00 | Normal | Normal | Normal | Normal | Normal | Off |
| `020A00` | 02 | 0A | 00 | Normal | Trouble | Normal | Trouble | Normal | Off |
| `032020` | 03 | 20 | 20 | Normal | Normal | Normal | Normal | Normal | **On** |
| `043F1F` | 04 | 3F | 1F | Alarm | Alarm | Alarm | Alarm | Alarm | Off |
| `050101` | 05 | 01 | 01 | **Alarm** | Normal | Normal | Normal | Normal | Off |

**Note:** Bell status is from bit 5 (0x20) of the Alarm byte

---

## Data Models

### ZoneStatus Model

Located at: `lib/data/models/zone_status_model.dart`

```dart
class ZoneStatus {
  final int globalZoneNumber;      // 1-315 (unique identifier)
  final int zoneInDevice;          // 1-5 (zone within device)
  final int deviceAddress;         // 1-63 (parent device)

  final bool isActive;             // Zone is configured/active
  final bool hasAlarm;             // Fire alarm condition (Priority 1)
  final bool hasTrouble;           // Trouble condition (Priority 2)
  final bool hasSupervisory;       // Supervisory condition
  final bool hasBellActive;        // Bell activation status

  final String description;        // Custom zone name
  final DateTime lastUpdate;       // Last update timestamp
  final ZoneType zoneType;         // Zone classification
  final Map<String, dynamic> metadata;

  ZoneStatusType get currentStatus { /* Priority logic */ }
  String get statusText { /* Status text */ }
  Color get statusColorKey { /* Color for UI */ }
}
```

### ZoneStatusType Enum

```dart
enum ZoneStatusType {
  inactive,    // Zone not configured/offline (lowest priority)
  normal,      // Zone operational, no issues
  supervisory, // Zone supervisory condition
  trouble,     // Zone trouble/maintenance needed
  alarm,       // Zone fire alarm (highest priority)
}
```

### ZoneType Enum

```dart
enum ZoneType {
  unknown,     // Unknown zone type
  inactive,    // Inactive/disabled zone
  heat,        // Heat detector
  smoke,       // Smoke detector
  manual,      // Manual pull station
  waterflow,   // Water flow switch
  supervisory, // Supervisory device
  trouble,     // Trouble monitoring
  relay,       // Relay output
  input,       // General input
  output,      // General output
}
```

### UnifiedZoneStatus Model

Located at: `lib/data/services/unified_fire_alarm_parser.dart`

```dart
class UnifiedZoneStatus {
  final int zoneNumber;           // 1-315 (global)
  final String status;            // 'Alarm', 'Trouble', 'Normal', 'Offline'
  final String description;       // Zone description
  final Color color;              // Display color
  final String deviceAddress;     // Device address (hex)
  final int deviceNumber;         // Device number (1-63)
  final int zoneInDevice;         // Zone in device (1-5)
  final DateTime timestamp;
  final bool isOffline;           // Device offline status
  final bool hasPower;            // Power status
  final bool hasBellActive;       // Bell status
  final String? rawData;          // Raw data for debugging
}
```

### UnifiedSystemStatus Model

```dart
class UnifiedSystemStatus {
  final bool hasAlarm;             // System has alarm
  final bool hasTrouble;           // System has trouble
  final bool hasPower;             // System has power
  final bool isSilenced;           // System silenced
  final bool isDrill;              // Drill mode active
  final bool isDisabled;           // System disabled
  final bool isSystemOffline;      // All devices offline
  final int connectedDevices;      // Connected device count
  final int disconnectedDevices;   // Disconnected device count
  final int totalAlarmZones;       // Total alarm zones
  final int totalTroubleZones;     // Total trouble zones
  final int totalActiveZones;      // Total active zones
  final String systemContext;      // System status description
  final DateTime timestamp;
  final List<String> activeEvents; // Active event list
}
```

---

## State Management

### FireAlarmData Provider

Located at: `lib/presentation/providers/fire_alarm_data_provider.dart`

**Central state management for fire alarm monitoring system.**

#### Responsibilities

- Store and manage zone status (315 zones)
- Process data from WebSocket
- Manage system status LEDs
- Track bells, alarms, and troubles
- Manage activity logs

#### Key Properties

```dart
class FireAlarmData extends ChangeNotifier {
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

  // Bell tracking per device
  final Map<int, bool> _bellConfirmationStatus = {};

  // Zone accumulation for alarms/troubles
  final Set<int> _accumulatedAlarmZones = {};
  final Set<int> _accumulatedTroubleZones = {};
}
```

#### Key Methods

| Method | Description |
|--------|-------------|
| `processWebSocketData(rawData)` | Process raw WebSocket data |
| `getZoneStatus(globalZoneNumber)` | Get status for specific zone |
| `getAlarmZones()` | Get all zones with alarm |
| `getTroubleZones()` | Get all zones with trouble |
| `setWebSocketConnectionStatus(isConnected)` | Update connection status |
| `getIndividualZoneStatus(zoneNumber)` | Get zone data for UI |
| `reset()` | Reset all state |

#### Data Flow

```
WebSocket Message
       │
       ▼
_fireAlarmWebSocketManager._handleWebSocketMessage()
       │
       ▼
_fireAlarmData.processWebSocketData(rawData)
       │
       ▼
UnifiedFireAlarmParser.parse(rawData)
       │
       ▼
_updateZoneStatuses(parseResult)
       │
       ├─▶ _zoneStatus[zoneNumber] = zoneStatus
       ├─▶ _updateZoneTracking() (bell, accumulation)
       └─▶ _updateSystemLEDStatus()
       │
       ▼
notifyListeners() → UI Update
```

---

## Zone System

### Zone Numbering

```
Global Zone Number = ((deviceAddress - 1) * 5) + zoneInDevice

┌──────────┬────────────────────────────────┐
│ Device   │ Global Zone Numbers            │
├──────────┼────────────────────────────────┤
│ Device 1 │ 1, 2, 3, 4, 5                  │
│ Device 2 │ 6, 7, 8, 9, 10                 │
│ Device 3 │ 11, 12, 13, 14, 15             │
│ ...      │ ...                            │
│ Device 63│ 311, 312, 313, 314, 315        │
└──────────┴────────────────────────────────┘
```

### Zone Status Colors

```dart
// Color mapping by status priority
if (!isActive)      → Colors.grey      // Offline
else if (hasAlarm)  → Colors.red       // ALARM (Priority 1)
else if (hasTrouble)→ Colors.orange    // TROUBLE (Priority 2)
else if (hasSupervisory) → Colors.yellow // SUPERVISORY (Priority 3)
else                → Colors.white     // NORMAL (Priority 4)
```

### Zone Utilities

Located at: `lib/data/models/zone_status_model.dart`

```dart
class ZoneStatusUtils {
  // Calculate global zone number
  static int calculateGlobalZoneNumber(int deviceAddress, int zoneInDevice);

  // Extract device address from global zone number
  static int getDeviceAddress(int globalZoneNumber);

  // Extract zone in device from global zone number
  static int getZoneInDevice(int globalZoneNumber);

  // Validate zone numbers
  static bool isValidZoneNumber(int globalZoneNumber); // 1-315
  static bool isValidDeviceAddress(int deviceAddress); // 1-63
  static bool isValidZoneInDevice(int zoneInDevice);   // 1-5

  // Sort zones by priority
  static List<ZoneStatus> sortByPriority(List<ZoneStatus> zones);

  // Filter zones by status
  static List<ZoneStatus> filterByStatus(List<ZoneStatus> zones, ZoneStatusType status);

  // Count zones by status
  static Map<ZoneStatusType, int> countByStatus(List<ZoneStatus> zones);
}
```

---

## LED Status System

### LED Indicators

| LED | Color | Description | Priority |
|-----|-------|-------------|----------|
| Alarm | Red | Fire alarm active | 1 |
| Trouble | Orange/Yellow | Trouble condition | 2 |
| Supervisory | Yellow | Supervisory condition | 3 |
| Normal | White | System normal | 4 |
| AC Power | Green | AC power on | - |
| DC Power | Green | DC power on | - |

### LED Status Decoding

Located at: `lib/data/services/enhanced_zone_parser.dart`

The LED status is decoded from the master control signal:

```
LED Byte Format (AABBCC):
  AA = Device address
  BB = Trouble/Alarm status
  CC = LED status byte

LED Byte (CC) Bit Mapping (0 = ON, 1 = OFF):
  Bit 0: Disabled
  Bit 1: Silenced
  Bit 2: Drill Active
  Bit 3: Trouble Active
  Bit 4: Alarm Active
  Bit 5: DC Power
  Bit 6: AC Power
  Bit 7: (reserved)
```

#### Example LED Decoding

```
LED Byte: 0x40 = 0100 0000

Bit 6: 0 → AC Power ON
Bit 5: 1 → DC Power OFF
Bit 4: 1 → Alarm OFF
Bit 3: 1 → Trouble OFF
Bit 2: 1 → Drill OFF
Bit 1: 1 → Silenced OFF
Bit 0: 1 → Disabled OFF

Result: Only AC Power LED is ON
```

### LEDStatusData Model

```dart
class LEDStatusData {
  final bool acPowerOn;
  final bool dcPowerOn;
  final bool alarmOn;
  final bool troubleOn;
  final bool drillOn;
  final bool silencedOn;
  final bool disabledOn;
  final DateTime timestamp;
  final String? rawData;
}
```

---

## Bell System

### Bell Confirmation Codes

| Code | Description |
|------|-------------|
| `$85` | Bell ON confirmation |
| `$84` | Bell OFF confirmation |

### Bell Status Detection

Bell status is detected from **bit 5 (0x20)** of the Alarm byte in each device module:

```
Device Module: [Address][Trouble][Alarm]
                           └────┬───┘
                                │
                                └─ Alarm Byte

Alarm Byte: 0x20 = 0010 0000
                   │
                   └── Bit 5 = 1 → Bell ACTIVE for this device
```

### BellManager

Located at: `lib/data/services/bell_manager.dart`

Manages bell state and audio playback for bell notifications.

### Bell Tracking

```dart
// Per-device bell tracking
final Map<int, bool> _bellConfirmationStatus = {};

// Check if device has active bell
bool hasActiveBell(int deviceAddress) {
  return _bellConfirmationStatus[deviceAddress] ?? fal1```
---

## File Reference

### WebSocket Files

| File | Path | Description |
|------|------|-------------|
| WebSocket Service | `lib/data/datasources/websocket/websocket_service.dart` | Core WebSocket connection management |
| Fire Alarm WS Manager | `lib/data/datasources/websocket/fire_alarm_websocket_manager.dart` | Fire alarm WebSocket manager |
| Connection Health | `lib/data/services/connection_health_service.dart` | Pre-connection health check |

### Parsing Files

| File | Path | Description |
|------|------|-------------|
| Unified Parser | `lib/data/services/unified_fire_alarm_parser.dart` | Main parsing orchestrator |
| Enhanced Zone Parser | `lib/data/services/enhanced_zone_parser.dart` | 63-device × 5-zone parser |
| Zone Data Parser | `lib/data/services/zone_data_parser.dart` | Alternative zone parser |
| Checksum Utils | `lib/core/utils/checksum_utils.dart` | Checksum calculation |
| Background Parser | `lib/core/utils/background_parser.dart` | Background parsing for large data |

### Data Model Files

| File | Path | Description |
|------|------|-------------|
| Zone Status Model | `lib/data/models/zone_status_model.dart` | Zone status data structure |

### Provider Files

| File | Path | Description |
|------|------|-------------|
| Fire Alarm Data | `lib/presentation/providers/fire_alarm_data_provider.dart` | Central state management |

### UI Files

| File | Path | Description |
|------|------|-------------|
| Monitoring Page | `lib/presentation/pages/monitoring/offline_monitoring_page.dart` | Main monitoring UI |
| Zone Monitoring | `lib/presentation/pages/monitoring/zone_monitoring.dart` | Zone detail UI |
| Full Monitoring | `lib/presentation/pages/monitoring/full_monitoring_page.dart` | Full grid monitoring |
| Tab Monitoring | `lib/presentation/pages/monitoring/tab_monitoring.dart` | Tab-based monitoring |
| Zone Config | `lib/presentation/pages/connection/zone_name_config_page.dart` | Zone name configuration |
| Connection Config | `lib/presentation/pages/connection/connection_config_page.dart` | Connection settings |

---

## Appendix

### Status Priority Logic

```dart
ZoneStatusType get currentStatus {
  if (!isActive) return ZoneStatusType.inactive;
  if (hasAlarm) return ZoneStatusType.alarm;      // Priority 1: Life safety
  if (hasTrouble) return ZoneStatusType.trouble;  // Priority 2: Maintenance
  if (hasSupervisory) return ZoneStatusType.supervisory; // Priority 3
  return ZoneStatusType.normal;                   // Priority 4
}
```

### System Context Determination

```dart
String _determineSystemContext(
  int alarmZones,
  int troubleZones,
  int connectedDevices,
  Map<String, BellConfirmationStatus> bellConfirmations
) {
  if (connectedDevices == 0) return 'SYSTEM OFFLINE';
  if (alarmZones > 0 && activeBellsCount > 0) return 'ALARM WITH ACTIVE BELLS';
  if (alarmZones > 0 && troubleZones > 0) return 'ALARM WITH TROUBLE CONDITION';
  if (alarmZones > 0) return 'ALARM ACTIVE';
  if (troubleZones > 0) return 'TROUBLE CONDITION';
  if (activeBellsCount > 0) return 'BELL ACTIVE WITHOUT ALARM';
  if (connectedDevices < 63) return 'PARTIAL CONNECTION';
  return 'SYSTEM NORMAL';
}
```

### Constants

```dart
// System Constants
static const int totalDevices = 63;
static const int zonesPerDevice = 5;
static const int totalZones = 315;  // 63 × 5

// Device Module Format
static const int deviceModuleLength = 6;  // chars
static const int addressLength = 2;       // chars
static const int statusLength = 4;        // chars (2 trouble + 2 alarm)

// WebSocket
static const int connectionTimeout = 10;  // seconds
static const int maxReconnectAttempts = 10;
static const Duration baseReconnectDelay = Duration(seconds: 2);
static const Duration maxReconnectDelay = Duration(seconds: 30);
```

---

## Quick Reference

### Parsing Flow Summary

```
Raw WebSocket Data
    ↓
Split by <STX>
    ↓
For each 6-char module:
    ↓
Extract [Address][Trouble][Alarm]
    ↓
For each of 5 zones:
    ↓
Check bit in Trouble byte → hasTrouble
    ↓
Check bit in Alarm byte → hasAlarm
    ↓
Determine status: Alarm > Trouble > Normal
    ↓
Set color: Red > Orange > White
    ↓
Check Bell: (Alarm byte & 0x20) != 0
    ↓
Create UnifiedZoneStatus
    ↓
Store in _zoneStatus[globalZoneNumber]
    ↓
Update UI via notifyListeners()
```

### Status Color Reference

| Status | Color | Hex |
|--------|-------|-----|
| Alarm | Red | `0xFFFF0000` |
| Trouble | Orange | `0xFFFFA500` |
| Supervisory | Yellow | `0xFFFFFF00` |
| Normal | White | `0xFFFFFFFF` |
| Offline/Inactive | Grey | `0xFF808080` |

---

*Document Version: 1.0.0*
*Last Updated: 2025-01-09*
*Generated for DDS OfflineApp Project*
