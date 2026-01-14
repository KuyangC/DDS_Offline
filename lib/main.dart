import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'presentation/providers/fire_alarm_data_provider.dart';
import 'data/services/logger.dart';
import 'data/services/bell_manager.dart';
import 'data/services/enhanced_zone_parser.dart';
import 'data/services/unified_ip_service.dart';
import 'data/datasources/local/offline_settings_service.dart';
import 'data/datasources/local/zone_name_local_storage.dart';
import 'data/datasources/local/exit_password_service.dart';
import 'data/datasources/local/zone_mapping_service.dart';
import 'data/services/websocket_mode_manager.dart';
import 'data/services/auto_refresh_service.dart';
import 'data/services/activity_log_repository.dart';
import 'presentation/pages/connection/connection_config_page.dart';

// GetIt service locator
final GetIt getIt = GetIt.instance;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize services
    await _initializeServices();
  } catch (e, stackTrace) {
    // Log error but don't crash
    debugPrint('❌ Error during initialization: $e');
    debugPrint('Stack trace: $stackTrace');
    // Continue running app even if initialization fails
  }

  runApp(const DDSOfflineApp());
}

/// Initialize all services
Future<void> _initializeServices() async {
  // Initialize logger
  getIt.registerSingleton<AppLogger>(AppLogger());

  // Initialize shared preferences
  final prefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(prefs);

  // Initialize zone name storage
  getIt.registerSingleton<ZoneNameLocalStorage>(ZoneNameLocalStorage());

  // Initialize offline settings
  final offlineSettingsService = OfflineSettingsService();
  // No initialize() method needed, service is ready to use
  getIt.registerSingleton<OfflineSettingsService>(offlineSettingsService);

  // Initialize exit password service
  getIt.registerSingleton<ExitPasswordService>(ExitPasswordService());

  // Initialize zone mapping service
  getIt.registerSingleton<ZoneMappingService>(ZoneMappingService());

  // Initialize WebSocket mode manager
  getIt.registerSingleton<WebSocketModeManager>(WebSocketModeManager());

  // Initialize unified IP service
  getIt.registerSingleton<UnifiedIPService>(UnifiedIPService());

  // Initialize enhanced zone parser
  getIt.registerSingleton<EnhancedZoneParser>(EnhancedZoneParser());

  // Initialize Bell Manager
  getIt.registerSingleton<BellManager>(BellManager());

  // Initialize Auto Refresh Service
  getIt.registerSingleton<AutoRefreshService>(AutoRefreshService.instance);

  // Initialize Activity Log Repository
  final activityLogRepo = ActivityLogRepository();
  await activityLogRepo.init();
  getIt.registerSingleton<ActivityLogRepository>(activityLogRepo);

  // Initialize Fire Alarm Data
  final fireAlarmData = FireAlarmData();
  await fireAlarmData.initialize();
  getIt.registerSingleton<FireAlarmData>(fireAlarmData);

  AppLogger.info('✅ All services initialized successfully');
}

class DDSOfflineApp extends StatelessWidget {
  const DDSOfflineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // 🔥 CRITICAL FIX: Use 'value' instead of 'create' to use singleton instance
        // 'create' would create a new instance every time, breaking WebSocket status sync
        ChangeNotifierProvider<FireAlarmData>.value(
          value: getIt<FireAlarmData>(),
        ),
        ChangeNotifierProvider<BellManager>.value(
          value: getIt<BellManager>(),
        ),
      ],
      child: MaterialApp(
        title: 'DDS Offline Monitoring',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
        ),
        home: const ConnectionConfigPage(),
      ),
    );
  }
}
