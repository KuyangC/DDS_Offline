import 'dart:convert';
import 'package:flutter/services.dart';
import 'logger.dart';

/// ARP Entry model representing a device in the ARP table
class ArpEntry {
  final String ip;
  final String mac;
  final String device;
  final String? manufacturer;

  const ArpEntry({
    required this.ip,
    required this.mac,
    required this.device,
    this.manufacturer,
  });

  factory ArpEntry.fromJson(Map<String, dynamic> json) {
    final mac = json['mac'] as String;
    return ArpEntry(
      ip: json['ip'] as String,
      mac: mac,
      device: json['device'] as String,
      manufacturer: ArpService.getManufacturerFromMac(mac),
    );
  }

  @override
  String toString() => 'ArpEntry(ip: $ip, mac: $mac, device: $device)';
}

/// ARP Service for reading ARP table and MAC address manufacturer lookup
///
/// Uses MethodChannel to communicate with native Android code
/// to read /proc/net/arp and lookup manufacturer from OUI database
class ArpService {
  static const String _tag = 'ARP_SERVICE';
  static const MethodChannel _channel = MethodChannel('com.dds.dds_offline_monitoring/arp');

  /// Cached ARP table to avoid repeated native calls
  static List<ArpEntry>? _cachedArpTable;
  static DateTime? _cacheTime;
  static const Duration _cacheValidity = Duration(minutes: 1);

