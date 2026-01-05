import 'package:flutter/material.dart';
import '../../../core/utils/validation_helpers.dart';
import '../../../data/datasources/local/zone_name_local_storage.dart';
import '../../../data/services/logger.dart';

class ZoneNameConfigPage extends StatefulWidget {
  final String projectName;
  final int moduleCount;

  const ZoneNameConfigPage({
    super.key,
    required this.projectName,
    required this.moduleCount,
  });

  @override
  State<ZoneNameConfigPage> createState() => _ZoneNameConfigPageState();
}

class _ZoneNameConfigPageState extends State<ZoneNameConfigPage> {
  final List<TextEditingController> _controllers = [];
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving = false;
  int _totalZones = 0;
  String _existingZoneData = '';
  final bool _noInternet = false; // Using local storage, so always false
  final bool _showNoInternetBanner = false; // Using local storage, so always false

  @override
  void initState() {
    super.initState();
    _loadZoneData();
  }

  @override
  void dispose() {
    // Dispose all controllers
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadZoneData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Calculate total zones (5 zones per module)
      _totalZones = widget.moduleCount * 5;

      // Migrate existing global data if needed and load project-specific zone names
      await ZoneNameLocalStorage.migrateGlobalToProjectSpecific(widget.projectName);

      // Load existing zone names from project-specific local storage
      final zones = await ZoneNameLocalStorage.loadZoneNamesForProject(widget.projectName);

      // Initialize controllers for each zone
      _controllers.clear();
      for (int i = 1; i <= _totalZones; i++) {
        final controller = TextEditingController();
        // Set existing zone name if available
        if (zones.containsKey(i)) {
          controller.text = zones[i]!;
        } else {
          // Default zone name
          controller.text = ZoneNameLocalStorage.getDefaultZoneName(i);
        }
        _controllers.add(controller);
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.error('Error loading zone data for project ${widget.projectName}', tag: 'ZONE_CONFIG', error: e);

      // Even if there's an error, try to initialize with default values
      _controllers.clear();
      for (int i = 1; i <= _totalZones; i++) {
        final controller = TextEditingController(text: 'Zone $i');
        _controllers.add(controller);
      }

      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error loading existing data. Using default zone names.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _saveZoneNames() async {
    // Validate form first
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Create zones map from controllers
      Map<int, String> zones = {};
      for (int i = 0; i < _controllers.length; i++) {
        final zoneNumber = i + 1;
        String zoneName = _controllers[i].text.trim();

        if (zoneName.isEmpty) {
          zoneName = ZoneNameLocalStorage.getDefaultZoneName(zoneNumber);
        }

        // Validate zone name
        final validationError = ZoneNameLocalStorage.validateZoneName(zoneName);
        if (validationError != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Zone $zoneNumber: $validationError'),
                backgroundColor: Colors.red,
              ),
            );
          }
          setState(() {
            _isSaving = false;
          });
          return;
        }

        zones[zoneNumber] = zoneName;
      }

      // Save using project-specific storage
      final success = await ZoneNameLocalStorage.saveZoneNamesForProject(widget.projectName, zones);

      setState(() {
        _isSaving = false;
      });

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Zone names saved successfully for project "${widget.projectName}"!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save zone names to local storage'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      AppLogger.error('Error saving zone names for project ${widget.projectName}', tag: 'ZONE_CONFIG', error: e);
      setState(() {
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving zone names: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildZoneTextField(int index) {
    final moduleNumber = (index ~/ 5) + 1;
    final zoneInModule = (index % 5) + 1;
    final zoneNumber = index + 1;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '#${zoneNumber.toString().padLeft(3, '0')}#',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue[700],
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Module $moduleNumber - Zone $zoneInModule',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: _controllers[index],
            enabled: !_isSaving,
            decoration: InputDecoration(
              hintText: 'Enter zone name (1-50 characters)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: Colors.grey[50],
              counterText: '${_controllers[index].text.length}/50',
            ),
            textCapitalization: TextCapitalization.words,
            maxLength: 50,
            validator: (value) => _validateZoneName(value, index),
          ),
        ],
      ),
    );
  }

  String? _validateZoneName(String? value, int index) {
    final zoneNumber = index + 1;

    // Use ValidationHelpers for zone name validation
    String? validationResult = ValidationHelpers.validateZoneName(value);
    if (validationResult != null) {
      return validationResult;
    }

    // Zone names can be empty (will get defaults), but if provided, check for uniqueness
    if (value != null && value.trim().isNotEmpty) {
      final zoneName = value.trim();

      // Check for duplicate zone names (case-insensitive)
      for (int i = 0; i < _controllers.length; i++) {
        if (i != index) {
          final otherZoneName = _controllers[i].text.trim();
          if (otherZoneName.toLowerCase() == zoneName.toLowerCase()) {
            final otherZoneNumber = i + 1;
            return 'Zone name already used by Zone #$otherZoneNumber';
          }
        }
      }

      // Additional validation for zone-specific requirements
      if (zoneName.toLowerCase() == 'zone $zoneNumber') {
        // Allow default naming pattern
        return null;
      }

      // Check for forbidden characters that might break the data format
      if (zoneName.contains(',') || zoneName.contains('#')) {
        return 'Zone name cannot contain commas (#) or hash (#) characters';
      }

      // Check for very short names (unless it's the default pattern)
      if (zoneName.trim().length < 2) {
        return 'Zone name must be at least 2 characters';
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Zone Name Config - ${widget.projectName}',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        backgroundColor: const Color.fromARGB(255, 35, 141, 39),
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadZoneData,
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        color: Color.fromARGB(255, 35, 141, 39),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Loading zone data...',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Header info
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: Colors.grey[100],
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 20,
                                color: Colors.grey[700],
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Configure names for each zone',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Project: ${widget.projectName} | Modules: ${widget.moduleCount} | Total Zones: $_totalZones',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Format: #001#Zone Name, #002#Zone Name, ...',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Zone list
                    Expanded(
                      child: _totalZones == 0
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    size: 64,
                                    color: Colors.orange[400],
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'No zones configured',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Please configure modules first',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Form(
                                key: _formKey,
                                child: ListView.builder(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: _controllers.length,
                                  itemBuilder: (context, index) {
                                // Add module separator
                                if (index % 5 == 0 && index > 0) {
                                  return Column(
                                    children: [
                                      Divider(
                                        height: 32,
                                        thickness: 2,
                                        color: Colors.grey[300],
                                      ),
                                      _buildZoneTextField(index),
                                    ],
                                  );
                                }
                                return _buildZoneTextField(index);
                              },
                                ),
                              ),
                    ),

                    // Save button with SafeArea for navigation bar
                    if (_totalZones > 0)
                      SafeArea(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.shade300,
                                spreadRadius: 1,
                                blurRadius: 5,
                                offset: const Offset(0, -2),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _saveZoneNames,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _noInternet ? Colors.grey : const Color.fromARGB(255, 35, 141, 39),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 2,
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : _noInternet
                                    ? const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.refresh),
                                          SizedBox(width: 8),
                                          Text(
                                            'Retry',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      )
                                    : const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.save),
                                          SizedBox(width: 8),
                                          Text(
                                            'Save Zone Names',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                          ),
                        ),
                      ),
                  ],
                ),
          if (_showNoInternetBanner && !_isLoading)
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 185, 185, 185).withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Check your internet connection',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}