/// Stub implementation for platforms that don't support FFI
library;
import 'package:sqflite/sqflite.dart';

void initializeDatabaseFactory() {
  // No-op for Web and Mobile platforms
  // They use the default sqflite implementation
}

DatabaseFactory getDatabaseFactory() {
  return databaseFactory;
}
