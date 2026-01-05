# Clean Code Refactoring Guide

## Overview

This document provides clean code principles and refactoring guidelines for the DDS Offline Monitoring project.

---

## 1. Meaningful Naming Conventions

### ✅ GOOD Names

```dart
// ✅ Clear and descriptive
int totalActiveZones = 0;
bool isWebSocketConnected = false;
Future<void> loadZoneConfiguration() async {}
ZoneStatus getZoneByNumber(int zoneNumber) {}

// ✅ Boolean variables use "is", "has", "should"
bool isConnected;
bool hasActiveAlarms;
bool shouldRefresh;

// ✅ Constants use UPPER_SNAKE_CASE
const int MAX_RETRY_ATTEMPTS = 3;
const double DEFAULT_TIMEOUT_SECONDS = 30.0;

// ✅ Classes use PascalCase
class ZoneStatus {}
class WebSocketManager {}

// ✅ Methods use camelCase with verbs
void updateZoneStatus() {}
String getZoneName() {}
bool checkConnection() {}
```

### ❌ BAD Names (Avoid These)

```dart
// ❌ Abbreviations - unclear
int tz = 0;  // What is tz?
bool wsCon = false;

// ❌ Single letter variables (except loop counters)
int a = 0;
bool b = true;
for (int i = 0; i < 10; i++) {  // ✅ 'i' is OK for loops
  // ...
}

// ❌ Magic numbers
if (zoneCount > 315) {  // ❌ What is 315?

// ❌ Misleading names
List<ZoneStatus> getZoneList() {  // ❌ Returns Map, not List!
  return _zoneStatus.values.toList();
}

// ❌ Redundant prefixes
ZoneStatus zoneStatus  // ❌ Don't repeat type name
```

### 🎯 Refactoring Examples

#### Example 1: Variable Names

**BEFORE:**
```dart
// Bad - unclear abbreviations
int tz = 0;
bool wsCon = false;
String pn = '';
int nom = 63;
```

**AFTER:**
```dart
// Good - clear and descriptive
int totalZones = 0;
bool isWebSocketConnected = false;
String projectName = '';
int numberOfModules = 63;
```

#### Example 2: Method Names

**BEFORE:**
```dart
// Bad - unclear what it does
void proc() {}
void getZone(int z) {}
bool chk() {}
```

**AFTER:**
```dart
// Good - clear verb + noun
void processZoneData() {}
ZoneStatus? getZoneByNumber(int zoneNumber) {}
bool checkConnectionStatus() {}
```

#### Example 3: Boolean Names

**BEFORE:**
```dart
// Bad - unclear
bool connection = false;
bool reset = false;
bool loading = false;
```

**AFTER:**
```dart
// Good - uses "is", "has", "should"
bool isConnectionActive = false;
bool isSystemResetting = false;
bool isLoading = false;
bool hasActiveAlarms = false;
bool shouldAutoReconnect = false;
```

---

## 2. Keep Methods Short and Focused

### Principles

1. **Single Responsibility** - Each method should do ONE thing
2. **Maximum 20-30 lines** - Break down if longer
3. **Maximum 3-4 parameters** - Use objects for more
4. **Clear naming** - Method name should describe WHAT it does

### ✅ GOOD Methods

```dart
// ✅ Short and focused
bool isActiveZone(int zoneNumber) {
  return _activeZones.contains(zoneNumber);
}

// ✅ Clear purpose, readable
void updateZoneStatus(int zoneNumber, ZoneStatus newStatus) {
  if (!_isValidZoneNumber(zoneNumber)) {
    return;
  }

  _zoneStatus[zoneNumber] = newStatus;
  _notifyZoneUpdate(zoneNumber);
}

// ✅ Break down complex logic
void processAlarmData(String rawData) {
  final parsedData = _parseAlarmData(rawData);
  final validatedData = _validateData(parsedData);
  _updateZoneStatuses(validatedData);
  _triggerNotifications(validatedData);
}
```

