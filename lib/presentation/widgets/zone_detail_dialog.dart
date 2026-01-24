import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../providers/fire_alarm_data_provider.dart';
import '../../data/datasources/local/zone_mapping_service.dart';
import '../../data/datasources/local/zone_name_local_storage.dart';
import '../../data/services/logger.dart';
import '../../data/models/zone_status_model.dart';
import '../services/alarm_queue_manager.dart';

/// Shared Zone Detail Dialog Widget
/// Used by both offline monitoring and tab monitoring pages
/// Supports both single-zone mode and multi-alarm queue mode with navigation
class ZoneDetailDialog extends StatefulWidget {
  // Single-zone mode (legacy support)
  final int? zoneNumber;
  
  // Multi-alarm queue mode (new)
  final List<int>? alarmQueue;
  final int? initialIndex;
  final VoidCallback? onClose;
  
  // Common parameters
  final FireAlarmData fireAlarmData;
  final Map<int, String> zoneNames;

  const ZoneDetailDialog({
    super.key,
    this.zoneNumber,  // For single-zone mode
    this.alarmQueue,  // For multi-alarm queue mode
    this.initialIndex = 0,
    this.onClose,
    required this.fireAlarmData,
    required this.zoneNames,
  }) : assert(
         (zoneNumber != null && alarmQueue == null) || 
         (zoneNumber == null && alarmQueue != null),
         'Either zoneNumber or alarmQueue must be provided, but not both'
       );

  @override
  State<ZoneDetailDialog> createState() => _ZoneDetailDialogState();
}

class _ZoneDetailDialogState extends State<ZoneDetailDialog> {
  String? _zoneMappingImagePath;
  bool _isLoadingImage = false;
  
  // Multi-alarm queue management
  late int _currentIndex;
  late List<int> _currentQueue;
  StreamSubscription<List<int>>? _queueSubscription;
  
  // Computed properties
  int get currentZoneNumber {
    // Single-zone mode
    if (widget.zoneNumber != null) return widget.zoneNumber!;
    
    // Multi-alarm queue mode
    if (_currentQueue.isEmpty) return 1; // Default fallback
    return _currentQueue[_currentIndex];
  }
  
  int get totalAlarms => _currentQueue.length;
  bool get hasPrevious => _currentIndex > 0;
  bool get hasNext => _currentIndex < _currentQueue.length - 1;
  bool get isMultiAlarmMode => widget.alarmQueue != null;

  @override
  void initState() {
    super.initState();
    
    // Initialize queue state
    if (widget.alarmQueue != null) {
      // Multi-alarm mode
      _currentIndex = widget.initialIndex ?? 0;
      _currentQueue = List.from(widget.alarmQueue!);
      
      // Listen to queue updates (new alarms added while dialog open)
      _queueSubscription = AlarmQueueManager().queueStream.listen((updatedQueue) {
        if (mounted && updatedQueue.isNotEmpty) {
          setState(() {
            // Preserve current zone if still in queue
            final currentZone = currentZoneNumber;
            _currentQueue = List.from(updatedQueue);
            
            // Update index to current zone's new position
            final newIndex = _currentQueue.indexOf(currentZone);
            if (newIndex >= 0) {
              _currentIndex = newIndex;
            } else if (_currentIndex >= _currentQueue.length) {
              // Current zone removed from queue, go to last
              _currentIndex = _currentQueue.length - 1;
            }
          });
          // Reload image for potentially new zone
          _loadZoneMappingImage();
        }
      });
    } else {
      // Single-zone mode
      _currentIndex = 0;
      _currentQueue = [widget.zoneNumber!];
    }
    
    // 🔥 NEW: Listen to FireAlarmData changes for real-time zone status updates
    // This ensures dialog updates immediately when zone status changes (Alarm → Normal)
    widget.fireAlarmData.addListener(_onFireAlarmDataChanged);
    
    _loadZoneMappingImage();
  }
  
  /// Callback when FireAlarmData changes (zone status updates)
  void _onFireAlarmDataChanged() {
    if (mounted) {
      setState(() {
        // Rebuild dialog to reflect latest zone status
        // This triggers real-time updates when zone changes from Alarm → Normal
      });
      AppLogger.debug('Dialog rebuilt due to zone status change (Zone $currentZoneNumber)', tag: 'ZONE_DETAIL');
    }
  }
  
