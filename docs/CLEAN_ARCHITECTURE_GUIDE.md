# Clean Architecture Guide - DDS Offline Monitoring

## Table of Contents
- [Overview](#overview)
- [Architecture Structure](#architecture-structure)
- [Layer-by-Layer Explanation](#layer-by-layer-explanation)
- [Dependency Rules](#dependency-rules)
- [File Mapping](#file-mapping)
- [Implementation Examples](#implementation-examples)

---

## Overview

This document explains the Simplified Layered Architecture implementation for the DDS Offline Monitoring project. This architecture follows clean architecture principles while maintaining practicality for a Flutter project that is already in development.

### Why This Architecture?

1. **Separation of Concerns** - UI, business logic, and data handling are separated
2. **Testability** - Each layer can be tested independently
3. **Scalability** - Easy to add new features without breaking existing code
4. **Maintainability** - Clear structure makes it easy to find and fix bugs
5. **Flexibility** - Easy to swap implementations (e.g., WebSocket → MQTT)

---

## Architecture Structure

### High-Level Structure


```
lib/
├── core/                   # Layer 0: Foundation
├── data/                   # Layer 1: Data Implementation
├── domain/                 # Layer 2: Business Logic
├── presentation/           # Layer 3: UI & State Management
├── shared/                 # Cross-cutting utilities
└── main.dart              # Entry point
```

### Detailed Folder Structure

```
lib/
├── core/
│   ├── constants/         # App-wide constants
│   ├── config/            # Configuration & DI
│   ├── error/             # Error handling
│   ├── theme/             # App themes
│   └── utils/             # Core utilities
│
├── data/
│   ├── models/            # Data Transfer Objects (DTOs)
│   ├── datasources/       # Data sources (WebSocket, Local, etc.)
│   ├── repositories/      # Repository implementations
│   └── services/          # Business logic services
│
├── domain/
│   ├── entities/          # Business entities (pure Dart)
│   └── repositories/      # Repository interfaces (abstractions)
│
├── presentation/
│   ├── pages/             # Full-screen pages
│   ├── widgets/           # Reusable widgets
│   └── providers/         # State management (Provider/Bloc)
│
├── shared/                # Shared utilities across layers
│   ├── validators.dart
│   ├── formatters.dart
│   └── helpers.dart
│
└── main.dart
```

---

## Layer-by-Layer Explanation

### Layer 0: Core (Foundation)

**Purpose:** App-level utilities, configuration, and constants that are used throughout the application.

```
lib/core/
├── constants/
│   ├── app_constants.dart           # General app constants
│   ├── websocket_constants.dart     # WebSocket-related constants
│   └── ui_constants.dart            # UI dimensions, margins
│
├── config/
│   ├── app_config.dart              # App environment configuration
│   └── dependency_injection.dart    # GetIt service locator setup
│
├── error/
│   ├── exceptions.dart              # Custom exception classes
│   └── failures.dart                # Failure types for error handling
│
├── theme/
│   ├── app_colors.dart              # Color palette
│   ├── app_text_styles.dart         # Typography definitions
│   └── app_theme.dart               # Complete Material theme
│
└── utils/
    ├── date_utils.dart              # Date formatting utilities
    ├── network_utils.dart           # Network-related helpers
    └── permission_utils.dart        # Permission handlers
```

**Rules:**
- ✅ Only contain GENERAL utilities (not feature-specific)
- ✅ No dependencies on other layers
- ❌ No business logic in this layer

---

### Layer 1: Data (Implementation)

**Purpose:** Manages data from various sources (WebSocket, Local Storage, etc.) and implements repository interfaces defined in the domain layer.

```
lib/data/
├── models/                          # Data Transfer Objects (DTOs)
│   ├── zone_model.dart              # Zone data model with JSON parsing
│   ├── device_model.dart            # Device data model
│   └── system_status_model.dart     # System status model
│
├── datasources/                     # Data sources
│   ├── websocket/                   # WebSocket-based sources
│   │   ├── websocket_service.dart   # Low-level WebSocket client
│   │   ├── fire_alarm_websocket_manager.dart  # WebSocket manager
│   │   └── websocket_datasource.dart  # Repository's WebSocket source
│   ├── local/                       # Local storage sources
│   │   ├── zone_name_local_storage.dart
│   │   ├── offline_settings_service.dart
│   │   ├── exit_password_service.dart
│   │   ├── zone_mapping_service.dart
│   │   └── websocket_settings_service.dart
│   └── remote/                      # Future API sources
│       └── api_datasource.dart
│
├── repositories/                    # Implements domain interfaces
│   ├── zone_repository_impl.dart    # Implementation of ZoneRepository
│   ├── device_repository_impl.dart  # Implementation of DeviceRepository
│   └── system_status_repository_impl.dart
│
└── services/                        # Business logic services
    ├── bell_manager.dart            # Bell management service
    ├── auto_refresh_service.dart    # Auto-refresh logic
    ├── enhanced_zone_parser.dart    # Zone parsing service
    ├── websocket_mode_manager.dart  # WebSocket mode switching
    ├── unified_ip_service.dart      # IP configuration service
    ├── connection_health_service.dart
    ├── offline_performance_manager.dart
    └── other services...
```

**Rules:**
- ✅ Models are DTOs (can contain JSON parsing logic)
- ✅ DataSources know implementation details (WebSocket, SharedPreferences)
- ✅ Repositories implement interfaces from domain layer
- ✅ Services contain feature-specific business logic
- ❌ No UI code in this layer
- ❌ No dependencies on presentation layer

---

### Layer 2: Domain (Business Logic)

**Purpose:** The core of the application - business logic and entities. This layer is independent of frameworks, UI, and data sources.

```
lib/domain/
├── entities/                        # Business objects (pure Dart)
│   ├── zone_entity.dart             # Clean Zone entity
│   ├── device_entity.dart           # Clean Device entity
│   └── system_status_entity.dart    # Clean SystemStatus entity
│
└── repositories/                    # Repository interfaces (abstractions)
    ├── zone_repository.dart         # Abstract interface
    ├── device_repository.dart       # Abstract interface
    └── system_status_repository.dart
```

**Rules:**
- ✅ Entities are pure Dart classes (no Flutter/framework dependencies)
- ✅ Repositories are only interfaces (no implementation)
- ✅ No knowledge of data sources (WebSocket? API? LocalStorage?)
- ❌ No dependencies on external packages (except basic Dart)
- ❌ No UI code

**Entity vs Model Example:**

```dart
// ❌ data/models/zone_model.dart (DTO - Data Transfer Object)
class ZoneModel {
  final String name;
  final String status;
  final String timestamp; // String from JSON

  ZoneModel.fromJson(Map<String, dynamic> json)
    : name = json['zone_name'],
      status = json['status'],
      timestamp = json['timestamp'];

  Map<String, dynamic> toJson() => {...};
}

// ✅ domain/entities/zone_entity.dart (Business Entity)
class ZoneEntity {
  final String name;
  final ZoneStatus status;  // Enum
  final DateTime timestamp; // DateTime object

  const ZoneEntity({
    required this.name,
    required this.status,
    required this.timestamp,
  });
}

enum ZoneStatus {
  normal,
  alarm,
  trouble,
  disabled,
}
```

---

### Layer 3: Presentation (UI)

**Purpose:** All UI-related code including pages, widgets, and state management.

```
lib/presentation/
├── pages/                           # Full-screen pages
│   ├── monitoring/                 # Monitoring feature pages
│   │   ├── offline_monitoring_page.dart
│   │   ├── full_monitoring_page.dart
│   │   ├── zone_monitoring.dart
│   │   ├── tab_monitoring.dart
│   │   └── websocket_debug_page.dart
│   ├── connection/                 # Connection setup pages
│   │   └── connection_config_page.dart
│   ├── control/                    # Control panel
│   │   └── control_page.dart
│   └── auth/                       # Authentication pages
│       └── login_page.dart
│
├── widgets/                        # Reusable widgets
│   ├── zone_detail_dialog.dart     # Zone detail dialog
│   ├── unified_status_bar.dart     # Status bar widget
│   ├── websocket_status_indicator.dart
│   ├── bell_status_widget.dart
│   ├── blinking_tab_header.dart
│   ├── websocket_toggle_button.dart
│   ├── esp32_ip_dialog.dart
│   ├── exit_password_dialog.dart
│   └── restart_app_widget.dart
│
└── providers/                      # State management
    ├── fire_alarm_data_provider.dart  # Main state provider
    └── bell_provider.dart             # Bell state provider
```

**Rules:**
- ✅ Can depend on domain layer (entities, repositories)
- ✅ Can depend on data layer (via dependency injection)
- ✅ State management (Provider/Bloc/Cubit) goes here
- ❌ No heavy business logic (move to domain/data layers)
- ❌ No direct access to WebSocket/SharedPreferences (use repositories)

---

### Shared Layer

**Purpose:** Utilities and helpers that are used across multiple layers.

```
lib/shared/
├── validators.dart                  # Input validation
│   ├── ip_validator.dart
│   └── password_validator.dart
├── formatters.dart                  # Formatting utilities
│   ├── date_formatter.dart
│   └── zone_name_formatter.dart
└── helpers.dart                     # Helper functions
    ├── zone_status_helper.dart
    └── bitmap_helper.dart           # LED status bitmap decoder
```

---

## Dependency Rules

### Dependency Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    PRESENTATION LAYER                        │
│  (Pages, Widgets, Providers)                                │
└───────────────────────┬─────────────────────────────────────┘
                        │ DEPENDS ON
                        ↓
┌─────────────────────────────────────────────────────────────┐
│                      DOMAIN LAYER                            │
│  (Entities, Repository Interfaces)                          │
│  ⚠️ INDEPENDENT: Does not depend on any other layer!         │
└───────────────────────┬─────────────────────────────────────┘
                        │ DEPENDS ON
                        ↓
┌─────────────────────────────────────────────────────────────┐
│                       DATA LAYER                             │
│  (Models, DataSources, Repositories Impl, Services)         │
└───────────────────────┬─────────────────────────────────────┘
                        │ USES
                        ↓
┌─────────────────────────────────────────────────────────────┐
│                    EXTERNAL SOURCES                          │
│  (WebSocket API, SharedPreferences, Sensors, etc.)          │
└─────────────────────────────────────────────────────────────┘
```

### Golden Rules

1. ✅ **Presentation → Domain** (allowed)
2. ✅ **Presentation → Data** (via dependency injection)
3. ✅ **Data → Domain** (implements interfaces)
4. ❌ **Domain → Data/External** (FORBIDDEN!)
5. ❌ **Domain → Presentation** (FORBIDDEN!)
6. ✅ **All layers → Core** (allowed)

### Dependency Inversion Principle

The domain layer defines interfaces (abstractions), and the data layer provides implementations:

```dart
// ✅ CORRECT: Domain defines interface
// domain/repositories/zone_repository.dart
abstract class ZoneRepository {
  Future<List<ZoneEntity>> getAllZones();
}

// ✅ CORRECT: Data implements interface
// data/repositories/zone_repository_impl.dart
class ZoneRepositoryImpl implements ZoneRepository {
  final WebSocketDataSource _dataSource;

  @override
  Future<List<ZoneEntity>> getAllZones() async {
    final models = await _dataSource.fetchAllZones();
    return models.map((m) => m.toEntity()).toList();
  }
}

// ✅ CORRECT: Presentation uses interface
// presentation/providers/fire_alarm_data_provider.dart
class FireAlarmData extends ChangeNotifier {
  final ZoneRepository _zoneRepository; // Interface, not implementation

  FireAlarmData(this._zoneRepository);
}
```

---

## File Mapping

### From Old Structure → New Structure

#### Core Layer

| Old Location | New Location | File |
|-------------|--------------|------|
| `constants/app_constants.dart` | `core/constants/` | `app_constants.dart` |
| `config/animation_constants.dart` | `core/constants/` | `animation_constants.dart` |
| `config/timing_constants.dart` | `core/constants/` | `timing_constants.dart` |
| `config/ui_constants.dart` | `core/constants/` | `ui_constants.dart` |
| `di/service_locator.dart` | `core/config/` | `dependency_injection.dart` |
| `utils/background_parser.dart` | `core/utils/` | `background_parser.dart` |
| `utils/checksum_utils.dart` | `core/utils/` | `checksum_utils.dart` |
| `utils/file_permission_utils.dart` | `core/utils/` | `file_permission_utils.dart` |
| `utils/memory_manager.dart` | `core/utils/` | `memory_manager.dart` |
| `utils/tablet_responsive_helper.dart` | `core/utils/` | `tablet_responsive_helper.dart` |
| `utils/validation_helpers.dart` | `core/utils/` | `validation_helpers.dart` |

#### Data Layer

| Old Location | New Location | File |
|-------------|--------------|------|
| `models/zone_status.dart` | `data/models/` | `zone_status_model.dart` |
| `services/websocket_service.dart` | `data/datasources/websocket/` | `websocket_service.dart` |
| `services/fire_alarm_websocket_manager.dart` | `data/datasources/websocket/` | `fire_alarm_websocket_manager.dart` |
| `services/zone_name_local_storage.dart` | `data/datasources/local/` | `zone_name_local_storage.dart` |
| `services/offline_settings_service.dart` | `data/datasources/local/` | `offline_settings_service.dart` |
| `services/exit_password_service.dart` | `data/datasources/local/` | `exit_password_service.dart` |
| `services/zone_mapping_service.dart` | `data/datasources/local/` | `zone_mapping_service.dart` |
| `services/websocket_settings_service.dart` | `data/datasources/local/` | `websocket_settings_service.dart` |
| `services/bell_manager.dart` | `data/services/` | `bell_manager.dart` |
| `services/auto_refresh_service.dart` | `data/services/` | `auto_refresh_service.dart` |
| `services/enhanced_zone_parser.dart` | `data/services/` | `enhanced_zone_parser.dart` |
| `services/websocket_mode_manager.dart` | `data/services/` | `websocket_mode_manager.dart` |
| `services/unified_ip_service.dart` | `data/services/` | `unified_ip_service.dart` |
| `services/connection_health_service.dart` | `data/services/` | `connection_health_service.dart` |
| `services/offline_performance_manager.dart` | `data/services/` | `offline_performance_manager.dart` |
| `services/zone_data_parser.dart` | `data/services/` | `zone_data_parser.dart` |
| `services/local_audio_manager.dart` | `data/services/` | `local_audio_manager.dart` |
| `services/button_action_service.dart` | `data/services/` | `button_action_service.dart` |
| `services/background_notification_service.dart` | `data/services/` | `background_notification_service.dart` |
| `services/background_app_service.dart` | `data/services/` | `background_app_service.dart` |

#### Domain Layer

| Old Location | New Location | File |
|-------------|--------------|------|
| (new file) | `domain/entities/` | `zone_entity.dart` |
| (new file) | `domain/entities/` | `device_entity.dart` |
| (new file) | `domain/entities/` | `system_status_entity.dart` |
| (new file) | `domain/repositories/` | `zone_repository.dart` |
| (new file) | `domain/repositories/` | `device_repository.dart` |

#### Presentation Layer

| Old Location | New Location | File |
|-------------|--------------|------|
| `monitoring/offline_monitoring_page.dart` | `presentation/pages/monitoring/` | `offline_monitoring_page.dart` |
| `monitoring/full_monitoring_page.dart` | `presentation/pages/monitoring/` | `full_monitoring_page.dart` |
| `monitoring/zone_monitoring.dart` | `presentation/pages/monitoring/` | `zone_monitoring.dart` |
| `monitoring/tab_monitoring.dart` | `presentation/pages/monitoring/` | `tab_monitoring.dart` |
| `monitoring/websocket_debug_page.dart` | `presentation/pages/monitoring/` | `websocket_debug_page.dart` |
| `config/connection_config_page.dart` | `presentation/pages/connection/` | `connection_config_page.dart` |
| `monitoring/control.dart` | `presentation/pages/control/` | `control_page.dart` |
| `auth/login.dart` | `presentation/pages/auth/` | `login_page.dart` |
| `widgets/zone_detail_dialog.dart` | `presentation/widgets/` | `zone_detail_dialog.dart` |
| `widgets/unified_status_bar.dart` | `presentation/widgets/` | `unified_status_bar.dart` |
| `widgets/websocket_status_indicator.dart` | `presentation/widgets/` | `websocket_status_indicator.dart` |
| `widgets/bell_status_widget.dart` | `presentation/widgets/` | `bell_status_widget.dart` |
| `widgets/blinking_tab_header.dart` | `presentation/widgets/` | `blinking_tab_header.dart` |
| `widgets/websocket_toggle_button.dart` | `presentation/widgets/` | `websocket_toggle_button.dart` |
| `widgets/esp32_ip_dialog.dart` | `presentation/widgets/` | `esp32_ip_dialog.dart` |
| `widgets/exit_password_dialog.dart` | `presentation/widgets/` | `exit_password_dialog.dart` |
| `widgets/restart_app_widget.dart` | `presentation/widgets/` | `restart_app_widget.dart` |
| `core/fire_alarm_data.dart` | `presentation/providers/` | `fire_alarm_data_provider.dart` |

#### Shared Layer

| Old Location | New Location | File |
|-------------|--------------|------|
| `utils/zone_status_utils.dart` | `shared/utils/` | `zone_status_utils.dart` |
| (new file) | `shared/utils/` | `bitmap_helper.dart` |

---

## Implementation Examples

### Example 1: Domain Layer (Independent)

**Entity:**
```dart
// domain/entities/zone_entity.dart
class ZoneEntity {
  final int number;
  final String name;
  final ZoneStatus status;
  final DateTime lastUpdate;

  const ZoneEntity({
    required this.number,
    required this.name,
    required this.status,
    required this.lastUpdate,
  });

  @override
  String toString() =>
      'Zone #$number: $name (${status.name})';
}

enum ZoneStatus {
  normal,
  alarm,
  trouble,
  disabled,
}
```

**Repository Interface:**
```dart
// domain/repositories/zone_repository.dart
abstract class ZoneRepository {
  // Get all zones
  Future<List<ZoneEntity>> getAllZones();

  // Get specific zone
  Future<ZoneEntity?> getZoneByNumber(int number);

  // Watch zones stream
  Stream<List<ZoneEntity>> watchZones();

  // Update zone name
  Future<void> updateZoneName(int number, String newName);
}
```

---

### Example 2: Data Layer (Implementation)

**Model (DTO):**
```dart
// data/models/zone_model.dart
class ZoneModel {
  final int zoneNumber;
  final String zoneName;
  final String status;  // String from JSON
  final String timestamp;

  ZoneModel({
    required this.zoneNumber,
    required this.zoneName,
    required this.status,
    required this.timestamp,
  });

  factory ZoneModel.fromJson(Map<String, dynamic> json) {
    return ZoneModel(
      zoneNumber: json['zone_number'] ?? 0,
      zoneName: json['zone_name'] ?? '',
      status: json['status'] ?? 'normal',
      timestamp: json['timestamp'] ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'zone_number': zoneNumber,
      'zone_name': zoneName,
      'status': status,
      'timestamp': timestamp,
    };
  }

  // Convert model to entity
  ZoneEntity toEntity() {
    return ZoneEntity(
      number: zoneNumber,
      name: zoneName,
      status: _parseStatus(status),
      lastUpdate: DateTime.parse(timestamp),
    );
  }

  ZoneStatus _parseStatus(String status) {
    switch (status.toLowerCase()) {
      case 'alarm': return ZoneStatus.alarm;
      case 'trouble': return ZoneStatus.trouble;
      case 'disabled': return ZoneStatus.disabled;
      default: return ZoneStatus.normal;
    }
  }
}
```

**Repository Implementation:**
```dart
// data/repositories/zone_repository_impl.dart
import '../../domain/entities/zone_entity.dart';
import '../../domain/repositories/zone_repository.dart';
import '../datasources/websocket/websocket_datasource.dart';
import '../models/zone_model.dart';

class ZoneRepositoryImpl implements ZoneRepository {
  final WebSocketDataSource _dataSource;
  final LocalStorageDataSource _localStorage;

  ZoneRepositoryImpl(this._dataSource, this._localStorage);

  @override
  Future<List<ZoneEntity>> getAllZones() async {
    try {
      // Fetch from WebSocket
      final models = await _dataSource.fetchAllZones();

      // Convert models to entities
      return models.map((model) => model.toEntity()).toList();
    } catch (e) {
      // Fallback to local storage
      final cachedModels = await _localStorage.getCachedZones();
      return cachedModels.map((m) => m.toEntity()).toList();
    }
  }

  @override
  Future<ZoneEntity?> getZoneByNumber(int number) async {
    final zones = await getAllZones();
    return zones.firstWhere(
      (zone) => zone.number == number,
      orElse: () => null as ZoneEntity,
    );
  }

  @override
  Stream<List<ZoneEntity>> watchZones() {
    // Stream from WebSocket, convert to entities
    return _dataSource.zoneStream.map(
      (models) => models.map((m) => m.toEntity()).toList()
    );
  }

  @override
  Future<void> updateZoneName(int number, String newName) async {
    await _localStorage.saveZoneName(number, newName);
  }
}
```

---

### Example 3: Presentation Layer (UI)

**Provider (State Management):**
```dart
// presentation/providers/fire_alarm_data_provider.dart
import 'package:flutter/foundation.dart';
import '../../domain/entities/zone_entity.dart';
import '../../domain/repositories/zone_repository.dart';

class FireAlarmData extends ChangeNotifier {
  final ZoneRepository _zoneRepository;  // Interface from domain

  List<ZoneEntity> _zones = [];
  bool _isLoading = false;
  String? _error;

  List<ZoneEntity> get zones => _zones;
  bool get isLoading => _isLoading;
  String? get error => _error;

  FireAlarmData(this._zoneRepository);

  Future<void> loadZones() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _zones = await _zoneRepository.getAllZones();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void listenToZones() {
    _zoneRepository.watchZones().listen(
      (zoneList) {
        _zones = zoneList;
        notifyListeners();
      },
      onError: (error) {
        _error = error.toString();
        notifyListeners();
      },
    );
  }

  ZoneEntity? getZoneByNumber(int number) {
    try {
      return _zones.firstWhere((zone) => zone.number == number);
    } catch (e) {
      return null;
    }
  }
}
```

**Page:**
```dart
// presentation/pages/monitoring/offline_monitoring_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/fire_alarm_data_provider.dart';
import '../../domain/entities/zone_entity.dart';
import '../../widgets/zone_card.dart';  // Reusable widget

class OfflineMonitoringPage extends StatefulWidget {
  const OfflineMonitoringPage({super.key});

  @override
  State<OfflineMonitoringPage> createState() => _OfflineMonitoringPageState();
}

class _OfflineMonitoringPageState extends State<OfflineMonitoringPage> {
  @override
  void initState() {
    super.initState();

    // Load zones on init
    Future.microtask(() {
      context.read<FireAlarmData>().loadZones();
      context.read<FireAlarmData>().listenToZones();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fire Alarm Monitoring'),
      ),
      body: Consumer<FireAlarmData>(
        builder: (context, fireAlarmData, child) {
          // Show loading indicator
          if (fireAlarmData.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          // Show error message
          if (fireAlarmData.error != null) {
            return Center(
              child: Text('Error: ${fireAlarmData.error}'),
            );
          }

          // Show zones
          if (fireAlarmData.zones.isEmpty) {
            return const Center(child: Text('No zones available'));
          }

          // Show zone list
          return ListView.builder(
            itemCount: fireAlarmData.zones.length,
            itemBuilder: (context, index) {
              final zone = fireAlarmData.zones[index];
              return ZoneCard(zone: zone);  // Widget uses entity
            },
          );
        },
      ),
    );
  }
}
```

---

## Benefits of This Architecture

### 1. Scalability
- Easy to add new features without breaking existing code
- Clear structure makes it simple to locate and modify code
- Multiple developers can work on different layers simultaneously

### 2. Testability
- Each layer can be tested independently
- Mock repositories for UI testing
- Mock data sources for business logic testing
- Unit tests for pure domain entities

### 3. Maintainability
- Clear separation of concerns
- Easy to locate bugs (WebSocket issue? → `data/datasources/websocket/`)
- Consistent structure across the project
- Self-documenting code structure

### 4. Flexibility
- Easy to swap implementations:
  - WebSocket → MQTT? Just change datasource
  - SharedPreferences → Hive? Just change datasource
  - Provider → Bloc? Just change provider
- UI remains unchanged when swapping backend

### 5. Team Collaboration
- Clear boundaries prevent conflicts
- New team members can understand structure quickly
- Parallel development on different features

---

## Migration Strategy

### Phase 1: Create Folder Structure
- Create all folders according to the new structure
- Do NOT move files yet

### Phase 2: Move Data Layer
- Move service files to `data/`
- Move models to `data/models/`
- Create datasources folder structure
- Update imports

### Phase 3: Create Domain Layer
- Create entity classes (clean versions of models)
- Create repository interfaces
- Move business logic from services to domain if needed

### Phase 4: Implement Repositories
- Create repository implementations in `data/repositories/`
- Implement interfaces from domain layer
- Use datasources for data access

### Phase 5: Update Presentation Layer
- Move pages to `presentation/pages/`
- Move widgets to `presentation/widgets/`
- Move providers to `presentation/providers/`
- Update to use repository interfaces instead of direct services

### Phase 6: Testing
- Run `flutter analyze` and fix errors
- Test all features
- Fix any runtime issues

---

## Best Practices

### DO's ✅
1. Use dependency injection for all layer boundaries
2. Write tests for business logic in domain layer
3. Keep entities pure (no framework dependencies)
4. Use interfaces (abstract classes) for repositories
5. Document public APIs in domain layer
6. Handle errors at layer boundaries

### DON'Ts ❌
1. Don't let domain layer depend on other layers
2. Don't put business logic in presentation layer
3. Don't access data sources directly from UI
4. Don't mix models (DTOs) with entities
5. Don't skip layers (e.g., UI → DataSource directly)
6. Don't put Flutter-specific code in domain layer

---

## Conclusion

This clean architecture provides a solid foundation for the DDS Offline Monitoring application. It balances theoretical purity with practical needs, making it suitable for real-world Flutter development.

For questions or suggestions about this architecture, please refer to the development team or update this document.

---

**Last Updated:** 2025-01-03
**Version:** 1.0
