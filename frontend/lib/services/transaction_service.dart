import 'package:bitcoin_base/bitcoin_base.dart' hide UTXO;
import 'package:blockchain_utils/bech32/segwit_bech32.dart';
import '../models/utxo.dart';
import '../models/wallet_transaction.dart';
import '../database/database_helper.dart';
import '../utils/constants.dart';
import 'api_services.dart' as local_api;
import 'hd_wallet_service.dart';

/// Transaction service for building, signing, and broadcasting Bitcoin transactions
/// Implements Phase 4: Transaction lifecycle (construction, signing, broadcasting)
class TransactionService {
  // ==================== Network Configuration ====================

  /// Get Bitcoin network configuration based on current network type
  static BitcoinNetwork _getBitcoinNetwork() {
    switch (AppConstants.currentNetwork) {
      case NetworkType.mainnet:
        return BitcoinNetwork.mainnet;
      case NetworkType.testnet:
      case NetworkType.regtest:
        // Both testnet and regtest use BitcoinNetwork.testnet
        //  (bcrt1...) need special handling
        return BitcoinNetwork.testnet;
    }
  }

  /// Convert regtest address (bcrt1...) to testnet format (tb1...) for validation
  /// Uses proper Bech32 encoding to maintain checksum validity
  static String _normalizeAddress(String address) {
    if (AppConstants.currentNetwork == NetworkType.regtest &&
        address.startsWith('bcrt1')) {
      try {
        // Decode regtest address (hrp: "bcrt", returns Tuple<witnessVer, witnessProgram>)
        final decoded = SegwitBech32Decoder.decode('bcrt', address);

        // decoded is Tuple<int, List<int>>
        // item1 = witness version, item2 = witness program
        final witnessVer = decoded.item1;
        final witnessProgram = decoded.item2;

        // Re-encode with testnet hrp: "tb"
        final testnetAddress = SegwitBech32Encoder.encode(
          'tb',
          witnessVer,
          witnessProgram,
        );

        return testnetAddress;
      } catch (e) {
        print('[TransactionService] Failed to normalize regtest address: $e');
        // If conversion fails, return original address
        // This might fail validation, but better than crashing
        return address;
      }
    }
    return address;
  }

  // ==================== Address Type Detection ====================

  /// Detect address type from address string
  /// This ensures flexibility - works with any address format automatically
  static AddressType detectAddressType(String address) {
    if (address.startsWith('bc1') ||
        address.startsWith('tb1') ||
        address.startsWith('bcrt1')) {
      return AddressType.segwit;
    } else if (address.startsWith('1') ||
        address.startsWith('m') ||
        address.startsWith('n')) {
      return AddressType.legacy;
    }
    // Default to current default setting
    return AppConstants.defaultAddressType;
  }

  /// Create appropriate BitcoinAddress object based on address string
  /// This automatically adapts to any address type and network
  static dynamic createBitcoinAddress(String address) {
    try {
      final addressType = detectAddressType(address);
      final network = _getBitcoinNetwork();

      // Normalize regtest addresses for validation
      final normalizedAddress = _normalizeAddress(address);
      switch (addressType) {
        case AddressType.legacy:
          return P2pkhAddress.fromAddress(
            address: normalizedAddress,
            network: network,
          );

        case AddressType.segwit:
          return P2wpkhAddress.fromAddress(
            address: normalizedAddress,
            network: network,
          );
      }
    } catch (e) {
      print(' Error: $e');
      rethrow;
    }
  }

  // ==================== Instance Members ====================

  static final TransactionService instance = TransactionService._internal();

  final local_api.ApiService _api = local_api.ApiService.instance;
  final DatabaseHelper _db = DatabaseHelper.instance;
  final HDWalletService _hdWallet = HDWalletService.instance;

  // Address cache: address -> WalletAddress (with private keys)
  final Map<String, WalletAddress> _addressCache = {};

  TransactionService._internal();

  // ==================== Initialization ====================

  /// Initialize address cache for transaction signing
  Future<void> initializeCache() async {
    // Clear any existing cache
    _addressCache.clear();
  }

  /// Clear address cache (call when wallet is deleted)
  void clearCache() {
    _addressCache.clear();
  }

