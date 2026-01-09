import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/datasources/local/zone_name_local_storage.dart';
import '../../../data/services/logger.dart';

/// Zone Name Configuration Page
///
/// Allows user to configure custom names for each zone
class ZoneNameConfigPage extends StatefulWidget {
  final int totalModules;
  final String projectName; // 🔥 FIX: Receive project name from config

  const ZoneNameConfigPage({
    super.key,
    required this.totalModules,
    required this.projectName,
  });

  @override
  State<ZoneNameConfigPage> createState() => _ZoneNameConfigPageState();
}

class _ZoneNameConfigPageState extends State<ZoneNameConfigPage> {
  // Controllers for all zones
  late Map<int, TextEditingController> _zoneControllers;
  bool _isLoading = false;
  bool _isSaving = false;
  final int _zonesPerModule = 5;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _loadZoneNames();
  }

  @override
  void dispose() {
    // Dispose all controllers
    for (var controller in _zoneControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Initialize text controllers for all zones
  void _initializeControllers() {
    _zoneControllers = {};
    final totalZones = widget.totalModules * _zonesPerModule;

    for (int i = 1; i <= totalZones; i++) {
      _zoneControllers[i] = TextEditingController();
    }
  }

  /// Load saved zone names
  Future<void> _loadZoneNames() async {
    setState(() => _isLoading = true);

    try {
      // 🔥 FIX: Load from project-specific storage with actual project name
      final zoneNames = await ZoneNameLocalStorage.loadZoneNamesForProject(widget.projectName);

      setState(() {
        for (var entry in zoneNames.entries) {
          final zoneNumber = entry.key;
          final zoneName = entry.value;

          if (_zoneControllers.containsKey(zoneNumber)) {
            _zoneControllers[zoneNumber]!.text = zoneName;
          }
        }
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.error('Failed to load zone names', error: e);
      setState(() => _isLoading = false);
    }
  }

  /// Save all zone names
  Future<void> _saveZoneNames() async {
    setState(() => _isSaving = true);

    try {
      final zoneNames = <int, String>{};

      for (var entry in _zoneControllers.entries) {
        final zoneNumber = entry.key;
        final controller = entry.value;
        final name = controller.text.trim();

        // Only save non-empty names
        if (name.isNotEmpty) {
          zoneNames[zoneNumber] = name;
        }
      }

      // 🔥 FIX: Save to project-specific storage with actual project name
      await ZoneNameLocalStorage.saveZoneNamesForProject(widget.projectName, zoneNames);

      if (!mounted) return;

      setState(() => _isSaving = false);
      _showSuccessSnackBar('Zone names saved successfully');
    } catch (e) {
      AppLogger.error('Failed to save zone names', error: e);
      setState(() => _isSaving = false);
      _showErrorSnackBar('Failed to save zone names');
    }
  }

  /// Reset all zone names to default
  Future<void> _resetToDefaults() async {
    final confirm = await _showConfirmDialog(
      'Reset Zone Names',
      'Are you sure you want to reset all zone names to default?',
    );

    if (!confirm) return;

    setState(() => _isLoading = true);

    try {
      // Clear all controllers
      for (var controller in _zoneControllers.values) {
        controller.clear();
      }

      // 🔥 FIX: Clear project-specific zone names with actual project name
      await ZoneNameLocalStorage.clearZoneNamesForProject(widget.projectName);

      if (!mounted) return;

      setState(() => _isLoading = false);
      _showSuccessSnackBar('Zone names reset to default');
    } catch (e) {
      AppLogger.error('Failed to reset zone names', error: e);
      setState(() => _isLoading = false);
      _showErrorSnackBar('Failed to reset zone names');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configure Zone Names'),
        backgroundColor: Colors.orange.shade700,
        foregroundColor: Colors.white,
        actions: [
          if (!_isSaving)
            TextButton.icon(
              onPressed: _resetToDefaults,
              icon: const Icon(Icons.restore),
              label: const Text('Reset All'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.totalModules,
                    itemBuilder: (context, index) {
                      final moduleNumber = index + 1;
                      return _buildModuleCard(moduleNumber);
                    },
                  ),
                ),
                if (_isSaving)
                  const LinearProgressIndicator(),
                _buildBottomBar(),
              ],
            ),
    );
  }

  /// Build card for one module with its 5 zones
  Widget _buildModuleCard(int moduleNumber) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: ExpansionTile(
        title: Text(
          'Module #$moduleNumber',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text('Zones ${((moduleNumber - 1) * _zonesPerModule) + 1} - ${moduleNumber * _zonesPerModule}'),
        leading: CircleAvatar(
          backgroundColor: Colors.orange.shade700,
          child: Text(
            '$moduleNumber',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: List.generate(_zonesPerModule, (zoneIndex) {
                final zoneNumber = ((moduleNumber - 1) * _zonesPerModule) + (zoneIndex + 1);
                return _buildZoneField(zoneNumber);
              }),
            ),
          ),
        ],
      ),
    );
  }

  /// Build text field for one zone
  Widget _buildZoneField(int zoneNumber) {
    final controller = _zoneControllers[zoneNumber]!;
    final defaultName = ZoneNameLocalStorage.getDefaultZoneName(zoneNumber);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: 'Zone #$zoneNumber',
          hintText: defaultName,
          prefixIcon: const Icon(Icons.label),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    controller.clear();
                    setState(() {});
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
        onChanged: (value) => setState(() {}),
      ),
    );
  }

  /// Build bottom bar with save button
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveZoneNames,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Save Zone Names',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  /// Show confirmation dialog
  Future<bool> _showConfirmDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Show success snackbar
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Show error snackbar
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
