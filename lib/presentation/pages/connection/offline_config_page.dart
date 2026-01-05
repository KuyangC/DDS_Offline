import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../monitoring/offline_monitoring_page.dart';
import '../../../data/services/logger.dart';
import '../../../data/services/unified_ip_service.dart';
import '../../../data/services/websocket_mode_manager.dart';
import '../../../data/datasources/local/zone_mapping_service.dart';
// import '../core/utils/file_permission_utils.dart'; // Temporarily disabled
import 'zone_name_config.dart';
import 'dart:async';
import 'dart:io';

// Offline validation methods
class OfflineValidationHelpers {
  static String? validateIpAddress(String? value, {bool isOnlineMode = false}) {
    if (value == null || value.trim().isEmpty) {
      return isOnlineMode ? null : 'IP address is required';
    }

    // Skip validation for online mode
    if (isOnlineMode) {
      return null;
    }

    final ip = value.trim();
    final ipv4Regex = RegExp(
      r'^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
    );

    if (!ipv4Regex.hasMatch(ip)) {
      return 'Please enter a valid IPv4 address (e.g., 192.168.1.100)';
    }

    return null;
  }

  static String? validatePort(String? value, {bool isOnlineMode = false}) {
    if (value == null || value.trim().isEmpty) {
      return isOnlineMode ? null : 'Port is required';
    }

    // Skip validation for online mode
    if (isOnlineMode) {
      return null;
    }

    final port = value.trim();
    final portNumber = int.tryParse(port);

    if (portNumber == null) {
      return 'Port must be a valid number';
    }

    if (portNumber < 1 || portNumber > 65535) {
      return 'Port must be between 1 and 65535';
    }

    return null;
  }

  static String? validateModuleCount(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Number of modules is required';
    }

    final moduleCount = value.trim();
    final count = int.tryParse(moduleCount);

    if (count == null) {
      return 'Module count must be a valid number';
    }

    if (count < 1) {
      return 'Module count must be at least 1';
    }

    if (count > 255) {
      return 'Module count cannot exceed 255';
    }

    return null;
  }

  static String? validateProjectName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Project name is required';
    }

    final projectName = value.trim();

    if (projectName.length < 3) {
      return 'Project name must be at least 3 characters long';
    }

    if (projectName.length > 50) {
      return 'Project name must be less than 50 characters';
    }

    return null;
  }
}

class OfflineConfigPage extends StatefulWidget {
  const OfflineConfigPage({super.key});

  @override
  State<OfflineConfigPage> createState() => _OfflineConfigPageState();
}

class _OfflineConfigPageState extends State<OfflineConfigPage> {
  // Form controllers
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _projectNameController = TextEditingController();
  final TextEditingController _moduleCountController = TextEditingController();
  int _selectedModuleCount = 1;
  final TextEditingController _zoneCountController = TextEditingController();

  // Form key
  final _formKey = GlobalKey<FormState>();

  // Loading state
  bool _isSaving = false;
  bool _isStarting = false;
  bool _isTestingConnection = false;

  // Zone mapping state
  String _zoneMappingFolder = '';
  bool _isConfiguringMapping = false;

  // Online/Offline mode state
  bool _isOnlineMode = false;

  // Focus nodes
  late FocusNode _ipFocusNode;
  late FocusNode _portFocusNode;
  late FocusNode _projectNameFocusNode;
  late FocusNode _moduleCountFocusNode;
  late FocusNode _zoneCountFocusNode;

  // 🔥 NEW: Service instances for the fix
  final UnifiedIPService _unifiedIPService = UnifiedIPService();
  final WebSocketModeManager _webSocketMode = WebSocketModeManager.instance;

  @override
  void initState() {
    super.initState();
    _initializeFocusNodes();
    _loadSavedConfiguration();
    _loadZoneMappingFolder();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _projectNameController.dispose();
    _moduleCountController.dispose();
    _zoneCountController.dispose();
    _ipFocusNode.dispose();
    _portFocusNode.dispose();
    _projectNameFocusNode.dispose();
    _moduleCountFocusNode.dispose();
    _zoneCountFocusNode.dispose();
    super.dispose();
  }

