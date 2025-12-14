import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Desktop implementation with FFI support
Future<void> initializeDatabaseForPlatform() async {
  try {
    // Initialize FFI for Linux/Windows/macOS
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    debugPrint('Desktop platform - FFI database factory initialized');
  } catch (e) {
    debugPrint('FFI initialization failed: $e');
    debugPrint('Falling back to default database factory');
  }
}
