import 'dart:io';
import 'dart:async';
import 'logger.dart';
import 'arp_service.dart';

/// Connection Health Service untuk testing network reachability
/// Provides pre-connection testing to avoid unnecessary WebSocket connection attempts
class ConnectionHealthService {
  static const String _tag = 'CONNECTION_HEALTH';
  static const Duration _defaultTimeout = Duration(seconds: 5);
  static const int _maxRetries = 3;

  /// Test if a host:port is reachable before attempting WebSocket connection
  static Future<ConnectionTestResult> testConnection(
    String host,
    int port, {
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? _defaultTimeout;

    AppLogger.info('Testing connection to $host:$port', tag: _tag);

    try {
      // Validate host and port
      if (host.isEmpty) {
        return ConnectionTestResult(
          isReachable: false,
          error: 'Host cannot be empty',
          errorType: ConnectionErrorType.invalidHost,
        );
      }

      if (port < 1 || port > 65535) {
        return ConnectionTestResult(
          isReachable: false,
          error: 'Port must be between 1 and 65535',
          errorType: ConnectionErrorType.invalidPort,
        );
      }

      // Perform socket connection test
      final result = await _performSocketTest(host, port, effectiveTimeout);

      if (result.isReachable) {
        AppLogger.info('✅ Connection test successful for $host:$port', tag: _tag);
      } else {
        AppLogger.warning('❌ Connection test failed for $host:$port - ${result.error}', tag: _tag);
      }

      return result;

    } catch (e, stackTrace) {
      AppLogger.error(
        'Unexpected error during connection test',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );

      return ConnectionTestResult(
        isReachable: false,
        error: 'Unexpected error: ${e.toString()}',
        errorType: ConnectionErrorType.unknownError,
      );
    }
  }

  /// Perform actual socket connection test
  static Future<ConnectionTestResult> _performSocketTest(
    String host,
    int port,
    Duration timeout,
  ) async {
    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        AppLogger.info('Socket test attempt $attempt/$_maxRetries for $host:$port', tag: _tag);

        final stopwatch = Stopwatch()..start();

        await Socket.connect(
          host,
          port,
          timeout: timeout,
        ).timeout(timeout);

        stopwatch.stop();

        return ConnectionTestResult(
          isReachable: true,
          responseTime: stopwatch.elapsed,
          attempt: attempt,
        );

      } on SocketException catch (e) {
        AppLogger.warning('Socket test attempt $attempt failed: ${e.message}', tag: _tag);

        if (attempt == _maxRetries) {
          return ConnectionTestResult(
            isReachable: false,
            error: _getSocketExceptionMessage(e),
            errorType: _classifySocketException(e),
            attempt: attempt,
          );
        }

        // Wait before retry with exponential backoff
        await Future.delayed(Duration(milliseconds: 500 * attempt));

      } on TimeoutException catch (e) {
        AppLogger.warning('Socket test attempt $attempt timed out', tag: _tag);

        if (attempt == _maxRetries) {
          return ConnectionTestResult(
            isReachable: false,
            error: 'Connection timeout after ${timeout.inSeconds}s',
            errorType: ConnectionErrorType.timeout,
            attempt: attempt,
          );
        }

        // Wait before retry with exponential backoff
        await Future.delayed(Duration(milliseconds: 500 * attempt));

      } catch (e) {
        AppLogger.error('Unexpected error in socket test attempt $attempt', tag: _tag, error: e);

        if (attempt == _maxRetries) {
          return ConnectionTestResult(
            isReachable: false,
            error: 'Unexpected error: ${e.toString()}',
            errorType: ConnectionErrorType.unknownError,
            attempt: attempt,
          );
        }

        // Wait before retry with exponential backoff
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }

    return ConnectionTestResult(
      isReachable: false,
      error: 'All $_maxRetries connection attempts failed',
      errorType: ConnectionErrorType.allAttemptsFailed,
    );
  }

  /// Get user-friendly message from SocketException
  static String _getSocketExceptionMessage(SocketException e) {
    if (e.message?.contains('Connection refused') == true) {
      return 'Connection refused - ESP32 may be off or wrong port';
    } else if (e.message?.contains('Network is unreachable') == true) {
      return 'Network unreachable - check WiFi connection';
    } else if (e.message?.contains('Host is down') == true) {
      return 'Host unreachable - ESP32 may be off';
    } else if (e.message?.contains('No address associated with hostname') == true) {
      return 'Invalid hostname or DNS resolution failed';
    } else if (e.message?.contains('Connection timed out') == true) {
      return 'Connection timed out - ESP32 not responding';
    } else {
      return e.message ?? 'Unknown socket error';
    }
  }

  /// Classify SocketException into error types
  static ConnectionErrorType _classifySocketException(SocketException e) {
    final message = e.message?.toLowerCase() ?? '';

    if (message.contains('connection refused')) {
      return ConnectionErrorType.connectionRefused;
    } else if (message.contains('network is unreachable')) {
      return ConnectionErrorType.networkUnreachable;
    } else if (message.contains('host is down') || message.contains('no address')) {
      return ConnectionErrorType.hostUnreachable;
    } else if (message.contains('timed out')) {
      return ConnectionErrorType.timeout;
    } else {
      return ConnectionErrorType.socketError;
    }
  }

