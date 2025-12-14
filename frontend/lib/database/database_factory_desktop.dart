/// Desktop implementation using FFI
library;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void initializeDatabaseFactory() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

DatabaseFactory getDatabaseFactory() {
  return databaseFactoryFfi;
}