  /// Ensure address is in cache (lazy loading)
  /// This will derive and cache the address if not already cached
  Future<WalletAddress> ensureAddressInCache(
    String address, {
    required int derivationIndex,
    required bool isChange,
  }) async {
    // Check if already cached
    if (_addressCache.containsKey(address)) {
      return _addressCache[address]!;
    }

    // Derive the address
    final walletAddr = isChange
        ? await _hdWallet.deriveChangeAddress(derivationIndex)
        : await _hdWallet.deriveAddress(derivationIndex);

    // Add to cache
    _addressCache[walletAddr.address] = walletAddr;

    return walletAddr;
  }

  // ==================== Transaction Building ====================

  /// Create and sign a transaction
  /// Returns: Signed transaction ready to broadcast
  Future<SignedTransaction> createTransaction({
    required String recipientAddress,
    required BigInt amount,
    int feeRate = AppConstants.defaultFeeRate,
    String? memo,
  }) async {
    try {
      print(' [TransactionService] Creating transaction...');
      print('   Recipient: $recipientAddress');
      print('   Amount: $amount sats');

      // 1. Get available UTXOs
      final availableUTXOs = await _db.getSpendableUTXOs();
      print('   Available UTXOs: ${availableUTXOs.length}');

      if (availableUTXOs.isEmpty) {
        throw TransactionException('No spendable UTXOs available');
      }

      // 2. Select UTXOs to cover amount + estimated fee
      final selectedUTXOs = UTXOSelector.selectUTXOs(
        availableUTXOs: availableUTXOs,
        targetAmount: amount,
        feeRate: feeRate,
      );
      print('   Selected UTXOs: ${selectedUTXOs.length}');

      // 3. Calculate exact fee based on transaction size
      final BigInt fee;
      if (AppConstants.fixedFee != null) {
        // Using fixed fee for testing
        fee = BigInt.from(AppConstants.fixedFee!);
        print('   Using FIXED fee: $fee sats (testing mode)');
      } else {
        // Calculate fee based on estimated transaction size
        final estimatedSize = _estimateTransactionSizeWithUTXOs(
          utxos: selectedUTXOs,
          outputCount: 2, // recipient + change
          hasMemo: memo != null,
        );
        fee = BigInt.from(estimatedSize * feeRate);
        print('   Estimated size: $estimatedSize bytes');
        print('   Calculated fee: $fee sats (@$feeRate sat/vB)');
      }

      // 4. Calculate change amount
      final totalInput = UTXOSelector.calculateTotal(selectedUTXOs);
      final totalOutput = amount + fee;

      if (totalInput < totalOutput) {
        throw TransactionException(
          'Insufficient funds: need $totalOutput sats, have $totalInput sats',
        );
      }

      final changeAmount = totalInput - totalOutput;
      print('   Change amount: $changeAmount sats');

      // 5. Get change address (only if change is above dust threshold)
      WalletAddress? changeAddress;
      final outputs = <BitcoinOutput>[];

      print('   Creating recipient output...');
      // Add recipient output (automatically detects address type and network)
      outputs.add(BitcoinOutput(
        address: createBitcoinAddress(recipientAddress),
        value: amount,
      ));

      // Add change output if above dust threshold (automatically uses default address type)
      if (changeAmount > BigInt.from(AppConstants.dustThreshold)) {
        print('   Creating change output...');
        changeAddress = await _hdWallet.getNextChangeAddress();
        outputs.add(BitcoinOutput(
          address: createBitcoinAddress(changeAddress.address),
          value: changeAmount,
        ));
      }

      // 6. Build and sign transaction
      final signedTx = await _buildAndSignTransaction(
        utxos: selectedUTXOs,
        outputs: outputs,
        memo: memo,
      );

      final rawTx = signedTx.serialize();
      final txId = signedTx.txId();

      return SignedTransaction(
        txId: txId,
        rawTx: rawTx,
        fee: fee,
        inputs: selectedUTXOs,
        recipient: recipientAddress,
        amount: amount,
        changeAmount: changeAmount,
        changeAddress: changeAddress?.address, // Include change address
      );
    } catch (e) {
      throw TransactionException('Failed to create transaction: $e');
    }
  }

  // ==================== Transaction Building Implementation ====================

