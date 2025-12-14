import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/block_header.dart';
import '../models/utxo.dart';
import '../utils/constants.dart';

/// Database helper for local SPV wallet storage
/// Manages block headers, transactions, and UTXOs
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  /// Get database instance (singleton pattern)
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize database and create tables
  /// Note: Database factory should be initialized in main() before this is called
  Future<Database> _initDatabase() async {
    print('Opening database...');

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, AppConstants.dbName);

    return await openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Create database tables
  Future<void> _onCreate(Database db, int version) async {
    // Block headers table - stores the blockchain header chain
    await db.execute('''
      CREATE TABLE block_headers (
        hash TEXT PRIMARY KEY,
        version INTEGER NOT NULL,
        previous_block_hash TEXT NOT NULL,
        merkle_root TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        bits INTEGER NOT NULL,
        nonce INTEGER NOT NULL,
        height INTEGER NOT NULL UNIQUE
      )
    ''');

    // Create index for faster queries
    await db.execute('''
      CREATE INDEX idx_block_height ON block_headers(height)
    ''');

    await db.execute('''
      CREATE INDEX idx_block_timestamp ON block_headers(timestamp)
    ''');

    // Wallet transactions table - stores relevant transactions
    await db.execute('''
      CREATE TABLE wallet_transactions (
        tx_hash TEXT PRIMARY KEY,
        block_height INTEGER,
        block_time INTEGER,
        fee TEXT NOT NULL,
        confirmations INTEGER,
        raw_data TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_tx_block_height ON wallet_transactions(block_height)
    ''');

    // UTXOs table - stores unspent outputs
    await db.execute('''
      CREATE TABLE utxos (
        tx_hash TEXT NOT NULL,
        vout INTEGER NOT NULL,
        value TEXT NOT NULL,
        script_pub_key TEXT NOT NULL,
        address TEXT NOT NULL,
        derivation_index INTEGER NOT NULL,
        is_change INTEGER NOT NULL,
        confirmations INTEGER,
        block_height INTEGER,
        address_type TEXT,
        PRIMARY KEY (tx_hash, vout)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_utxo_address ON utxos(address)
    ''');

    await db.execute('''
      CREATE INDEX idx_utxo_spendable ON utxos(confirmations)
    ''');

    // Wallet metadata table - stores sync state and settings
    await db.execute('''
      CREATE TABLE wallet_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('Upgrading database from version $oldVersion to $newVersion');

    // Version 1 -> 2: Add address_type column to utxos table
    if (oldVersion < 2) {
      await db.execute('''
        ALTER TABLE utxos ADD COLUMN address_type TEXT
      ''');

      print('Added address_type column to utxos table');

      // Note: Existing UTXOs will have NULL address_type
      // The UTXO model's fromMap() will auto-detect the type from address
      // when loading these rows
    }

    // Version 2 -> 3: address_cache table removed (no longer needed for simple testing)
    // Addresses are now derived on-demand from HD wallet
  }

  // ==================== Block Header Operations ====================

  /// Insert a block header
  Future<void> insertBlockHeader(BlockHeader header) async {
    final db = await database;
    await db.insert(
      'block_headers',
      header.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Insert multiple block headers in a transaction
  Future<void> insertBlockHeaders(List<BlockHeader> headers) async {
    final db = await database;
    final batch = db.batch();

    for (final header in headers) {
      batch.insert(
        'block_headers',
        header.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  /// Get block header by hash
  Future<BlockHeader?> getBlockHeader(String hash) async {
    final db = await database;
    final results = await db.query(
      'block_headers',
      where: 'hash = ?',
      whereArgs: [hash],
    );

    if (results.isEmpty) return null;
    return BlockHeader.fromMap(results.first);
  }

  /// Get block header by height
  Future<BlockHeader?> getBlockHeaderByHeight(int height) async {
    final db = await database;
    final results = await db.query(
      'block_headers',
      where: 'height = ?',
      whereArgs: [height],
    );

    if (results.isEmpty) return null;
    return BlockHeader.fromMap(results.first);
  }

  /// Get block header by hash
  Future<BlockHeader?> getBlockHeaderByHash(String blockHash) async {
    final db = await database;
    final results = await db.query(
      'block_headers',
      where: 'hash = ?',
      whereArgs: [blockHash.toLowerCase()],
    );

    if (results.isEmpty) return null;
    return BlockHeader.fromMap(results.first);
  }

  /// Get the latest (highest) block header
  Future<BlockHeader?> getLatestBlockHeader() async {
    final db = await database;
    final results = await db.query(
      'block_headers',
      orderBy: 'height DESC',
      limit: 1,
    );

    if (results.isEmpty) return null;
    return BlockHeader.fromMap(results.first);
  }

  /// Get block headers in a range
  Future<List<BlockHeader>> getBlockHeadersInRange(
      int startHeight, int endHeight) async {
    final db = await database;
    final results = await db.query(
      'block_headers',
      where: 'height >= ? AND height <= ?',
      whereArgs: [startHeight, endHeight],
      orderBy: 'height ASC',
    );

    return results.map((map) => BlockHeader.fromMap(map)).toList();
  }

  /// Get total number of block headers
  Future<int> getBlockHeaderCount() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as count FROM block_headers');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Delete block headers from a certain height (for reorg handling)
  Future<void> deleteBlockHeadersFromHeight(int height) async {
    final db = await database;
    await db.delete(
      'block_headers',
      where: 'height >= ?',
      whereArgs: [height],
    );
  }

  // ==================== UTXO Operations ====================

  /// Insert a UTXO
  Future<void> insertUTXO(UTXO utxo) async {
    final db = await database;
    await db.insert(
      'utxos',
      utxo.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all UTXOs
  Future<List<UTXO>> getAllUTXOs() async {
    final db = await database;
    final results = await db.query('utxos');
    return results.map((map) => UTXO.fromMap(map)).toList();
  }

  /// Get UTXOs for a specific address
  Future<List<UTXO>> getUTXOsByAddress(String address) async {
    final db = await database;
    final results = await db.query(
      'utxos',
      where: 'address = ?',
      whereArgs: [address],
    );
    return results.map((map) => UTXO.fromMap(map)).toList();
  }

  /// Get spendable UTXOs (confirmed)
  Future<List<UTXO>> getSpendableUTXOs() async {
    final db = await database;
    final results = await db.query(
      'utxos',
      where: 'confirmations >= ?',
      whereArgs: [AppConstants.minConfirmations],
    );
    return results.map((map) => UTXO.fromMap(map)).toList();
  }

  /// Get unconfirmed change UTXOs (change address and unconfirmed)
  Future<List<UTXO>> getUnconfirmedChangeUTXOs() async {
    final db = await database;
    final results = await db.query(
      'utxos',
      where: 'is_change = ? AND (confirmations IS NULL OR confirmations < ?)',
      whereArgs: [1, AppConstants.minConfirmations],
    );
    return results.map((map) => UTXO.fromMap(map)).toList();
  }

  /// Calculate total unconfirmed change amount
  Future<BigInt> getUnconfirmedChangeAmount() async {
    try {
      final unconfirmedChangeUTXOs = await getUnconfirmedChangeUTXOs();
      final total = unconfirmedChangeUTXOs.fold<BigInt>(
        BigInt.zero,
        (sum, utxo) => sum + utxo.value,
      );

      print('[DB] Unconfirmed change UTXOs: ${unconfirmedChangeUTXOs.length}');
      if (unconfirmedChangeUTXOs.isNotEmpty) {
        for (final utxo in unconfirmedChangeUTXOs) {
          print(
              '   - ${utxo.txHash.substring(0, 8)}:${utxo.vout} = ${utxo.value} sats (confirmations: ${utxo.confirmations})');
        }
      }
      print('   Total unconfirmed change: $total sats');

      return total;
    } catch (e) {
      print('[DB] Error calculating unconfirmed change: $e');
      return BigInt.zero;
    }
  }

  /// Get a specific UTXO by transaction hash and vout
  Future<UTXO?> getUTXO(String txHash, int vout) async {
    final db = await database;
    final results = await db.query(
      'utxos',
      where: 'tx_hash = ? AND vout = ?',
      whereArgs: [txHash, vout],
    );

    if (results.isEmpty) {
      return null;
    }

    return UTXO.fromMap(results.first);
  }

  /// Delete a UTXO (when spent)
  Future<void> deleteUTXO(String txHash, int vout) async {
    final db = await database;
    await db.delete(
      'utxos',
      where: 'tx_hash = ? AND vout = ?',
      whereArgs: [txHash, vout],
    );
  }

  /// Update UTXO confirmations
  Future<void> updateUTXOConfirmations(
      String txHash, int vout, int confirmations) async {
    final db = await database;
    await db.update(
      'utxos',
      {'confirmations': confirmations},
      where: 'tx_hash = ? AND vout = ?',
      whereArgs: [txHash, vout],
    );
  }

  /// Calculate total balance
  Future<BigInt> getTotalBalance() async {
    final utxos = await getAllUTXOs();
    return utxos.fold<BigInt>(BigInt.zero, (sum, utxo) => sum + utxo.value);
  }

  /// Calculate confirmed balance
  Future<BigInt> getConfirmedBalance() async {
    final utxos = await getSpendableUTXOs();
    return utxos.fold<BigInt>(BigInt.zero, (sum, utxo) => sum + utxo.value);
  }

  // ==================== Wallet Metadata Operations ====================

  /// Set metadata value
  Future<void> setMetadata(String key, String value) async {
    final db = await database;
    await db.insert(
      'wallet_metadata',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get metadata value
  Future<String?> getMetadata(String key) async {
    final db = await database;
    final results = await db.query(
      'wallet_metadata',
      where: 'key = ?',
      whereArgs: [key],
    );

    if (results.isEmpty) return null;
    return results.first['value'] as String;
  }

  /// Get last synced block height
  Future<int> getLastSyncedHeight() async {
    final value = await getMetadata('last_synced_height');
    return value != null ? int.parse(value) : 0;
  }

  /// Set last synced block height
  Future<void> setLastSyncedHeight(int height) async {
    await setMetadata('last_synced_height', height.toString());
  }

  // ==================== Utility Operations ====================

  /// Clear all data (for testing or wallet reset)
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('block_headers');
    await db.delete('wallet_transactions');
    await db.delete('utxos');
    await db.delete('wallet_metadata');
  }

  /// Close database connection
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
