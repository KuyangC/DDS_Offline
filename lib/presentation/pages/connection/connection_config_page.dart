import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../monitoring/offline_monitoring_page.dart';
import '../connection/zone_name_config_page.dart';
import '../../../data/services/logger.dart';
import '../../../data/datasources/local/zone_mapping_service.dart';

/// Connection Configuration Page
///
/// First page shown to user - allows configuring ESP32 connection parameters
/// before starting the fire alarm monitoring system.
class ConnectionConfigPage extends StatefulWidget {
  const ConnectionConfigPage({super.key});

  @override
  State<ConnectionConfigPage> createState() => _ConnectionConfigPageState();
}

class _ConnectionConfigPageState extends State<ConnectionConfigPage> {
  // Form key
  final _formKey = GlobalKey<FormState>();

  // Text editing controllers
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  final _projectNameController = TextEditingController();
  final _moduleCountController = TextEditingController();

  // UI state
  bool _isLoading = false;
  String? _errorMessage;
  bool _isConfiguringMapping = false;

  // Constants
  static const String _defaultIP = '192.168.1.100';
  static const int _defaultPort = 81;
  static const String _defaultProjectName = 'DDS Project';
  static const int _defaultModuleCount = 63;
  static const int _zonesPerModule = 5;
  static const int _maxModuleCount = 63;
  static const int _minPort = 1;
  static const int _maxPort = 65535;

  @override
  void initState() {
    super.initState();
    _loadSavedConfiguration();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _projectNameController.dispose();
    _moduleCountController.dispose();
    super.dispose();
  }