  /// Build and sign a Bitcoin transaction
  Future<BtcTransaction> _buildAndSignTransaction({
    required List<UTXO> utxos,
    required List<BitcoinOutput> outputs,
    String? memo,
  }) async {
    try {
      // Pre-load all required private keys into cache
      final privateKeys = <String, String>{}; // address -> privateKey

      for (final utxo in utxos) {
        if (!_addressCache.containsKey(utxo.address)) {
          // Load from HD wallet
          final walletAddr = utxo.isChange
              ? await _hdWallet.deriveChangeAddress(utxo.derivationIndex)
              : await _hdWallet.deriveAddress(utxo.derivationIndex);
          _addressCache[utxo.address] = walletAddr;
        }
        privateKeys[utxo.address] = _addressCache[utxo.address]!.privateKey;
      }

      // Convert UTXOs to UtxoWithAddress objects
      final utxoWithAddressList = <UtxoWithAddress>[];

      for (final utxo in utxos) {
        // Get wallet address info (with private key)
        final walletAddr = _addressCache[utxo.address];
        if (walletAddr == null) {
          throw TransactionException(
              'No private key found for address: ${utxo.address}');
        }

        // Automatically detect and create correct address type and network
        final utxoAddress = createBitcoinAddress(utxo.address);

        final utxoWithAddress = UtxoWithAddress(
          utxo: BitcoinUtxo(
            txHash: utxo.txHash,
            value: utxo.value,
            vout: utxo.vout,
            scriptType: utxoAddress.type,
          ),
          ownerDetails: UtxoAddressDetails(
            publicKey: walletAddr.publicKey,
            address: utxoAddress,
          ),
        );

        utxoWithAddressList.add(utxoWithAddress);
      }

      // Calculate total input value
      final totalInput = utxos.fold<BigInt>(
        BigInt.zero,
        (sum, utxo) => sum + utxo.value,
      );

      // Calculate total output value
      final totalOutput = outputs.fold<BigInt>(
        BigInt.zero,
        (sum, output) => sum + output.value,
      );

      // Fee is the difference
      final fee = totalInput - totalOutput;

      // Build transaction using BitcoinTransactionBuilder
      final builder = BitcoinTransactionBuilder(
        outPuts: outputs,
        fee: fee,
        network: _getBitcoinNetwork(),
        utxos: utxoWithAddressList,
        memo: memo,
        enableRBF: false, // Disable RBF
      );

      // Sign transaction
      final transaction = builder.buildTransaction(
        (txDigest, utxo, publicKey, sighash) {
          // Get private key for this input (already cached)
          final utxoAddr = utxos.firstWhere(
            (u) => u.txHash == utxo.utxo.txHash && u.vout == utxo.utxo.vout,
          );

          // Get private key from pre-loaded cache
          final privateKeyHex = privateKeys[utxoAddr.address];
          if (privateKeyHex == null) {
            throw TransactionException(
                'Private key not found for ${utxoAddr.address}');
          }

          final privateKey = ECPrivate.fromHex(privateKeyHex);

          // Sign with ECDSA for SegWit (returns DER-encoded signature with SIGHASH flag)
          return privateKey.signECDSA(txDigest, sighash: sighash);
        },
      );

      return transaction;
    } catch (e) {
      throw TransactionException('Failed to build and sign transaction: $e');
    }
  }

  /// Get private key for a UTXO (with lazy caching)
  Future<String> _getPrivateKeyForUTXO(UTXO utxo) async {
    // Check cache first
    if (_addressCache.containsKey(utxo.address)) {
      return _addressCache[utxo.address]!.privateKey;
    }

    // Cache miss - derive the address based on stored derivation info
    print(
        'Cache miss for address ${utxo.address}, deriving from index ${utxo.derivationIndex}');

    final walletAddr = utxo.isChange
        ? await _hdWallet.deriveChangeAddress(utxo.derivationIndex)
        : await _hdWallet.deriveAddress(utxo.derivationIndex);

    // Add to cache for future use
    _addressCache[walletAddr.address] = walletAddr;

    // Verify address matches
    if (walletAddr.address != utxo.address) {
      throw TransactionException(
          'Derived address mismatch: expected ${utxo.address}, got ${walletAddr.address}');
    }

    return walletAddr.privateKey;
  }

  // ==================== Size Estimation ====================

