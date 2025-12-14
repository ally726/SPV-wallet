import 'package:flutter/foundation.dart';
import '../services/mnemonic_service.dart';
import '../services/hd_wallet_service.dart';
import '../services/block_header_service.dart';
import '../services/transaction_service.dart';
import '../services/api_services.dart';
import '../services/storage_service.dart';
import '../database/database_helper.dart';
import '../models/utxo.dart';
import '../utils/constants.dart';

/// Central wallet state provider
/// Manages all wallet operations and notifies UI of changes
class WalletProvider with ChangeNotifier {
  final MnemonicService _mnemonicService = MnemonicService.instance;
  final HDWalletService _hdWallet = HDWalletService.instance;
  final BlockHeaderService _headerService = BlockHeaderService.instance;
  final TransactionService _txService = TransactionService.instance;
  final ApiService _apiService = ApiService.instance;
  final DatabaseHelper _db = DatabaseHelper.instance;

  // Wallet state
  bool _isInitialized = false;
  bool _isSyncing = false;
  String? _currentAddress;
  BigInt _balance = BigInt.zero;
  BigInt _confirmedBalance = BigInt.zero;
  BigInt _pendingChangeAmount = BigInt.zero;
  int _syncHeight = 0;
  int _lastScannedHeight =
      -1; // Track last scanned height to avoid redundant scans
  List<String> _addresses = [];

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isSyncing => _isSyncing;
  String? get currentAddress => _currentAddress;
  BigInt get balance => _balance;
  BigInt get confirmedBalance => _confirmedBalance;
  BigInt get pendingChangeAmount => _pendingChangeAmount;
  int get syncHeight => _syncHeight;
  List<String> get addresses => _addresses;

  // Service getters
  DatabaseHelper get databaseHelper => _db;
  HDWalletService get hdWalletService => _hdWallet;

  // ==================== Wallet Initialization ====================

  /// Initialize existing wallet
  Future<void> initializeWallet() async {
    try {
      debugPrint('[WalletProvider] Initializing wallet...');

      // Initialize HD wallet
      await _hdWallet.initialize();

      // Initialize block header service
      await _headerService.initialize();

      // Initialize transaction service cache (lazy loading mode)
      await _txService.initializeCache();

      // Get current receiving address
      final addr = await _hdWallet.getCurrentReceivingAddress();
      _currentAddress = addr.address;
      _addresses = [addr.address]; // Only store current address for UI

      // Load last synced height from storage
      final storage = StorageService.instance;
      _lastScannedHeight = await storage.getLastSyncedHeight();
      debugPrint(
          '[WalletProvider] Loaded last synced height: $_lastScannedHeight');

      // Update balance
      await _updateBalance();

      // Get sync status
      _syncHeight = _headerService.currentHeight;

      _isInitialized = true;
      notifyListeners();

      debugPrint(
          ' [WalletProvider] Wallet initialized with address: $_currentAddress');
    } catch (e) {
      debugPrint(' [WalletProvider] Failed to initialize wallet: $e');
      rethrow;
    }
  }

  /// Create new wallet with mnemonic
  Future<String> createWallet({int wordCount = 12}) async {
    try {
      debugPrint('Creating new wallet...');

      // Generate and store mnemonic
      final mnemonic = await _mnemonicService.createNewWallet(
        wordCount: wordCount,
      );

      // Initialize wallet
      await initializeWallet();

      debugPrint('Wallet created successfully');
      return mnemonic;
    } catch (e) {
      debugPrint('Failed to create wallet: $e');
      rethrow;
    }
  }

  /// Import wallet from mnemonic
  /// Note: After importing, you MUST call startSync() to discover addresses
  /// The first sync after import will use restoration mode (gap limit scanning)
  Future<void> importWallet(String mnemonic) async {
    try {
      debugPrint('Importing wallet from mnemonic...');

      // Import and store mnemonic
      await _mnemonicService.importWallet(mnemonic);

      // Initialize wallet (this builds initial address map)
      await initializeWallet();

      debugPrint('Wallet imported successfully');
      debugPrint(
          'IMPORTANT: Call startSync(isRestoration: true) to discover addresses');
    } catch (e) {
      debugPrint('Failed to import wallet: $e');
      rethrow;
    }
  }

