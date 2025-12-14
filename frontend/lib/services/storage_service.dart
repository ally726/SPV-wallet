import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/constants.dart';
import 'dart:convert';

/// Secure storage service for sensitive wallet data
/// Uses platform-specific secure storage (Keychain on iOS, Keystore on Android)
class StorageService {
  static final StorageService instance = StorageService._internal();

  late final FlutterSecureStorage _secureStorage;

  StorageService._internal() {
    // Configure secure storage with encryption options
    _secureStorage = const FlutterSecureStorage(
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true,
      ),
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock,
      ),
    );
  }

  // ==================== Mnemonic Operations ====================

  /// Save mnemonic phrase securely
  /// This is the most sensitive data - loss means loss of all funds
  Future<void> saveMnemonic(String mnemonic) async {
    try {
      await _secureStorage.write(
        key: AppConstants.storageKeyMnemonic,
        value: mnemonic,
      );
    } catch (e) {
      throw StorageException('Failed to save mnemonic: $e');
    }
  }

  /// Retrieve mnemonic phrase
  Future<String?> getMnemonic() async {
    try {
      return await _secureStorage.read(
        key: AppConstants.storageKeyMnemonic,
      );
    } catch (e) {
      throw StorageException('Failed to read mnemonic: $e');
    }
  }

  /// Check if mnemonic exists
  Future<bool> hasMnemonic() async {
    final mnemonic = await getMnemonic();
    return mnemonic != null && mnemonic.isNotEmpty;
  }

  /// Delete mnemonic (use with extreme caution!)
  Future<void> deleteMnemonic() async {
    try {
      await _secureStorage.delete(
        key: AppConstants.storageKeyMnemonic,
      );
    } catch (e) {
      throw StorageException('Failed to delete mnemonic: $e');
    }
  }

  // ==================== Seed Operations ====================

  /// Save seed (derived from mnemonic)
  /// Storing seed allows faster wallet initialization
  Future<void> saveSeed(String seedHex) async {
    try {
      await _secureStorage.write(
        key: AppConstants.storageKeySeed,
        value: seedHex,
      );
    } catch (e) {
      throw StorageException('Failed to save seed: $e');
    }
  }

  /// Retrieve seed
  Future<String?> getSeed() async {
    try {
      return await _secureStorage.read(
        key: AppConstants.storageKeySeed,
      );
    } catch (e) {
      throw StorageException('Failed to read seed: $e');
    }
  }

  /// Check if seed exists
  Future<bool> hasSeed() async {
    final seed = await getSeed();
    return seed != null && seed.isNotEmpty;
  }

  /// Delete seed
  Future<void> deleteSeed() async {
    try {
      await _secureStorage.delete(
        key: AppConstants.storageKeySeed,
      );
    } catch (e) {
      throw StorageException('Failed to delete seed: $e');
    }
  }

  // ==================== General Key-Value Storage ====================

  /// Save a secure value
  Future<void> saveValue(String key, String value) async {
    try {
      await _secureStorage.write(key: key, value: value);
    } catch (e) {
      throw StorageException('Failed to save value for key $key: $e');
    }
  }

  /// Read a secure value
  Future<String?> getValue(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (e) {
      throw StorageException('Failed to read value for key $key: $e');
    }
  }

  /// Delete a secure value
  Future<void> deleteValue(String key) async {
    try {
      await _secureStorage.delete(key: key);
    } catch (e) {
      throw StorageException('Failed to delete value for key $key: $e');
    }
  }

  /// Check if a key exists
  Future<bool> hasValue(String key) async {
    final value = await getValue(key);
    return value != null;
  }

  // ==================== Wallet Settings ====================

  /// Save wallet creation timestamp
  Future<void> saveWalletCreationTime(DateTime time) async {
    await saveValue('wallet_creation_time', time.toIso8601String());
  }

  /// Get wallet creation timestamp
  Future<DateTime?> getWalletCreationTime() async {
    final timeStr = await getValue('wallet_creation_time');
    if (timeStr == null) return null;
    return DateTime.parse(timeStr);
  }

  /// Save last used derivation index for external chain
  Future<void> saveLastExternalIndex(int index) async {
    await saveValue('last_external_index', index.toString());
  }

  /// Get last used derivation index for external chain
  Future<int> getLastExternalIndex() async {
    final indexStr = await getValue('last_external_index');
    return indexStr != null ? int.parse(indexStr) : 0;
  }

  /// Save last used derivation index for internal chain (change)
  Future<void> saveLastInternalIndex(int index) async {
    await saveValue('last_internal_index', index.toString());
  }

  /// Get last used derivation index for internal chain (change)
  Future<int> getLastInternalIndex() async {
    final indexStr = await getValue('last_internal_index');
    return indexStr != null ? int.parse(indexStr) : 0;
  }

  /// Save last synced block height
  Future<void> saveLastSyncedHeight(int height) async {
    await saveValue('last_synced_height', height.toString());
  }

  /// Get last synced block height
  /// Returns -1 if never synced before (will trigger full scan from genesis)
  Future<int> getLastSyncedHeight() async {
    final heightStr = await getValue('last_synced_height');
    return heightStr != null ? int.parse(heightStr) : -1;
  }

  Future<Set<String>> getSubmittedProofCycleIds() async {
    try {
      final jsonString = await _secureStorage.read(
        key: 'submitted_proof_cycle_ids',
      );
      if (jsonString == null) {
        return <String>{}; // Return empty set
      }
      // Decode stored JSON list
      final List<dynamic> list = jsonDecode(jsonString);
      return list.map((item) => item.toString()).toSet();
    } catch (e) {
      print('[Storage] Failed to get submitted proofs: $e');
      return <String>{};
    }
  }

  /// Save list of Cycle IDs for which Proof has been submitted
  Future<void> saveSubmittedProofCycleIds(Set<String> cycleIds) async {
    try {
      // Convert Set to List and encode as JSON
      final jsonString = jsonEncode(cycleIds.toList());
      await _secureStorage.write(
        key: 'submitted_proof_cycle_ids',
        value: jsonString,
      );
    } catch (e) {
      throw StorageException('Failed to save submitted proofs: $e');
    }
  }
  // ==================== Cleanup Operations ====================

  /// Delete all wallet data (for wallet reset or deletion)
  /// WARNING: This will delete the mnemonic - funds will be permanently lost
  /// unless the user has backed up their mnemonic phrase!
  Future<void> deleteAllWalletData() async {
    try {
      await _secureStorage.deleteAll();
    } catch (e) {
      throw StorageException('Failed to delete all wallet data: $e');
    }
  }

  /// Get all stored keys (for debugging - be careful with sensitive data)
  Future<Map<String, String>> getAllValues() async {
    try {
      return await _secureStorage.readAll();
    } catch (e) {
      throw StorageException('Failed to read all values: $e');
    }
  }

  // ==================== Validation ====================

  /// Check if wallet is initialized
  /// A wallet is considered initialized if it has both mnemonic and seed
  Future<bool> isWalletInitialized() async {
    return await hasMnemonic() && await hasSeed();
  }

  /// Validate storage integrity
  /// Returns true if all critical data is present and valid
  Future<bool> validateStorageIntegrity() async {
    try {
      // Check if mnemonic exists
      final hasMnem = await hasMnemonic();
      if (!hasMnem) return false;

      // Check if seed exists
      final hasSd = await hasSeed();
      if (!hasSd) return false;

      // Get mnemonic and validate it's not empty
      final mnemonic = await getMnemonic();
      if (mnemonic == null || mnemonic.isEmpty) return false;

      // Get seed and validate it's not empty
      final seed = await getSeed();
      if (seed == null || seed.isEmpty) return false;

      return true;
    } catch (e) {
      return false;
    }
  }
}

/// Custom exception for storage operations
class StorageException implements Exception {
  final String message;

  StorageException(this.message);

  @override
  String toString() => 'StorageException: $message';
}