  /// Test multiple common ESP32 ports to find working one
  static Future<List<PortTestResult>> testCommonPorts(
    String host, {
    List<int> ports = const [80, 81, 8080, 3000, 5000],
    Duration? timeout,
  }) async {
    AppLogger.info('Testing common ports for $host: $ports', tag: _tag);

    final results = <PortTestResult>[];

    for (final port in ports) {
      final result = await testConnection(host, port, timeout: timeout);
      results.add(PortTestResult(
        port: port,
        result: result,
      ));

      // Small delay between tests
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Sort by response time (successful connections first)
    results.sort((a, b) {
      if (a.result.isReachable && !b.result.isReachable) return -1;
      if (!a.result.isReachable && b.result.isReachable) return 1;
      if (a.result.isReachable && b.result.isReachable) {
        return a.result.responseTime?.inMilliseconds.compareTo(b.result.responseTime?.inMilliseconds ?? 0) ?? 0;
      }
      return 0;
    });

    return results;
  }

  /// Auto-discover ESP32 on local network by testing common IPs
  static Future<List<DiscoveryResult>> discoverESP32Devices({
    List<String> baseNetworks = const ['192.168.1', '192.168.0', '10.0.0'],
    List<int> ports = const [80, 81, 8080],
    int maxIPRange = 254,
    Duration? timeout,
    Duration? testDelay,
  }) async {
    final results = <DiscoveryResult>[];
    final effectiveTimeout = timeout ?? const Duration(seconds: 2);
    final effectiveDelay = testDelay ?? const Duration(milliseconds: 50);

    AppLogger.info('Starting ESP32 device discovery', tag: _tag);

    for (final network in baseNetworks) {
      AppLogger.info('Scanning network: $network.x', tag: _tag);

      for (int i = 1; i <= maxIPRange && i <= 254; i++) { // Limit scan to first 254 IPs
        final host = '$network.$i';

        // Test all ports for this host
        final portResults = await testCommonPorts(host, ports: ports, timeout: effectiveTimeout);
        final reachablePorts = portResults.where((r) => r.result.isReachable).toList();

        if (reachablePorts.isNotEmpty) {
          results.add(DiscoveryResult(
            host: host,
            reachablePorts: reachablePorts,
            bestPort: reachablePorts.first.port,
            bestResponseTime: reachablePorts.first.result.responseTime,
          ));

          AppLogger.info('🎯 Found ESP32 at $host:${reachablePorts.first.port}', tag: _tag);
        }

        // Small delay between hosts to avoid flooding network
        await Future.delayed(effectiveDelay);
      }
    }

    // Sort by best response time
    results.sort((a, b) {
      if (a.bestResponseTime != null && b.bestResponseTime != null) {
        return a.bestResponseTime!.inMilliseconds.compareTo(b.bestResponseTime!.inMilliseconds);
      }
      return 0;
    });

    AppLogger.info('Discovery completed. Found ${results.length} devices.', tag: _tag);
    return results;
  }

  /// Optimized ESP32 discovery for faster scanning
  /// - Single attempt per port (no retries)
  /// - Faster timeout (500ms default)
  /// - Parallel port testing
  /// - Stops after finding maxDevices
  /// - Enriches results with MAC address and manufacturer from ARP table
  static Future<List<DiscoveryResult>> discoverESP32DevicesOptimized({
    List<String> baseNetworks = const ['192.168.1', '192.168.0', '10.0.0'],
    List<int> ports = const [80, 81, 8080],
    int maxIPRange = 50,
    Duration? timeout = const Duration(milliseconds: 500),
    int maxDevices = 10,
  }) async {
    final results = <DiscoveryResult>[];

    AppLogger.info('Starting FAST ESP32 discovery (maxIPRange=$maxIPRange, maxDevices=$maxDevices)', tag: _tag);

    // Get ARP table for MAC address and manufacturer lookup
    final arpTable = await ArpService.getArpTable();
    AppLogger.info('Loaded ${arpTable.length} ARP entries for device identification', tag: _tag);

    // Create IP->ARP lookup map
    final arpMap = <String, ArpEntry>{};
    for (final entry in arpTable) {
      arpMap[entry.ip] = entry;
    }

    for (final network in baseNetworks) {
      AppLogger.info('Scanning network: $network.x', tag: _tag);

      for (int i = 1; i <= maxIPRange && i <= 254; i++) {
        final host = '$network.$i';

        // Fast parallel port test (single attempt, no retry)
        final portResults = await _testCommonPortsFast(host, ports: ports, timeout: timeout!);
        final reachablePorts = portResults.where((r) => r.isReachable).toList();

        if (reachablePorts.isNotEmpty) {
          final bestPort = reachablePorts.first.port;
          final bestTime = reachablePorts.first.responseTime;

          // Look up MAC and manufacturer from ARP table
          final arpEntry = arpMap[host];

          results.add(DiscoveryResult(
            host: host,
            reachablePorts: reachablePorts.map((p) => PortTestResult(
              port: p.port,
              result: ConnectionTestResult(isReachable: true, responseTime: p.responseTime),
            )).toList(),
            bestPort: bestPort,
            bestResponseTime: bestTime,
            macAddress: arpEntry?.mac,
            manufacturer: arpEntry?.manufacturer,
          ));

          final mfrStr = arpEntry?.manufacturer != null ? ' (${arpEntry!.manufacturer})' : '';
          AppLogger.info('🎯 Found ESP32 at $host:$bestPort (${bestTime?.inMilliseconds ?? 0}ms)$mfrStr', tag: _tag);

          // Stop if we found enough devices
          if (results.length >= maxDevices) {
            AppLogger.info('Found $maxDevices devices, stopping scan', tag: _tag);
            break;
          }
        }
      }

      // Stop scanning networks if we found enough devices
      if (results.length >= maxDevices) {
        break;
      }
    }

    // Sort by best response time
    results.sort((a, b) {
      if (a.bestResponseTime != null && b.bestResponseTime != null) {
        return a.bestResponseTime!.inMilliseconds.compareTo(b.bestResponseTime!.inMilliseconds);
      }
      return 0;
    });

    AppLogger.info('Fast discovery completed. Found ${results.length} devices.', tag: _tag);
    return results;
  }

  /// Fast port test - single attempt per port, parallel testing
  static Future<List<_FastPortResult>> _testCommonPortsFast(
    String host, {
    required List<int> ports,
    required Duration timeout,
  }) async {
    final results = await Future.wait(
      ports.map((port) => _testPortFast(host, port, timeout)),
    );

    return results;
  }

  /// Fast single-attempt port test
  static Future<_FastPortResult> _testPortFast(
    String host,
    int port,
    Duration timeout,
  ) async {
    final stopwatch = Stopwatch()..start();

    try {
      await Socket.connect(host, port, timeout: timeout).timeout(timeout);
      stopwatch.stop();
      return _FastPortResult(port, true, stopwatch.elapsed);
    } catch (_) {
      stopwatch.stop();
      return _FastPortResult(port, false, null);
    }
  }
}

/// Connection test result
class ConnectionTestResult {
  final bool isReachable;
  final String? error;
  final ConnectionErrorType? errorType;
  final Duration? responseTime;
  final int? attempt;