  /// Loads saved configuration from SharedPreferences
  Future<void> _loadSavedConfiguration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _ipController.text = prefs.getString('ip') ?? _defaultIP;
        _portController.text = (prefs.getInt('port') ?? _defaultPort).toString();
        _projectNameController.text = prefs.getString('projectName') ?? _defaultProjectName;
        _moduleCountController.text = (prefs.getInt('moduleCount') ?? _defaultModuleCount).toString();
      });
    } catch (e) {
      AppLogger.error('Failed to load saved configuration', error: e);
    }
  }

  /// Validates and saves configuration to SharedPreferences
  Future<void> _saveConfiguration() async {
    // Validate form
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final config = _parseConfigurationFromForm();

      // Save to persistent storage
      await _saveConfigurationToPrefs(prefs, config);

      if (!mounted) return;

      setState(() => _isLoading = false);
      _showSuccessSnackBar('Configuration saved successfully');
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: ${e.toString()}';
      });
      _showErrorSnackBar('Failed to save configuration');
    }
  }

  /// Navigates to monitoring page with current configuration
  Future<void> _startMonitoring() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final config = await _loadConfiguration(prefs);

      if (!mounted) return;

      _navigateToMonitoringPage(config);
    } catch (e) {
      _showErrorSnackBar('Failed to start monitoring: ${e.toString()}');
    }
  }

  /// Parses configuration from form text controllers
  Map<String, dynamic> _parseConfigurationFromForm() {
    return {
      'ip': _ipController.text.trim(),
      'port': int.parse(_portController.text.trim()),
      'projectName': _projectNameController.text.trim(),
      'moduleCount': int.parse(_moduleCountController.text.trim()),
    };
  }

  /// Saves configuration to SharedPreferences
  Future<void> _saveConfigurationToPrefs(
    SharedPreferences prefs,
    Map<String, dynamic> config,
  ) async {
    await prefs.setString('ip', config['ip'] as String);
    await prefs.setInt('port', config['port'] as int);
    await prefs.setString('projectName', config['projectName'] as String);
    await prefs.setInt('moduleCount', config['moduleCount'] as int);
  }

  /// Loads configuration from SharedPreferences or form
  Future<Map<String, dynamic>> _loadConfiguration(SharedPreferences prefs) async {
    return {
      'ip': prefs.getString('ip') ?? _ipController.text.trim(),
      'port': prefs.getInt('port') ?? int.parse(_portController.text.trim()),
      'projectName': prefs.getString('projectName') ?? _projectNameController.text.trim(),
      'moduleCount': prefs.getInt('moduleCount') ?? int.parse(_moduleCountController.text.trim()),
    };
  }

  /// Navigates to monitoring page
  void _navigateToMonitoringPage(Map<String, dynamic> config) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => OfflineMonitoringPage(
          ip: config['ip'] as String,
          port: config['port'] as int,
          projectName: config['projectName'] as String,
          moduleCount: config['moduleCount'] as int,
        ),
      ),
    );
  }

  /// Navigates to zone name configuration page
  void _navigateToZoneNameConfig() async {
    // Get module count and project name from form
    final moduleCount = int.tryParse(_moduleCountController.text.trim()) ?? _defaultModuleCount;
    final projectName = _projectNameController.text.trim().isEmpty
        ? _defaultProjectName
        : _projectNameController.text.trim();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ZoneNameConfigPage(
          totalModules: moduleCount,
          projectName: projectName, // 🔥 FIX: Pass project name
        ),
      ),
    );
  }

  /// Configure zone mapping folder directly
  Future<void> _navigateToZoneMappingConfig() async {
    await _selectZoneMappingFolder();
  }

  /// Shows success snackbar message
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Shows error snackbar message
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
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
            _showSuccessSnackBar(
              'Zone mapping folder configured successfully!\n'
              'Found ${foundZones.length} zone mapping images\n'
              'Path: $selectedDirectory'
            );
            AppLogger.info('Zone mapping configured with ${foundZones.length} images at: $selectedDirectory', tag: 'CONNECTION_CONFIG');
          } else {
            _showErrorSnackBar('Failed to save zone mapping configuration');
          }
        }
      } else {
        // User cancelled selection
        AppLogger.info('User cancelled folder selection', tag: 'CONNECTION_CONFIG');
      }

    } catch (e) {
      AppLogger.error('Error selecting zone mapping folder: $e', tag: 'CONNECTION_CONFIG');
      _showErrorSnackBar('Failed to select zone mapping folder: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isConfiguringMapping = false;
        });
      }
    }
  }

  /// Open native folder picker with fallback options
  Future<String?> _openFolderPicker() async {
    AppLogger.info('Starting native folder picker attempt', tag: 'ZONE_MAPPING');

    try {
      // Android 13+ requires different permissions for media access
      Map<Permission, PermissionStatus> statuses;

      AppLogger.info('Requesting storage permissions...', tag: 'ZONE_MAPPING');

      // Try to get all necessary permissions for folder access
      statuses = await [
        Permission.photos,
        Permission.videos,
        Permission.audio,
        Permission.storage,
        Permission.manageExternalStorage,
      ].request();

      // Check if we have any useful permission granted
      final hasAnyPermission = statuses.values.any((status) => status.isGranted);

      if (!hasAnyPermission) {
        AppLogger.warning('No storage permissions granted - using manual input', tag: 'ZONE_MAPPING');
        _showErrorSnackBar('Storage permission required for folder access');
        return await _showManualFolderInputDialog();
      }

      AppLogger.info('Permissions granted - opening folder picker', tag: 'ZONE_MAPPING');

      // Try native file picker
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Zone Mapping Folder',
        lockParentWindow: false,
      );

      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        AppLogger.info('Folder selected: $selectedDirectory', tag: 'ZONE_MAPPING');
        return selectedDirectory;
      } else {
        AppLogger.info('Folder picker cancelled - using manual input', tag: 'ZONE_MAPPING');
        return await _showManualFolderInputDialog();
      }
    } catch (e) {
      AppLogger.error('Exception in folder picker: $e', tag: 'ZONE_MAPPING');
      _showErrorSnackBar('Failed to open native folder picker');
      return await _showManualFolderInputDialog();
    }
  }

  /// Show manual folder input dialog as fallback
  Future<String?> _showManualFolderInputDialog() async {
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
                          'Enter the path to your zone mapping folder.',
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
                  'Image Requirements:',
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
                      Text('• File names: 1.jpg, 2.jpg, 3.jpg, etc.'),
                      Text('• Formats: .jpg, .jpeg, .png, .gif, .bmp, .webp'),
                      Text('• All images in one folder'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Common Paths:',
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
                      Text('/storage/emulated/0/ZoneMappings', style: TextStyle(fontSize: 11, fontFamily: 'monospace')),
                      Text('/storage/emulated/0/Download/ZoneImages', style: TextStyle(fontSize: 11, fontFamily: 'monospace')),
                      Text('/sdcard/Documents/FireAlarmZones', style: TextStyle(fontSize: 11, fontFamily: 'monospace')),
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
                  ),
                  autofocus: true,
                  maxLines: 2,
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
              _selectZoneMappingFolder();
            },
            child: const Text('Try Different Folder'),
          ),
        ],
      ),
    );
  }

  /// Calculates total zones based on module count
  int _calculateTotalZones() {
    final moduleCountText = _moduleCountController.text;
    if (moduleCountText.isEmpty) {
      return _defaultModuleCount * _zonesPerModule;
    }
    final moduleCount = int.tryParse(moduleCountText) ?? _defaultModuleCount;
    return moduleCount * _zonesPerModule;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildLogo(),
                  const SizedBox(height: 24),
                  _buildTitle(),
                  const SizedBox(height: 8),
                  _buildSubtitle(),
                  const SizedBox(height: 32),
                  if (_errorMessage != null) ...[
                    _buildErrorMessage(),
                    const SizedBox(height: 16),
                  ],
                  _buildIPField(),
                  const SizedBox(height: 16),
                  _buildPortField(),
                  const SizedBox(height: 16),
                  _buildProjectNameField(),
                  const SizedBox(height: 16),
                  _buildModuleCountField(),
                  const SizedBox(height: 16),
                  _buildZoneNameConfigButton(),
                  const SizedBox(height: 8),
                  _buildZoneMappingConfigButton(),
                  const SizedBox(height: 24),
                  _buildInfoCard(),
                  const SizedBox(height: 24),
                  _buildSaveButton(),
                  const SizedBox(height: 16),
                  _buildStartButton(),
                  const SizedBox(height: 16),
                  _buildVersionInfo(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Builds logo widget
  Widget _buildLogo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.transparent,  // Hilang background biru
        shape: BoxShape.circle,
      ),
      child: Image.asset(
        'assets/data/images/LOGO TEXT.png',
        width: 200,
        height: 200,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // Fallback ke icon jika gambar tidak ditemukan
          return const Icon(
            Icons.settings_input_antenna,
            size: 80,
            color: Colors.blue,
          );
        },
      ),
    );
  }

  /// Builds title widget
  Widget _buildTitle() {
    return const Text(
      'DDS Connection Config',
      style: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
      textAlign: TextAlign.center,
    );
  }

  /// Builds subtitle widget
  Widget _buildSubtitle() {
    return Text(
      'Configure your fire alarm monitoring system',
      style: TextStyle(
        fontSize: 14,
        color: Colors.grey[600],
      ),
      textAlign: TextAlign.center,
    );
  }

  /// Builds error message widget
  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds IP address text field
  Widget _buildIPField() {
    return TextFormField(
      controller: _ipController,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: 'IP Address',
        hintText: _defaultIP,
        prefixIcon: const Icon(Icons.computer),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Colors.white,
      ),
      validator: _validateIP,
    );
  }

  /// Builds port text field
  Widget _buildPortField() {
    return TextFormField(
      controller: _portController,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: 'Port',
        hintText: '$_defaultPort',
        prefixIcon: const Icon(Icons.settings_ethernet),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Colors.white,
      ),
      validator: _validatePort,
    );
  }

  /// Builds project name text field
  Widget _buildProjectNameField() {
    return TextFormField(
      controller: _projectNameController,
      decoration: InputDecoration(
        labelText: 'Project Name',
        hintText: _defaultProjectName,
        prefixIcon: const Icon(Icons.business),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Colors.white,
      ),
      validator: _validateProjectName,
    );
  }

  /// Builds module count text field
  Widget _buildModuleCountField() {
    return TextFormField(
      controller: _moduleCountController,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: 'Total Address (Modules)',
        hintText: '$_defaultModuleCount',
        prefixIcon: const Icon(Icons.memory),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Colors.white,
        helperText: 'Each module has $_zonesPerModule zones',
      ),
      validator: _validateModuleCount,
    );
  }

  /// Builds zone name configuration button
  Widget _buildZoneNameConfigButton() {
    return ElevatedButton.icon(
      onPressed: _navigateToZoneNameConfig,
      icon: const Icon(Icons.edit),
      label: const Text('Configure Zone Names'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// Builds zone mapping configuration button
  Widget _buildZoneMappingConfigButton() {
    return ElevatedButton.icon(
      onPressed: _isConfiguringMapping ? null : _navigateToZoneMappingConfig,
      icon: _isConfiguringMapping
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : const Icon(Icons.map),
      label: Text(_isConfiguringMapping ? 'Configuring...' : 'Configure Zone Mapping'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.purple.shade700,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// Builds info card showing total zones
  Widget _buildInfoCard() {
    final totalZones = _calculateTotalZones();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Total Zones: $totalZones',
              style: TextStyle(
                color: Colors.blue.shade700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds save configuration button
  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _saveConfiguration,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: _isLoading
          ? const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.save),
                SizedBox(width: 8),
                Text(
                  'SAVE CONFIGURATION',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
    );
  }

  /// Builds start monitoring button
  Widget _buildStartButton() {
    return ElevatedButton(
      onPressed: _startMonitoring,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.play_arrow),
          SizedBox(width: 8),
          Text(
            'START MONITORING',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// Builds version info footer
  Widget _buildVersionInfo() {
    return Text(
      'Version 1.0.0 | DDS Fire Alarm System',
      style: TextStyle(
        fontSize: 12,
        color: Colors.grey[500],
      ),
      textAlign: TextAlign.center,
    );
  }

  // Validators

  /// Validates IP address format
  String? _validateIP(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'IP Address is required';
    }
    final ipPattern = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    if (!ipPattern.hasMatch(value.trim())) {
      return 'Invalid IP Address format (e.g., 192.168.1.100)';
    }
    return null;
  }

  /// Validates port number
  String? _validatePort(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Port is required';
    }
    final port = int.tryParse(value.trim());
    if (port == null || port < _minPort || port > _maxPort) {
      return 'Port must be between $_minPort and $_maxPort';
    }
    return null;
  }

  /// Validates project name
  String? _validateProjectName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Project Name is required';
    }
    return null;
  }

  /// Validates module count
  String? _validateModuleCount(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Module Count is required';
    }
    final count = int.tryParse(value.trim());
    if (count == null || count < 1 || count > _maxModuleCount) {
      return 'Must be between 1 and $_maxModuleCount';
    }
    return null;
  }
}