### ❌ BAD Methods (Too Long/Complex)

```dart
// ❌ Too long, doing too many things
void processZoneData(String data) {
  // 50+ lines of parsing, validation, updating, notifying...
  // This should be broken down!
}

// ❌ Too many parameters
void updateZone(
  int zoneNumber,
  String name,
  String status,
  bool isActive,
  DateTime timestamp,
  String deviceAddress,
  int moduleNumber,
  String user
) {
  // Use a data class instead!
}

// ❌ Nested logic - hard to read
void checkZones() {
  for (var device in devices) {
    for (var zone in device.zones) {
      if (zone.status == 'alarm') {
        if (zone.isActive) {
          if (zone.hasTrouble) {
            // Deep nesting!
          }
        }
      }
    }
  }
}
```

### 🎯 Refactoring Examples

#### Example 1: Break Down Long Method

**BEFORE:**
```dart
// ❌ 50+ lines, doing too many things
void processWebSocketMessage(String message) {
  try {
    final data = jsonDecode(message);
    if (data['type'] == 'zone_update') {
      for (var zoneData in data['zones']) {
        final zoneNumber = zoneData['number'];
        final status = ZoneStatus.fromJson(zoneData);
        _zoneStatus[zoneNumber] = status;
        if (status.isAlarm || status.isTrouble) {
          _activeAlarms.add(zoneNumber);
          _updateUI();
          _sendNotification(status);
          if (status.isAlarm) {
            _logAlarm(zoneNumber, status);
          }
        }
      }
    }
  } catch (e) {
    print('Error: $e');
  }
}
```

**AFTER:**
```dart
// ✅ Broken down into focused methods
void processWebSocketMessage(String message) {
  try {
    final messageData = _parseMessage(message);
    _handleZoneUpdate(messageData);
  } catch (e) {
    _handleParsingError(e);
  }
}

Map<String, dynamic> _parseMessage(String message) {
  return jsonDecode(message) as Map<String, dynamic>;
}

void _handleZoneUpdate(Map<String, dynamic> data) {
  if (data['type'] != 'zone_update') return;

  final zones = data['zones'] as List;
  for (var zoneData in zones) {
    _updateSingleZone(zoneData);
  }
}

void _updateSingleZone(Map<String, dynamic> zoneData) {
  final zoneNumber = zoneData['number'] as int;
  final status = ZoneStatus.fromJson(zoneData);

  _zoneStatus[zoneNumber] = status;

  if (status.needsAttention) {
    _handleAlertZone(zoneNumber, status);
  }
}

void _handleAlertZone(int zoneNumber, ZoneStatus status) {
  _activeAlarms.add(zoneNumber);
  _updateUI();
  _sendNotification(status);

  if (status.isAlarm) {
    _logAlarm(zoneNumber, status);
  }
}
```

#### Example 2: Use Parameter Objects

**BEFORE:**
```dart
// ❌ Too many parameters
void updateZone(
  int number,
  String name,
  String status,
  bool isActive,
  DateTime timestamp,
  String device,
  int module
) { }
```

**AFTER:**
```dart
// ✅ Use a parameter object
void updateZone(ZoneUpdateData data) {
  _zoneStatus[data.number] = ZoneStatus(
    number: data.number,
    name: data.name,
    status: data.status,
    isActive: data.isActive,
    timestamp: data.timestamp,
  );
}

class ZoneUpdateData {
  final int number;
  final String name;
  final String status;
  final bool isActive;
  final DateTime timestamp;
  final String deviceAddress;
  final int moduleNumber;

  ZoneUpdateData({
    required this.number,
    required this.name,
    required this.status,
    required this.isActive,
    required this.timestamp,
    required this.deviceAddress,
    required this.moduleNumber,
  });
}
```

---

## 3. Comment Wisely

### When to Add Comments

**✅ ADD Comments For:**