  const ConnectionTestResult({
    required this.isReachable,
    this.error,
    this.errorType,
    this.responseTime,
    this.attempt = 1,
  });

  @override
  String toString() {
    if (isReachable) {
      final timeStr = responseTime != null ? ' (${responseTime!.inMilliseconds}ms)' : '';
      return 'Reachable$timeStr';
    } else {
      return 'Not reachable: $error';
    }
  }
}

/// Port test result for multi-port testing
class PortTestResult {
  final int port;
  final ConnectionTestResult result;

  const PortTestResult({
    required this.port,
    required this.result,
  });

  @override
  String toString() {
    return 'Port $port: ${result.toString()}';
  }
}

/// Device discovery result
class DiscoveryResult {
  final String host;
  final List<PortTestResult> reachablePorts;
  final int bestPort;
  final Duration? bestResponseTime;
  final String? macAddress;
  final String? manufacturer;

  const DiscoveryResult({
    required this.host,
    required this.reachablePorts,
    required this.bestPort,
    this.bestResponseTime,
    this.macAddress,
    this.manufacturer,
  });

  String get bestAddress => '$host:$bestPort';

  DiscoveryResult copyWith({
    String? host,
    List<PortTestResult>? reachablePorts,
    int? bestPort,
    Duration? bestResponseTime,
    String? macAddress,
    String? manufacturer,
  }) {
    return DiscoveryResult(
      host: host ?? this.host,
      reachablePorts: reachablePorts ?? this.reachablePorts,
      bestPort: bestPort ?? this.bestPort,
      bestResponseTime: bestResponseTime ?? this.bestResponseTime,
      macAddress: macAddress ?? this.macAddress,
      manufacturer: manufacturer ?? this.manufacturer,
    );
  }

  @override
  String toString() {
    final timeStr = bestResponseTime != null ? ' (${bestResponseTime!.inMilliseconds}ms)' : '';
    final macStr = macAddress != null ? ' | MAC: $macAddress' : '';
    final mfrStr = manufacturer != null ? ' ($manufacturer)' : '';
    return 'ESP32 at $bestAddress$timeStr$macStr$mfrStr';
  }
}

/// Connection error types for better error handling
enum ConnectionErrorType {
  invalidHost,
  invalidPort,
  connectionRefused,
  networkUnreachable,
  hostUnreachable,
  timeout,
  socketError,
  allAttemptsFailed,
  unknownError,
}

/// Fast port result for optimized scanning
class _FastPortResult {
  final int port;
  final bool isReachable;
  final Duration? responseTime;

  const _FastPortResult(this.port, this.isReachable, this.responseTime);
}