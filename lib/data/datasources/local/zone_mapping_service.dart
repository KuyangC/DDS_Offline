import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import '../../../data/services/logger.dart';

/// Service for managing zone mapping images
/// Handles folder selection, image validation, and storage of mapping paths
class ZoneMappingService {
  static const String _zoneMappingPathKey = 'zone_mapping_path';
  static const List<String> _supportedExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'];

  /// Save the selected folder path for zone mapping images
  static Future<bool> saveMappingFolderPath(String folderPath) async {
    try {
      AppLogger.info('Attempting to save zone mapping path: "$folderPath"', tag: 'ZONE_MAPPING');
      AppLogger.info('Using key: "$_zoneMappingPathKey"', tag: 'ZONE_MAPPING');

      final prefs = await SharedPreferences.getInstance();
      AppLogger.info('SharedPreferences instance obtained successfully', tag: 'ZONE_MAPPING');

      final success = await prefs.setString(_zoneMappingPathKey, folderPath);
      AppLogger.info('SharedPreferences.setString() operation result: $success', tag: 'ZONE_MAPPING');

      if (success) {
        // Verification step - immediately read back to confirm
        final savedPath = prefs.getString(_zoneMappingPathKey);
        AppLogger.info('Verification - saved path matches: "$savedPath"', tag: 'ZONE_MAPPING');

        if (savedPath == folderPath) {
          AppLogger.info('✅ Zone mapping folder path saved and verified successfully: $folderPath', tag: 'ZONE_MAPPING');
        } else {
          AppLogger.error('❌ Path mismatch! Expected: "$folderPath", Got: "$savedPath"', tag: 'ZONE_MAPPING');
        }
      } else {
        AppLogger.error('❌ Failed to save zone mapping folder path - SharedPreferences.setString() returned false', tag: 'ZONE_MAPPING');
      }

      return success;
    } catch (e) {
      AppLogger.error('❌ Exception in saveMappingFolderPath: $e', tag: 'ZONE_MAPPING');
      AppLogger.error('Stack trace: ${StackTrace.current}', tag: 'ZONE_MAPPING');
      return false;
    }
  }

  /// Load the saved folder path for zone mapping images
  static Future<String> loadMappingFolderPath() async {
    try {
      AppLogger.info('Attempting to load zone mapping path using key: "$_zoneMappingPathKey"', tag: 'ZONE_MAPPING');

      final prefs = await SharedPreferences.getInstance();
      AppLogger.info('SharedPreferences instance obtained for loading', tag: 'ZONE_MAPPING');

      final folderPath = prefs.getString(_zoneMappingPathKey);
      AppLogger.info('SharedPreferences.getString() result: "$folderPath"', tag: 'ZONE_MAPPING');

      if (folderPath != null && folderPath.isNotEmpty) {
        AppLogger.info('✅ Zone mapping folder path loaded successfully: "$folderPath"', tag: 'ZONE_MAPPING');
        return folderPath;
      } else {
        AppLogger.info('ℹ️ No zone mapping folder path found (null or empty)', tag: 'ZONE_MAPPING');

        // Debug: Check if key exists but value is empty/null
        final keys = prefs.getKeys();
        AppLogger.info('Available SharedPreferences keys: ${keys.toList()}', tag: 'ZONE_MAPPING');
        AppLogger.info('Key "$_zoneMappingPathKey" exists: ${keys.contains(_zoneMappingPathKey)}', tag: 'ZONE_MAPPING');

        return '';
      }
    } catch (e) {
      AppLogger.error('❌ Exception in loadMappingFolderPath: $e', tag: 'ZONE_MAPPING');
      AppLogger.error('Stack trace: ${StackTrace.current}', tag: 'ZONE_MAPPING');
      return '';
    }
  }

  /// Check if a specific zone has a mapping image
  static Future<bool> hasZoneMapping(int zoneNumber) async {
    try {
      final imagePath = await getZoneMappingPath(zoneNumber);
      return imagePath != null && await File(imagePath).exists();
    } catch (e) {
      AppLogger.error('Error checking zone mapping for zone $zoneNumber: $e', tag: 'ZONE_MAPPING');
      return false;
    }
  }