  /// Estimate transaction size based on actual UTXO types
  /// This automatically adapts to mixed Legacy and SegWit inputs
  // int _estimateTransactionSize({
  //   required int inputCount,
  //   required int outputCount,
  //   bool hasMemo = false,
  // }) {
  //   // Since we don't know the actual UTXO types here, use conservative estimate
  //   // based on current default address type
  //   int size = 10; // Base transaction overhead

  //   if (AppConstants.defaultAddressType == AddressType.legacy) {
  //     // Legacy P2PKH inputs
  //     // Each input: ~148 bytes (outpoint + script + signature)
  //     size += inputCount * 148;
  //   } else {
  //     // SegWit P2WPKH inputs
  //     // Each input: ~68 vbytes (with witness discount)
  //     size += inputCount * 68;
  //   }

  //   // Outputs (similar size for both types)
  //   size += outputCount * 34;

  //   // Add OP_RETURN if memo exists
  //   if (hasMemo) {
  //     size += 43;
  //   }

  //   return size;
  // }

  /// Estimate transaction size with known UTXOs (more accurate)
  /// This version knows the actual address types
  int _estimateTransactionSizeWithUTXOs({
    required List<UTXO> utxos,
    required int outputCount,
    bool hasMemo = false,
  }) {
    int size = 10; // Base transaction overhead

    // Calculate input size based on actual UTXO types
    for (final utxo in utxos) {
      if (utxo.addressType == AddressType.legacy) {
        // Legacy P2PKH input: ~148 bytes
        size += 148;
      } else {
        // SegWit P2WPKH input: ~68 vbytes
        size += 68;
      }
    }

    // Add outputs
    size += outputCount * 34;

    // Add OP_RETURN if memo exists
    if (hasMemo) {
      size += 43;
    }

    return size;
  }

  // ==================== Transaction Broadcasting ====================

  /// Broadcast a signed transaction to the network
  /// @param signedTx: SignedTransaction object
  /// Returns: Transaction ID if successful
  Future<String> broadcastTransaction(SignedTransaction signedTx) async {
    try {
      // Broadcast raw transaction
      final txid = await _api.broadcastTransaction(signedTx.rawTx);

      // Verify txid matches
      if (txid != signedTx.txId) {
        print(
            'Warning: Returned txid ($txid) differs from calculated (${signedTx.txId})');
      }

      // Mark UTXOs as spent (delete inputs)
      for (final utxo in signedTx.inputs) {
        await _db.deleteUTXO(utxo.txHash, utxo.vout);
      }

      // Add change UTXO if exists
      if (signedTx.changeAddress != null &&
          signedTx.changeAmount > BigInt.zero) {
        // Get derivation info for change address
        final derivationInfo =
            await _hdWallet.getAddressDerivationInfo(signedTx.changeAddress!);

        if (derivationInfo != null) {
          // Create change UTXO (vout=1, since change is always the second output)
          final changeUtxo = UTXO(
            txHash: txid,
            vout: 1,
            value: signedTx.changeAmount,
            scriptPubKey: '', // Will be filled when transaction is confirmed
            address: signedTx.changeAddress!,
            derivationIndex: derivationInfo.index,
            isChange: derivationInfo.isChange,
            confirmations: 0, // Unconfirmed
            blockHeight: 0, // Not in block yet
            addressType: derivationInfo.addressType,
          );

          await _db.insertUTXO(changeUtxo);
          print(
              ' Added unconfirmed change UTXO: ${signedTx.changeAmount} sats at ${signedTx.changeAddress}');
        } else {
          print(
              ' Warning: Could not find derivation info for change address ${signedTx.changeAddress}');
        }
      }

      print(' Transaction broadcast successfully: $txid');
      return txid;
    } catch (e) {
      throw TransactionException('Failed to broadcast transaction: $e');
    }
  }

  // ==================== Transaction Parsing ====================

  /// Parse a block's transactions and extract relevant ones
  /// Returns: List of relevant transactions
  Future<List<WalletTransaction>> parseBlockTransactions({
    required Map<String, dynamic> blockData,
    required Set<String> walletAddresses,
  }) async {
    try {
      final transactions = blockData['tx'] as List<dynamic>?;
      if (transactions == null) {
        return [];
      }

      final blockHeight = blockData['height'] as int;
      final blockTime = blockData['time'] as int;

      final walletTransactions = <WalletTransaction>[];

      for (final txData in transactions) {
        final tx = txData as Map<String, dynamic>;

        // Check if transaction involves any wallet addresses
        if (_isRelevantTransaction(tx, walletAddresses)) {
          final walletTx = _parseTransaction(tx, blockHeight, blockTime);
          walletTransactions.add(walletTx);

          // Update UTXOs
          await _updateUTXOsFromTransaction(walletTx, walletAddresses);
        }
      }

      return walletTransactions;
    } catch (e) {
      throw TransactionException('Failed to parse block transactions: $e');
    }
  }