  // ==================== Address Management ====================

  // Note: _loadAddresses() removed - we only show current address in UI
  // Previous implementation loaded 5 addresses which caused unnecessary derivation

  /// Get new receiving address
  Future<String> getNewAddress() async {
    try {
      final addr = await _hdWallet.getNextReceivingAddress();
      _currentAddress = addr.address;
      _addresses = [addr.address]; // Update UI with new current address only

      notifyListeners();
      debugPrint(' [WalletProvider] New address generated: $addr.address');
      return addr.address;
    } catch (e) {
      debugPrint(' [WalletProvider] Failed to get new address: $e');
      rethrow;
    }
  }

  // ==================== Balance & UTXOs ====================

  /// Update wallet balance
  Future<void> _updateBalance() async {
    try {
      final balanceInfo = await _txService.getBalance();
      _balance = balanceInfo.total;
      _confirmedBalance = balanceInfo.confirmed;

      _pendingChangeAmount = await _db.getUnconfirmedChangeAmount();

      debugPrint('Balance updated:');
      debugPrint('   Total: $_balance sats');
      debugPrint('   Confirmed: $_confirmedBalance sats');
      debugPrint('   Pending change: $_pendingChangeAmount sats');

      notifyListeners();
    } catch (e) {
      debugPrint('Failed to update balance: $e');
      debugPrint('   Stack trace: ${StackTrace.current}');
    }
  }

  /// Get all UTXOs
  Future<List<UTXO>> getUTXOs() async {
    return await _db.getAllUTXOs();
  }

  /// Update last_used_index if discovered address has higher index
  /// This ensures subsequent scans cover all discovered addresses
  Future<void> _updateLastUsedIndex(int discoveredIndex, bool isChange) async {
    final storage = StorageService.instance;

    final currentIndex = isChange
        ? await storage.getLastInternalIndex()
        : await storage.getLastExternalIndex();

    // Only update if discovered index is higher
    if (discoveredIndex > currentIndex) {
      if (isChange) {
        await storage.saveLastInternalIndex(discoveredIndex);
        debugPrint(
            '   Updated last_internal_index: $currentIndex → $discoveredIndex');
      } else {
        await storage.saveLastExternalIndex(discoveredIndex);
        debugPrint(
            '   Updated last_external_index: $currentIndex → $discoveredIndex');
      }
    }
  }

  // ==================== Synchronization ====================

