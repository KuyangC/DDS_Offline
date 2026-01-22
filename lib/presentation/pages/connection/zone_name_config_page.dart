import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/datasources/local/zone_name_local_storage.dart';
import '../../../data/services/logger.dart';

/// Zone Name Configuration Page - Modern Flat Design
class ZoneNameConfigPage extends StatefulWidget {
  final int totalModules;
  final String projectName;

  const ZoneNameConfigPage({
    super.key,
    required this.totalModules,
    required this.projectName,
  });

  @override
  State<ZoneNameConfigPage> createState() => _ZoneNameConfigPageState();
}

class _ZoneNameConfigPageState extends State<ZoneNameConfigPage> {
  late Map<int, TextEditingController> _zoneControllers;
  bool _isLoading = false;
  bool _isSaving = false;
  final int _zonesPerModule = 5;

  // Design System - Matching connection_config_page theme
  static const Color _primary = Color(0xFF16A34A);
  static const Color _primaryDark = Color(0xFF15803D);
  static const Color _primaryLight = Color(0xFFDCFCE7);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _background = Color(0xFFF8FAFC);
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF0F172A);
  static const Color _textSecondary = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _loadZoneNames();
  }

  @override
  void dispose() {
    for (var controller in _zoneControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _initializeControllers() {
    _zoneControllers = {};
    final totalZones = widget.totalModules * _zonesPerModule;
    for (int i = 1; i <= totalZones; i++) {
      _zoneControllers[i] = TextEditingController();
    }
  }

  Future<void> _loadZoneNames() async {
    setState(() => _isLoading = true);

    try {
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

  Future<void> _saveZoneNames() async {
    setState(() => _isSaving = true);

    try {
      final zoneNames = <int, String>{};

      for (var entry in _zoneControllers.entries) {
        final zoneNumber = entry.key;
        final controller = entry.value;
        final name = controller.text.trim();
        if (name.isNotEmpty) {
          zoneNames[zoneNumber] = name;
        }
      }

      await ZoneNameLocalStorage.saveZoneNamesForProject(widget.projectName, zoneNames);

      if (!mounted) return;

      setState(() => _isSaving = false);
      _showSnackBar('Zone names saved successfully', isError: false);
    } catch (e) {
      AppLogger.error('Failed to save zone names', error: e);
      setState(() => _isSaving = false);
      _showSnackBar('Failed to save zone names', isError: true);
    }
  }

  Future<void> _resetToDefaults() async {
    final confirm = await _showConfirmDialog(
      'Reset Zone Names',
      'Are you sure you want to reset all zone names to default?',
    );

    if (!confirm) return;

    setState(() => _isLoading = true);

    try {
      for (var controller in _zoneControllers.values) {
        controller.clear();
      }
      await ZoneNameLocalStorage.clearZoneNamesForProject(widget.projectName);

      if (!mounted) return;

      setState(() => _isLoading = false);
      _showSnackBar('Zone names reset to default', isError: false);
    } catch (e) {
      AppLogger.error('Failed to reset zone names', error: e);
      setState(() => _isLoading = false);
      _showSnackBar('Failed to reset zone names', isError: true);
    }
  }

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

  Future<bool> _showConfirmDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        content: Text(message, style: TextStyle(color: _textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: _textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: _textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Zone Names', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            Text(widget.projectName, style: TextStyle(fontSize: 12, color: _textSecondary, fontWeight: FontWeight.normal)),
          ],
        ),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.arrow_back, color: _primary, size: 20),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!_isSaving)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _resetToDefaults,
                icon: Icon(Icons.restart_alt, color: _textSecondary, size: 20),
                label: Text('Reset', style: TextStyle(color: _textSecondary, fontWeight: FontWeight.w500)),
                style: TextButton.styleFrom(
                  backgroundColor: _background,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _primary))
          : Column(
              children: [
                // Header info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _primaryLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _primary.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.info_outline, color: _primary, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total: ${widget.totalModules} modules, ${widget.totalModules * _zonesPerModule} zones',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _primaryDark)),
                            const SizedBox(height: 2),
                            Text('Tap on a module to expand and edit zone names',
                              style: TextStyle(fontSize: 12, color: _textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Module list
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: widget.totalModules,
                    itemBuilder: (context, index) {
                      final moduleNumber = index + 1;
                      return _buildModuleCard(moduleNumber);
                    },
                  ),
                ),
                if (_isSaving)
                  LinearProgressIndicator(color: _primary, backgroundColor: _primaryLight),
                _buildBottomBar(),
              ],
            ),
    );
  }

  Widget _buildModuleCard(int moduleNumber) {
    final startZone = ((moduleNumber - 1) * _zonesPerModule) + 1;
    final endZone = moduleNumber * _zonesPerModule;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                '$moduleNumber',
                style: TextStyle(
                  color: _primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          title: Text(
            'Module $moduleNumber',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _textPrimary),
          ),
          subtitle: Text(
            'Zones $startZone - $endZone',
            style: TextStyle(fontSize: 13, color: _textSecondary),
          ),
          iconColor: _primary,
          collapsedIconColor: _textSecondary,
          children: List.generate(_zonesPerModule, (zoneIndex) {
            final zoneNumber = ((moduleNumber - 1) * _zonesPerModule) + (zoneIndex + 1);
            return _buildZoneField(zoneNumber);
          }),
        ),
      ),
    );
  }

  Widget _buildZoneField(int zoneNumber) {
    final controller = _zoneControllers[zoneNumber]!;
    final defaultName = ZoneNameLocalStorage.getDefaultZoneName(zoneNumber);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _textPrimary),
        decoration: InputDecoration(
          labelText: 'Zone $zoneNumber',
          hintText: defaultName,
          labelStyle: TextStyle(color: _textSecondary),
          prefixIcon: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.location_on_outlined, color: _primary, size: 18),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 52),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close, color: _textSecondary, size: 20),
                  onPressed: () {
                    controller.clear();
                    setState(() {});
                  },
                )
              : null,
          filled: true,
          fillColor: _background,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _primary, width: 2)),
        ),
        onChanged: (value) => setState(() {}),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveZoneNames,
            icon: _isSaving
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined),
            label: Text(_isSaving ? 'Saving...' : 'Save Zone Names', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ),
    );
  }
}
