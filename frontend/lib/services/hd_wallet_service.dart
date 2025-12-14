import 'package:blockchain_utils/bip/bip/bip44/bip44.dart';
import 'package:blockchain_utils/bip/bip/conf/bip44/bip44_coins.dart';
import 'package:blockchain_utils/utils/binary/utils.dart';
import 'package:blockchain_utils/crypto/quick_crypto.dart';
import 'package:blockchain_utils/bech32/segwit_bech32.dart';
import 'package:bitcoin_base/bitcoin_base.dart';
import 'mnemonic_service.dart';
import 'storage_service.dart';
import '../utils/constants.dart';

class HDWalletService {
  static final HDWalletService instance = HDWalletService._internal();
  final MnemonicService _mnemonicService = MnemonicService.instance;
  final StorageService _storage = StorageService.instance;

  // Cached to avoid repeated derivation
  Bip44? _cachedBip44;

  HDWalletService._internal();

  // ==================== Master Key & Account Setup ====================

  /// Initialize HD wallet from stored seed
  /// Must be called before any address derivation
  Future<void> initialize() async {
    try {
      final seed = await _mnemonicService.getStoredSeed();
      if (seed == null) {
        throw HDWalletException(
            'No seed found. Create or import wallet first.');
      }

      // Convert seed from hex to bytes
      final seedBytes = BytesUtils.fromHexString(seed);

      // Create BIP44 context for Bitcoin
      // Using BIP84 path: m/84'/0'/0' (Native SegWit)
      _cachedBip44 = Bip44.fromSeed(
        seedBytes,
        Bip44Coins.bitcoinTestnet, // Use testnet for regtest
      );
    } catch (e) {
      throw HDWalletException('Failed to initialize HD wallet: $e');
    }
  }

  /// Get BIP44 context (initialize if needed)
  Future<Bip44> _getBip44() async {
    if (_cachedBip44 == null) {
      await initialize();
    }
    return _cachedBip44!;
  }

  /// Clear cached keys (call when wallet is deleted)
  Future<void> clearCache() async {
    _cachedBip44 = null;
  }

  // ==================== Address Derivation ====================

  /// Derive address at specific index on external chain (receiving addresses)
  Future<WalletAddress> deriveAddress(
    int index, {
    AddressType? addressType,
  }) async {
    return _deriveAddressAtPath(
      index: index,
      isChange: false,
      addressType: addressType ?? AppConstants.defaultAddressType,
    );
  }

  /// Derive change address at specific index on internal chain
  Future<WalletAddress> deriveChangeAddress(
    int index, {
    AddressType? addressType,
  }) async {
    return _deriveAddressAtPath(
      index: index,
      isChange: true,
      addressType: addressType ?? AppConstants.defaultAddressType,
    );
  }

  /// Internal method to derive address at specific path
  Future<WalletAddress> _deriveAddressAtPath({
    required int index,
    required bool isChange,
    required AddressType addressType,
  }) async {
    try {
      final bip44 = await _getBip44();
      final account = bip44.purpose.coin.account(0);

      final chainType =
          isChange ? Bip44Changes.chainInt : Bip44Changes.chainExt;
      final chain = account.change(chainType);
      final addressKey = chain.addressIndex(index);

      final publicKeyHex = BytesUtils.toHexString(
        addressKey.publicKey.compressed,
      );

      final privateKeyHex = BytesUtils.toHexString(
        addressKey.privateKey.raw,
      );

      final ecPublic = ECPublic.fromHex(publicKeyHex);
      final bitcoinNetwork = _getBitcoinNetwork();

      // Generate address based on address type
      String addressStr;
      switch (addressType) {
        case AddressType.legacy:
          // P2PKH - Legacy address
          final legacyAddress = ecPublic.toAddress();
          addressStr = legacyAddress.toAddress(bitcoinNetwork);
          break;

        case AddressType.segwit:
          // P2WPKH - Native SegWit address
          final segwitAddress = ecPublic.toSegwitAddress();
          final testnetAddress = segwitAddress.toAddress(bitcoinNetwork);
          // Convert to regtest format if needed (tb1 → bcrt1)
          addressStr = _convertToRegtestAddress(testnetAddress);
          break;
      }

      return WalletAddress(
        address: addressStr,
        publicKey: publicKeyHex,
        privateKey: privateKeyHex,
        derivationPath: _buildDerivationPath(index, isChange, addressType),
        index: index,
        isChange: isChange,
        addressType: addressType,
      );
    } catch (e) {
      print(' [HDWallet] Failed to derive address at index $index: $e');
      throw HDWalletException('Failed to derive address at index $index: $e');
    }
  }