  /// Start SPV synchronization
  ///
  /// @param isRestoration Set to true when restoring wallet from mnemonic
  ///                      This will use gap limit scanning to discover all addresses
  ///                      Default false for normal operations (scans only used addresses)
  Future<void> startSync({bool isRestoration = false}) async {
    if (_isSyncing) {
      debugPrint('Sync already in progress');
      return;
    }

    _isSyncing = true;
    notifyListeners();

    try {
      if (isRestoration) {
        debugPrint(
            'Starting header sync (RESTORATION MODE - using gap limit)...');
      } else {
        debugPrint(
            'Starting header sync (NORMAL MODE - scanning used addresses)...');
      }

      // Set up progress callback
      _headerService.onSyncProgress = (current, target) {
        _syncHeight = current;
        notifyListeners();
      };

      // Start syncing headers
      await _headerService.startSync();

      // Update sync height to final height after sync completes
      _syncHeight = _headerService.currentHeight;
      notifyListeners(); // Notify UI of final height

      debugPrint('Header sync complete at height $_syncHeight');

      // Only scan if height has changed since last scan
      if (_syncHeight > _lastScannedHeight) {
        debugPrint(
            'Scanning for transactions (last scanned: $_lastScannedHeight, current: $_syncHeight)...');

        // Scan for wallet transactions
        // Pass isRestoration flag to determine scanning strategy
        await _scanWalletTransactions(isRestoration: isRestoration);

        // Update last scanned height (both in memory and storage)
        _lastScannedHeight = _syncHeight;
        final storage = StorageService.instance;
        await storage.saveLastSyncedHeight(_syncHeight);
        debugPrint('[WalletProvider] Saved last synced height: $_syncHeight');

        // Update balance after scan
        await _updateBalance();

        debugPrint('Transaction scan completed');

        // Check for unconfirmed change
        if (_pendingChangeAmount > BigInt.zero) {
          debugPrint('Still have ${_pendingChangeAmount} sats pending change');
        } else {
          debugPrint('All changes are confirmed');
        }
      } else {
        debugPrint(
            'No new blocks to scan (current height: $_syncHeight, last scanned: $_lastScannedHeight)');
      }

      debugPrint('Sync completed successfully');
    } catch (e) {
      debugPrint('Sync failed: $e');
      rethrow;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Scan blockchain for wallet transactions
  /// Backend handles all SPV verification (filters, block downloads, parsing)
  /// Frontend only sends addresses and receives UTXO results
  Future<void> _scanWalletTransactions({bool isRestoration = false}) async {
    await _scanUTXOs(isRestoration: isRestoration);
  }

  /// Scan for UTXOs by querying backend with wallet addresses
  ///
  /// Architecture: Backend-Centric SPV
  /// - Frontend: Only sends addresses and receives UTXO results
  /// - Backend: Handles all SPV logic (BIP158 filters, block parsing, verification)
  ///
  /// Benefits for lab/testing:
  /// - Simplified client code (no complex filter matching)
  /// - Faster performance (backend has better resources)
  /// - Easier to maintain and debug
  Future<void> _scanUTXOs({bool isRestoration = false}) async {
    try {
      final walletAddresses = await _getAllWalletAddresses(
        isRestoration: isRestoration,
      );

      debugPrint(
          '[Backend Scan] Scanning for UTXOs (last scanned: $_lastScannedHeight, current: $_syncHeight)...');

      // Determine scan range based on mode:
      // 1. Wallet restoration: scan from genesis (0) to discover all historical transactions
      // 2. Normal/incremental sync: only scan new blocks since last scan
      int startHeight;
      if (isRestoration) {
        startHeight = 0; // Full scan from genesis for wallet restoration
        debugPrint('   Mode: RESTORATION - scanning from genesis block');
      } else {
        // Incremental scan: only scan blocks we haven't seen yet
        if (_lastScannedHeight < 0) {
          // First time sync - start from genesis
          startHeight = 0;
          debugPrint('   Mode: FIRST SYNC - scanning from genesis block');
        } else {
          // Subsequent syncs - only scan new blocks
          startHeight = _lastScannedHeight + 1;
          debugPrint(
              '   Mode: INCREMENTAL - scanning only new blocks from $_lastScannedHeight + 1');
        }
      }

      int endHeight = _syncHeight;

      if (startHeight > endHeight) {
        debugPrint('No new blocks to scan');
        return;
      }

      debugPrint(
          'Scanning blocks $startHeight to $endHeight (${endHeight - startHeight + 1} blocks) for ${walletAddresses.length} addresses...');

      const batchSize = 500; // 500 blocks per batch

      // Scan in batches
      for (int batchStart = startHeight;
          batchStart <= endHeight;
          batchStart += batchSize) {
        int batchEnd = batchStart + batchSize - 1;
        if (batchEnd > endHeight) batchEnd = endHeight;

        debugPrint('Scanning batch: blocks $batchStart to $batchEnd...');

        try {
          final scanResult = await _apiService.scanUTXOs(
            addresses: walletAddresses,
            startHeight: batchStart,
            endHeight: batchEnd,
          );

          final utxos = scanResult['utxos'] as List<dynamic>;
          debugPrint('Found ${utxos.length} UTXOs in this batch');

          // Process each UTXO
          for (final utxoData in utxos) {
            try {
              final address = utxoData['address'] as String;
              final derivationInfo =
                  await _hdWallet.getAddressDerivationInfo(address);

              if (derivationInfo != null) {
                final utxo = UTXO(
                  txHash: utxoData['txid'] as String,
                  vout: utxoData['vout'] as int,
                  value: BigInt.from(utxoData['satoshis'] as int),
                  address: address,
                  scriptPubKey: utxoData['script_pubkey'] as String,
                  derivationIndex: derivationInfo.index,
                  isChange: derivationInfo.isChange,
                  confirmations: utxoData['confirmations'] as int,
                );

                // Check if UTXO already exists
                final existing = await _db.getUTXO(utxo.txHash, utxo.vout);
                if (existing == null) {
                  // New UTXO - insert
                  await _db.insertUTXO(utxo);
                  debugPrint(
                      '   New UTXO: ${utxo.value} sats (${utxo.confirmations} confirmations)');

                  // Update last_used_index if this address has a higher index
                  await _updateLastUsedIndex(
                    derivationInfo.index,
                    derivationInfo.isChange,
                  );
                } else {
                  // Existing UTXO - only update confirmations if not yet fully confirmed
                  // Once a UTXO reaches minConfirmations, we don't need to track further
                  final oldConfirmations = existing.confirmations ?? 0;

                  // Skip update if already fully confirmed (optimization)
                  if (oldConfirmations >= AppConstants.minConfirmations) {
                    continue; // No need to update, already confirmed enough
                  }

                  // Update confirmations for unconfirmed or partially confirmed UTXOs
                  final newConfirmations = utxo.confirmations ?? 0;

                  if (oldConfirmations != newConfirmations) {
                    await _db.updateUTXOConfirmations(
                      utxo.txHash,
                      utxo.vout,
                      newConfirmations,
                    );
                    debugPrint(
                        '   Updated UTXO confirmations: ${utxo.txHash}:${utxo.vout} -> $newConfirmations confirmations');

                    // If UTXO reaches minimum confirmations threshold, log it
                    if (oldConfirmations < AppConstants.minConfirmations &&
                        newConfirmations >= AppConstants.minConfirmations) {
                      debugPrint(
                          '   ✅ UTXO fully confirmed: ${utxo.value} sats${existing.isChange ? " (change)" : ""}');
                    }
                  }
                }
              }
            } catch (e) {
              debugPrint('   Error processing UTXO: $e');
            }
          }
        } catch (e) {
          debugPrint('Error scanning batch $batchStart-$batchEnd: $e');
        }
      }

      debugPrint('Direct UTXO scan complete');

      // Update confirmations for existing UTXOs (for incremental scans)
      if (!isRestoration) {
        await _updateExistingUTXOConfirmations();
      }
    } catch (e) {
      debugPrint('Failed direct UTXO scan: $e');
      rethrow;
    }
  }

  /// Update confirmations for all existing UTXOs based on current sync height
  /// This is needed for incremental scans where backend only returns new UTXOs
  Future<void> _updateExistingUTXOConfirmations() async {
    try {
      final allUTXOs = await _db.getAllUTXOs();

      if (allUTXOs.isEmpty) {
        return;
      }

      debugPrint(
          'Updating confirmations for ${allUTXOs.length} existing UTXOs...');
      int updated = 0;

      for (final utxo in allUTXOs) {
        // Skip if we don't have block height information
        if (utxo.blockHeight == null) continue;

        // Calculate confirmations from block height
        final calculatedConfirmations = _syncHeight - utxo.blockHeight! + 1;
        final oldConfirmations = utxo.confirmations ?? 0;

        // Skip if already at or above minimum confirmations (optimization)
        if (oldConfirmations >= AppConstants.minConfirmations) {
          continue;
        }

        // Update if confirmations changed
        if (oldConfirmations != calculatedConfirmations) {
          await _db.updateUTXOConfirmations(
            utxo.txHash,
            utxo.vout,
            calculatedConfirmations,
          );
          updated++;

          // Log when UTXO reaches minimum confirmations
          if (oldConfirmations < AppConstants.minConfirmations &&
              calculatedConfirmations >= AppConstants.minConfirmations) {
            debugPrint(
                '   ✅ UTXO fully confirmed: ${utxo.value} sats${utxo.isChange ? " (change)" : ""}');
          }
        }
      }

      if (updated > 0) {
        debugPrint('Updated $updated UTXO confirmations');
      }
    } catch (e) {
      debugPrint('Error updating UTXO confirmations: $e');
    }
  }

  /// Get all wallet addresses (for scanning)
  ///
  /// Strategy depends on context:
  /// 1. Normal operations: scan only used addresses + small buffer
  /// 2. Wallet restoration: use gap limit to discover all addresses
  Future<List<String>> _getAllWalletAddresses({
    bool isRestoration = false,
  }) async {
    if (isRestoration) {
      // Wallet restoration: use gap limit to discover all previously used addresses
      return await _getAddressesForRestoration();
    } else {
      // Normal operations: only scan used addresses + small buffer
      return await _getUsedAddressesWithBuffer();
    }
  }

  /// Get addresses for normal scanning (used addresses + buffer)
  /// This minimizes unnecessary scanning for wallets in regular use
  Future<List<String>> _getUsedAddressesWithBuffer() async {
    final addresses = <String>[];
    final storage = StorageService.instance;

    // Get last used indices from storage
    final lastExternalIndex = await storage.getLastExternalIndex();
    final lastInternalIndex = await storage.getLastInternalIndex();

    // Calculate scan range with buffer
    final externalMaxIndex = lastExternalIndex + AppConstants.normalScanBuffer;
    final internalMaxIndex = lastInternalIndex + AppConstants.normalScanBuffer;

    debugPrint(
        '[Normal Scan] External: 0-$externalMaxIndex, Internal: 0-$internalMaxIndex');

    // Generate external (receiving) addresses
    for (int i = 0; i <= externalMaxIndex; i++) {
      final addr = await _hdWallet.deriveAddress(i);
      addresses.add(addr.address);
    }

    // Generate internal (change) addresses
    for (int i = 0; i <= internalMaxIndex; i++) {
      final addr = await _hdWallet.deriveChangeAddress(i);
      addresses.add(addr.address);
    }

    debugPrint('[Normal Scan] Total addresses to scan: ${addresses.length}');

    return addresses;
  }

  /// Get addresses for wallet restoration using gap limit
  /// This scans a larger range to discover all previously used addresses
  Future<List<String>> _getAddressesForRestoration() async {
    final addresses = <String>[];

    debugPrint('[Restoration Scan] Using gap limit to discover addresses...');

    // Use gap limit for wallet restoration
    final externalAddrs = await _hdWallet.generateAddressesWithGapLimit(
      isChange: false,
      gapLimit: AppConstants.walletRestorationGapLimit,
    );

    final changeAddrs = await _hdWallet.generateAddressesWithGapLimit(
      isChange: true,
      gapLimit: AppConstants.walletRestorationGapLimit,
    );

    addresses.addAll(externalAddrs.map((a) => a.address));
    addresses.addAll(changeAddrs.map((a) => a.address));

    debugPrint(
        '[Restoration Scan] Total addresses to scan: ${addresses.length}');

    return addresses;
  }

  // ==================== Transactions ====================

  /// Send transaction
  Future<String> sendTransaction({
    required String recipientAddress,
    required BigInt amount,
    int feeRate = 5,
  }) async {
    try {
      debugPrint('Creating transaction...');

      // Create and sign transaction
      final signedTx = await _txService.createTransaction(
        recipientAddress: recipientAddress,
        amount: amount,
        feeRate: feeRate,
      );

      debugPrint('Transaction created: ${signedTx.txId}');
      debugPrint('Fee: ${signedTx.fee} sats');
      debugPrint('Change amount: ${signedTx.changeAmount} sats');

      // Broadcast transaction
      final txid = await _txService.broadcastTransaction(signedTx);

      debugPrint('Transaction broadcast: $txid');

      // Update balance
      await _updateBalance();

      notifyListeners();
      return txid;
    } catch (e) {
      debugPrint('Failed to send transaction: $e');
      rethrow;
    }
  }

  // ==================== Utilities ====================

  /// Convert satoshis to BTC string
  String satoshiToBTC(BigInt satoshi) {
    final btc = satoshi.toDouble() / 100000000.0;
    return btc.toStringAsFixed(8);
  }

  /// Convert BTC string to satoshis
  BigInt btcToSatoshi(String btc) {
    final amount = double.parse(btc);
    return BigInt.from((amount * 100000000).round());
  }

  /// Check API health
  Future<bool> checkAPIHealth() async {
    return await _apiService.checkHealth();
  }

  /// Get sync statistics
  Future<String> getSyncStatistics() async {
    final stats = await _headerService.getSyncStatistics();
    return stats.toString();
  }
}
