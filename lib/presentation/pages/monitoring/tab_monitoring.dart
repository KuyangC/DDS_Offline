import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:dds_offline_monitoring/data/services/bell_manager.dart';
import 'package:dds_offline_monitoring/presentation/providers/fire_alarm_data_provider.dart';

class TabMonitoring extends StatelessWidget {
  const TabMonitoring({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FireAlarmData>(
      builder: (context, fireAlarmData, child) {
        final bellManager = GetIt.instance<BellManager>();
        final devices = fireAlarmData.getAlarmZones();
        
        return ListView.builder(
          itemCount: devices.length,
          itemBuilder: (context, index) {
            final device = devices[index];
            final isBellActive = bellManager.getBellStatusForDevice(device.deviceAddress)?.isActive ?? false;

            return ListTile(
              title: Text(device.description),
              subtitle: Text('Device: ${device.deviceAddress}'),
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