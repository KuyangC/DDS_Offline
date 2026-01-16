import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:dds_offline_monitoring/data/services/bell_manager.dart';
import 'package:dds_offline_monitoring/presentation/providers/fire_alarm_data_provider.dart';

class ZoneMonitoring extends StatelessWidget {
  const ZoneMonitoring({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FireAlarmData>(
      builder: (context, fireAlarmData, child) {
        final bellManager = GetIt.instance<BellManager>();
        final zones = fireAlarmData.getAllZones();

        if (zones.isEmpty) {
          return const Center(child: Text('No zones to display.'));
        }
        
        return ListView.builder(
          itemCount: zones.length,
          itemBuilder: (context, index) {
            final zone = zones[index];
            final isBellActive = bellManager.getBellStatusForDevice(zone.deviceAddress)?.isActive ?? false;

            return ListTile(
              title: Text(zone.description),
              subtitle: Text('Device: ${zone.deviceAddress} | Global Zone: ${zone.globalZoneNumber}'),
              trailing: Icon(
                Icons.notifications,
                color: isBellActive ? Colors.red : Colors.grey,
              ),
            );
          },
        );
      },
    );
  }
}