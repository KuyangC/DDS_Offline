import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:math' as math;
import '../../providers/fire_alarm_data_provider.dart';
import '../../../data/services/local_audio_manager.dart';
// REMOVED: enhanced_notification_service (file deleted)
import '../../../data/services/background_app_service.dart' as bg_notification;
import '../../../data/services/button_action_service.dart';

class FullMonitoringPage extends StatefulWidget {
  const FullMonitoringPage({super.key});

  @override
  State<FullMonitoringPage> createState() => _FullMonitoringPageState();
}

class _FullMonitoringPageState extends State<FullMonitoringPage> with WidgetsBindingObserver {
  // State untuk zona yang dipilih
  int? _selectedZoneNumber;

  // State untuk visibility kontrol container
  bool _showProjectContainer = true;
  bool _showZonesContainer = true;
  bool _showZoneNameContainer = true;

  // Local Audio Manager untuk independen audio control
  final LocalAudioManager _audioManager = LocalAudioManager();

  // REMOVED: EnhancedNotificationService (file deleted)

  // Stream subscription untuk audio status updates
  StreamSubscription<Map<String, bool>>? _audioStatusSubscription;

  // Store FireAlarmData reference for safe dispose
  late FireAlarmData _fireAlarmData;

  // Flag untuk mencegah multiple dispose calls
  bool _isDisposed = false;

  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Force landscape mode
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    // Hide status bar for full screen experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    
    // Initialize services
    _initializeServices();
    
    // Listen to FireAlarmData changes
    _fireAlarmData = context.read<FireAlarmData>(); // Store reference for safe dispose
    _fireAlarmData.addListener(_onSystemStatusChanged);
    
