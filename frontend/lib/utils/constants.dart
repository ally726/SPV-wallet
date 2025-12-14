/// Network type enum for Bitcoin networks
enum NetworkType { mainnet, testnet, regtest }

/// Address type enum for different Bitcoin address formats
enum AddressType {
  legacy, // P2PKH
  segwit, // P2WPKH
}

/// Constants used throughout the SPV wallet application
class AppConstants {
  // BIP44 derivation paths for different address types
  static const String bip44PathPrefix = "m/44'/0'/0'"; // Legacy (P2PKH)
  static const String bip84PathPrefix = "m/84'/0'/0'"; // Native SegWit (P2WPKH)

  static const int externalChain = 0; // For receiving addresses
  static const int internalChain = 1; // For change addresses

  // Default address type for new wallets
  static AddressType defaultAddressType = AddressType.legacy;

  // Network configuration
  static const int bitcoinMainnetCoinType = 0;
  static const int bitcoinTestnetCoinType = 1;

  // Network type selection
  static NetworkType currentNetwork = NetworkType.regtest; // For lab testing

  // Block header constants
  static const int blockHeadersPerBatch = 2000;

  // ==================== Scanning Configuration ====================

  // Transaction constants
  static const int minConfirmations =
      1; // Minimum confirmations to consider transaction confirmed
  static const int defaultFeeRate = 5;
  static const int dustThreshold = 546;

  // Fixed fee for testing (set to null to use calculated fee based on tx size)
  static const int? fixedFee = 5000; // Change to 5000 to enable fixed fee mode

  // Database constants
  static const String dbName = 'spv_wallet.db';
  static const int dbVersion = 3;

  // Secure storage keys
  static const String storageKeyMnemonic = 'mnemonic';
  static const String storageKeySeed = 'seed';

  // API endpoints (to be configured with actual backend URL)
  static String apiBaseUrl = 'http://localhost:3000';

  static String getHeadersEndpoint() => '$apiBaseUrl/headers';
  static String getFiltersEndpoint() => '$apiBaseUrl/filters';
  static String getFilterMatchEndpoint() => '$apiBaseUrl/filters/match';
  static String getBlockEndpoint(String hash) => '$apiBaseUrl/block/$hash';
  static String getBroadcastEndpoint() => '$apiBaseUrl/broadcast';
  static String getUTXOScanEndpoint() => '$apiBaseUrl/utxos/scan';

  // Wallet defaults
  static const int defaultMnemonicWordCount = 12; // 12 or 24 words

  // ==================== Address Management ====================
  // Gap Limit: ONLY used for wallet restoration (import from mnemonic)
  // Scans this many addresses beyond last discovered address to find all used addresses
  static const int walletRestorationGapLimit = 20;
  // Normal Scan Buffer: For regular operations (how many unused addresses to include)
  static const int normalScanBuffer = 0;
  // Search Limit: Maximum index to search when looking up address derivation info
  static const int maxAddressSearchIndex = 20;

  /// Get the BitcoinNetwork enum value based on current network configuration
  /// This is used by bitcoin_base package for address validation and creation
  static dynamic getBitcoinNetwork() {
    // Need to import bitcoin_base package to use BitcoinNetwork enum
    // For now, we return the string representation
    // The calling code will need to map this to BitcoinNetwork
    switch (currentNetwork) {
      case NetworkType.mainnet:
        return 'mainnet';
      case NetworkType.testnet:
        return 'testnet';
      case NetworkType.regtest:
        return 'regtest';
    }
  }
}
