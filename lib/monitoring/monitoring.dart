import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:dds_offline_monitoring/data/services/bell_manager.dart';
import 'package:dds_offline_monitoring/presentation/providers/fire_alarm_data_provider.dart';
import 'package:dds_offline_monitoring/data/models/zone_status_model.dart';

class MonitoringPage extends StatelessWidget {
  const MonitoringPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoring'),
      ),
      body: Consumer<FireAlarmData>(
        builder: (context, fireAlarmData, child) {
          final bellManager = GetIt.instance<BellManager>();
          final zones = fireAlarmData.getAllZones();

          if (zones.isEmpty) {
            return const Center(
              child: Text('No zone data available.'),
            );
          }

          final Map<int, List<ZoneStatus>> devices = {};
          for (var zone in zones) {
            (devices[zone.deviceAddress] ??= []).add(zone);
          }
          
          final sortedDevices = devices.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key));

          return ListView.builder(
            itemCount: sortedDevices.length,
            itemBuilder: (context, index) {
              final deviceEntry = sortedDevices[index];
              final deviceAddress = deviceEntry.key;
              final deviceZones = deviceEntry.value;
              final deviceName = 'Device $deviceAddress';
              
              final isBellActive = bellManager.getBellStatusForDevice(deviceAddress)?.isActive ?? false;

              return ExpansionTile(
                title: Text(deviceName),
                trailing: Icon(
                  Icons.notifications,
                  color: isBellActive ? Colors.red : Colors.grey,
                ),
                children: deviceZones.map((zone) => ListTile(
                  title: Text(zone.description),
                  subtitle: Text('Global Zone: ${zone.globalZoneNumber} | Status: ${zone.statusText}'),
                )).toList(),
              );
            },
          );
        },
      ),
    );
  }
}