  void _initializeFocusNodes() {
    _ipFocusNode = FocusNode();
    _portFocusNode = FocusNode();
    _projectNameFocusNode = FocusNode();
    _moduleCountFocusNode = FocusNode();
    _zoneCountFocusNode = FocusNode();
  }

  void _updateZoneCount() {
    final totalZones = _selectedModuleCount * 5;
    _zoneCountController.text = '$totalZones';
    _moduleCountController.text = '$_selectedModuleCount';
  }

  /// Load saved zone mapping folder path
  Future<void> _loadZoneMappingFolder() async {
    try {
      final folderPath = await ZoneMappingService.loadMappingFolderPath();
      if (folderPath.isNotEmpty) {
        setState(() {
          _zoneMappingFolder = folderPath;
        });
        AppLogger.info('Zone mapping folder loaded: $folderPath', tag: 'OFFLINE_CONFIG');
      }
    } catch (e) {
      AppLogger.error('Error loading zone mapping folder: $e', tag: 'OFFLINE_CONFIG');
    }
  }

  Widget _buildModuleDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Number of Modules',
          style: TextStyle(
            fontWeight: FontWeight.w300,
            fontSize: 16,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.grey[300]!,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _selectedModuleCount,
              isExpanded: true,
              icon: const Icon(Icons.arrow_drop_down),
              items: List.generate(63, (index) {
                final moduleNumber = index + 1;
                return DropdownMenuItem<int>(
                  value: moduleNumber,
                  child: Text(
                    '$moduleNumber Module${moduleNumber > 1 ? 's' : ''}',
                    style: const TextStyle(fontSize: 16),
                  ),
                );
              }),
              onChanged: _isSaving ? null : (value) {
                if (value != null) {
                  setState(() {
                    _selectedModuleCount = value;
                    _updateZoneCount();
                  });
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOnlineOfflineToggle() {
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  _isOnlineMode ? Icons.cloud_done : Icons.cloud_off,
                  color: _isOnlineMode ? Colors.green : Colors.grey,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Online Mode',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                          color: _isOnlineMode ? Colors.green : Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isOnlineMode
                            ? 'Firebase connected monitoring'
                            : 'Direct ESP32 connection',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _isOnlineMode,
                  onChanged: _isSaving ? null : (bool value) {
                    setState(() {
                      _isOnlineMode = value;
                    });
                  },
                  activeThumbColor: Colors.green,
                  inactiveThumbColor: Colors.grey[400],
                  activeTrackColor: Colors.green.withValues(alpha: 0.3),
                  inactiveTrackColor: Colors.grey.withValues(alpha: 0.2),
                ),
              ],
            ),
            if (_isOnlineMode) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.green[700],
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Online mode uses Firebase for remote monitoring',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green[700],
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildZoneCountDisplay() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Total Zones',
          style: TextStyle(
            fontWeight: FontWeight.w300,
            fontSize: 16,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _zoneCountController,
          enabled: false, // Read-only
          decoration: InputDecoration(
            hintText: '5',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: Colors.green),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.grey[200]!),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            fillColor: Colors.grey[50],
            filled: true,
            helperText: '5 zones per module • Total: ${_selectedModuleCount * 5} zones',
            helperStyle: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          style: const TextStyle(
            fontSize: 16,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildZoneNameConfigButton() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ElevatedButton.icon(
        onPressed: _navigateToZoneNameConfig,
        icon: const Icon(Icons.edit),
        label: const Text('Zone Name Config'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.all(16),
          backgroundColor: Colors.blue[600],
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 2,
        ),
      ),
    );
  }

