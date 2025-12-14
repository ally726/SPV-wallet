import 'package:blockchain_utils/bip/bip/bip39/bip39.dart';
import 'package:blockchain_utils/bip/mnemonic/mnemonic.dart';
import 'package:blockchain_utils/utils/binary/utils.dart';
import 'storage_service.dart';
import '../utils/constants.dart';

/// Service for BIP39 mnemonic generation and management
/// Handles creation, validation, and seed derivation from mnemonic phrases
class MnemonicService {
  static final MnemonicService instance = MnemonicService._internal();
  final StorageService _storage = StorageService.instance;

  MnemonicService._internal();

  // ==================== Mnemonic Generation ====================

  /// Generate a new BIP39 mnemonic phrase
  Future<String> generateMnemonic({
    int wordCount = AppConstants.defaultMnemonicWordCount, // 12
    Bip39Languages language = Bip39Languages.english,
  }) async {
    try {
      // Validate word count
      if (wordCount != 12 && wordCount != 24) {
        throw MnemonicException('Word count must be 12 or 24');
      }

      // Map word count to Bip39WordsNum enum
      final Bip39WordsNum wordsNum =
          wordCount == 12 ? Bip39WordsNum.wordsNum12 : Bip39WordsNum.wordsNum24;

      // Generate mnemonic using the correct API
      final mnemonic =
          Bip39MnemonicGenerator(language).fromWordsNumber(wordsNum);

      return mnemonic.toStr();
    } catch (e) {
      throw MnemonicException('Failed to generate mnemonic: $e');
    }
  }

