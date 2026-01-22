import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../monitoring/offline_monitoring_page.dart';
import '../connection/zone_name_config_page.dart';
import '../../../data/services/logger.dart';
import '../../../data/services/connection_health_service.dart';
import '../../../data/datasources/local/zone_mapping_service.dart';

/// Connection Configuration Page - Modern Flat Design
class ConnectionConfigPage extends StatefulWidget {
  const ConnectionConfigPage({super.key});

  @override
  State<ConnectionConfigPage> createState() => _ConnectionConfigPageState();
}

class _ConnectionConfigPageState extends State<ConnectionConfigPage> {
  final _formKey = GlobalKey<FormState>();
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  final _projectNameController = TextEditingController();
  final _moduleCountController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  bool _isConfiguringMapping = false;
  bool _isScanning = false;
  List<DiscoveryResult> _discoveredDevices = [];

  // Design System - Flat Modern Theme
  static const Color _primary = Color(0xFF16A34A);      // Green 600
  static const Color _primaryDark = Color(0xFF15803D);  // Green 700
  static const Color _primaryLight = Color(0xFFDCFCE7); // Green 100
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _background = Color(0xFFF8FAFC);   // Slate 50
  static const Color _border = Color(0xFFE2E8F0);       // Slate 200
  static const Color _textPrimary = Color(0xFF0F172A);  // Slate 900
  static const Color _textSecondary = Color(0xFF64748B); // Slate 500

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

