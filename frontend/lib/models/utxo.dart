import '../utils/constants.dart';

/// Represents an Unspent Transaction Output (UTXO)
/// UTXOs are the fundamental unit of Bitcoin's accounting model
class UTXO {
  final String txHash; // Transaction hash containing this output
  final int vout; // Output index in the transaction
  final BigInt value; // Value in satoshis
  final String scriptPubKey; // Locking script (determines who can spend)
  final String address; // Address that can spend this UTXO
  final int derivationIndex; // HD wallet derivation index
  final bool isChange; // Whether this is a change output (internal chain)
  final int? confirmations; // Number of confirmations (null if unconfirmed)
  final int? blockHeight; // Block height where this UTXO was created
  final AddressType addressType; // Type of address (legacy, segwit, etc.)

  UTXO({
    required this.txHash,
    required this.vout,
    required this.value,
    required this.scriptPubKey,
    required this.address,
    required this.derivationIndex,
    required this.isChange,
    this.confirmations,
    this.blockHeight,
    AddressType? addressType,
  }) : addressType = addressType ?? _detectAddressType(address);

  /// Detect address type from address string
  static AddressType _detectAddressType(String address) {
    if (address.startsWith('bc1') ||
        address.startsWith('tb1') ||
        address.startsWith('bcrt1')) {
      return AddressType.segwit;
    } else if (address.startsWith('1') ||
        address.startsWith('m') ||
        address.startsWith('n')) {
      return AddressType.legacy;
    }
    // Default to current default if can't detect
    return AppConstants.defaultAddressType;
  }

  /// Convert UTXO to Map for database storage
  Map<String, dynamic> toMap() {
    return {
      'tx_hash': txHash,
      'vout': vout,
      'value': value.toString(), // Store as string to preserve large numbers
      'script_pub_key': scriptPubKey,
      'address': address,
      'derivation_index': derivationIndex,
      'is_change': isChange ? 1 : 0, // SQLite uses 1/0 for boolean
      'confirmations': confirmations,
      'block_height': blockHeight,
      'address_type': addressType.name, // Store as string
    };
  }

  /// Create UTXO from database Map
  factory UTXO.fromMap(Map<String, dynamic> map) {
    final address = map['address'] as String;

    // Try to get address type from database, fallback to detection
    final addressTypeStr = map['address_type'] as String?;
    AddressType? detectedType;
    if (addressTypeStr != null) {
      try {
        detectedType = AddressType.values.firstWhere(
          (type) => type.name == addressTypeStr,
        );
      } catch (e) {
        detectedType = null; // Will be detected from address
      }
    }

    return UTXO(
      txHash: map['tx_hash'] as String,
      vout: map['vout'] as int,
      value: BigInt.parse(map['value'] as String),
      scriptPubKey: map['script_pub_key'] as String,
      address: address,
      derivationIndex: map['derivation_index'] as int,
      isChange: (map['is_change'] as int) == 1,
      confirmations: map['confirmations'] as int?,
      blockHeight: map['block_height'] as int?,
      addressType: detectedType, // Will auto-detect if null
    );
  }

  /// Check if this UTXO is confirmed
  bool get isConfirmed => confirmations != null && confirmations! > 0;

  /// Check if this UTXO is mature enough to spend
  /// For regular transactions, 1 confirmation is enough
  bool get isSpendable => confirmations != null && confirmations! >= 1;

  /// Get unique identifier for this UTXO
  String get outpoint => '$txHash:$vout';

  /// Calculate the weight of this UTXO when used as input
  /// P2WPKH inputs have specific weight in vbytes
  int get inputWeight {
    // P2WPKH input weight calculation:
    // - Outpoint: 36 bytes (32 txid + 4 vout)
    // - Script length: 1 byte (empty for segwit)
    // - Sequence: 4 bytes
    // - Witness: ~27 vbytes (signature + pubkey)
    return 41 + 27; // Approximately 68 vbytes for P2WPKH
  }

  @override
  String toString() {
    return 'UTXO(outpoint: $outpoint, value: $value sats, address: $address, confirmed: $isConfirmed)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UTXO && other.txHash == txHash && other.vout == vout;
  }

  @override
  int get hashCode => txHash.hashCode ^ vout.hashCode;
}

/// Helper class for UTXO selection algorithms
class UTXOSelector {
  /// Select UTXOs to cover the target amount plus fee
  /// Uses a simple greedy algorithm (largest first)
  static List<UTXO> selectUTXOs({
    required List<UTXO> availableUTXOs,
    required BigInt targetAmount,
    required int feeRate, // sat/vB
  }) {
    // Filter only spendable UTXOs and sort by value (largest first)
    final spendableUTXOs = availableUTXOs
        .where((utxo) => utxo.isSpendable)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (spendableUTXOs.isEmpty) {
      throw Exception('No spendable UTXOs available');
    }

    final selectedUTXOs = <UTXO>[];
    BigInt totalSelected = BigInt.zero;

    // Estimate base transaction size
    // Base: 10 bytes (version, locktime, etc.)
    // Each output: ~31 bytes for P2WPKH
    int estimatedSize = 10 + (2 * 31); // Assume 2 outputs (payment + change)

    for (final utxo in spendableUTXOs) {
      selectedUTXOs.add(utxo);
      totalSelected += utxo.value;
      estimatedSize += utxo.inputWeight;

      // Calculate current fee
      final currentFee = BigInt.from(estimatedSize * feeRate);

      // Check if we have enough to cover target + fee
      if (totalSelected >= targetAmount + currentFee) {
        return selectedUTXOs;
      }
    }

    // Not enough funds
    throw Exception(
        'Insufficient funds: need ${targetAmount + BigInt.from(estimatedSize * feeRate)} sats, '
        'have $totalSelected sats');
  }

  /// Calculate total value of a list of UTXOs
  static BigInt calculateTotal(List<UTXO> utxos) {
    return utxos.fold(
      BigInt.zero,
      (sum, utxo) => sum + utxo.value,
    );
  }
}