1. **Complex business logic**
```dart
// Bitmap Status Encoding:
// Bit 6 (0x40): AC Power (0=ON, 1=OFF)
// Bit 5 (0x20): DC Power (0=ON, 1=OFF)
// Bit 4 (0x10): Alarm    (0=ON, 1=OFF)
// Bit 3 (0x08): Trouble  (0=ON, 1=OFF)
bool isSystemNormal(int bitmap) {
  return (bitmap & 0xF8) == 0;
}
```

2. **Why something is done (not what)**
```dart
// Use polling instead of WebSocket for compatibility
// with older ESP32 firmware versions (< 2.0)
Future<void> fetchZoneStatus() async {
  return _legacyApi.getZones();
}
```

3. **TODO/FIXME/HACK markers**
```dart
// TODO: Implement exponential backoff for retries
// FIXME: This causes memory leak on large datasets
// HACK: Temporary workaround for ESP32 bug #123
```

4. **Algorithm explanations**
```dart
/// Implements binary search for O(log n) zone lookup.
///
/// Precondition: zones must be sorted by number
/// Returns: Zone number or -1 if not found
int findZone(List<Zone> zones, int targetNumber) { }
```

**❌ DON'T Add Comments For:**

1. **Stating the obvious**
```dart
// ❌ Bad - comment repeats code
int zoneCount = 0;  // Set zone count to zero

// ✅ Better - no comment needed
int zoneCount = 0;
```

2. **Explaining bad code - FIX IT INSTEAD**
```dart
// ❌ Bad: Don't document bad code, fix it!
// This is O(n²) but we can't change it now
void findAllDuplicates(List items) {
  for (var i in items) {
    for (var j in items) {  // O(n²) nested loop
      // ...
    }
  }
}

// ✅ Better: Fix the code or use Set
void findAllDuplicates(List items) {
  final seen = Set<dynamic>();
  for (var item in items) {
    if (seen.contains(item)) {
      duplicates.add(item);
    }
    seen.add(item);
  }
}
```

3. **Commented-out code**
```dart
// ❌ Bad: Delete dead code, don't comment it
// void oldMethod() {
//   // This is deprecated but we keep it just in case
// }
```

### Documentation Comments

**Class Documentation:**
```dart
/// Manages fire alarm zone data and WebSocket connections.
///
/// This class serves as the single source of truth for all zone-related
/// data in the application. It handles:
/// - Zone status updates from WebSocket
/// - Zone name persistence
/// - LED status management
///
/// Example usage:
/// ```dart
/// final fireAlarmData = FireAlarmData();
/// await fireAlarmData.initialize();
/// fireAlarmData.processZoneData(rawData);
/// ```
///
/// See also:
/// - [BellManager] for bell-related functionality
/// - [WebSocketModeManager] for connection management
class FireAlarmData extends ChangeNotifier {
  // ...
}
```

**Method Documentation:**
```dart
/// Gets the current status of a specific zone.
///
/// Parameters:
/// - [zoneNumber]: The global zone number (1-315)
///
/// Returns:
/// - [ZoneStatus] if zone exists
/// - `null` if zone number is invalid or not found
///
/// Throws:
/// - [ArgumentError] if zoneNumber is out of range (not 1-315)
///
/// Example:
/// ```dart
/// final zone = fireAlarmData.getZoneByNumber(5);
/// if (zone != null) {
///   print('Zone 5: ${zone.status}');
/// }
/// ```
ZoneStatus? getZoneByNumber(int zoneNumber) {
  if (zoneNumber < 1 || zoneNumber > numberOfZones) {
    throw ArgumentError('Invalid zone number: $zoneNumber');
  }

  return _zoneStatus[zoneNumber];
}
```

---

## 4. Code Organization

### Class Structure

```dart
/// Class documentation
class MyClass {
  // 1. Static constants
  static const int MAX_VALUE = 100;

  // 2. Public properties (getters first)
  final String id;
  String get displayName => _name;

