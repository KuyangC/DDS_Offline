import 'package:get_it/get_it.dart';

/// Export getIt instance from main.dart
///
/// This is a simple wrapper to provide access to the service locator
/// without directly importing from main.dart
final GetIt getIt = GetIt.instance;