  /// Check if transaction is relevant to wallet
  bool _isRelevantTransaction(
    Map<String, dynamic> tx,
    Set<String> walletAddresses,
  ) {
    // Check outputs
    final vout = tx['vout'] as List<dynamic>?;
    if (vout != null) {
      for (final output in vout) {
        final scriptPubKey = output['scriptPubKey'] as Map<String, dynamic>?;

        // Bitcoin Core can return either 'address' (singular) or 'addresses' (plural)
        // depending on the script type and configuration

        // Try 'addresses' field first (array)
        final addresses = scriptPubKey?['addresses'] as List<dynamic>?;
        if (addresses != null) {
          for (final addr in addresses) {
            if (walletAddresses.contains(addr as String)) {
              print(' [TxService] Found relevant output: $addr');
              return true;
            }
          }
        }

        // Try 'address' field (single string) - common in newer Bitcoin Core versions
        final singleAddress = scriptPubKey?['address'] as String?;
        if (singleAddress != null && walletAddresses.contains(singleAddress)) {
          print(' [TxService] Found relevant output: $singleAddress');
          return true;
        }
      }
    }

    // Check inputs (if we're spending)
    // This requires checking prevout addresses, which may not be available
    // For SPV, we mainly care about outputs we receive

    return false;
  }

  /// Parse transaction data into WalletTransaction
  WalletTransaction _parseTransaction(
    Map<String, dynamic> txData,
    int blockHeight,
    int blockTime,
  ) {
    final txHash = txData['txid'] as String;

    // Parse inputs
    final inputs = <TransactionInput>[];
    final vin = txData['vin'] as List<dynamic>?;
    if (vin != null) {
      for (final input in vin) {
        inputs.add(TransactionInput(
          prevTxHash: input['txid'] as String? ?? '',
          prevVout: input['vout'] as int? ?? 0,
          value: BigInt.zero, // Not available in standard format
          scriptSig: input['scriptSig']?['hex'] as String?,
          witness: (input['txinwitness'] as List<dynamic>?)?.cast<String>(),
        ));
      }
    }

    // Parse outputs
    final outputs = <TransactionOutput>[];
    final vout = txData['vout'] as List<dynamic>?;
    if (vout != null) {
      for (final output in vout) {
        final scriptPubKey = output['scriptPubKey'] as Map<String, dynamic>?;

        // Bitcoin Core can return either 'address' (singular) or 'addresses' (plural)
        String address = '';

        // Try 'addresses' field first (array)
        final addresses = scriptPubKey?['addresses'] as List<dynamic>?;
        if (addresses?.isNotEmpty == true) {
          address = addresses!.first as String;
        } else {
          // Try 'address' field (single string)
          final singleAddress = scriptPubKey?['address'] as String?;
          if (singleAddress != null) {
            address = singleAddress;
          }
        }

        outputs.add(TransactionOutput(
          vout: output['n'] as int,
          address: address,
          value: _btcToSatoshi(output['value'] as num),
          scriptPubKey: scriptPubKey?['hex'] as String? ?? '',
        ));
      }
    }

    print(' [TxService] Parsed transaction: $txHash');
    print('   Inputs: ${inputs.length}, Outputs: ${outputs.length}');
    for (final out in outputs) {
      if (out.address.isNotEmpty) {
        print('   Output ${out.vout}: ${out.address} = ${out.value} sats');
      }
    }

    return WalletTransaction(
      txHash: txHash,
      blockHeight: blockHeight,
      blockTime: blockTime,
      inputs: inputs,
      outputs: outputs,
      fee: BigInt.zero, // Calculate from inputs/outputs if available
      confirmations: 1,
    );
  }