  // 3. Private properties
  String _name;
  bool _isLoading;

  // 4. Constructor
  MyClass({required this.id, String? name}) : _name = name ?? '';

  // 5. Public methods (grouped by functionality)

  // Lifecycle methods
  void init() { }
  void dispose() { }

  // Data access methods
  String getData() { }
  void updateData(String data) { }

  // UI methods
  void refresh() { }

  // 6. Private methods (after public)
  void _validateData() { }
  void _notifyListeners() { }

  // 7. Nested types (if any)
  class NestedClass { }
}
```

---

## 5. DRY Principle (Don't Repeat Yourself)

### ❌ BAD: Repeated Code

```dart
// ❌ Same logic repeated 3 times
void updateZone1() {
  _zone1.status = 'active';
  _zone1.timestamp = DateTime.now();
  _zone1.lastUpdateBy = 'system';
  notifyListeners();
}

void updateZone2() {
  _zone2.status = 'active';
  _zone2.timestamp = DateTime.now();
  _zone2.lastUpdateBy = 'system';
  notifyListeners();
}

void updateZone3() {
  _zone3.status = 'active';
  _zone3.timestamp = DateTime.now();
  _zone3.lastUpdateBy = 'system';
  notifyListeners();
}
```

### ✅ GOOD: Extract Common Logic

```dart
// ✅ Single reusable method
void updateZone(Zone zone) {
  zone.status = 'active';
  zone.timestamp = DateTime.now();
  zone.lastUpdateBy = 'system';
  notifyListeners();
}

// Usage
void updateAllZones() {
  for (var zone in _zones) {
    updateZone(zone);
  }
}
```

---

## 6. Error Handling

### ✅ GOOD Error Handling

```dart
// ✅ Specific error handling
Future<List<Zone>> fetchZones() async {
  try {
    final response = await _api.getZones();
    return response.map((data) => Zone.fromJson(data)).toList();
  } on SocketException catch (e) {
    throw NetworkException('Network error: ${e.message}');
  } on FormatException catch (e) {
    throw DataParseException('Invalid data format: ${e.message}');
  } catch (e) {
    throw UnknownException('Unexpected error: $e');
  }
}

// ✅ Guard clauses for validation
ZoneStatus? getZone(int zoneNumber) {
  // Guard clause - early return
  if (zoneNumber < 1 || zoneNumber > numberOfZones) {
    return null;
  }

  return _zoneStatus[zoneNumber];
}
```

---

## 7. Constants vs Magic Numbers

### ❌ BAD: Magic Numbers

```dart
// ❌ What do these numbers mean?
if (zoneCount > 315) {
  throw Exception('Too many zones');
}

if (status == 0x10) {
  // Handle alarm
}
```

### ✅ GOOD: Named Constants

```dart
// ✅ Clear, self-documenting
const int MAX_ZONES = 315;
const int LED_ALARM_BIT = 0x10;
const int LED_TROUBLE_BIT = 0x08;

if (zoneCount > MAX_ZONES) {
  throw Exception('Too many zones (max: $MAX_ZONES)');
}

if (status & LED_ALARM_BIT != 0) {
  _handleAlarm();
}
```

---

## 8. Async/Await Best Practices

### ✅ GOOD Async Code

```dart
// ✅ Proper error handling
Future<void> loadConfiguration() async {
  try {
    final config = await _loadConfig();
    await _validateConfig(config);
    _applyConfig(config);
  } catch (e) {
    _handleError(e);
  }
}

// ✅ Async generator
Stream<ZoneStatus> watchZoneStatus(int zoneNumber) async* {
  while (_isMonitoring) {
    yield await _getZoneStatus(zoneNumber);
    await Future.delayed(Duration(seconds: 1));
  }
}
```

---

## 9. String Interpolation vs Concatenation

### ❌ BAD: Concatenation

```dart
// ❌ Hard to read
String message = 'Zone ' + zoneNumber.toString() + ' has status ' + status;
```

### ✅ GOOD: Interpolation

```dart
// ✅ Clear and readable
String message = 'Zone $zoneNumber has status $status';

