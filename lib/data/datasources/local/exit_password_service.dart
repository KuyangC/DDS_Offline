import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/services/logger.dart';

/// Service for managing exit password protection for OfflineMonitoringPage
/// Provides simple 4-digit password validation with fixed password "0000"
class ExitPasswordService {
  static const String _correctPassword = "0000";
  static const String _passwordKey = "exit_password_hash";
  static const String _initializedKey = "exit_password_initialized";

  /// Validate if the entered password matches the correct password
  /// Since this is a fixed password system, we simply compare strings
  /// Returns true if password matches "0000", false otherwise
  static bool validatePassword(String input) {
    // Remove any whitespace and ensure exactly 4 digits
    final cleanInput = input.trim();

    // Check if input is exactly 4 digits and matches the correct password
    return cleanInput.length == 4 &&
           cleanInput == _correctPassword &&
           RegExp(r'^\d{4}$').hasMatch(cleanInput);
  }

  /// Initialize the password service with default password on first run
  /// This ensures the system is ready for password validation
  static Future<void> initializePassword() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if password service has been initialized
      if (!(prefs.getBool(_initializedKey) ?? false)) {
        // Set the default password (for future extensibility)
        await prefs.setString(_passwordKey, _correctPassword);
        await prefs.setBool(_initializedKey, true);

        AppLogger.info('Exit password service initialized with default password');
      }
    } catch (e) {
      AppLogger.error('Failed to initialize exit password service', error: e);
      // Don't throw error - the app should still work even if initialization fails
      // since we're using a fixed password comparison
    }
  }

  /// Get the expected password format description for UI display
  static String getPasswordHint() {
    return 'Enter 4-digit password';
  }

  /// Check if the password service is properly initialized
  static Future<bool> isInitialized() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_initializedKey) ?? false;
    } catch (e) {
      AppLogger.error('Failed to check password service initialization', error: e);
      return false;
    }
  }

  /// Validate password format (4 digits) without checking correctness
  /// Useful for real-time validation in the UI
  static bool isValidPasswordFormat(String input) {
    if (input.isEmpty) return false;

    // Check if input contains only digits and has max 4 digits
    return RegExp(r'^\d{1,4}$').hasMatch(input);
  }

  /// Format password input for display (mask with dots)
  static String formatPasswordDisplay(String input) {
    if (input.isEmpty) return '';

    // Show dots for entered digits
    return '•' * input.length;
  }
}