  /// OUI (Organizationally Unique Identifier) database for manufacturer lookup
  /// First 3 bytes (6 hex digits) of MAC address identify the vendor
  static const Map<String, String> _ouiDatabase = {
    // Espressif (ESP32)
    'AC:67:B2': 'Espressif',
    '54:5A:A6': 'Espressif',
    'D8:A0:1D': 'Espressif',
    'CC:50:E3': 'Espressif',
    '84:F3:EB': 'Espressif',
    'C8:C9:A3': 'Espressif',
    '7C:DF:A1': 'Espressif',
    'BC:DD:C2': 'Espressif',
    '4C:11:BF': 'Espressif',
    '44:17:93': 'Espressif',
    '24:0A:C4': 'Espressif',
    '30:C6:F7': 'Espressif',
    'A4:CF:12': 'Espressif',
    'E8:DB:84': 'Espressif',
    'F0:08:D1': 'Espressif',

    // Espressif (Espressif Inc.)
    '24:62:AB': 'Espressif',
    'DC:4F:22': 'Espressif',
    'A0:20:A6': 'Espressif',
    'C4:4F:33': 'Espressif',
    'D4:8A:FC': 'Espressif',
    'E4:65:B8': 'Espressif',
    'F4:B8:5E': 'Espressif',
    '38:2B:78': 'Espressif',
    '40:91:51': 'Espressif',
    '48:3F:DA': 'Espressif',
    '58:CF:79': 'Espressif',
    '60:01:94': 'Espressif',
    '68:C6:3A': 'Espressif',
    '70:04:9D': 'Espressif',
    '78:E3:6D': 'Espressif',
    '80:7D:3A': 'Espressif',
    '84:F3:E9': 'Espressif',
    '90:03:0B': 'Espressif',
    '94:B5:55': 'Espressif',
    '98:F4:AB': 'Espressif',
    '9C:9C:1E': 'Espressif',
    'A0:76:4E': 'Espressif',
    'A4:7B:9D': 'Espressif',
    'AC:D0:74': 'Espressif',
    'B0:A7:32': 'Espressif',
    'C4:BB:5D': 'Espressif',

    // Cisco
    '00:00:0C': 'Cisco',
    '00:01:42': 'Cisco',
    '00:0B:BE': 'Cisco',
    '00:0C:29': 'Cisco',
    '00:0D:BC': 'Cisco',
    '00:0E:D7': 'Cisco',
    '00:11:BC': 'Cisco',
    '00:12:43': 'Cisco',
    '00:13:80': 'Cisco',
    '00:14:1C': 'Cisco',
    '00:15:63': 'Cisco',
    '00:16:47': 'Cisco',
    '00:17:94': 'Cisco',
    '00:18:74': 'Cisco',
    '00:19:55': 'Cisco',
    '00:1A:A1': 'Cisco',
    '00:1B:D5': 'Cisco',
    '00:1C:B0': 'Cisco',
    '00:1D:AA': 'Cisco',
    '00:1E:14': 'Cisco',
    '00:1F:CA': 'Cisco',
    '00:22:90': 'Cisco',
    '00:23:04': 'Cisco',
    '00:24:C4': 'Cisco',
    '00:25:84': 'Cisco',
    '00:26:CB': 'Cisco',
    '00:27:90': 'Cisco',
    '00:50:56': 'Cisco',
    '00:1E:C9': 'Cisco',
    'F0:29:29': 'Cisco',

    // TP-Link
    '00:01:2E': 'TP-Link',
    '00:03:0F': 'TP-Link',
    '00:0E:A6': 'TP-Link',
    '00:14:A5': 'TP-Link',
    '00:15:E9': 'TP-Link',
    '00:16:B6': 'TP-Link',
    '00:17:3F': 'TP-Link',
    '00:18:82': 'TP-Link',
    '00:19:15': 'TP-Link',
    '00:1B:A5': 'TP-Link',
    '00:1C:26': 'TP-Link',
    '00:1D:0F': 'TP-Link',
    '00:1E:59': 'TP-Link',
    '00:21:CC': 'TP-Link',
    '00:22:75': 'TP-Link',
    '00:23:C9': 'TP-Link',
    '00:24:A5': 'TP-Link',
    '00:25:56': 'TP-Link',
    '00:26:C7': 'TP-Link',
    '00:27:19': 'TP-Link',
    '00:B0:ED': 'TP-Link',
    '00:B8:93': 'TP-Link',
    '00:EA:28': 'TP-Link',
    '04:4B:1E': 'TP-Link',
    '10:FE:ED': 'TP-Link',
    '14:B9:68': 'TP-Link',
    '18:82:91': 'TP-Link',
    '1C:3E:84': 'TP-Link',
    '20:DC:1F': 'TP-Link',
    '24:05:0F': 'TP-Link',
    '28:28:5D': 'TP-Link',
    '30:B5:C2': 'TP-Link',
    '34:96:72': 'TP-Link',
    '3C:45:12': 'TP-Link',
    '40:16:9E': 'TP-Link',
    '44:07:0B': 'TP-Link',
    '4C:54:99': 'TP-Link',
    '50:C7:BF': 'TP-Link',
    '54:72:92': 'TP-Link',
    '58:97:28': 'TP-Link',
    '5C:E7:27': 'TP-Link',
    '60:45:CB': 'TP-Link',
    '64:70:02': 'TP-Link',
    '68:C7:6A': 'TP-Link',
    '6C:E8:73': 'TP-Link',
    '70:4F:57': 'TP-Link',
    '74:EA:3A': 'TP-Link',
    '78:44:FD': 'TP-Link',
    '7C:7D:3F': 'TP-Link',
    '80:89:17': 'TP-Link',
    '84:A8:E4': 'TP-Link',
    '88:25:93': 'TP-Link',
    '8C:C2:EA': 'TP-Link',
    '90:97:5E': 'TP-Link',
    '94:83:C1': 'TP-Link',
    '98:6E:68': 'TP-Link',
    '9C:C9:EB': 'TP-Link',
    'A0:15:B1': 'TP-Link',
    'A4:11:B8': 'TP-Link',
    'A8:6E:84': 'TP-Link',
    'AC:C9:4E': 'TP-Link',
    'B0:A8:6E': 'TP-Link',
    'B4:55:BE': 'TP-Link',
    'B8:59:9F': 'TP-Link',
    'BC:46:1E': 'TP-Link',
    'C0:06:CB': 'TP-Link',
    'C4:04:15': 'TP-Link',
    'C8:3A:35': 'TP-Link',
    'CC:05:C5': 'TP-Link',
    'D0:19:B8': 'TP-Link',
    'D4:28:7B': 'TP-Link',
    'D8:15:0D': 'TP-Link',
    'DC:A0:3A': 'TP-Link',
    'E0:70:B0': 'TP-Link',
    'E4:95:6E': 'TP-Link',
    'E8:94:F6': 'TP-Link',
    'EC:08:6B': 'TP-Link',
    'F0:79:59': 'TP-Link',
    'F4:79:59': 'TP-Link',
    'F8:5F:B2': 'TP-Link',

    // D-Link
    '00:05:5D': 'D-Link',
    '00:0B:82': 'D-Link',
    '00:0E:2A': 'D-Link',
    '00:0F:E2': 'D-Link',
    '00:12:17': 'D-Link',
    '00:13:46': 'D-Link',
    '00:14:5A': 'D-Link',
    '00:16:EC': 'D-Link',
    '00:17:9A': 'D-Link',
    '00:19:5B': 'D-Link',
    '00:1B:2C': 'D-Link',
    '00:1C:F0': 'D-Link',
    '00:1D:70': 'D-Link',
    '00:1E:58': 'D-Link',
    '00:22:B0': 'D-Link',
    '00:24:01': 'D-Link',
    '00:26:5A': 'D-Link',
    '00:E0:4C': 'D-Link',
    '00:E0:7D': 'D-Link',
    '1C:5F:2B': 'D-Link',
    '1C:B7:2C': 'D-Link',
    '14:CC:20': 'D-Link',
    '1C:B0:EA': 'D-Link',
    '20:DC:9F': 'D-Link',
    '2C:B0:5D': 'D-Link',
    '34:08:04': 'D-Link',
    '38:83:45': 'D-Link',
    '3C:F0:11': 'D-Link',
    '40:4D:86': 'D-Link',
    '44:8A:5B': 'D-Link',
    '48:5B:39': 'D-Link',
    '4C:66:41': 'D-Link',
    '54:75:D0': 'D-Link',
    '58:BF:EA': 'D-Link',
    '5C:D9:98': 'D-Link',
    '60:6C:66': 'D-Link',
    '6C:19:8F': 'D-Link',
    '70:6F:96': 'D-Link',
    '74:D0:2B': 'D-Link',
    '78:54:2E': 'D-Link',
    '80:5F:C9': 'D-Link',
    '84:C9:B2': 'D-Link',
    '88:75:56': 'D-Link',
    '8C:A6:9F': 'D-Link',
    '90:6F:18': 'D-Link',
    '94:44:52': 'D-Link',
    '98:84:85': 'D-Link',
    'A0:AB:1B': 'D-Link',
    'A4:54:93': 'D-Link',
    'A8:5E:45': 'D-Link',
    'AC:A2:15': 'D-Link',
    'B0:C0:90': 'D-Link',
    'B4:52:0D': 'D-Link',
    'B8:A3:86': 'D-Link',
    'BC:D1:D3': 'D-Link',
    'C0:C1:C0': 'D-Link',
    'C8:60:00': 'D-Link',
    'CC:B2:55': 'D-Link',
    'D0:17:C2': 'D-Link',
    'D8:54:9E': 'D-Link',
    'DC:53:7C': 'D-Link',
    'E0:60:66': 'D-Link',
    'E4:6A:4A': 'D-Link',
    'F4:EC:38': 'D-Link',

    // Ubiquiti
    '00:27:22': 'Ubiquiti',
    '04:18:D6': 'Ubiquiti',
    '68:72:51': 'Ubiquiti',
    '6C:E2:8D': 'Ubiquiti',
    '74:83:C2': 'Ubiquiti',
    '78:8A:20': 'Ubiquiti',
    '80:2A:A8': 'Ubiquiti',
    '84:16:F9': 'Ubiquiti',
    '88:E1:79': 'Ubiquiti',
    'A0:63:91': 'Ubiquiti',
    'A8:F7:50': 'Ubiquiti',
    'AC:86:74': 'Ubiquiti',
    'B4:FB:E4': 'Ubiquiti',
    'C0:EA:34': 'Ubiquiti',
    'C4:41:1E': 'Ubiquiti',
    'C8:4B:00': 'Ubiquiti',
    'D0:73:D5': 'Ubiquiti',
    'D4:FA:D9': 'Ubiquiti',
    'DC:9F:DB': 'Ubiquiti',
    'E0:63:DA': 'Ubiquiti',
    'E4:8F:4C': 'Ubiquiti',
    'E8:84:A7': 'Ubiquiti',
    'F0:9F:C2': 'Ubiquiti',
    'F4:C2:68': 'Ubiquiti',
    'FC:EC:DA': 'Ubiquiti',

    // Mikrotik
    '00:0C:42': 'MikroTik',
    'B8:69:F4': 'MikroTik',
    'C4:8E:8F': 'MikroTik',
    'D4:CA:6D': 'MikroTik',
    'E4:8D:8C': 'MikroTik',
    'F0:39:9D': 'MikroTik',
    '74:4D:28': 'MikroTik',
    '4C:5E:0C': 'MikroTik',
    '2C:C8:1B': 'MikroTik',
    '6C:3B:6B': 'MikroTik',
    'CC:2D:E0': 'MikroTik',
    'A8:58:40': 'MikroTik',
    '24:1F:28': 'MikroTik',
    '68:D5:43': 'MikroTik',
    '4E:A3:75': 'MikroTik',
    'E0:A1:93': 'MikroTik',
    'D6:CA:8D': 'MikroTik',
    'C2:61:6D': 'MikroTik',
    'A2:56:92': 'MikroTik',
    'D4:AE:52': 'MikroTik',

    // Apple
    '00:03:93': 'Apple',
    '00:0A:95': 'Apple',
    '00:0D:93': 'Apple',
    '00:11:24': 'Apple',
    '00:14:51': 'Apple',
    '00:16:CB': 'Apple',
    '00:17:F2': 'Apple',
    '00:1B:63': 'Apple',
    '00:1C:B3': 'Apple',
    '00:1D:4F': 'Apple',
    '00:1E:52': 'Apple',
    '00:1E:C2': 'Apple',
    '00:23:32': 'Apple',
    '00:23:DF': 'Apple',
    '00:25:00': 'Apple',
    '00:25:4B': 'Apple',
    '00:25:BC': 'Apple',
    '04:1E:64': 'Apple',
    '04:54:AB': 'Apple',
    '04:C7:3E': 'Apple',
    '14:99:02': 'Apple',
    '1C:AB:A7': 'Apple',
    '24:A0:74': 'Apple',
    '28:CF:E9': 'Apple',
    '2C:F0:A2': 'Apple',
    '34:15:9D': 'Apple',
    '3C:15:C2': 'Apple',
    '40:A6:D9': 'Apple',
    '44:1E:A1': 'Apple',
    '4C:32:75': 'Apple',
    '58:1F:EA': 'Apple',
    '5C:59:48': 'Apple',
    '60:33:4B': 'Apple',
    '64:20:6C': 'Apple',
    '68:A3:C4': 'Apple',
    '6C:40:08': 'Apple',
    '70:73:CB': 'Apple',
    '74:65:2E': 'Apple',
    '78:7C:5D': 'Apple',
    '7C:04:D0': 'Apple',
    '84:85:F4': 'Apple',
    '88:C6:26': 'Apple',
    '8C:85:90': 'Apple',
    '90:84:0D': 'Apple',
    '94:A4:A3': 'Apple',
    '98:03:D8': 'Apple',
    '9C:4E:36': 'Apple',
    'A0:99:9B': 'Apple',
    'A4:D1:D2': 'Apple',
    'A8:66:7F': 'Apple',
    'AC:BC:32': 'Apple',
    'B0:B2:1C': 'Apple',
    'B4:B0:24': 'Apple',
    'B8:8D:12': 'Apple',
    'C0:38:68': 'Apple',
    'C4:2C:03': 'Apple',
    'C8:69:CD': 'Apple',
    'CC:F4:78': 'Apple',
    'D0:3C:91': 'Apple',
    'D4:61:9E': 'Apple',
    'D8:30:62': 'Apple',
    'DC:41:A9': 'Apple',
    'E0:AC:CB': 'Apple',
    'E4:63:A1': 'Apple',
    'E8:8D:28': 'Apple',
    'F0:18:98': 'Apple',
    'F4:7B:8D': 'Apple',
    'F8:FF:C2': 'Apple',
    'FC:A3:28': 'Apple',

    // Samsung
    '00:04:75': 'Samsung',
    '00:0B:E8': 'Samsung',
    '00:0E:2D': 'Samsung',
    '00:0F:AE': 'Samsung',
    '00:12:FB': 'Samsung',
    '00:15:99': 'Samsung',
    '00:16:32': 'Samsung',
    '00:16:6C': 'Samsung',
    '00:17:C9': 'Samsung',
    '00:18:AF': 'Samsung',
    '00:19:B9': 'Samsung',
    '00:1A:D8': 'Samsung',
    '00:1B:FC': 'Samsung',
    '00:1C:C5': 'Samsung',
    '00:1D:BA': 'Samsung',
    '00:1E:E2': 'Samsung',
    '00:22:F3': 'Samsung',
    '00:23:1A': 'Samsung',
    '00:24:54': 'Samsung',
    '00:25:A3': 'Samsung',
    '00:26:18': 'Samsung',
    '00:27:10': 'Samsung',
    '00:E0:64': 'Samsung',
    '04:18:5F': 'Samsung',
    '04:C9:79': 'Samsung',
    '08:3E:0A': 'Samsung',
    '0C:D2:B5': 'Samsung',
    '10:68:3F': 'Samsung',
    '14:DD:A9': 'Samsung',
    '18:87:96': 'Samsung',
    '1C:52:16': 'Samsung',
    '20:64:32': 'Samsung',
    '24:2B:70': 'Samsung',
    '28:CF:DA': 'Samsung',
    '30:97:A8': 'Samsung',
    '34:02:86': 'Samsung',
    '38:8B:59': 'Samsung',
    '3C:A8:2A': 'Samsung',
    '40:4E:36': 'Samsung',
    '44:DF:70': 'Samsung',
    '48:5A:3F': 'Samsung',
    '4C:72:B9': 'Samsung',
    '50:1A:E8': 'Samsung',
    '54:1F:9E': 'Samsung',
    '58:48:BA': 'Samsung',
    '5C:FD:41': 'Samsung',
    '64:16:A6': 'Samsung',
    '68:7B:3A': 'Samsung',
    '6C:AD:F8': 'Samsung',
    '70:1B:91': 'Samsung',
    '74:5D:84': 'Samsung',
    '78:11:DC': 'Samsung',
    '7C:61:5D': 'Samsung',
    '80:1F:02': 'Samsung',
    '84:4D:B8': 'Samsung',
    '88:1E:96': 'Samsung',
    '8C:34:FD': 'Samsung',
    '90:26:75': 'Samsung',
    '94:C4:EE': 'Samsung',
    '98:D8:63': 'Samsung',
    '9C:28:EF': 'Samsung',
    'A0:82:C6': 'Samsung',
    'A4:C3:61': 'Samsung',
    'A8:1B:5A': 'Samsung',
    'AC:5F:3E': 'Samsung',
    'B0:72:BF': 'Samsung',
    'B4:9E:46': 'Samsung',
    'B8:AC:6F': 'Samsung',
    'BC:D1:95': 'Samsung',
    'C0:4A:00': 'Samsung',
    'C4:8E:0F': 'Samsung',
    'C8:7B:EA': 'Samsung',
    'CC:C3:EA': 'Samsung',
    'D0:76:AA': 'Samsung',
    'D4:3B:8D': 'Samsung',
    'D8:5D:C2': 'Samsung',
    'DC:44:19': 'Samsung',
    'E0:75:2C': 'Samsung',
    'E4:9E:11': 'Samsung',
    'E8:50:8B': 'Samsung',
    'EC:41:82': 'Samsung',
    'F0:27:65': 'Samsung',
    'F4:4E:05': 'Samsung',
    'F8:CF:C5': 'Samsung',
    'FC:01:74': 'Samsung',

    // Huawei
    '00:1E:EC': 'Huawei',
    '00:E0:FC': 'Huawei',
    '08:10:76': 'Huawei',
    '18:E8:29': 'Huawei',
    '2C:56:DC': 'Huawei',
    '34:12:78': 'Huawei',
    '50:7B:9D': 'Huawei',
    '58:AF:35': 'Huawei',
    '6C:53:B3': 'Huawei',
    '7C:6D:62': 'Huawei',
    '8C:21:0A': 'Huawei',
    '94:DE:80': 'Huawei',
    'A0:96:27': 'Huawei',
    'AC:85:3D': 'Huawei',
    'B0:83:FE': 'Huawei',
    'C4:73:1F': 'Huawei',
    'CC:34:29': 'Huawei',
    'E0:CB:4E': 'Huawei',
    'F0:DB:40': 'Huawei',

    // Xiaomi
    '34:CE:00': 'Xiaomi',
    '64:09:80': 'Xiaomi',
    '78:02:F8': 'Xiaomi',
    'F4:8C:EB': 'Xiaomi',
    '38:BC:1A': 'Xiaomi',
    '7C:70:BF': 'Xiaomi',
    'AC:23:3F': 'Xiaomi',
    '60:AB:D2': 'Xiaomi',
    'F0:B4:29': 'Xiaomi',
    '50:BD:5F': 'Xiaomi',
    'A4:4E:31': 'Xiaomi',
    'CC:81:D6': 'Xiaomi',
    'D4:6E:0E': 'Xiaomi',
    'E4:67:1C': 'Xiaomi',
    'F8:A4:5F': 'Xiaomi',

    // Realtek
    '00:00:4C': 'Realtek',
    '00:E0:4D': 'Realtek',
    '00:05:1C': 'Realtek',
    '00:0F:EA': 'Realtek',
    '00:1B:B9': 'Realtek',
    '00:1E:8C': 'Realtek',
    '00:26:4E': 'Realtek',
    '00:30:18': 'Realtek',
    '00:90:CC': 'Realtek',
    '00:D0:59': 'Realtek',
    '04:98:0F': 'Realtek',
    '10:BF:48': 'Realtek',
    '14:D6:4D': 'Realtek',
    '20:CF:30': 'Realtek',
    '28:94:0F': 'Realtek',
    '2C:AB:2E': 'Realtek',
    '30:85:A9': 'Realtek',
    '38:2C:80': 'Realtek',
    '3C:9C:0F': 'Realtek',
    '40:F0:08': 'Realtek',
    '4C:ED:FB': 'Realtek',
    '50:46:5D': 'Realtek',
    '54:12:6F': 'Realtek',
    '58:8C:7A': 'Realtek',
    '5C:AA:6D': 'Realtek',
    '60:A7:27': 'Realtek',
    '7C:4C:2E': 'Realtek',

    // Google
    'F4:F5:DB': 'Google',
    '54:60:09': 'Google',
    'AC:3B:97': 'Google',
    '78:4F:43': 'Google',
    'A4:C8:38': 'Google',
    'B4:79:73': 'Google',
    'E4:70:B8': 'Google',

    // Unknown / Other
  };