// ✅ Multi-line with triple quotes
String detailedMessage = '''
Zone Information:
  Number: $zoneNumber
  Status: $status
  Last Update: $timestamp
''';
```

---

## 10. Collection Operations

### ✅ GOOD Collection Usage

```dart
// ✅ Filter - clear intent
final activeZones = zones.where((z) => z.isActive).toList();

// ✅ Map - transform data
final zoneNames = zones.map((z) => z.name).toList();

// ✅ Fold/Reduce - aggregate
final totalAlarms = zones.fold(
  0,
  (sum, zone) => sum + (zone.isAlarm ? 1 : 0),
);

// ✅ Any/Every - check conditions
bool hasActiveAlarms = zones.any((z) => z.isAlarm);
bool allZonesNormal = zones.every((z) => z.isNormal);

// ❌ BAD: Manual loops when collection methods exist
var activeZones = [];
for (var zone in zones) {
  if (zone.isActive) {
    activeZones.add(zone);
  }
}
```

---

## Refactoring Checklist

Use this checklist when reviewing code:

- [ ] All variables have clear, descriptive names
- [ ] Boolean variables use "is", "has", "should" prefix
- [ ] Methods are short (< 30 lines ideally)
- [ ] Methods have single responsibility
- [ ] No magic numbers (use constants)
- [ ] Comments explain "why" not "what"
- [ ] No dead/commented-out code
- [ ] Complex logic has documentation
- [ ] Error handling is specific
- [ ] No code duplication (DRY principle)
- [ ] Collections use appropriate methods (map, filter, etc.)
- [ ] Async code has proper error handling
- [ ] Class structure is organized (constants → properties → constructor → methods)

---

## Tools & Automation

### VSCode Extensions

1. **Dart** - Official Dart language support
2. **Awesome Flutter Snippets** - Code snippets
3. **Todo Tree** - Track TODO comments
4. **Error Lens** - Inline error display

### Dart Analyzers

Enable strict analysis in `analysis_options.yaml`:

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  strong-mode:
    implicit-casts: false
    implicit-dynamic: false

  errors:
    # Treat warnings as errors
    missing_return: error
    dead_code: error
    unused_import: error

  exclude:
    - '**/*.g.dart'
    - '**/*.freezed.dart'
```

---

## Quick Reference

### Naming Quick Reference

| Type | Convention | Example |
|------|------------|---------|
| Classes | PascalCase | `ZoneManager`, `WebSocketService` |
| Methods | camelCase | `getZoneData()`, `updateStatus()` |
| Variables | camelCase | `totalZones`, `isActive` |
| Constants | UPPER_SNAKE_CASE | `MAX_RETRY_COUNT` |
| Private members | prefix `_` | `_internalMethod()`, `_privateVar` |
| Booleans | prefix `is/has/should` | `isValid`, `hasData` |

### Method Length Guidelines

| Lines | Action |
|-------|--------|
| 1-10 | ✅ Perfect |
| 11-20 | ✅ Good |
| 21-30 | ⚠️ Consider breaking down |
| 31+ | ❌ Should refactor |

### Comments Quick Reference

| Type | When to Use |
|------|-------------|
| `///` | Public API documentation |
| `//` | Inline explanations |
| `/* */` | Rarely - only for multi-line comments |
| `// TODO:` | Future work needed |
| `// FIXME:` | Bug that needs fixing |
| `// HACK:` | Temporary workaround |

---

## Conclusion

Clean code is not about following rules blindly—it's about writing code that:
1. Is **easy to understand**
2. Is **easy to maintain**
3. Is **easy to test**
4. **Communicates intent** clearly

Remember: **Code is read much more often than it is written.** Invest time in making it readable!

---

**Last Updated:** 2025-01-04
**Version:** 1.0
