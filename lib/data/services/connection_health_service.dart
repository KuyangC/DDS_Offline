import 'dart:io';
import 'dart:async';
import 'logger.dart';

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

      for (int i = 1; i <= maxIPRange && i <= 50; i++) { // Limit scan to first 50 IPs
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

  const DiscoveryResult({
    required this.host,
    required this.reachablePorts,
    required this.bestPort,
    this.bestResponseTime,
  });

  String get bestAddress => '$host:$bestPort';

  @override
  String toString() {
    final timeStr = bestResponseTime != null ? ' (${bestResponseTime!.inMilliseconds}ms)' : '';
    return 'ESP32 at $bestAddress$timeStr';
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