  /// Get the file path for a specific zone's mapping image
  static Future<String?> getZoneMappingPath(int zoneNumber) async {
    try {
      final folderPath = await loadMappingFolderPath();

      if (folderPath.isEmpty) {
        return null;
      }

      // Check for supported image extensions
      for (final extension in _supportedExtensions) {
        final imagePath = path.join(folderPath, '$zoneNumber$extension');
        if (await File(imagePath).exists()) {
          AppLogger.debug('Found zone mapping for zone $zoneNumber: $imagePath', tag: 'ZONE_MAPPING');
          return imagePath;
        }
      }

      AppLogger.debug('No zone mapping found for zone $zoneNumber', tag: 'ZONE_MAPPING');
      return null;
    } catch (e) {
      AppLogger.error('Error getting zone mapping path for zone $zoneNumber: $e', tag: 'ZONE_MAPPING');
      return null;
    }
  }

  /// Validate that the selected folder contains zone mapping images
  static Future<Map<int, String>> validateMappingFolder(String folderPath) async {
    final Map<int, String> foundZones = {};

    try {
      AppLogger.info('Starting validation for folder: $folderPath', tag: 'ZONE_MAPPING');

      final folder = Directory(folderPath);

      if (!await folder.exists()) {
        AppLogger.error('Folder does not exist: $folderPath', tag: 'ZONE_MAPPING');
        return foundZones;
      }

      AppLogger.info('Folder exists, checking accessibility...', tag: 'ZONE_MAPPING');

      // Check if folder is accessible
      try {
        await folder.list().first;
        AppLogger.info('Folder is accessible, reading files...', tag: 'ZONE_MAPPING');
      } catch (e) {
        AppLogger.error('Folder is not accessible: $folderPath, error: $e', tag: 'ZONE_MAPPING');
        return foundZones;
      }

      final files = await folder.list().toList();
      AppLogger.info('Found ${files.length} total items in folder', tag: 'ZONE_MAPPING');

      for (final file in files) {
        AppLogger.debug('Processing file: ${file.path} (type: ${file.runtimeType})', tag: 'ZONE_MAPPING');

        if (file is File) {
          final fileName = path.basenameWithoutExtension(file.path);
          final extension = path.extension(file.path).toLowerCase();

          AppLogger.debug('File: $fileName, extension: $extension', tag: 'ZONE_MAPPING');

          // Check if filename is a valid zone number
          final zoneNumber = int.tryParse(fileName);
          if (zoneNumber != null && zoneNumber > 0 && zoneNumber <= 315) {
            AppLogger.debug('Valid zone number: $zoneNumber, checking extension...', tag: 'ZONE_MAPPING');

            if (_supportedExtensions.contains(extension)) {
              foundZones[zoneNumber] = file.path;
              AppLogger.info('✅ Found valid zone mapping: Zone $zoneNumber -> ${file.path}', tag: 'ZONE_MAPPING');
            } else {
              AppLogger.debug('❌ Invalid extension: $extension (supported: $_supportedExtensions)', tag: 'ZONE_MAPPING');
            }
          } else {
            AppLogger.debug('❌ Invalid zone number: $fileName (parsed: $zoneNumber)', tag: 'ZONE_MAPPING');
          }
        } else {
          AppLogger.debug('Skipping non-file item: ${file.path}', tag: 'ZONE_MAPPING');
        }
      }

      AppLogger.info('Folder validation complete. Found ${foundZones.length} valid zone mappings out of ${files.length} items', tag: 'ZONE_MAPPING');

    } catch (e) {
      AppLogger.error('Error validating mapping folder $folderPath: $e', tag: 'ZONE_MAPPING');
    }

    return foundZones;
  }

  /// Clear the saved mapping folder path
  static Future<bool> clearMappingFolder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final success = await prefs.remove(_zoneMappingPathKey);

      if (success) {
        AppLogger.info('Zone mapping folder path cleared', tag: 'ZONE_MAPPING');
      } else {
        AppLogger.error('Failed to clear zone mapping folder path', tag: 'ZONE_MAPPING');
      }

