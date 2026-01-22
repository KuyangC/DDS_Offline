import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../data/services/bell_manager.dart';

class BellStatusWidget extends StatefulWidget {
  const BellStatusWidget({super.key});

  @override
  State<BellStatusWidget> createState() => _BellStatusWidgetState();
}

class _BellStatusWidgetState extends State<BellStatusWidget> {
  late final BellManager bellManager;
  late StreamSubscription<BellSystemStatus> _bellStatusSubscription;
  BellSystemStatus? _latestStatus;

  @override
  void initState() {
    super.initState();
    bellManager = GetIt.instance<BellManager>();
    _latestStatus = bellManager.currentStatus;
    _bellStatusSubscription = bellManager.bellStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _latestStatus = status;
        });
      }
    });
  }

  @override
  void dispose() {
    _bellStatusSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _latestStatus;
    if (status == null) {
      return const SizedBox.shrink();
    }

    final bool isBellActive = status.activeBells > 0;
    final Color bellColor = isBellActive ? Colors.red : Colors.grey;

    return GestureDetector(
      onTap: () => _showAnalyticsDialog(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isBellActive ? bellColor.withOpacity(0.1) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: bellColor.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isBellActive ? Icons.notifications_active : Icons.notifications_off,
              color: bellColor,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'BELL',
              style: TextStyle(
                color: bellColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (isBellActive)
              Text(
                ' (${status.activeBells})',
                style: TextStyle(
                  color: bellColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showAnalyticsDialog(BuildContext context) {
    final status = _latestStatus;
    if (status == null) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bell System Analytics'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Active Bells: ${status.activeBells}'),
            Text('System Muted: ${status.isSystemMuted}'),
            Text('Bell Paused: ${status.isBellPaused}'),
          ],
        ),
        actions: [
          TextButton(gh
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}