  /// Build derivation path string based on address type
  String _buildDerivationPath(
      int index, bool isChange, AddressType addressType) {
    final chain =
        isChange ? AppConstants.internalChain : AppConstants.externalChain;

    // Choose path prefix based on address type
    final pathPrefix = addressType == AddressType.legacy
        ? AppConstants.bip44PathPrefix
        : AppConstants.bip84PathPrefix;

    return "$pathPrefix/$chain/$index";
  }

  /// Get Bitcoin network configuration based on current network type
  BitcoinNetwork _getBitcoinNetwork() {
    switch (AppConstants.currentNetwork) {
      case NetworkType.mainnet:
        return BitcoinNetwork.mainnet;
      case NetworkType.testnet:
        return BitcoinNetwork.testnet;
      case NetworkType.regtest:
        return BitcoinNetwork.testnet;
    }
  }

  /// Convert testnet address (tb1...) to regtest format (bcrt1...)
  /// Uses proper Bech32 encoding to maintain checksum validity
  String _convertToRegtestAddress(String testnetAddress) {
    if (AppConstants.currentNetwork == NetworkType.regtest &&
        testnetAddress.startsWith('tb1')) {
      try {
        // Decode testnet address (hrp: "tb", returns Tuple<witnessVer, witnessProgram>)
        final decoded = SegwitBech32Decoder.decode('tb', testnetAddress);

        // decoded is Tuple<int, List<int>>
        // item1 = witness version, item2 = witness program
        final witnessVer = decoded.item1;
        final witnessProgram = decoded.item2;

        // Re-encode with regtest hrp: "bcrt"
        final regtestAddress = SegwitBech32Encoder.encode(
          'bcrt',
          witnessVer,
          witnessProgram,
        );

        return regtestAddress;
      } catch (e) {
        print(' [HDWallet] Failed to convert to regtest address: $e');
        // Fallback to simple replacement (may not work with strict validation)
        return 'bcrt1${testnetAddress.substring(3)}';
      }
    }
    return testnetAddress;
  }

  // ==================== Batch Address Generation ====================

  /// Generate multiple addresses at once (for wallet scanning)
  Future<List<WalletAddress>> generateAddresses({
    required int startIndex,
    required int count,
    bool isChange = false,
    AddressType? addressType,
  }) async {
    final addresses = <WalletAddress>[];
    final type = addressType ?? AppConstants.defaultAddressType;

    for (int i = startIndex; i < startIndex + count; i++) {
      final address = await _deriveAddressAtPath(
        index: i,
        isChange: isChange,
        addressType: type,
      );
      addresses.add(address);
    }

    return addresses;
  }

  /// Generate a batch of addresses starting from a specific index
  /// Used for bulk address generation
  Future<List<WalletAddress>> generateAddressBatch({
    required int startIndex,
    required int count,
    bool isChange = false,
    AddressType? addressType,
  }) async {
    final addresses = <WalletAddress>[];
    final type = addressType ?? AppConstants.defaultAddressType;

    for (int i = startIndex; i < startIndex + count; i++) {
      final address = await _deriveAddressAtPath(
        index: i,
        isChange: isChange,
        addressType: type,
      );
      addresses.add(address);
    }

    return addresses;
  }

  /// Generate addresses up to gap limit
  /// Implements BIP44 address gap limit for wallet discovery
  ///
  /// This method is ONLY used for wallet restoration scenarios.
  /// For normal operations, use direct address derivation instead.
  Future<List<WalletAddress>> generateAddressesWithGapLimit({
    bool isChange = false,
    int? gapLimit,
    AddressType? addressType,
  }) async {
    final addresses = <WalletAddress>[];
    final type = addressType ?? AppConstants.defaultAddressType;

    // Get last used index from storage
    // For imported wallets, this starts at 0 (default)
    final lastUsedIndex = isChange
        ? await _storage.getLastInternalIndex()
        : await _storage.getLastExternalIndex();

    // Generate addresses up to last used + gap limit
    // Use provided gapLimit or default to walletRestorationGapLimit
    final effectiveGapLimit =
        gapLimit ?? AppConstants.walletRestorationGapLimit;
    final maxIndex = lastUsedIndex + effectiveGapLimit;

    for (int i = 0; i <= maxIndex; i++) {
      final address = await _deriveAddressAtPath(
        index: i,
        isChange: isChange,
        addressType: type,
      );
      addresses.add(address);
    }

    return addresses;
  }