  /// Update UTXOs based on a transaction
  Future<void> _updateUTXOsFromTransaction(
    WalletTransaction tx,
    Set<String> walletAddresses,
  ) async {
    // Add new UTXOs from outputs we received
    for (final output in tx.outputs) {
      if (walletAddresses.contains(output.address)) {
        // Check if this UTXO already exists (to avoid duplicates during re-scan)
        final existingUTXO = await _db.getUTXO(tx.txHash, output.vout);
        if (existingUTXO != null) {
          print(
              ' [TxService] UTXO already exists: ${tx.txHash}:${output.vout}, skipping');
          continue;
        }

        // Quick check: Skip if address type doesn't match our default
        final addressType = detectAddressType(output.address);
        if (addressType != AppConstants.defaultAddressType) {
          print(
              ' [TxService] Address type mismatch: ${output.address} is $addressType, but wallet uses ${AppConstants.defaultAddressType}. Skipping.');
          continue;
        }

        // Get derivation info for this address
        final derivationInfo = await _hdWallet.getAddressDerivationInfo(
          output.address,
          maxSearchIndex: AppConstants.maxAddressSearchIndex,
        );

        if (derivationInfo == null) {
          print(
              ' [TxService] Could not find derivation info for address: ${output.address}');
          continue; // Skip this UTXO if we can't find derivation info
        }

        // This is our UTXO with correct derivation info
        final utxo = UTXO(
          txHash: tx.txHash,
          vout: output.vout,
          value: output.value,
          scriptPubKey: output.scriptPubKey,
          address: output.address,
          derivationIndex: derivationInfo.index,
          isChange: derivationInfo
              .isChange, // Use derivation info, not output.isChange
          confirmations: tx.confirmations,
          blockHeight: tx.blockHeight,
        );

        await _db.insertUTXO(utxo);
        print(
            ' [TxService] Added UTXO: ${output.address} (index: ${derivationInfo.index}, change: ${derivationInfo.isChange})');
      }
    }

    // Remove spent UTXOs from inputs
    for (final input in tx.inputs) {
      await _db.deleteUTXO(input.prevTxHash, input.prevVout);
    }
  }

  // ==================== Utility Methods ====================

  /// Convert BTC to satoshis
  BigInt _btcToSatoshi(num btc) {
    return BigInt.from((btc * 100000000).round());
  }

  /// Convert satoshis to BTC
  double satoshiToBTC(BigInt satoshi) {
    return satoshi.toInt() / 100000000.0;
  }

  /// Get wallet balance
  Future<WalletBalance> getBalance() async {
    final totalBalance = await _db.getTotalBalance();
    final confirmedBalance = await _db.getConfirmedBalance();
    final pendingBalance = totalBalance - confirmedBalance;

    return WalletBalance(
      total: totalBalance,
      confirmed: confirmedBalance,
      pending: pendingBalance,
    );
  }

  /// Get transaction history
  Future<List<WalletTransaction>> getTransactionHistory({
    int limit = 50,
    int offset = 0,
  }) async {
    // This would query the database for stored transactions
    // Placeholder implementation
    return [];
  }
}

/// Represents a signed transaction ready for broadcast
class SignedTransaction {
  final String txId; // Transaction ID
  final String rawTx; // Raw transaction hex
  final BigInt fee; // Transaction fee
  final List<UTXO> inputs; // Input UTXOs
  final String recipient; // Recipient address
  final BigInt amount; // Amount sent
  final BigInt changeAmount; // Change amount
  final String? changeAddress; // Change address (null if no change)

  SignedTransaction({
    required this.txId,
    required this.rawTx,
    required this.fee,
    required this.inputs,
    required this.recipient,
    required this.amount,
    required this.changeAmount,
    this.changeAddress,
  });

  @override
  String toString() {
    return 'SignedTransaction(txId: $txId, amount: $amount sats, fee: $fee sats)';
  }
}

/// Wallet balance information
class WalletBalance {
  final BigInt total; // Total balance (confirmed + pending)
  final BigInt confirmed; // Confirmed balance only
  final BigInt pending; // Pending (unconfirmed) balance

  WalletBalance({
    required this.total,
    required this.confirmed,
    required this.pending,
  });

  @override
  String toString() {
    return 'WalletBalance(total: $total sats, confirmed: $confirmed sats, pending: $pending sats)';
  }
}

/// Custom exception for transaction operations
class TransactionException implements Exception {
  final String message;

  TransactionException(this.message);

  @override
  String toString() => 'TransactionException: $message';
}