    // Listen to audio status updates
    _audioStatusSubscription = _audioManager.audioStatusStream.listen((audioStatus) {
      if (mounted) {
        setState(() {
          // Update UI based on audio status if needed
        });
      }
    });

      }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        // When app is resumed, ensure landscape mode for full monitoring
        if (mounted) {
          
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
          // Also ensure immersive mode
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        }
        break;
        
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // Don't restore orientations here - keep landscape until user manually leaves
        
        break;
        
      case AppLifecycleState.hidden:
        // App is hidden but not destroyed
        
        break;
    }
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    
    WidgetsBinding.instance.removeObserver(this);
    
  // Cancel subscriptions
  _audioStatusSubscription?.cancel();

  // Remove listener using stored reference (safe for dispose)
  try {
    _fireAlarmData.removeListener(_onSystemStatusChanged);
  } catch (e) {
    // FireAlarmData already disposed or context not available
    print('Warning: Could not remove FireAlarmData listener: $e');
  }

  // Dispose services
  _audioManager.dispose();
  // REMOVED: _notificationService (service deleted)

  // Restore user preferred orientations when leaving the page
    _restoreUserPreferredOrientations();
    
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _restoreUserPreferredOrientations() {
    

    // Restore to flexible orientations, allowing the system to decide based on device orientation.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Also restore system UI to normal mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // Force a short delay to ensure orientation change takes effect
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        
      }
    });
  }

  
  // Local helper method to get zone name, moved from FireAlarmData to fix resolution issue.
  String _getZoneName(int zoneNumber, FireAlarmData fireAlarmData) {
    if (fireAlarmData.modules.isEmpty || zoneNumber <= 0) {
      return 'Unknown Zone';
    }

    const int zonesPerModule = 5;
    final int moduleIndex = ((zoneNumber - 1) ~/ zonesPerModule);
    final int zoneIndexInModule = (zoneNumber - 1) % zonesPerModule;

    if (moduleIndex < fireAlarmData.modules.length) {
      final module = fireAlarmData.modules[moduleIndex];
      if (module['zones'] is List) {
        final zones = module['zones'] as List<dynamic>;
        if (zoneIndexInModule < zones.length) {
          return zones[zoneIndexInModule].toString();
        }
      }
    }

    return 'Zone $zoneNumber'; // Fallback if not found
  }

  @override
  Widget build(BuildContext context) {
    // Don't force landscape mode in build - let initState handle it
    // Forcing landscape mode here interferes with orientation restoration when exiting
    
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          // Restore user preferred orientations when page is popped
          _restoreUserPreferredOrientations();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Consumer<FireAlarmData>(
            builder: (context, fireAlarmData, child) {
              return Container(
                width: double.infinity,
                padding: _getResponsivePadding(context),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // TOP CONTAINER with Back Button
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(13),
                                    spreadRadius: 1,
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: _getContainerPadding(context),
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    // Back Button (seemless)
                                    IconButton(
                                      onPressed: () {
                                        // Restore orientations before navigating back
                                        _restoreUserPreferredOrientations();
                                        Navigator.of(context).pop();
                                      },
                                      icon: const Icon(
                                        Icons.arrow_back_ios_new,
                                        color: Colors.black87,
                                        size: 22,
                                      ),
                                      padding: const EdgeInsets.all(10),
                                      constraints: const BoxConstraints(
                                        minWidth: 45,
                                        minHeight: 45,
                                      ),
                                    ),

                                    // Spacer
                                    const SizedBox(width: 15),

                                    // Title
                                    Expanded(
                                      child: Text(
                                        'MONITORED AREAS',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.black87,
                                          fontWeight: FontWeight.w600,
                                          fontSize: _calculateResponsiveFontSize(context) * 1.3,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ),

                                    // Spacer untuk balance dengan back button
                                    const SizedBox(width: 55),
                                  ],
                                ),
                              ),
                            ),

                            // Spacing
                            const SizedBox(height: 10),

                            // Header info (Project info - tanpa back button karena sudah di atas)
                            if (_showProjectContainer)
                              Container(
                                width: double.infinity,
                                padding: EdgeInsets.symmetric(
                                  horizontal: _getContainerPadding(context),
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: Row(
                                  children: [
                                    // Space instead of back button
                                    const SizedBox(width: 53),
                                    // Project info
                                    Expanded(
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                                        children: [
                                          Column(
                                            children: [
                                              const Text(
                                                'PROJECT',
                                                style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                fireAlarmData.projectName,
                                                style: const TextStyle(
                                                  color: Colors.black87,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Column(
                                            children: [
                                              const Text(
                                                'STATUS',
                                                style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                // 🎯 Get system status text based on alarms/troubles
                                                _getSystemStatusText(fireAlarmData),
                                                style: TextStyle(
                                                  // 🎯 Consistent status colors - Alarm=Red, Trouble=Orange, Normal=Green, No Data=Grey
                                                  color: _getSystemStatusColor(fireAlarmData),
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Column(
                                            children: [
                                              const Text(
                                                'TOTAL ZONES',
                                                style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                fireAlarmData.numberOfZones.toString(),
                                                style: const TextStyle(
                                                  color: Colors.black87,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 10),

                            // Selected Zone Info Container
                            if (_showZoneNameContainer) ...[
                              const SizedBox(height: 10),
                              _buildSelectedZoneInfoContainer(fireAlarmData),
                            ],

                            if (_showZonesContainer)
                              const SizedBox(height: 10),

                            // Zones container
                            if (_showZonesContainer)
                              Flexible(
                                child: Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.all(_getContainerPadding(context)),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.grey[300]!),
                                  ),
                                  child: _buildZonesGrid(fireAlarmData),
                                ),
                              ),
                            if (_showZonesContainer)
                              const SizedBox(height: 10),

                            const SizedBox(height: 10),
                            // Visibility Controls at the bottom
                            _buildVisibilityControls(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedZoneInfoContainer(FireAlarmData fireAlarmData) {
    String zoneName;
    if (_selectedZoneNumber == null) {
      zoneName = 'Pilih sebuah zona untuk melihat nama';
    } else {
      zoneName = _getZoneName(_selectedZoneNumber!, fireAlarmData);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        children: [
         
          const SizedBox(height: 2),
          Text(
            _selectedZoneNumber != null 
              ? 'ZONA ${_selectedZoneNumber.toString().padLeft(3, '0')}'
              : '--',
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            zoneName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZonesGrid(FireAlarmData fireAlarmData) {
    final int totalZones = fireAlarmData.numberOfZones > 0 ? fireAlarmData.numberOfZones : 250;
    const int crossAxisCount = 10;
    const double crossAxisSpacing = 2.0;
    const double largeHorizontalGap = 16.0; // The gap between 5-zone groups
    const double childAspectRatio = 2.5;

    
    
    

    return LayoutBuilder(builder: (context, constraints) {
      // Calculate item width considering the different spacings
      final double availableWidth = constraints.maxWidth;
      // For a full row, there are 8 small gaps and 1 large gap
      final double totalSpacing = (crossAxisSpacing * 8) + largeHorizontalGap;
      final double itemWidth = (availableWidth - totalSpacing) / crossAxisCount;
      final double itemHeight = itemWidth / childAspectRatio;

      final int numRows = (totalZones / crossAxisCount).ceil();

      // Generate all rows
      List<Widget> rows = List.generate(numRows, (rowIndex) {
        final bool isLastRow = rowIndex == numRows - 1;
        
        int itemsInThisRow = crossAxisCount;
        if (isLastRow && totalZones % crossAxisCount != 0) {
          itemsInThisRow = totalZones % crossAxisCount;
        }
        
        MainAxisAlignment rowAlignment = MainAxisAlignment.start;
        if (isLastRow) {
          if (itemsInThisRow % 2 != 0) {
            rowAlignment = MainAxisAlignment.center;
          }
        } else {
          // Full rows should be aligned to start, the width calculation will fill the space.
          rowAlignment = MainAxisAlignment.start;
        }

        // Generate all items and spacers for the current row
        List<Widget> rowChildren = [];
        for (int itemIndex = 0; itemIndex < itemsInThisRow; itemIndex++) {
          final int zoneIndex = (rowIndex * crossAxisCount) + itemIndex;
          final int zoneNumber = zoneIndex + 1;

          final zoneItemWidget = SizedBox(
            width: itemWidth,
            height: itemHeight,
            child: Container(
              decoration: BoxDecoration(
                color: _getZoneColorFromSystem(zoneNumber),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: _selectedZoneNumber == zoneNumber
                      ? Colors.blueAccent
                      : _getZoneBorderColor(zoneNumber),
                  width: _selectedZoneNumber == zoneNumber ? 2.5 : 1.0,
                ),
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Text(
                      zoneNumber.toString().padLeft(3, '0'),
                      style: TextStyle(
                        color: _getZoneTextColor(zoneNumber),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

          // Add the zone item, wrapped in InkWell
          rowChildren.add(
            InkWell(
              onTap: () {
                setState(() {
                  _selectedZoneNumber = zoneNumber;
                });
              },
              borderRadius: BorderRadius.circular(3),
              child: zoneItemWidget,
            ),
          );

          // Add spacing after the item, if it's not the last one in the row
          if (itemIndex < itemsInThisRow - 1) {
            // Use large gap after the 5th item (index 4)
            if (itemIndex == 4) {
              rowChildren.add(const SizedBox(width: largeHorizontalGap));
            } else {
              rowChildren.add(const SizedBox(width: crossAxisSpacing));
            }
          }
        }

        // The Row widget that holds the zones
        final rowWidget = Row(
          mainAxisAlignment: rowAlignment,
          children: rowChildren,
        );

        // Return a Column with the row and a divider (if not the last row)
        return Column(
          children: [
            rowWidget,
            if (!isLastRow)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4.0), // Add some space around the divider
                child: Divider(color: Colors.grey, thickness: 1),
              ),
          ],
        );
      });

      return Column(children: rows);
    });
  }

  // Get zone color based on individual zone status first, then system status as fallback
  Color _getZoneColorFromSystem(int zoneNumber) {
    final fireAlarmData = Provider.of<FireAlarmData>(context, listen: false);

    // NEW: Check individual zone status first (from Enhanced Zone Parser)
    final zoneStatus = fireAlarmData.getIndividualZoneStatus(zoneNumber);
    if (zoneStatus != null) {
      final status = zoneStatus['status'] as String?;
      switch (status) {
        case 'Alarm':
          return Colors.red;
        case 'Trouble':
          return Colors.orange;
        case 'Active':
          return Colors.blue.shade200;
        case 'Normal':
          return Colors.white;
        default:
          return Colors.grey.shade300;
      }
    }

    // FALLBACK: Use system status if no individual zone data available
    // getSystemStatus returns String, convert to bool
    if (fireAlarmData.getSystemStatus('Alarm') == 'active') {
      return Colors.red;
    }

    if (fireAlarmData.getSystemStatus('Trouble') == 'active') {
      return Colors.orange;
    }

    if (fireAlarmData.getSystemStatus('Drill') == 'active') {
      return Colors.red;
    }

    if (fireAlarmData.getSystemStatus('Silenced') == 'active') {
      return Colors.yellow.shade700;
    }

    // Default white for normal status
    return Colors.white;
  }

  // Get zone border color
  Color _getZoneBorderColor(int zoneNumber) {
    return Colors.grey.shade300;
  }

  // Get zone text color based on background color for better visibility
  Color _getZoneTextColor(int zoneNumber) {
    Color backgroundColor = _getZoneColorFromSystem(zoneNumber);
    
    // Return black text for light backgrounds, white for dark backgrounds
    if (backgroundColor == Colors.white) {
      return Colors.black; // White background = black text
    } else if (backgroundColor == Colors.yellow) {
      return Colors.black; // Yellow background = black text
    } else {
      return Colors.white; // Red/Grey backgrounds = white text
    }
  }

  // Calculate responsive font size based on screen diagonal
  double _calculateResponsiveFontSize(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final diagonal = math.sqrt(size.width * size.width + size.height * size.height);
    final baseSize = diagonal / 100;
    return baseSize.clamp(8.0, 15.0);
  }

  // Build visibility controls for containers
  Widget _buildVisibilityControls() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: _getContainerPadding(context),
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 255, 255, 255),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green[300]!),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Project Container Checkbox
          Row(
            children: [
              Checkbox(
                value: _showProjectContainer,
                onChanged: (bool? value) {
                  setState(() {
                    _showProjectContainer = value ?? true;
                  });
                },
                activeColor: const Color.fromARGB(255, 38, 152, 17),
              ),
              const Text('Project'),
            ],
          ),
          // Zones Container Checkbox
          Row(
            children: [
              Checkbox(
                value: _showZonesContainer,
                onChanged: (bool? value) {
                  setState(() {
                    _showZonesContainer = value ?? true;
                  });
                },
                activeColor: const Color.fromARGB(255, 38, 152, 17),
              ),
              const Text('Zones'),
            ],
          ),
          // Zone Name Container Checkbox
          Row(
            children: [
              Checkbox(
                value: _showZoneNameContainer,
                onChanged: (bool? value) {
                  setState(() {
                    _showZoneNameContainer = value ?? true;
                  });
                },
                activeColor: const Color.fromARGB(255, 38, 152, 17),
              ),
              const Text('Zone Name'),
            ],
          ),
        ],
      ),
    );
  }

  // Get responsive padding for main container
  EdgeInsets _getResponsivePadding(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Base padding: 3% of screen width, minimum 13px, maximum 25px
    final horizontalPadding = (screenWidth * 0.03).clamp(13.0, 25.0);
    final verticalPadding = (screenWidth * 0.02).clamp(8.0, 15.0);
    return EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding);
  }

  // Get responsive padding for individual containers
  double _getContainerPadding(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Container padding: 2% of screen width, minimum 10px, maximum 20px
    return (screenWidth * 0.02).clamp(10.0, 20.0);
  }

  // Initialize services
  Future<void> _initializeServices() async {
    try {
      await _audioManager.initialize();

    } catch (e) {

    }
  }

  // Listener for system status changes to sync with audio
  void _onSystemStatusChanged() {
    final fireAlarmData = context.read<FireAlarmData>();
    
    final currentDrillStatus = fireAlarmData.getSystemStatus('Drill');
    final currentAlarmStatus = fireAlarmData.getSystemStatus('Alarm');
    final currentTroubleStatus = fireAlarmData.getSystemStatus('Trouble');
    final currentSilencedStatus = fireAlarmData.getSystemStatus('Silenced');

    // Update audio manager with new button statuses
    // getSystemStatus returns String, convert to bool
    _audioManager.updateAudioStatusFromButtons(
      isDrillActive: currentDrillStatus == 'active',
      isAlarmActive: currentAlarmStatus == 'active',
      isTroubleActive: currentTroubleStatus == 'active',
      isSilencedActive: currentSilencedStatus == 'active',
    );
  }

  // 🎯 Get system status text based on alarms and troubles
  String _getSystemStatusText(FireAlarmData fireAlarmData) {
    final hasAlarms = fireAlarmData.getAlarmZones().isNotEmpty;
    final hasTroubles = fireAlarmData.getTroubleZones().isNotEmpty;

    if (hasAlarms) {
      return 'ALARM';
    } else if (hasTroubles) {
      return 'SYSTEM TROUBLE';
    } else if (fireAlarmData.hasValidZoneData) {
      return 'SYSTEM NORMAL';
    } else {
      return 'NO DATA';
    }
  }

  // 🎯 Get system status color based on current state
  Color _getSystemStatusColor(FireAlarmData fireAlarmData) {
    final statusText = _getSystemStatusText(fireAlarmData);
    return _getConsistentStatusColor(statusText);
  }

  // 🎯 Consistent status color mapping across all pages (Universal Colors)
  Color _getConsistentStatusColor(String statusText) {
    switch (statusText) {
      case 'ALARM':
        return Colors.red;      // 🔴 Red for Alarm
      case 'ALARM DRILL':
        return Colors.red;      // 🔴 Red for ALARM DRILL (same as Alarm)
      case 'SYSTEM TROUBLE':
        return Colors.orange;   // 🟠 Orange for Trouble
      case 'SYSTEM NORMAL':
        return Colors.green;    // 🟢 Green for Normal (FIXED)
      case 'NO DATA':
        return Colors.grey;     // ⚫ Grey for No Data
      default:
        return Colors.green;    // 🟢 Default to Green
    }
  }
}