  // ==================== Address Management ====================

  /// Get next unused external address (for receiving)
  Future<WalletAddress> getNextReceivingAddress() async {
    final lastIndex = await _storage.getLastExternalIndex();
    final nextIndex = lastIndex + 1;

    final address = await deriveAddress(nextIndex);
    await _storage.saveLastExternalIndex(nextIndex);

    return address;
  }

  /// Get next unused change address (for transaction change)
  Future<WalletAddress> getNextChangeAddress({
    AddressType? addressType,
  }) async {
    final lastIndex = await _storage.getLastInternalIndex();
    final nextIndex = lastIndex + 1;

    // Use provided addressType or default to current default
    final type = addressType ?? AppConstants.defaultAddressType;
    final address = await deriveChangeAddress(nextIndex, addressType: type);

    await _storage.saveLastInternalIndex(nextIndex);

    return address;
  }

  /// Get current receiving address (without incrementing)
  Future<WalletAddress> getCurrentReceivingAddress() async {
    final lastIndex = await _storage.getLastExternalIndex();
    return await deriveAddress(lastIndex);
  }

  /// Get current change address (without incrementing)
  Future<WalletAddress> getCurrentChangeAddress() async {
    final lastIndex = await _storage.getLastInternalIndex();
    return await deriveChangeAddress(lastIndex);
  }

  // ==================== Key Operations ====================

  /// Get private key for a specific address by searching derivation paths
  /// This is a brute-force search and may be slow for high indices
  Future<String?> getPrivateKeyForAddress(
    String address, {
    int maxSearchIndex = 100,
  }) async {
    try {
      // Search external chain first
      for (int i = 0; i <= maxSearchIndex; i++) {
        final walletAddr = await deriveAddress(i);
        if (walletAddr.address == address) {
          return walletAddr.privateKey;
        }
      }

      // Search internal (change) chain
      for (int i = 0; i <= maxSearchIndex; i++) {
        final walletAddr = await deriveChangeAddress(i);
        if (walletAddr.address == address) {
          return walletAddr.privateKey;
        }
      }

      return null; // Address not found
    } catch (e) {
      throw HDWalletException('Failed to get private key for address: $e');
    }
  }

  /// Sign transaction digest with private key
  /// This is used for signing Bitcoin transactions
  String signTransactionDigest(String digestHex, String privateKeyHex) {
    try {
      final privateKey = ECPrivate.fromHex(privateKeyHex);
      final digest = BytesUtils.fromHexString(digestHex);

      // Sign using ECDSA for legacy/segwit transactions
      // Returns DER-encoded signature with SIGHASH_ALL flag
      final signature = privateKey.signECDSA(digest);

      return signature;
    } catch (e) {
      throw HDWalletException('Failed to sign transaction: $e');
    }
  }

  // ==================== Wallet Info ====================
  // ==================== Advanced functions ====================

  /// Get master public key (xpub) for account
  /// Can be used for watch-only wallets
  Future<String> getMasterPublicKey() async {
    try {
      final bip44 = await _getBip44();
      final account = bip44.purpose.coin.account(0);

      // Get extended public key
      return account.publicKey.toExtended;
    } catch (e) {
      throw HDWalletException('Failed to get master public key: $e');
    }
  }

  /// Get account fingerprint (for wallet identification)
  Future<String> getAccountFingerprint() async {
    try {
      final bip44 = await _getBip44();

      // Get the master public key compressed bytes
      // Fingerprint is the first 4 bytes of HASH160(public key)
      final masterPubKey = bip44.publicKey.compressed;
      final hash160 = QuickCrypto.hash160(masterPubKey);
      final fingerprint = hash160.sublist(0, 4);

      // Return fingerprint as hex
      return BytesUtils.toHexString(fingerprint);
    } catch (e) {
      throw HDWalletException('Failed to get account fingerprint: $e');
    }
  }

  // ==================== Validation ====================

