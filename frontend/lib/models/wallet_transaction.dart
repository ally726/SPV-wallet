/// Represents a transaction relevant to the wallet
/// Contains only information needed for wallet management
class WalletTransaction {
  final String txHash; // Transaction ID
  final int? blockHeight; // Block height (null if unconfirmed)
  final int? blockTime; // Block timestamp (null if unconfirmed)
  final List<TransactionInput> inputs; // Transaction inputs
  final List<TransactionOutput> outputs; // Transaction outputs
  final BigInt fee; // Transaction fee in satoshis
  final int? confirmations; // Number of confirmations

  WalletTransaction({
    required this.txHash,
    this.blockHeight,
    this.blockTime,
    required this.inputs,
    required this.outputs,
    required this.fee,
    this.confirmations,
  });

  /// Convert to Map for database storage
  Map<String, dynamic> toMap() {
    return {
      'tx_hash': txHash,
      'block_height': blockHeight,
      'block_time': blockTime,
      'inputs': inputs.map((i) => i.toMap()).toList(),
      'outputs': outputs.map((o) => o.toMap()).toList(),
      'fee': fee.toString(),
      'confirmations': confirmations,
    };
  }

  /// Create from database Map
  factory WalletTransaction.fromMap(Map<String, dynamic> map) {
    return WalletTransaction(
      txHash: map['tx_hash'] as String? ?? '',
      blockHeight: map['block_height'] as int?,
      blockTime: map['block_time'] as int?,
      inputs: (map['inputs'] as List?)
              ?.map((i) => TransactionInput.fromMap(i as Map<String, dynamic>))
              .toList() ??
          [],
      outputs: (map['outputs'] as List?)
              ?.map((o) => TransactionOutput.fromMap(o as Map<String, dynamic>))
              .toList() ??
          [],
      fee: BigInt.tryParse(map['fee'] as String? ?? '0') ?? BigInt.zero,
      confirmations: map['confirmations'] as int?,
    );
  }

  /// Check if transaction is confirmed
  bool get isConfirmed => confirmations != null && confirmations! > 0;

  /// Check if transaction is pending (in mempool)
  bool get isPending => confirmations == null || confirmations == 0;

  /// Calculate net change for wallet addresses
  /// Positive = received, Negative = sent
  BigInt calculateNetAmount(Set<String> walletAddresses) {
    BigInt received = BigInt.zero;
    BigInt sent = BigInt.zero;

    // Sum outputs to our addresses (received)
    for (final output in outputs) {
      if (walletAddresses.contains(output.address)) {
        received += output.value;
      }
    }

    // Sum inputs from our addresses (sent)
    for (final input in inputs) {
      if (input.address != null && walletAddresses.contains(input.address)) {
        sent += input.value;
      }
    }

    return received - sent;
  }

  /// Determine transaction type
  TransactionType getType(Set<String> walletAddresses) {
    final netAmount = calculateNetAmount(walletAddresses);

    if (netAmount > BigInt.zero) {
      return TransactionType.received;
    } else if (netAmount < BigInt.zero) {
      return TransactionType.sent;
    } else {
      return TransactionType.selfTransfer; // All inputs and outputs are ours
    }
  }

  @override
  String toString() {
    return 'WalletTransaction(txHash: $txHash, confirmations: $confirmations, fee: $fee sats)';
  }
}

/// Represents a transaction input
class TransactionInput {
  final String prevTxHash; // Previous transaction hash
  final int prevVout; // Previous output index
  final String? address; // Address that spent this input (if known)
  final BigInt value; // Value in satoshis
  final String? scriptSig; // Unlocking script (for non-segwit)
  final List<String>? witness; // Witness data (for segwit)

  TransactionInput({
    required this.prevTxHash,
    required this.prevVout,
    this.address,
    required this.value,
    this.scriptSig,
    this.witness,
  });

  Map<String, dynamic> toMap() {
    return {
      'prev_tx_hash': prevTxHash,
      'prev_vout': prevVout,
      'address': address,
      'value': value.toString(),
      'script_sig': scriptSig,
      'witness': witness,
    };
  }

  factory TransactionInput.fromMap(Map<String, dynamic> map) {
    return TransactionInput(
      prevTxHash: map['prev_tx_hash'] as String,
      prevVout: map['prev_vout'] as int,
      address: map['address'] as String?,
      value: BigInt.parse(map['value'] as String),
      scriptSig: map['script_sig'] as String?,
      witness: (map['witness'] as List?)?.cast<String>(),
    );
  }

  /// Get unique identifier for this input
  String get outpoint => '$prevTxHash:$prevVout';
}

/// Represents a transaction output
class TransactionOutput {
  final int vout; // Output index in transaction
  final String address; // Receiving address
  final BigInt value; // Value in satoshis
  final String scriptPubKey; // Locking script
  final bool isChange; // Whether this is a change output
  final bool isSpent; // Whether this output has been spent

  TransactionOutput({
    required this.vout,
    required this.address,
    required this.value,
    required this.scriptPubKey,
    this.isChange = false,
    this.isSpent = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'vout': vout,
      'address': address,
      'value': value.toString(),
      'script_pub_key': scriptPubKey,
      'is_change': isChange ? 1 : 0,
      'is_spent': isSpent ? 1 : 0,
    };
  }

  factory TransactionOutput.fromMap(Map<String, dynamic> map) {
    return TransactionOutput(
      vout: map['vout'] as int,
      address: map['address'] as String,
      value: BigInt.parse(map['value'] as String),
      scriptPubKey: map['script_pub_key'] as String,
      isChange: (map['is_change'] as int?) == 1,
      isSpent: (map['is_spent'] as int?) == 1,
    );
  }
}

/// Transaction type classification
enum TransactionType {
  received, // Net positive (received funds)
  sent, // Net negative (sent funds)
  selfTransfer, // Internal transfer (all addresses are ours)
}