  /// Validate a BIP39 mnemonic phrase
  /// Returns true if the mnemonic is valid according to BIP39 standard
  bool validateMnemonic(
    String mnemonic, {
    Bip39Languages language = Bip39Languages.english,
  }) {
    try {
      // Trim and normalize whitespace
      final normalizedMnemonic = _normalizeMnemonic(mnemonic);

      // Split into words
      final words = normalizedMnemonic.split(' ');

      // Check word count is valid (12, 15, 18, 21, or 24)
      if (![12, 15, 18, 21, 24].contains(words.length)) {
        return false;
      }

      // Try to generate seed - if mnemonic is invalid, it will throw
      // This is the most reliable way to validate
      try {
        final mnemonicObj = Mnemonic.fromList(words);
        Bip39SeedGenerator(mnemonicObj).generate('');
        return true;
      } catch (e) {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  /// Generate seed from mnemonic phrase
  /// @param mnemonic: The BIP39 mnemonic phrase
  /// @param passphrase: Optional BIP39 passphrase (empty string if not used)
  /// Returns: 64-byte seed as hex string
  String generateSeed(String mnemonic, {String passphrase = ''}) {
    try {
      // Validate mnemonic first
      if (!validateMnemonic(mnemonic)) {
        throw MnemonicException('Invalid mnemonic phrase');
      }

      // Normalize mnemonic
      final normalizedMnemonic = _normalizeMnemonic(mnemonic);

      // Convert string to Mnemonic object by splitting into words
      final words = normalizedMnemonic.split(' ');
      final mnemonicObj = Mnemonic.fromList(words);

      // Generate seed using BIP39 seed generator
      final seed = Bip39SeedGenerator(mnemonicObj).generate(passphrase);

      // Return seed as hex string
      return BytesUtils.toHexString(seed);
    } catch (e) {
      throw MnemonicException('Failed to generate seed: $e');
    }
  }

  // ==================== Wallet Creation & Import ====================

  /// Create a new wallet with a fresh mnemonic
  /// Generates mnemonic, derives seed, and stores both securely
  Future<String> createNewWallet({
    int wordCount = AppConstants.defaultMnemonicWordCount,
    String passphrase = '',
  }) async {
    try {
      // Check if wallet already exists
      if (await _storage.isWalletInitialized()) {
        throw MnemonicException(
            'Wallet already exists. Delete existing wallet first.');
      }

      // Generate new mnemonic
      final mnemonic = await generateMnemonic(wordCount: wordCount);

      // Generate seed from mnemonic
      final seed = generateSeed(mnemonic, passphrase: passphrase);

      // Save mnemonic and seed securely
      await _storage.saveMnemonic(mnemonic);
      await _storage.saveSeed(seed);
      await _storage.saveWalletCreationTime(DateTime.now());

      return mnemonic;
    } catch (e) {
      throw MnemonicException('Failed to create wallet: $e');
    }
  }

  /// Import existing wallet from mnemonic phrase
  /// Validates mnemonic, derives seed, and stores both
  Future<void> importWallet(
    String mnemonic, {
    String passphrase = '',
  }) async {
    try {
      // Normalize and validate mnemonic
      final normalizedMnemonic = _normalizeMnemonic(mnemonic);
      if (!validateMnemonic(normalizedMnemonic)) {
        throw MnemonicException('Invalid mnemonic phrase');
      }

      // Check if wallet already exists
      if (await _storage.isWalletInitialized()) {
        throw MnemonicException(
            'Wallet already exists. Delete existing wallet first.');
      }

      // Generate seed from mnemonic
      final seed = generateSeed(normalizedMnemonic, passphrase: passphrase);

      // Save mnemonic and seed securely
      await _storage.saveMnemonic(normalizedMnemonic);
      await _storage.saveSeed(seed);
      await _storage.saveWalletCreationTime(DateTime.now());
    } catch (e) {
      throw MnemonicException('Failed to import wallet: $e');
    }
  }

  /// Get stored mnemonic (for backup display)
  Future<String?> getStoredMnemonic() async {
    try {
      return await _storage.getMnemonic();
    } catch (e) {
      throw MnemonicException('Failed to retrieve mnemonic: $e');
    }
  }

  /// Get stored seed
  Future<String?> getStoredSeed() async {
    try {
      return await _storage.getSeed();
    } catch (e) {
      throw MnemonicException('Failed to retrieve seed: $e');
    }
  }

  /// Check if wallet exists
  Future<bool> hasWallet() async {
    return await _storage.isWalletInitialized();
  }

  /// Delete wallet (mnemonic and seed)
  Future<void> deleteWallet() async {
    try {
      await _storage.deleteMnemonic();
      await _storage.deleteSeed();
    } catch (e) {
      throw MnemonicException('Failed to delete wallet: $e');
    }
  }

  // ==================== Utility Functions ====================

  /// Normalize mnemonic phrase
  /// Trims whitespace, converts to lowercase, and ensures single spaces
  String _normalizeMnemonic(String mnemonic) {
    return mnemonic.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Get word count from mnemonic
  int getWordCount(String mnemonic) {
    final normalizedMnemonic = _normalizeMnemonic(mnemonic);
    return normalizedMnemonic.split(' ').length;
  }

  /// Get mnemonic word at specific index
  /// Useful for verification during backup
  String getWordAtIndex(String mnemonic, int index) {
    final normalizedMnemonic = _normalizeMnemonic(mnemonic);
    final words = normalizedMnemonic.split(' ');

    if (index < 0 || index >= words.length) {
      throw MnemonicException('Index out of bounds');
    }

    return words[index];
  }

  /// Split mnemonic into word list
  List<String> getMnemonicWords(String mnemonic) {
    final normalizedMnemonic = _normalizeMnemonic(mnemonic);
    return normalizedMnemonic.split(' ');
  }

  /// Check if a word is in the BIP39 wordlist
  bool isValidWord(
    String word, {
    Bip39Languages language = Bip39Languages.english,
  }) {
    try {
      // Get the wordlist for the specified language
      final wordList = bip39WordList(language);

      // Check if the word exists in the wordlist (case-insensitive)
      return wordList.contains(word.toLowerCase());
    } catch (e) {
      return false;
    }
  }

  /// Get suggestions for partial word input
  /// Useful for autocomplete in UI
  List<String> getWordSuggestions(
    String partialWord, {
    Bip39Languages language = Bip39Languages.english,
    int maxSuggestions = 10,
  }) {
    try {
      // Normalize input to lowercase
      final lowerPartial = partialWord.toLowerCase().trim();

      // If empty input, return empty list
      if (lowerPartial.isEmpty) {
        return [];
      }

      // Get the wordlist for the specified language
      final wordList = bip39WordList(language);

      // Filter words that start with the partial input
      return wordList
          .where((word) => word.startsWith(lowerPartial))
          .take(maxSuggestions)
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Calculate checksum validity
  /// Returns true if the last word (checksum) is correct
  bool validateChecksum(String mnemonic) {
    try {
      return validateMnemonic(mnemonic);
    } catch (e) {
      return false;
    }
  }

  /// Get entropy bits from word count
  int getEntropyBits(int wordCount) {
    // BIP39: entropy = (wordCount * 11) - (wordCount / 3)
    // 12 words = 128 bits, 24 words = 256 bits
    switch (wordCount) {
      case 12:
        return 128;
      case 15:
        return 160;
      case 18:
        return 192;
      case 21:
        return 224;
      case 24:
        return 256;
      default:
        throw MnemonicException('Invalid word count: $wordCount');
    }
  }
}

/// Custom exception for mnemonic operations
class MnemonicException implements Exception {
  final String message;

  MnemonicException(this.message);

  @override
  String toString() => 'MnemonicException: $message';
}
