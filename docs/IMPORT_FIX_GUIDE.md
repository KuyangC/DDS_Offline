# Import Fix Guide - Clean Architecture Migration

## Current Status

✅ **Completed:**
- Folder structure created
- Files moved to new locations
- main.dart fixed
- FireAlarmData provider fixed
- Connection config page fixed

📊 **Errors:** 748 (down from 802)

🎯 **Remaining:** 56 dart files need import path updates

---

## Quick Fix Using VSCode

### Method 1: Find & Replace in Files (RECOMMENDED)

Use VSCode's **Find & Replace in Files** (Ctrl+Shift+H) with these replacements:

#### Batch 1: Core Layer Imports

| Find | Replace | Files to Include |
|------|---------|------------------|
| `import 'constants/` | `import 'core/constants/` | `**/*.dart` |
| `from 'constants/` | `from 'core/constants/` | `**/*.dart` |
| `import 'di/` | `import 'core/config/` | `**/*.dart` |
| `from 'di/` | `from 'core/config/` | `**/*.dart` |

#### Batch 2: Data Layer Imports

| Find | Replace | Files to Include |
|------|---------|------------------|
| `import 'models/zone_status` | `import 'data/models/zone_status_model` | `**/*.dart` |
| `from 'models/zone_status` | `from 'data/models/zone_status_model` | `**/*.dart` |

#### Batch 3: Services → Data Services

| Find | Replace | Files to Include |
|------|---------|------------------|
| `import 'services/logger` | `import 'data/services/logger` | `**/*.dart` |
| `from 'services/logger` | `from 'data/services/logger'` | `**/*.dart` |
| `import 'services/bell_manager` | `import 'data/services/bell_manager'` | `**/*.dart` |
| `from 'services/bell_manager` | `from 'data/services/bell_manager'` | `**/*.dart` |
| `import 'services/enhanced_zone_parser` | `import 'data/services/enhanced_zone_parser'` | `**/*.dart` |
| `from 'services/enhanced_zone_parser` | `from 'data/services/enhanced_zone_parser'` | `**/*.dart` |
| `import 'services/websocket_mode_manager` | `import 'data/services/websocket_mode_manager'` | `**/*.dart` |
| `from 'services/websocket_mode_manager` | `from 'data/services/websocket_mode_manager'` | `**/*.dart` |
| `import 'services/auto_refresh_service` | `import 'data/services/auto_refresh_service'` | `**/*.dart` |
| `from 'services/auto_refresh_service` | `from 'data/services/auto_refresh_service'` | `**/*.dart` |
| `import 'services/unified_ip_service` | `import 'data/services/unified_ip_service'` | `**/*.dart` |
| `from 'services/unified_ip_service` | `from 'data/services/unified_ip_service'` | `**/*.dart` |

#### Batch 4: Services → Data Sources (Local)

| Find | Replace | Files to Include |
|------|---------|------------------|
| `import 'services/zone_name_local_storage` | `import 'data/datasources/local/zone_name_local_storage'` | `**/*.dart` |
| `from 'services/zone_name_local_storage` | `from 'data/datasources/local/zone_name_local_storage'` | `**/*.dart` |
| `import 'services/offline_settings_service` | `import 'data/datasources/local/offline_settings_service'` | `**/*.dart` |
| `from 'services/offline_settings_service` | `from 'data/datasources/local/offline_settings_service'` | `**/*.dart` |
| `import 'services/exit_password_service` | `import 'data/datasources/local/exit_password_service'` | `**/*.dart` |
| `from 'services/exit_password_service` | `from 'data/datasources/local/exit_password_service'` | `**/*.dart` |
| `import 'services/zone_mapping_service` | `import 'data/datasources/local/zone_mapping_service'` | `**/*.dart` |
| `from 'services/zone_mapping_service` | `from 'data/datasources/local/zone_mapping_service'` | `**/*.dart` |
| `import 'services/websocket_settings_service` | `import 'data/datasources/local/websocket_settings_service'` | `**/*.dart` |
| `from 'services/websocket_settings_service` | `from 'data/datasources/local/websocket_settings_service'` | `**/*.dart` |

#### Batch 5: Services → Data Sources (WebSocket)

| Find | Replace | Files to Include |
|------|---------|------------------|
| `import 'services/websocket_service` | `import 'data/datasources/websocket/websocket_service'` | `**/*.dart` |
| `from 'services/websocket_service` | `from 'data/datasources/websocket/websocket_service'` | `**/*.dart` |
| `import 'services/fire_alarm_websocket_manager` | `import 'data/datasources/websocket/fire_alarm_websocket_manager'` | `**/*.dart` |
| `from 'services/fire_alarm_websocket_manager` | `from 'data/datasources/websocket/fire_alarm_websocket_manager'` | `**/*.dart` |

#### Batch 6: Presentation Layer