  Future<void> _saveConfiguration() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final config = _parseConfigurationFromForm();
      await _saveConfigurationToPrefs(prefs, config);
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar('Configuration saved', isError: false);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: ${e.toString()}';
      });
      _showSnackBar('Failed to save', isError: true);
    }
  }

  Future<void> _startMonitoring() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final config = await _loadConfiguration(prefs);
      if (!mounted) return;
      _navigateToMonitoringPage(config);
    } catch (e) {
      _showSnackBar('Failed to start: ${e.toString()}', isError: true);
    }
  }

  Map<String, dynamic> _parseConfigurationFromForm() => {
    'ip': _ipController.text.trim(),
    'port': int.parse(_portController.text.trim()),
    'projectName': _projectNameController.text.trim(),
    'moduleCount': int.parse(_moduleCountController.text.trim()),
  };

  Future<void> _saveConfigurationToPrefs(SharedPreferences prefs, Map<String, dynamic> config) async {
    await prefs.setString('ip', config['ip'] as String);
    await prefs.setInt('port', config['port'] as int);
    await prefs.setString('projectName', config['projectName'] as String);
    await prefs.setInt('moduleCount', config['moduleCount'] as int);
  }

  Future<Map<String, dynamic>> _loadConfiguration(SharedPreferences prefs) async => {
    'ip': prefs.getString('ip') ?? _ipController.text.trim(),
    'port': prefs.getInt('port') ?? int.parse(_portController.text.trim()),
    'projectName': prefs.getString('projectName') ?? _projectNameController.text.trim(),
    'moduleCount': prefs.getInt('moduleCount') ?? int.parse(_moduleCountController.text.trim()),
  };

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

  void _navigateToZoneNameConfig() {
    final moduleCount = int.tryParse(_moduleCountController.text.trim()) ?? _defaultModuleCount;
    final projectName = _projectNameController.text.trim().isEmpty
        ? _defaultProjectName
        : _projectNameController.text.trim();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => ZoneNameConfigPage(totalModules: moduleCount, projectName: projectName)),
    );
  }

  Future<void> _navigateToZoneMappingConfig() async => await _selectZoneMappingFolder();

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w500)),
        backgroundColor: isError ? Colors.red.shade600 : _primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _selectZoneMappingFolder() async {
    if (!mounted) return;
    setState(() => _isConfiguringMapping = true);

    try {
      String? selectedDirectory = await _openFolderPicker();
      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        final foundZones = await ZoneMappingService.validateMappingFolder(selectedDirectory);
        if (foundZones.isEmpty) {
          final analysis = await ZoneMappingService.analyzeFolder(selectedDirectory);
          _showDetailedAnalysisDialog(analysis, selectedDirectory);
        } else {
          final success = await ZoneMappingService.saveMappingFolderPath(selectedDirectory);
          if (success) {
            _showSnackBar('Found ${foundZones.length} zone images', isError: false);
          } else {
            _showSnackBar('Failed to save configuration', isError: true);
          }
        }
      }
    } catch (e) {
      _showSnackBar('Error selecting folder', isError: true);
    } finally {
      if (mounted) setState(() => _isConfiguringMapping = false);
    }
  }

  Future<String?> _openFolderPicker() async {
    try {
      await [Permission.photos, Permission.videos, Permission.audio, Permission.storage, Permission.manageExternalStorage].request();
      String? dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select Zone Mapping Folder');
      return dir ?? await _showManualFolderInputDialog();
    } catch (e) {
      return await _showManualFolderInputDialog();
    }
  }

  Future<String?> _showManualFolderInputDialog() async {
    final controller = TextEditingController();
    return showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Enter Folder Path', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: '/storage/emulated/0/ZoneMappings',
            prefixIcon: Icon(Icons.folder, color: _primary),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _primary, width: 2)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: _textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }

  void _showDetailedAnalysisDialog(String analysis, String folderPath) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.folder_open, color: _primary, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Folder Analysis', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
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
                  color: _background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.folder, size: 18, color: _textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        folderPath,
                        style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: _textSecondary),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  analysis,
                  style: TextStyle(fontSize: 13, color: _textPrimary, height: 1.6),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: _textSecondary, fontWeight: FontWeight.w500)),
          ),
          ElevatedButton.icon(
            onPressed: () { Navigator.pop(context); _selectZoneMappingFolder(); },
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  int _calculateTotalZones() {
    final count = int.tryParse(_moduleCountController.text) ?? _defaultModuleCount;
    return count * _zonesPerModule;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                _buildLogo(),
                const SizedBox(height: 32),
                if (_errorMessage != null) _buildError(),
                _buildCard(
                  icon: Icons.wifi,
                  title: 'Communication',
                  children: [
                    _buildInput(_ipController, 'IP Address', Icons.dns_outlined, validator: _validateIP, suffix: _buildScanBtn()),
                    const SizedBox(height: 14),
                    _buildInput(_portController, 'Port', Icons.settings_ethernet, keyboardType: TextInputType.number, validator: _validatePort),
                  ],
                ),
                const SizedBox(height: 16),
                _buildCard(
                  icon: Icons.business,
                  title: 'Project',
                  children: [
                    _buildInput(_projectNameController, 'Project Name', Icons.badge_outlined, validator: _validateProjectName),
                    const SizedBox(height: 14),
                    _buildInput(_moduleCountController, 'Total Modules', Icons.memory, keyboardType: TextInputType.number, validator: _validateModuleCount),
                    const SizedBox(height: 14),
                    _buildZoneCounter(),
                  ],
                ),
                const SizedBox(height: 16),
                _buildCard(
                  icon: Icons.tune,
                  title: 'Settings',
                  children: [
                    _buildMenuItem('Zone Names', 'Custom labels for zones', Icons.edit_note, _navigateToZoneNameConfig),
                    const Divider(height: 24),
                    _buildMenuItem('Zone Mapping', 'Floor plan images', Icons.map_outlined, _isConfiguringMapping ? null : _navigateToZoneMappingConfig, isLoading: _isConfiguringMapping),
                  ],
                ),
                const SizedBox(height: 28),
                _buildButtons(),
                const SizedBox(height: 24),
                Center(
                  child: Text('v1.0.0 • DDS Fire Alarm System', style: TextStyle(fontSize: 12, color: _textSecondary)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            color: _surface,
            shape: BoxShape.circle,
            border: Border.all(color: _primary.withOpacity(0.2), width: 3),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: ClipOval(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Image.asset(
                'assets/data/images/LOGO TEXT.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(Icons.local_fire_department, size: 50, color: _primary),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text('DDS Fire Alarm', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: _textPrimary, letterSpacing: -0.5)),
        const SizedBox(height: 4),
        Text('Communication Setup', style: TextStyle(fontSize: 15, color: _textSecondary)),
      ],
    );
  }

  Widget _buildError() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade600),
          const SizedBox(width: 12),
          Expanded(child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade700))),
        ],
      ),
    );
  }

  Widget _buildCard({required IconData icon, required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: _primaryLight, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: _primary, size: 20),
              ),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: _textPrimary)),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInput(TextEditingController controller, String label, IconData icon, {TextInputType? keyboardType, String? Function(String?)? validator, Widget? suffix}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: _textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: _textSecondary),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 12, right: 8),
          child: Icon(icon, color: _primary, size: 22),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 48),
        suffixIcon: suffix,
        filled: true,
        fillColor: _background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _primary, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.red.shade400)),
      ),
    );
  }

  Widget _buildScanBtn() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: IconButton(
        onPressed: _isScanning ? null : _startNetworkScan,
        icon: _isScanning
            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _primary))
            : Icon(Icons.wifi_find, color: _primary),
        tooltip: 'Scan for Host',
        style: IconButton.styleFrom(
          backgroundColor: _primaryLight,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _buildZoneCounter() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _primaryLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.grid_view_rounded, color: _primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total Zones', style: TextStyle(fontSize: 12, color: _textSecondary)),
                Text('${_calculateTotalZones()}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _primaryDark)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(String title, String subtitle, IconData icon, VoidCallback? onTap, {bool isLoading = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _primaryLight, borderRadius: BorderRadius.circular(10)),
              child: isLoading
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _primary))
                  : Icon(icon, color: _primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _textPrimary)),
                  Text(subtitle, style: TextStyle(fontSize: 13, color: _textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: _textSecondary, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: _isLoading ? null : _saveConfiguration,
            icon: _isLoading ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _primary)) : Icon(Icons.save_outlined, color: _primary),
            label: Text('Save Configuration', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _primary)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _primary, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _startMonitoring,
            icon: const Icon(Icons.play_arrow_rounded, size: 26),
            label: const Text('Start Monitoring', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  // Network Discovery
  Future<void> _startNetworkScan() async {
    setState(() { _isScanning = true; _discoveredDevices = []; });
    _showScanningDialog();

    try {
      final results = await ConnectionHealthService.discoverESP32DevicesOptimized(
        ports: const [81, 80], // WebSocket port first, then HTTP for routers
        maxIPRange: 100,       // Scan more IPs for better coverage
        timeout: const Duration(milliseconds: 600), // Longer timeout for reliability
        maxDevices: 15,
      );

      if (mounted) {
        Navigator.of(context).pop();
        setState(() => _isScanning = false);
        results.isNotEmpty ? _showDiscoveryResults(results) : _showNoDevicesFound();
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        setState(() => _isScanning = false);
        _showSnackBar('Scan failed', isError: true);
      }
    }
  }

  void _showScanningDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3, color: _primary)),
              const SizedBox(height: 20),
              const Text('Scanning Network', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('Looking for Host devices...', style: TextStyle(color: _textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  void _showDiscoveryResults(List<DiscoveryResult> results) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _primaryLight, borderRadius: BorderRadius.circular(10)), child: Icon(Icons.devices, color: _primary)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Devices Found', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                        Text('${results.length} Host detected', style: TextStyle(color: _textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: results.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 70),
                itemBuilder: (context, index) {
                  final device = results[index];
                  final ms = device.bestResponseTime?.inMilliseconds ?? 0;
                  final color = ms < 50 ? _primary : (ms < 100 ? Colors.lightGreen : (ms < 200 ? Colors.orange : Colors.red));
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.router, color: color),
                    ),
                    title: Text(device.host, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                          child: Text('${ms}ms', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 8),
                        Text('Port ${device.bestPort}', style: TextStyle(fontSize: 13, color: _textSecondary)),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      _ipController.text = device.host;
                      _portController.text = device.bestPort.toString();
                      Navigator.pop(context);
                      _showSnackBar('Selected ${device.host}', isError: false);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNoDevicesFound() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Icon(Icons.search_off, size: 48, color: Colors.orange.shade600),
        title: const Text('No Devices Found'),
        content: Text('Ensure Host Communication is powered on and connected to the same network.', style: TextStyle(color: _textSecondary), textAlign: TextAlign.center),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('OK', style: TextStyle(color: _primary)))],
      ),
    );
  }

  // Validators
  String? _validateIP(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    if (!RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(v.trim())) return 'Invalid IP';
    return null;
  }

  String? _validatePort(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final p = int.tryParse(v.trim());
    if (p == null || p < _minPort || p > _maxPort) return '$_minPort-$_maxPort';
    return null;
  }

  String? _validateProjectName(String? v) => v == null || v.trim().isEmpty ? 'Required' : null;

  String? _validateModuleCount(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final c = int.tryParse(v.trim());
    if (c == null || c < 1 || c > _maxModuleCount) return '1-$_maxModuleCount';
    return null;
  }
}
