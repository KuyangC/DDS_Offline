import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'logger.dart';

/// Repository untuk menyimpan activity logs ke JSON file
/// File disimpan di External Storage Documents/DDS APPS folder (survive uninstall di Android)
class ActivityLogRepository {
  static const String _fileName = 'activity_logs_v2.jsonl'; // New Line-Delimited JSON format
  static const Duration _autoSaveInterval = Duration(minutes: 10);

  File? _jsonFile;
  List<Map<String, dynamic>> _logs = [];
  Timer? _autoSaveTimer;
  bool _isInitialized = false;

  /// Check if repository is initialized
  bool get isInitialized => _isInitialized;

  /// Initialize repository and load logs from file if exists
  Future<void> init() async {
    if (_isInitialized) {
      AppLogger.info('ActivityLogRepository already initialized', tag: 'ACTIVITY_LOG_REPO');
      return;
    }

    try {
      await _initFile();
      await _loadFromFile();
      _isInitialized = true;
      AppLogger.info('✅ ActivityLogRepository initialized successfully', tag: 'ACTIVITY_LOG_REPO');
    } catch (e, stackTrace) {
      AppLogger.error(
        '❌ Failed to initialize ActivityLogRepository',
        tag: 'ACTIVITY_LOG_REPO',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Initialize JSON file in external storage
  Future<void> _initFile() async {
    Directory dir;

    // For Android: Use Documents/DDS APPS folder (publicly accessible, survives uninstall)
    // For iOS: Use app documents directory
    if (Platform.isAndroid) {
      try {
        final documentsDir = Directory('/storage/emulated/0/Documents');

        if (await documentsDir.exists()) {
          // Create "DDS APPS" folder if it doesn't exist
          final ddsAppsDir = Directory('/storage/emulated/0/Documents/DDS APPS');
          if (!await ddsAppsDir.exists()) {
            await ddsAppsDir.create(recursive: true);
            AppLogger.info('Created DDS APPS folder in Documents', tag: 'ACTIVITY_LOG_REPO');
          }
          dir = ddsAppsDir;
          AppLogger.info('Using Documents/DDS APPS folder for logs (survives uninstall)', tag: 'ACTIVITY_LOG_REPO');
        } else {
          final externalDir = await getExternalStorageDirectory();
          if (externalDir != null) {
            dir = externalDir;
            AppLogger.warning('Documents not available, using external storage: ${dir.path}', tag: 'ACTIVITY_LOG_REPO');
          } else {
            dir = await getApplicationDocumentsDirectory();
            AppLogger.warning('Using app documents directory (will NOT survive uninstall)', tag: 'ACTIVITY_LOG_REPO');
          }
        }
      } catch (e) {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          dir = externalDir;
          AppLogger.warning('Exception accessing Documents, using external storage: ${dir.path}', tag: 'ACTIVITY_LOG_REPO');
        } else {
          dir = await getApplicationDocumentsDirectory();
          AppLogger.warning('Using app documents directory (will NOT survive uninstall)', tag: 'ACTIVITY_LOG_REPO');
        }
      }
    } else {
      dir = await getApplicationDocumentsDirectory();
      AppLogger.info('iOS: Using app documents directory', tag: 'ACTIVITY_LOG_REPO');
    }

    _jsonFile = File('${dir.path}/$_fileName');
    AppLogger.info('📁 Log file path: ${_jsonFile!.path}', tag: 'ACTIVITY_LOG_REPO');
  }
  
  /// Load logs from file (Last 100 only)
  Future<void> _loadFromFile() async {
    if (_jsonFile == null) return;

    try {
      if (await _jsonFile!.exists()) {
        // Read lines efficiently
        final lines = await _jsonFile!.readAsLines();
        
        // Take only last 100 lines for RAM cache
        final recentLines = lines.length > 100 
            ? lines.sublist(lines.length - 100) 
            : lines;
            
        final jsonString = '[${recentLines.join(',')}]'; // Hack to make it valid JSON array for the parser
        
        _logs = await compute(_parseLogs, jsonString);
        AppLogger.info('Loaded ${_logs.length} recent logs (from ${lines.length} total history)', tag: 'ACTIVITY_LOG_REPO');
      } else {
        _logs = [];
      }
    } catch (e, stackTrace) {
      AppLogger.error('Failed to load logs', tag: 'ACTIVITY_LOG_REPO', error: e, stackTrace: stackTrace);
      _logs = [];
    }
  }

  /// Static helper for parsing logs
  static List<Map<String, dynamic>> _parseLogs(String jsonString) {
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.cast<Map<String, dynamic>>().toList();
    } catch (e) {
      return [];
    }
  }

  /// Save logs to JSON file
  Future<void> _saveToFile() async {
    // No-op for full save in NDJSON usually, but if we need to rewrite cache
    // For V2, we usually only Append. 
    // This is kept if we clear logs or mass update.
     if (_jsonFile == null) return;
     try {
       final sb = StringBuffer();
       for (final log in _logs) {
         sb.writeln(jsonEncode(log));
       }
       await _jsonFile!.writeAsString(sb.toString());
     } catch (e) {
       AppLogger.error('Failed to rewrite log file', tag: 'ACTIVITY_LOG_REPO', error: e);
     }
  }

  /// Save a single log entry using APPEND mode
  Future<void> saveLog(Map<String, dynamic> log) async {
    try {
      // Prepare log
      final logToSave = Map<String, dynamic>.from(log);
      if (logToSave['timestamp'] is DateTime) {
        logToSave['timestamp'] = (logToSave['timestamp'] as DateTime).toIso8601String();
      }

      // Add to Memory Cache (First)
      _logs.insert(0, logToSave);
      if (_logs.length > 100) _logs.removeLast(); // Keep cache small

      // Append to File (Disk)
      if (_jsonFile != null) {
        final line = jsonEncode(logToSave);
        await _jsonFile!.writeAsString('$line\n', mode: FileMode.append);
      }
      
      AppLogger.debug('Log saved (Appended): ${log['activity']}', tag: 'ACTIVITY_LOG_REPO');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to save log', tag: 'ACTIVITY_LOG_REPO', error: e, stackTrace: stackTrace);
    }
  }

  /// Save multiple log entries
  Future<void> saveLogs(List<Map<String, dynamic>> logs) async {
    if (logs.isEmpty) return;
    for (final log in logs) {
      await saveLog(log);
    }
  }

  /// Get all logs (Returns RAM cache - recent only)
  /// To get full history, we would need a separate method to read the full file
  Future<List<Map<String, dynamic>>> getAllLogs() async {
    return _logs.map((log) {
       final logCopy = Map<String, dynamic>.from(log);
        if (logCopy['timestamp'] is String) {
          logCopy['timestamp'] = DateTime.parse(logCopy['timestamp'] as String);
        }
        return logCopy;
    }).toList();
  }

  /// Get logs filtered by date
  Future<List<Map<String, dynamic>>> getLogsByDate(String date) async {
    try {
      final filtered = _logs.where((log) => log['date'] == date).toList();
      return filtered.map((log) {
        final logCopy = Map<String, dynamic>.from(log);
        if (logCopy['timestamp'] is String) {
          logCopy['timestamp'] = DateTime.parse(logCopy['timestamp'] as String);
        }
        return logCopy;
      }).toList();
    } catch (e, stackTrace) {
      AppLogger.error('Failed to get logs by date', tag: 'ACTIVITY_LOG_REPO', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Get all unique dates from logs
  Future<List<String>> getAvailableDates() async {
    try {
      final dates = _logs.map((log) => log['date'] as String).toSet().toList();
      dates.sort((a, b) => b.compareTo(a)); // Sort descending
      return dates;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to get available dates', tag: 'ACTIVITY_LOG_REPO', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Get total log count
  Future<int> getLogCount() async {
    return _logs.length;
  }

  /// Clear all logs
  Future<void> clearAllLogs() async {
    try {
      _logs.clear();
      await _saveToFile();
      AppLogger.info('All logs cleared', tag: 'ACTIVITY_LOG_REPO');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to clear logs', tag: 'ACTIVITY_LOG_REPO', error: e, stackTrace: stackTrace);
    }
  }

  /// Delete logs older than specified days
  Future<int> deleteOldLogs({int daysToKeep = 30}) async {
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
      final initialCount = _logs.length;

      _logs.removeWhere((log) {
        if (log['timestamp'] is String) {
          final timestamp = DateTime.parse(log['timestamp'] as String);
          return timestamp.isBefore(cutoffDate);
        }
        return false;
      });

      await _saveToFile();
      final deletedCount = initialCount - _logs.length;
      AppLogger.info('Deleted $deletedCount old logs (older than $daysToKeep days)', tag: 'ACTIVITY_LOG_REPO');
      return deletedCount;
    } catch (e, stackTrace) {
      AppLogger.error('Failed to delete old logs', tag: 'ACTIVITY_LOG_REPO', error: e, stackTrace: stackTrace);
      return 0;
    }
  }

  /// Start auto-save timer (periodically saves logs from memory to file)
  /// The logsGetter function should return the current list of logs from memory
  void startAutoSave(List<Map<String, dynamic>> Function() logsGetter) {
    stopAutoSave();

    _autoSaveTimer = Timer.periodic(_autoSaveInterval, (timer) async {
      try {
        final logs = logsGetter();
        if (logs.isNotEmpty) {
          await saveLogs(logs);
          AppLogger.info('Auto-saved ${logs.length} logs to file', tag: 'ACTIVITY_LOG_REPO');
        }
      } catch (e, stackTrace) {
        AppLogger.error('Auto-save failed', tag: 'ACTIVITY_LOG_REPO', error: e, stackTrace: stackTrace);
      }
    });

    AppLogger.info('Auto-save timer started (${_autoSaveInterval.inMinutes} minutes)', tag: 'ACTIVITY_LOG_REPO');
  }

  /// Stop auto-save timer
  void stopAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    AppLogger.info('Auto-save timer stopped', tag: 'ACTIVITY_LOG_REPO');
  }

  /// Close repository
  Future<void> close() async {
    stopAutoSave();
    _isInitialized = false;
    AppLogger.info('ActivityLogRepository closed', tag: 'ACTIVITY_LOG_REPO');
  }

  /// Get log file path (for debugging)
  Future<String> getFilePath() async {
    if (_jsonFile != null) {
      return _jsonFile!.path;
    }

    Directory dir;
    if (Platform.isAndroid) {
      final documentsDir = Directory('/storage/emulated/0/Documents');
      if (await documentsDir.exists()) {
        final ddsAppsDir = Directory('/storage/emulated/0/Documents/DDS APPS');
        if (!await ddsAppsDir.exists()) {
          await ddsAppsDir.create(recursive: true);
        }
        dir = ddsAppsDir;
      } else {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          dir = externalDir;
        } else {
          dir = await getApplicationDocumentsDirectory();
        }
      }
    } else {
      dir = await getApplicationDocumentsDirectory();
    }

    return '${dir.path}/$_fileName';
  }

  /// Check if log file exists
  Future<bool> fileExists() async {
    try {
      if (_jsonFile != null) {
        return await _jsonFile!.exists();
      }
      final path = await getFilePath();
      final file = File(path);
      return await file.exists();
    } catch (e) {
      AppLogger.error('Failed to check file existence', tag: 'ACTIVITY_LOG_REPO', error: e);
      return false;
    }
  }
}