      return success;
    } catch (e) {
      AppLogger.error('Error clearing zone mapping folder path: $e', tag: 'ZONE_MAPPING');
      return false;
    }
  }

  /// Get list of supported image file extensions
  static List<String> getSupportedExtensions() {
    return List.unmodifiable(_supportedExtensions);
  }

  /// Get detailed folder analysis for debugging
  static Future<String> analyzeFolder(String folderPath) async {
    final buffer = StringBuffer();

    try {
      buffer.writeln('📁 Folder Analysis: $folderPath');
      buffer.writeln('');

      final folder = Directory(folderPath);

      if (!await folder.exists()) {
        buffer.writeln('❌ Folder does not exist');
        return buffer.toString();
      }

      buffer.writeln('✅ Folder exists');

      // Check accessibility
      try {
        await folder.list().first;
        buffer.writeln('✅ Folder is accessible');
      } catch (e) {
        buffer.writeln('❌ Folder not accessible: $e');
        return buffer.toString();
      }

      final files = await folder.list().toList();
      buffer.writeln('📄 Found ${files.length} total items');

      final imageFiles = <String>[];
      final validZoneFiles = <String>[];
      final invalidNames = <String>[];
      final invalidExtensions = <String>[];
      final nonFiles = <String>[];

      for (final file in files) {
        if (file is File) {
          final fileName = path.basename(file.path);
          final fileNameWithoutExt = path.basenameWithoutExtension(file.path);
          final extension = path.extension(file.path).toLowerCase();

          imageFiles.add(fileName);

          final zoneNumber = int.tryParse(fileNameWithoutExt);
          if (zoneNumber != null && zoneNumber > 0 && zoneNumber <= 315) {
            if (_supportedExtensions.contains(extension)) {
              validZoneFiles.add('$fileName (Zone $zoneNumber)');
            } else {
              invalidExtensions.add('$fileName (.$extension not supported)');
            }
          } else {
            if (_supportedExtensions.contains(extension)) {
              invalidNames.add('$fileName (name: "$fileNameWithoutExt" not a valid zone number 1-315)');
            } else {
              invalidExtensions.add('$fileName (.$extension not supported)');
            }
          }
        } else {
          nonFiles.add(file.path);
        }
      }

      buffer.writeln('');
      buffer.writeln('📊 Summary:');
      buffer.writeln('  • Valid zone mappings: ${validZoneFiles.length}');
      buffer.writeln('  • Image files with invalid names: ${invalidNames.length}');
      buffer.writeln('  • Files with unsupported extensions: ${invalidExtensions.length}');
      buffer.writeln('  • Non-file items (folders): ${nonFiles.length}');

      if (validZoneFiles.isNotEmpty) {
        buffer.writeln('');
        buffer.writeln('✅ Valid Zone Mappings:');
        for (final file in validZoneFiles) {
          buffer.writeln('  • $file');
        }
      }

      if (invalidNames.isNotEmpty) {
        buffer.writeln('');
        buffer.writeln('⚠️  Images with Invalid Names:');
        for (final file in invalidNames.take(10)) {
          buffer.writeln('  • $file');
        }
        if (invalidNames.length > 10) {
          buffer.writeln('  • ... and ${invalidNames.length - 10} more');
        }
      }

      if (invalidExtensions.isNotEmpty) {
        buffer.writeln('');
        buffer.writeln('⚠️  Files with Unsupported Extensions:');
        buffer.writeln('  Supported extensions: ${_supportedExtensions.join(', ')}');
        for (final file in invalidExtensions.take(5)) {
          buffer.writeln('  • $file');
        }
        if (invalidExtensions.length > 5) {
          buffer.writeln('  • ... and ${invalidExtensions.length - 5} more');
        }
      }

      if (nonFiles.isNotEmpty) {
        buffer.writeln('');
        buffer.writeln('📁 Non-File Items (ignored):');
        for (final item in nonFiles.take(5)) {
          buffer.writeln('  • ${path.basename(item)}');
        }
        if (nonFiles.length > 5) {
          buffer.writeln('  • ... and ${nonFiles.length - 5} more');
        }
      }

      buffer.writeln('');
      if (validZoneFiles.isNotEmpty) {
        buffer.writeln('🎉 RESULT: Folder contains ${validZoneFiles.length} valid zone mappings!');
      } else {
        buffer.writeln('❌ RESULT: No valid zone mappings found');
        buffer.writeln('');
        buffer.writeln('💡 Solution:');
        buffer.writeln('  1. Rename images to match zone numbers: 1.jpg, 2.jpg, 3.jpg, etc.');
        buffer.writeln('  2. Use supported extensions: ${_supportedExtensions.join(', ')}');
        buffer.writeln('  3. Ensure zone numbers are between 1-315');
        buffer.writeln('  4. Remove any leading zeros (use "1.jpg", not "01.jpg")');
      }

    } catch (e) {
      buffer.writeln('❌ Error analyzing folder: $e');
    }

    return buffer.toString();
  }

  /// Get summary statistics for the mapping folder
  static Future<Map<String, dynamic>> getMappingFolderStats() async {
    final stats = <String, dynamic>{
      'totalZones': 315,
      'mappedZones': 0,
      'folderPath': '',
      'isValid': false,
    };

    try {
      final folderPath = await loadMappingFolderPath();
      stats['folderPath'] = folderPath;

      if (folderPath.isNotEmpty) {
        final foundZones = await validateMappingFolder(folderPath);
        stats['mappedZones'] = foundZones.length;
        stats['isValid'] = foundZones.isNotEmpty;
      }
    } catch (e) {
      AppLogger.error('Error getting mapping folder stats: $e', tag: 'ZONE_MAPPING');
    }

    return stats;
  }

  /// Check if mapping is configured and valid
  static Future<bool> isMappingConfigured() async {
    try {
      final folderPath = await loadMappingFolderPath();

      if (folderPath.isEmpty) {
        return false;
      }

      final stats = await getMappingFolderStats();
      return stats['isValid'] as bool;
    } catch (e) {
      AppLogger.error('Error checking if mapping is configured: $e', tag: 'ZONE_MAPPING');
      return false;
    }
  }

  /// Debug function to test SharedPreferences functionality
  static Future<void> debugSharedPreferences() async {
    AppLogger.info('=== DEBUG SHARED PREFERENCES START ===', tag: 'ZONE_MAPPING');

    try {
      final prefs = await SharedPreferences.getInstance();
      AppLogger.info('SharedPreferences instance obtained', tag: 'ZONE_MAPPING');

      final keys = prefs.getKeys();
      AppLogger.info('All SharedPreferences keys: ${keys.toList()}', tag: 'ZONE_MAPPING');

      final zoneMappingPath = prefs.getString(_zoneMappingPathKey);
      AppLogger.info('Current zone mapping path: "$zoneMappingPath"', tag: 'ZONE_MAPPING');

      // Test saving and loading a test path
      const testPath = '/test/zone/mapping/path';
      AppLogger.info('Testing save with test path: "$testPath"', tag: 'ZONE_MAPPING');
      final saveResult = await prefs.setString(_zoneMappingPathKey, testPath);
      AppLogger.info('Save test result: $saveResult', tag: 'ZONE_MAPPING');

      final loadedPath = prefs.getString(_zoneMappingPathKey);
      AppLogger.info('Load test result: "$loadedPath"', tag: 'ZONE_MAPPING');

      // Restore original path if it existed
      if (zoneMappingPath != null && zoneMappingPath != testPath) {
        await prefs.setString(_zoneMappingPathKey, zoneMappingPath);
        AppLogger.info('Restored original path: "$zoneMappingPath"', tag: 'ZONE_MAPPING');
      }

      AppLogger.info('=== DEBUG SHARED PREFERENCES END ===', tag: 'ZONE_MAPPING');

    } catch (e) {
      AppLogger.error('Error in debugSharedPreferences: $e', tag: 'ZONE_MAPPING');
      AppLogger.error('Stack trace: ${StackTrace.current}', tag: 'ZONE_MAPPING');
    }
  }
}