  @override
  void dispose() {
    _queueSubscription?.cancel();
    widget.fireAlarmData.removeListener(_onFireAlarmDataChanged);
    super.dispose();
  }

  /// Load zone mapping image for current zone
  Future<void> _loadZoneMappingImage() async {
    setState(() => _isLoadingImage = true);

    try {
      final imagePath = await ZoneMappingService.getZoneMappingPath(currentZoneNumber);
      if (mounted) {
        setState(() {
          _zoneMappingImagePath = imagePath;
          _isLoadingImage = false;
        });
      }
    } catch (e) {
      AppLogger.error('Error loading zone mapping image for zone $currentZoneNumber: $e', tag: 'ZONE_DETAIL');
      if (mounted) {
        setState(() => _isLoadingImage = false);
      }
    }
  }
  
  /// Navigate to previous alarm in queue
  void _goToPrevious() {
    if (hasPrevious) {
      setState(() {
        _currentIndex--;
      });
      _loadZoneMappingImage();
      AppLogger.info('Navigated to previous alarm: Zone $currentZoneNumber ($_currentIndex + 1 of $totalAlarms)', tag: 'ALARM_NAV');
    }
  }
  
  /// Navigate to next alarm in queue
  void _goToNext() {
    if (hasNext) {
      setState(() {
        _currentIndex++;
      });
      _loadZoneMappingImage();
      AppLogger.info('Navigated to next alarm: Zone $currentZoneNumber (${_currentIndex + 1} of $totalAlarms)', tag: 'ALARM_NAV');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get zone status for header
    final zoneStatus = widget.fireAlarmData.getIndividualZoneStatus(currentZoneNumber);

    // Local variables for zone status display
    String statusText;
    Color statusColor;
    IconData statusIcon;
    String timestampStr;

    // 🔥 FIX: CEK ZONE STATUS DULU, baru cek hasValidZoneData
    // Kalau zoneStatus null → baru cek hasValidZoneData
    if (zoneStatus == null) {
      // Tidak ada data untuk zone ini → OFFLINE
      if (!widget.fireAlarmData.hasValidZoneData || widget.fireAlarmData.isInitiallyLoading) {
        // Belum ada data sama sekali di sistem
        statusText = 'OFFLINE';
        statusColor = Colors.grey.shade300;
        statusIcon = Icons.signal_cellular_off;
        timestampStr = 'N/A';
      } else {
        // Ada data di sistem tapi zone ini tidak ada → OFFLINE juga
        statusText = 'OFFLINE';
        statusColor = Colors.grey.shade300;
        statusIcon = Icons.signal_cellular_off;
        timestampStr = 'N/A';
      }
    } else {
      // Priority 2: Use actual zone status if data is valid
      final status = (zoneStatus['status'] as String?)?.toUpperCase();
      switch (status) {
        case 'ALARM':
          statusText = 'ALARM';
          statusColor = Colors.red;
          statusIcon = Icons.warning;
          break;
        case 'TROUBLE':
          statusText = 'TROUBLE';
          statusColor = Colors.yellow.shade700;  // TROUBLE = KUNING
          statusIcon = Icons.error;
          break;
        case 'OFFLINE':
        case 'INACTIVE':
          statusText = 'OFFLINE';
          statusColor = Colors.grey.shade300;  // OFFLINE = ABU-ABU
          statusIcon = Icons.signal_cellular_off;
          break;
        case 'NORMAL':
        default:
          // Only show NORMAL if we have valid data
          statusText = 'NORMAL';
          statusColor = Colors.green;
          statusIcon = Icons.check_circle;
          break;
      }

      // Get timestamp
      if (zoneStatus['timestamp'] != null) {
        try {
          final timestamp = DateTime.fromMillisecondsSinceEpoch(
            int.parse(zoneStatus['timestamp'].toString())
          );
          timestampStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(timestamp);
        } catch (e) {
          timestampStr = 'Invalid timestamp';
        }
      } else {
        timestampStr = 'N/A';
      }
    }

    // Get custom zone name
    final customZoneName = widget.zoneNames[currentZoneNumber] ?? ZoneNameLocalStorage.getDefaultZoneName(currentZoneNumber);

    // Debug: Log what's being displayed
    AppLogger.debug('ZoneDetailDialog - Zone $currentZoneNumber: "$customZoneName" (custom: ${widget.zoneNames[currentZoneNumber] ?? "none"})', tag: 'ZONE_DETAIL_DIALOG');

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with status color
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
                border: Border(
                  bottom: BorderSide(
                    color: statusColor.withOpacity(0.3),
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    statusIcon,
                    color: statusColor,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    customZoneName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Zone #$currentZoneNumber',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  // Multi-alarm position indicator
                  if (isMultiAlarmMode && totalAlarms > 1) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: statusColor.withOpacity(0.5),
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: statusColor,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'ALARM ${_currentIndex + 1} of $totalAlarms',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Zone Mapping Image Section
                    if (_zoneMappingImagePath != null) ...[
                      _buildInfoSection(
                        title: 'Zone Mapping',
                        children: [
                          Container(
                            width: double.infinity,
                            height: 300,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: GestureDetector(
                                onTap: () => _showFullscreenImage(context),
                                child: InteractiveViewer(
                                  minScale: 1.0,
                                  maxScale: 4.0,
                                  child: Stack(
                                    children: [
                                      // Image
                                      Image.file(
                                        File(_zoneMappingImagePath!),
                                        fit: BoxFit.contain,
                                        width: double.infinity,
                                        height: double.infinity,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            color: Colors.grey[100],
                                            child: const Center(
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.broken_image, size: 48, color: Colors.grey),
                                                  SizedBox(height: 8),
                                                  Text(
                                                    'Image not available',
                                                    style: TextStyle(color: Colors.grey),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),

                                      // Zone overlay
                                      Positioned(
                                        top: 8,
                                        left: 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.7),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            'Zone $currentZoneNumber',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    // Show mapping status if no image available
                    if (_zoneMappingImagePath == null && !_isLoadingImage) ...[
                      const SizedBox(height: 20),
                      _buildInfoSection(
                        title: 'Zone Mapping',
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.image_not_supported, color: Colors.grey[600]),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'No mapping image configured for Zone $currentZoneNumber\n'
                                    'Configure mapping folder in Offline Config',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],

                    // Show loading indicator
                    if (_isLoadingImage) ...[
                      const SizedBox(height: 20),
                      _buildInfoSection(
                        title: 'Zone Mapping',
                        children: [
                          Container(
                            width: double.infinity,
                            height: 100,
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 8),
                                  Text(
                                    'Loading mapping image...',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Footer with navigation buttons (multi-alarm) or close button (single-zone)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                border: Border(
                  top: BorderSide(
                    color: Colors.grey.shade300,
                    width: 1,
                  ),
                ),
              ),
              child: isMultiAlarmMode && totalAlarms > 1
                  ? Row(
                      children: [
                        // Previous button
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: hasPrevious ? _goToPrevious : null,
                            icon: const Icon(Icons.arrow_back, size: 18),
                            label: const Text('Previous'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: hasPrevious ? Colors.blue.shade600 : Colors.grey.shade400,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: hasPrevious ? 2 : 0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Close button
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              widget.onClose?.call();
                              Navigator.of(context).pop();
                            },
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Close'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: statusColor,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Next button
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: hasNext ? _goToNext : null,
                            icon: const Icon(Icons.arrow_forward, size: 18),
                            label: const Text('Next'),
                            iconAlignment: IconAlignment.end,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: hasNext ? Colors.blue.shade600 : Colors.grey.shade400,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: hasNext ? 2 : 0,
                            ),
                          ),
                        ),
                      ],
                    )
                  : ElevatedButton(
                      onPressed: () {
                        widget.onClose?.call();
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: statusColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          const Text(': ', style: TextStyle(color: Colors.grey)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: valueColor ?? Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Show fullscreen image viewer
  void _showFullscreenImage(BuildContext context) {
    if (_zoneMappingImagePath == null) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            children: [
              // Fullscreen image with zoom
              InteractiveViewer(
                minScale: 1.0,
                maxScale: 6.0,
                child: Center(
                  child: Image.file(
                    File(_zoneMappingImagePath!),
                    fit: BoxFit.contain,
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.black,
                        child: const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image, size: 64, color: Colors.white),
                              SizedBox(height: 16),
                              Text(
                                'Failed to load image',
                                style: TextStyle(color: Colors.white, fontSize: 18),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Close button
              Positioned(
                top: 40,
                right: 20,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),

              // Zone info overlay
              Positioned(
                bottom: 40,
                left: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'Zone $currentZoneNumber',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              // Instructions
              Positioned(
                top: 40,
                left: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'Pinch to zoom • Tap outside to close',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}