  /// Get manufacturer from MAC address using OUI lookup
  ///
  /// The OUI (Organizationally Unique Identifier) is the first 3 bytes
  /// (first 6 hex characters) of a MAC address
  static String? getManufacturerFromMac(String macAddress) {
    if (macAddress.isEmpty || macAddress.length < 17) {
      return null;
    }

    // Extract first 3 octets (OUI) - format: AA:BB:CC:DD:EE:FF
    final oui = macAddress.substring(0, 8).toUpperCase();

    return _ouiDatabase[oui];
  }

  /// Get ARP table from native Android code
  ///
  /// Reads /proc/net/arp and returns list of ArpEntry objects
  /// Results are cached for 1 minute to avoid repeated native calls
  static Future<List<ArpEntry>> getArpTable() async {
    // Check cache first
    if (_cachedArpTable != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheValidity) {
      AppLogger.info('Using cached ARP table (${_cachedArpTable!.length} entries)', tag: _tag);
      return _cachedArpTable!;
    }

    try {
      AppLogger.info('Fetching ARP table from native...', tag: _tag);

      final String result = await _channel.invokeMethod('getArpTable') as String;
      final List<dynamic> jsonList = json.decode(result);

      final entries = jsonList
          .map((json) => ArpEntry.fromJson(json as Map<String, dynamic>))
          .toList();

      // Update cache
      _cachedArpTable = entries;
      _cacheTime = DateTime.now();

      AppLogger.info('Got ${entries.length} ARP entries', tag: _tag);
      return entries;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to get ARP table',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Find MAC address for a specific IP address
  static Future<String?> getMacAddressForIp(String ip) async {
    final arpTable = await getArpTable();

    for (final entry in arpTable) {
      if (entry.ip == ip) {
        return entry.mac;
      }
    }

    return null;
  }

  /// Find manufacturer for a specific IP address
  static Future<String?> getManufacturerForIp(String ip) async {
    final arpTable = await getArpTable();

    for (final entry in arpTable) {
      if (entry.ip == ip) {
        return entry.manufacturer;
      }
    }

    return null;
  }

  /// Clear the ARP cache
  static void clearCache() {
    _cachedArpTable = null;
    _cacheTime = null;
    AppLogger.info('ARP cache cleared', tag: _tag);
  }

  /// Get ARP entry for a specific IP
  static Future<ArpEntry?> getEntryForIp(String ip) async {
    final arpTable = await getArpTable();

    for (final entry in arpTable) {
      if (entry.ip == ip) {
        return entry;
      }
    }

    return null;
  }
}
