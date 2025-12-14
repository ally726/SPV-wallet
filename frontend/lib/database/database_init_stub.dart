import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

// Stub implementation for Web and Mobile platforms
Future<void> initializeDatabaseForPlatform() async {
  if (kIsWeb) {
    // Initialize FFI for Web (uses IndexedDB)
    databaseFactory = databaseFactoryFfiWeb;
    debugPrint(
        'Web platform - FFI Web database factory initialized (IndexedDB)');
  } else {
    // Mobile platforms use default sqflite (native SQLite)
    debugPrint('Mobile platform - using native SQLite');
  }
}