  /// Validate if an address belongs to this wallet
  /// Searches both external and internal chains up to maxSearchIndex
  Future<bool> isOwnAddress(
    String address, {
    int maxSearchIndex = 100,
  }) async {
    try {
      // Search external chain
      for (int i = 0; i <= maxSearchIndex; i++) {
        final walletAddr = await deriveAddress(i);
        if (walletAddr.address == address) {
          return true;
        }
      }

      // Search internal (change) chain
      for (int i = 0; i <= maxSearchIndex; i++) {
        final walletAddr = await deriveChangeAddress(i);
        if (walletAddr.address == address) {
          return true;
        }
      }

      return false;
    } catch (e) {
      throw HDWalletException('Failed to validate address ownership: $e');
    }
  }

  /// Get derivation info for an address
  ///
  /// Simplified version: Derives addresses on-demand within the search range.
  /// Search range is determined by last_used_index + buffer for efficiency.
  ///
  /// Returns null if address is not found within the search range.
  Future<AddressDerivationInfo?> getAddressDerivationInfo(
    String address, {
    int? maxSearchIndex,
  }) async {
    try {
      // Determine search range based on last_used_index
      final lastExternal = await _storage.getLastExternalIndex();
      final lastInternal = await _storage.getLastInternalIndex();

      // Search up to last_used + buffer (or use provided maxSearchIndex)
      final externalLimit =
          maxSearchIndex ?? (lastExternal + AppConstants.normalScanBuffer + 5);
      final internalLimit =
          maxSearchIndex ?? (lastInternal + AppConstants.normalScanBuffer + 5);

      // Search external chain (0 to externalLimit)
      for (int i = 0; i <= externalLimit; i++) {
        final walletAddr = await deriveAddress(i);
        if (walletAddr.address == address) {
          return AddressDerivationInfo(
            address: address,
            index: i,
            isChange: false,
            derivationPath: walletAddr.derivationPath,
            addressType: walletAddr.addressType,
          );
        }
      }

      // Search internal (change) chain (0 to internalLimit)
      for (int i = 0; i <= internalLimit; i++) {
        final walletAddr = await deriveChangeAddress(i);
        if (walletAddr.address == address) {
          return AddressDerivationInfo(
            address: address,
            index: i,
            isChange: true,
            derivationPath: walletAddr.derivationPath,
            addressType: walletAddr.addressType,
          );
        }
      }

      return null; // Address not found
    } catch (e) {
      throw HDWalletException('Failed to get address derivation info: $e');
    }
  }
}

/// Represents a derived wallet address with its keys
class WalletAddress {
  final String address; // Bitcoin address (format depends on addressType)
  final String publicKey; // Public key hex
  final String privateKey; // Private key hex (handle with care!)
  final String derivationPath; // BIP32 path (e.g., m/84'/0'/0'/0/0)
  final int index; // Address index in derivation chain
  final bool isChange; // Whether this is a change address
  final AddressType addressType; // Type of address (legacy, segwit, etc.)

  WalletAddress({
    required this.address,
    required this.publicKey,
    required this.privateKey,
    required this.derivationPath,
    required this.index,
    required this.isChange,
    required this.addressType,
  });

  @override
  String toString() {
    return 'WalletAddress(address: $address, type: ${addressType.name}, path: $derivationPath, isChange: $isChange)';
  }

  /// Convert to map for storage or serialization
  Map<String, dynamic> toMap() {
    return {
      'address': address,
      'public_key': publicKey,
      'private_key': privateKey,
      'derivation_path': derivationPath,
      'index': index,
      'is_change': isChange,
      'address_type': addressType.name,
    };
  }

  /// Create from map
  factory WalletAddress.fromMap(Map<String, dynamic> map) {
    return WalletAddress(
      address: map['address'] as String,
      publicKey: map['public_key'] as String,
      privateKey: map['private_key'] as String,
      derivationPath: map['derivation_path'] as String,
      index: map['index'] as int,
      isChange: map['is_change'] as bool,
      addressType: AddressType.values.firstWhere(
        (type) => type.name == (map['address_type'] as String?),
        orElse: () =>
            AddressType.segwit, // Default to segwit for backward compatibility
      ),
    );
  }
}

/// Information about address derivation
class AddressDerivationInfo {
  final String address;
  final int index;
  final bool isChange;
  final String derivationPath;
  final AddressType addressType;

  AddressDerivationInfo({
    required this.address,
    required this.index,
    required this.isChange,
    required this.derivationPath,
    required this.addressType,
  });
}

/// Custom exception for HD wallet operations
class HDWalletException implements Exception {
  final String message;

  HDWalletException(this.message);

  @override
  String toString() => 'HDWalletException: $message';
}