| Find | Replace | Files to Include |
|------|---------|------------------|
| `import 'core/fire_alarm_data` | `import 'presentation/providers/fire_alarm_data_provider'` | `**/*.dart` |
| `from 'core/fire_alarm_data` | `from 'presentation/providers/fire_alarm_data_provider'` | `**/*.dart` |
| `import 'widgets/` | `import 'presentation/widgets/` | `**/*.dart` |
| `from 'widgets/` | `from 'presentation/widgets/` | `**/*.dart` |
| `import 'config/connection_config_page` | `import 'presentation/pages/connection/connection_config_page'` | `**/*.dart` |
| `from 'config/connection_config_page` | `from 'presentation/pages/connection/connection_config_page'` | `**/*.dart` |
| `import 'monitoring/` | `import 'presentation/pages/monitoring/` | `**/*.dart` |
| `from 'monitoring/` | `from 'presentation/pages/monitoring/'` | `**/*.dart` |
| `import 'auth/login` | `import 'presentation/pages/auth/login_page'` | `**/*.dart` |
| `from 'auth/login` | `from 'presentation/pages/auth/login_page'` | `**/*.dart` |

#### Batch 7: Other Files

| Find | Replace | Files to Include |
|------|---------|------------------|
| `import 'utils/zone_status_utils` | `import 'shared/utils/zone_status_utils'` | `**/*.dart` |
| `from 'utils/zone_status_utils` | `from 'shared/utils/zone_status_utils'` | `**/*.dart` |
| `import 'unified_fire_alarm_parser` | `import 'data/services/unified_fire_alarm_parser'` | `**/*.dart` |
| `from 'unified_fire_alarm_parser` | `from 'data/services/unified_fire_alarm_parser'` | `**/*.dart` |

---

### Method 2: Automated Script (Alternative)

If you prefer automated approach, run this command in PowerShell:

```powershell
# Run from project root
cd D:\Ndut\DDS\DDS_Offline\dds_offline_monitoring

# Fix all imports using regex
Get-ChildItem -Path "lib" -Filter "*.dart" -Recurse | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    $content = $content -replace "import 'constants/", "import 'core/constants/"
    $content = $content -replace "import 'di/", "import 'core/config/"
    # ... add all other replacements
    Set-Content $_.FullName $content -NoNewline
}
```

---

## Step-by-Step Instructions

### For VSCode Users:

1. **Open VSCode**
2. **Press Ctrl+Shift+H** (Find & Replace in Files)
3. **Copy each "Find" pattern** from table above
4. **Copy corresponding "Replace" pattern**
5. **Click "Replace All"**
6. **Repeat for each batch** (1-7)

### After Fixing Imports:

1. **Run Flutter Analyze:**
   ```bash
   flutter analyze
   ```

2. **Check remaining errors:**
   ```bash
   flutter analyze 2>&1 | grep "error -"
   ```

3. **Fix any remaining errors manually**

---

## File Location Reference

### New Structure (After Migration)

```
lib/
├── core/
│   ├── constants/           # ✅ Old: constants/
│   ├── config/              # ✅ Old: di/
│   └── utils/               # ✅ Old: utils/ (partial)
│
├── data/
│   ├── models/              # ✅ Old: models/
│   ├── datasources/
│   │   ├── websocket/       # ✅ Old: services/ (websocket-related)
│   │   └── local/           # ✅ Old: services/ (local storage)
│   ├── repositories/        # 🆕 New
│   └── services/            # ✅ Old: services/ (business logic)
│
├── domain/
│   ├── entities/            # 🆕 New
│   └── repositories/        # 🆕 New
│
├── presentation/
│   ├── pages/
│   │   ├── monitoring/      # ✅ Old: monitoring/
│   │   ├── connection/      # ✅ Old: config/ (pages)
│   │   ├── control/         # ✅ Old: monitoring/control.dart
│   │   └── auth/            # ✅ Old: auth/
│   ├── widgets/             # ✅ Old: widgets/
│   └── providers/           # ✅ Old: core/fire_alarm_data.dart
│
├── shared/
│   └── utils/               # ✅ Old: utils/zone_status_utils.dart
│
└── main.dart                # ✅ Entry point (fixed)
```

---

## Common Issues & Solutions

### Issue 1: "Target of URI doesn't exist"

**Cause:** Import path incorrect after restructuring

**Solution:** Check file location and update import path

**Example:**
```dart
// ❌ WRONG (old path)
import '../services/logger.dart';

// ✅ CORRECT (new path)
import '../../data/services/logger.dart';
```

### Issue 2: Circular Dependencies

**Cause:** Import structure creates circular reference

**Solution:** Use dependency injection or move common code to shared layer

### Issue 3: Relative vs Absolute Imports

**Recommendation:** Use absolute imports starting from `lib/`

```dart
// ✅ GOOD - Absolute import
import 'data/services/logger.dart';

// ⚠️ ACCEPTABLE - Relative import (if in same folder)
import 'logger.dart';

// ❌ AVOID - Deep relative import
import '../../../data/services/logger.dart';
```

---

## Validation Checklist

After fixing all imports, verify:

- [ ] `flutter analyze` shows 0 errors
- [ ] `flutter doctor -v` passes
- [ ] App can be hot restarted without errors
- [ ] All pages load correctly
- [ ] WebSocket connection works
- [ ] No red lines in VSCode

---

## Next Steps

After imports are fixed:

1. **Run full test:**
   ```bash
   flutter run
   ```

2. **Test all features:**
   - Connection configuration
   - Monitoring pages
   - Control panel
   - WebSocket data flow

3. **Fix any runtime errors**

4. **Commit changes:**
   ```bash
   git add .
   git commit -m "refactor: migrate to clean architecture"
   ```

---

**Need Help?** Refer to `CLEAN_ARCHITECTURE_GUIDE.md` for detailed architecture documentation.