  void _navigateToZoneNameConfig() {
    if (_formKey.currentState!.validate()) {
      final projectName = _projectNameController.text.trim();
      final moduleCount = _selectedModuleCount;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ZoneNameConfigPage(
            projectName: projectName,
            moduleCount: moduleCount,
          ),
        ),
      );
    } else {
      // Show error if form is not valid
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please configure project name and modules first'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  /// Build Zone Mapping button
  Widget _buildZoneMappingButton() {
    final bool hasMapping = _zoneMappingFolder.isNotEmpty;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ElevatedButton.icon(
        onPressed: _isConfiguringMapping ? null : _selectZoneMappingFolder,
        icon: _isConfiguringMapping
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.map),
        label: Text(_isConfiguringMapping ? 'Configuring...' : 'Mapping Zona'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.all(16),
          backgroundColor: hasMapping ? Colors.purple[600] : Colors.purple[400],
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 2,
        ),
      ),
    );
  }

  /// Select zone mapping folder
  Future<void> _selectZoneMappingFolder() async {
    if (!mounted) return;

    setState(() {
      _isConfiguringMapping = true;
    });

    try {
      // Use native Android Intent folder picker with fallback
      String? selectedDirectory = await _openFolderPicker();

      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        // Validate the selected folder
        final foundZones = await ZoneMappingService.validateMappingFolder(selectedDirectory);

        if (foundZones.isEmpty) {
          // Get detailed analysis of why validation failed
          final analysis = await ZoneMappingService.analyzeFolder(selectedDirectory);
          _showDetailedAnalysisDialog(analysis, selectedDirectory);
        } else {
          // Save the folder path
          final success = await ZoneMappingService.saveMappingFolderPath(selectedDirectory);
          if (success) {
            setState(() {
              _zoneMappingFolder = selectedDirectory;
            });
            _showSuccessSnackBar(
              'Zone mapping folder configured successfully!\n'
              'Found ${foundZones.length} zone mapping images\n'
              'Path: $selectedDirectory'
            );
            AppLogger.info('Zone mapping configured with ${foundZones.length} images at: $selectedDirectory', tag: 'OFFLINE_CONFIG');
          } else {
            _showErrorSnackBar('Failed to save zone mapping configuration');
          }
        }
      } else {
        // User cancelled selection
        AppLogger.info('User cancelled folder selection', tag: 'OFFLINE_CONFIG');
      }

    } catch (e) {
      AppLogger.error('Error selecting zone mapping folder: $e', tag: 'OFFLINE_CONFIG');
      _showErrorSnackBar('Failed to select zone mapping folder: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isConfiguringMapping = false;
        });
      }
    }
  }

  /// Show error snackbar
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[600],
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Show success snackbar
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green[600],
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Show detailed folder analysis dialog
  void _showDetailedAnalysisDialog(String analysis, String folderPath) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.folder_open, color: Colors.orange[600]),
            const SizedBox(width: 8),
            const Text('Folder Analysis'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '📂 Path: $folderPath',
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                analysis,
                style: const TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Try folder selection again after showing analysis
              _selectZoneMappingFolder();
            },
            child: const Text('Try Different Folder'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSavedConfiguration() async {
    

    try {
      final prefs = await SharedPreferences.getInstance();

      // 🔥 Load online mode preference
      _isOnlineMode = prefs.getBool('online_mode') ?? false;
      

      // 🔥 Load saved values with logging
      final savedIp = prefs.getString('offline_ip') ?? '192.168.1.100';
      final savedPort = prefs.getString('offline_port') ?? '80';
      final savedProject = prefs.getString('offline_project_name') ?? 'Fire Alarm System';
      final savedModuleCount = prefs.getString('offline_module_count') ?? '1';

      
      
      
      
      

      // 🔥 CRITICAL: Reset controllers with fresh state to prevent validation conflicts
      _ipController.clear();
      _portController.clear();
      _projectNameController.clear();
      _moduleCountController.clear();

      // Set new values
      _ipController.text = savedIp;
      _portController.text = savedPort;
      _projectNameController.text = savedProject;
      _moduleCountController.text = savedModuleCount;

      // Parse module count safely
      _selectedModuleCount = int.tryParse(savedModuleCount) ?? 1;
      _selectedModuleCount = _selectedModuleCount.clamp(1, 63); // Ensure valid range

      

      // Update zone count display and trigger UI rebuild
      _updateZoneCount();
      setState(() {}); // Critical: Trigger dropdown rebuild to show saved value



    } catch (e, stackTrace) {
      // Configuration loading failed - resetting to safe defaults
      print('Error: Failed to load configuration: $e');
      print('Stack trace: $stackTrace');

      // 🔥 CRITICAL: Reset controllers to safe defaults on error
      _ipController.clear();
      _portController.clear();
      _projectNameController.clear();
      _moduleCountController.clear();

      // Set default values
      _ipController.text = '192.168.1.100';
      _portController.text = '80';
      _projectNameController.text = 'Fire Alarm System';
      _moduleCountController.text = '1';
      _selectedModuleCount = 1;
      _isOnlineMode = false;

      _updateZoneCount();
      setState(() {}); // Ensure consistent UI state in error path


    }
  }

  Future<void> _saveOnly() async {
    
    

    // 🔥 CRITICAL: Add detailed validation logging
    bool isFormValid = _formKey.currentState?.validate() ?? false;
    

    if (!isFormValid) {
      

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please fill in all required fields correctly'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    
    setState(() {
      _isSaving = true;
    });

    try {
      // 🔥 Log controller values for debugging
      
      
      
      
      
      

      final prefs = await SharedPreferences.getInstance();

      // Save configuration
      await prefs.setString('offline_ip', _ipController.text.trim());
      await prefs.setString('offline_port', _portController.text.trim());
      await prefs.setString('offline_project_name', _projectNameController.text.trim());
      await prefs.setString('offline_module_count', '$_selectedModuleCount');
      await prefs.setBool('online_mode', _isOnlineMode);

      // 🔥 CRITICAL FIX: Sync with UnifiedIPService for navigation compatibility
      await _unifiedIPService.setIP(_ipController.text.trim());
      await _unifiedIPService.setPort(int.parse(_portController.text.trim()));
      await _unifiedIPService.setProjectName(_projectNameController.text.trim());
      await _unifiedIPService.setModuleCount(_selectedModuleCount);
      await _unifiedIPService.markConfigured(configured: true);

      // 🔥 CRITICAL FIX: Sync to legacy storage for IPConfigurationService compatibility
      await _unifiedIPService.syncToHomeSettings();

      // Mark offline mode as configured (backward compatibility)
      await prefs.setBool('offline_configured', true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_isOnlineMode ? 'Online' : 'Offline'} configuration saved successfully!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        
      }
    } catch (e, stackTrace) {
      // Configuration save failed
      print('Error: Failed to save configuration: $e');
      print('Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save configuration: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        
      }
    }
  }

  Future<void> _startMonitoring() async {
    // Check if configuration is saved first using UnifiedIPService
    final isConfigured = await _unifiedIPService.isConfigured();

    if (!isConfigured) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please save configuration first'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() {
      _isStarting = true;
    });

    try {
      // 🔥 CRITICAL FIX: Initialize WebSocketModeManager before navigation
      // This fixes the "Case 1 GAGAL" bug where WebSocket data doesn't flow
      final config = await _unifiedIPService.getConfiguration();

      // 🔥 CRITICAL FIX: Initialize WebSocket mode with offline configuration
      // This fixes the "Case 1 GAGAL" bug - update IP to trigger WebSocket setup
      await _webSocketMode.updateESP32IP(config['ip'] as String);

      // Initialize manager (this will switch to WebSocket mode if needed)
      await _webSocketMode.initializeManager(null); // We don't have FireAlarmData here, but it should be initialized later

      AppLogger.info('WebSocketModeManager initialized for offline mode from OfflineConfig');

      // 🔥 Store context reference to avoid async gap issues
      final navigationContext = context;

      if (_isOnlineMode) {
        // 🔥 Show confirmation dialog when online user tries to access offline mode
        final shouldContinueToOffline = await _showOnlineModeConfirmation();

        if (!shouldContinueToOffline) {
          return; // Stay on config page
        }
      }

      // Check context is still mounted before navigation
      if (!navigationContext.mounted) {
        return;
      }

      // 🔥 Enhanced: Set auto-redirect flag with retry mechanism for future app restarts
      bool flagSetSuccess = false;
      int retryCount = 0;
      const maxRetries = 3;

      while (!flagSetSuccess && retryCount < maxRetries) {
        try {
          final prefs = await SharedPreferences.getInstance();

          // Set flag with verification
          await prefs.setBool('auto_redirect_to_offline', true);

          // Verify flag was actually set
          final verification = prefs.getBool('auto_redirect_to_offline');
          if (verification == true) {
            flagSetSuccess = true;
            AppLogger.info('✅ [AUTO-REDIRECT] Flag successfully set and verified (attempt ${retryCount + 1})', tag: 'AUTO_REDIRECT');
          } else {
            throw Exception('Flag verification failed');
          }
        } catch (e) {
          retryCount++;
          AppLogger.warning('⚠️ [AUTO-REDIRECT] Flag setting failed (attempt $retryCount): $e', tag: 'AUTO_REDIRECT');

          if (retryCount < maxRetries) {
            await Future.delayed(Duration(milliseconds: 500 * retryCount)); // Progressive delay
          }
        }
      }

      if (!flagSetSuccess) {
        AppLogger.error('❌ [AUTO-REDIRECT] Failed to set flag after $maxRetries attempts', tag: 'AUTO_REDIRECT');
        // Show user warning but continue with navigation
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Warning: Auto-redirect may not work after app restart'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
      }

      // 🔥 CRITICAL: Initialize WebSocket mode BEFORE navigation for ESP32 connectivity
      try {
        AppLogger.info('🔥 Setting up WebSocket mode for ESP32 connection', tag: 'OFFLINE_CONFIG');

        // Update WebSocket manager IP configuration
        final wsManager = WebSocketModeManager.instance;
        await wsManager.updateESP32IP(config['ip'] as String);

        // Force WebSocket mode activation
        final toggleSuccess = await wsManager.toggleMode();
        if (toggleSuccess) {
          AppLogger.info('✅ WebSocket mode successfully enabled', tag: 'OFFLINE_CONFIG');
        } else {
          AppLogger.warning('⚠️ WebSocket mode toggle failed, but continuing anyway', tag: 'OFFLINE_CONFIG');
        }
      } catch (wsError) {
        AppLogger.error('❌ WebSocket setup error: $wsError', tag: 'OFFLINE_CONFIG');
        // Continue anyway - monitoring page will handle WebSocket initialization
      }

      // Navigate to offline monitoring page (for both online and offline modes)
      Navigator.pushReplacement(
        navigationContext,
        MaterialPageRoute(
          builder: (context) => OfflineMonitoringPage(
            ip: config['ip'] as String,
            port: config['port'] as int,
            projectName: config['projectName'] as String,
            moduleCount: config['moduleCount'] as int,
          ),
        ),
      );
    } catch (navError) {
      // Navigation error occurred
      AppLogger.error('Navigation error occurred', error: navError);

      // Store context before async operations to avoid lifecycle issues
      final errorContext = context;

      // Use WidgetsBinding.instance.addPostFrameCallback for safety
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (errorContext.mounted) {
          ScaffoldMessenger.of(errorContext).showSnackBar(
            SnackBar(
              content: Text('Navigation failed: $navError'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  /// Show confirmation dialog when online user tries to access offline monitoring
  Future<bool> _showOnlineModeConfirmation() async {
    

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // User must make a choice
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.wifi,
                color: Colors.green,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Online Mode Detected',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.green[700],
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'You have internet connectivity available. Online mode provides real-time Firebase synchronization and remote monitoring capabilities.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.orange[700],
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Are you sure you want to continue to full offline monitoring mode?',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Offline mode will use direct ESP32 connection without Firebase synchronization.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          actions: [
            TextButton(
              onPressed: () {
                
                Navigator.of(context).pop(false); // Cancel
              },
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                
                Navigator.of(context).pop(true); // Continue to offline
              },
              icon: const Icon(Icons.wifi_off, size: 18),
              label: const Text('Continue Offline'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        );
      },
    );

    
    return result ?? false;
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isTestingConnection = true;
    });

    try {
      // Basic connection test using socket connection
      final ip = _ipController.text.trim();
      final port = int.parse(_portController.text.trim());

      // Simulate connection test
      AppLogger.info('Testing connection to $ip:$port');
      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection test successful!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection test failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTestingConnection = false;
        });
      }
    }
  }

  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.grey),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isOnlineMode ? 'ONLINE CONFIG' : 'OFFLINE CONFIG',
          style: TextStyle(
            fontWeight: FontWeight.w300,
            letterSpacing: 4,
            color: _isOnlineMode ? Colors.green : Colors.black,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton.icon(
            onPressed: _isTestingConnection ? null : _testConnection,
            icon: _isTestingConnection
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: Colors.grey,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.wifi_tethering, size: 18),
            label: Text(
              _isTestingConnection ? 'Testing...' : 'Test',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildOnlineOfflineToggle(),
                      const SizedBox(height: 20),
                      _buildLabeledTextField('ESP32 IP Address', _ipController,
                        TextInputType.number, [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                        (value) => OfflineValidationHelpers.validateIpAddress(value, isOnlineMode: _isOnlineMode), '192.168.1.100'),
                      const SizedBox(height: 20),
                      _buildLabeledTextField('Port', _portController,
                        TextInputType.number, [FilteringTextInputFormatter.digitsOnly],
                        (value) => OfflineValidationHelpers.validatePort(value, isOnlineMode: _isOnlineMode), '80'),
                      const SizedBox(height: 20),
                      _buildLabeledTextField('Project Name', _projectNameController,
                        TextInputType.text, [],
                        OfflineValidationHelpers.validateProjectName, 'Fire Alarm System'),
                      const SizedBox(height: 20),
                      _buildModuleDropdown(),
                      const SizedBox(height: 20),
                      _buildZoneCountDisplay(),
                      const SizedBox(height: 8),
                      _buildZoneNameConfigButton(),
                      const SizedBox(height: 8),
                      _buildZoneMappingButton(),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : _saveOnly,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: Colors.blue[400]!),
                    ),
                    child: _isSaving
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Colors.blue,
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('Saving...'),
                            ],
                          )
                        : Text(
                            'Save',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.blue[600],
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: (_isSaving || _isStarting) ? null : _startMonitoring,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                    ),
                    child: _isStarting
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('Starting...'),
                            ],
                          )
                        : const Text('Start Monitoring'),
                  ),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildLabeledTextField(String label, TextEditingController controller,
      TextInputType keyboardType, List<TextInputFormatter> inputFormatters,
      String? Function(String?) validator, String hintText, {bool? enabled}) {
    final isEnabled = enabled ?? (!_isSaving && !_isOnlineMode);
    final isDisabledField = _isOnlineMode && (label.contains('ESP32') || label.contains('Port'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w300,
            fontSize: 16,
            letterSpacing: 1,
            color: isDisabledField ? Colors.grey[400] : Colors.black,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          enabled: isEnabled,
          decoration: InputDecoration(
            hintText: isDisabledField ? 'Not available in online mode' : hintText,
            hintStyle: TextStyle(
              color: isDisabledField ? Colors.grey[400] : Colors.grey[500],
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: isDisabledField ? Colors.grey[200]! : Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(
                color: isDisabledField ? Colors.grey[200]! : Colors.grey[300]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(
                color: isDisabledField ? Colors.grey[300]! : Colors.green,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.grey[200]!),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: const BorderSide(color: Colors.red),
            ),
            filled: isDisabledField,
            fillColor: Colors.grey[50],
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          textInputAction: TextInputAction.next,
        ),
      ],
    );
  }

  /// Open native folder picker with fallback options
  Future<String?> _openFolderPicker() async {
    print('🗂️ FOLDER PICKER: Starting native folder picker attempt');
    print('🔑 Checking file_picker availability...');

    try {
      // Android 13+ requires different permissions for media access
      // For folder access, we need to request multiple permissions
      Map<Permission, PermissionStatus> statuses;

      print('📱 Requesting storage permissions for Android 13+...');

      // Try to get all necessary permissions for folder access
      statuses = await [
        // For Android 13+ (API 33+) - these are the granular media permissions
        Permission.photos,
        Permission.videos,
        Permission.audio,
        // For older Android versions
        Permission.storage,
        // Additional permission for full file system access
        Permission.manageExternalStorage,
      ].request();

      print('🔍 Permission status results:');
      statuses.forEach((permission, status) {
        print('   - ${permission.toString()}: $status');
        print('     isGranted: ${status.isGranted}');
        print('     isDenied: ${status.isDenied}');
        print('     isPermanentlyDenied: ${status.isPermanentlyDenied}');
        print('     isLimited: ${status.isLimited}');
      });

      // Check if we have any useful permission granted
      final hasAnyPermission = statuses.values.any((status) => status.isGranted);
      final hasStoragePermission = statuses[Permission.storage]?.isGranted ?? false;
      final hasPhotosPermission = statuses[Permission.photos]?.isGranted ?? false;
      final hasManagePermission = statuses[Permission.manageExternalStorage]?.isGranted ?? false;

      print('📊 Permission analysis:');
      print('   - hasAnyPermission: $hasAnyPermission');
      print('   - hasStoragePermission (legacy): $hasStoragePermission');
      print('   - hasPhotosPermission (Android 13+): $hasPhotosPermission');
      print('   - hasManagePermission (full access): $hasManagePermission');

      if (!hasAnyPermission) {
        print('❌ NO STORAGE PERMISSIONS GRANTED - falling back to manual input');
        _showErrorSnackBar('Storage permission required for folder access');
        print('🔄 Calling _showImprovedFolderDialog() due to permission denied');
        return await _showImprovedFolderDialog();
      }

      print('✅ At least one storage permission granted - proceeding with FilePicker');
      print('📂 Attempting FilePicker.platform.getDirectoryPath()...');
      print('   - dialogTitle: "Select Zone Mapping Folder"');
      print('   - lockParentWindow: false (removing potential issue)');

      // Try native file picker first (remove lockParentWindow which might cause issues)
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Zone Mapping Folder',
        lockParentWindow: false, // Changed to false to avoid potential issues
      );

      print('📋 FilePicker result: "$selectedDirectory"');
      print('📋 FilePicker null check: ${selectedDirectory == null}');
      print('📋 FilePicker empty check: ${selectedDirectory?.isEmpty ?? true}');

      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        print('✅ SUCCESS: Native folder picker selected: "$selectedDirectory"');
        print('💾 Calling saveMappingFolderPath() with: "$selectedDirectory"');
        return selectedDirectory;
      } else {
        print('⚠️ FilePicker returned null or empty - falling back to manual input');
        print('🔄 Calling _showImprovedFolderDialog() due to FilePicker failure');
        return await _showImprovedFolderDialog();
      }
    } catch (e, stackTrace) {
      print('❌ EXCEPTION in native folder picker: $e');
      print('📋 Stack trace: $stackTrace');
      _showErrorSnackBar('Failed to open native folder picker');
      print('🔄 Calling _showImprovedFolderDialog() due to exception');
      return await _showImprovedFolderDialog();
    }
  }

  Future<String?> _showImprovedFolderDialog() async {
    final TextEditingController controller = TextEditingController();

    return showDialog<String?>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Zone Mapping Folder'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.folder_open, color: Colors.green[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Android folder access is now ready! Please enter the path to your zone mapping folder.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.green[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '📁 What is Zone Mapping?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Display custom images for each fire alarm zone in the detail view.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                const Text(
                  '📸 Image Requirements:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• File names: 1.jpg, 2.jpg, 3.jpg, etc. (matching zone numbers)'),
                      Text('• Formats: .jpg, .jpeg, .png, .gif, .bmp, .webp'),
                      Text('• Location: All images in one folder'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '📂 Find Your Path:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('1. Open your File Manager app', style: TextStyle(fontWeight: FontWeight.w500)),
                      Text('2. Create folder: /storage/emulated/0/ZoneMappings'),
                      Text('3. Copy your zone images (1.jpg, 2.jpg, etc.)'),
                      Text('4. Long-press folder → Details → Copy path'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '🎯 Common Android Paths:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• /storage/emulated/0/ZoneMappings', style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.black87)),
                      Text('• /storage/emulated/0/Download/ZoneImages', style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.black87)),
                      Text('• /sdcard/Documents/FireAlarmZones', style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.black87)),
                      Text('• /storage/emulated/0/Pictures', style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.black87)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: 'Enter Folder Path',
                    hintText: '/storage/emulated/0/ZoneMappings',
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.grey[50],
                    prefixIcon: const Icon(Icons.folder),
                    helperText: 'Example: /storage/emulated/0/ZoneMappings',
                  ),
                  autofocus: true,
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                Text(
                  '💡 Tip: You can copy the path directly from your File Manager app',
                  style: TextStyle(fontSize: 12, color: Colors.blue, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.cancel),
              label: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final path = controller.text.trim();
                if (path.isNotEmpty) {
                  Navigator.of(context).pop(path);
                } else {
                  _showErrorSnackBar('Please enter a folder path');
                }
              },
              icon: const Icon(Icons.check_circle),
              label: const Text('Select Folder'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }
}