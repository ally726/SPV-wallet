// Conditional export based on platform
// Web and mobile use this stub, desktop uses database_init_desktop.dart
export 'database_init_stub.dart'
    if (dart.library.io) 'database_init_desktop.dart';
