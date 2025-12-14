import 'dart:typed_data';
import 'package:blockchain_utils/blockchain_utils.dart';

/// Represents a Bitcoin block header
/// Used for SPV verification without downloading full blocks
class BlockHeader {
  final String hash; // Block hash (calculated)
  final int version; // Block version
  final String previousBlockHash; // Hash of previous block
  final String merkleRoot; // Merkle root of transactions
  final int timestamp; // Block timestamp (Unix time)
  final int bits; // Difficulty target in compact format
  final int nonce; // Proof-of-work nonce
  final int height; // Block height in the chain

  BlockHeader({
    required this.hash,
    required this.version,
    required this.previousBlockHash,
    required this.merkleRoot,
    required this.timestamp,
    required this.bits,
    required this.nonce,
    required this.height,
  });

  /// Convert BlockHeader to Map for database storage
  Map<String, dynamic> toMap() {
    return {
      'hash': hash,
      'version': version,
      'previous_block_hash': previousBlockHash,
      'merkle_root': merkleRoot,
      'timestamp': timestamp,
      'bits': bits,
      'nonce': nonce,
      'height': height,
    };
  }

  /// Create BlockHeader from database Map
  factory BlockHeader.fromMap(Map<String, dynamic> map) {
    return BlockHeader(
      hash: map['hash'] as String,
      version: map['version'] as int,
      previousBlockHash: map['previous_block_hash'] as String,
      merkleRoot: map['merkle_root'] as String,
      timestamp: map['timestamp'] as int,
      bits: map['bits'] as int,
      nonce: map['nonce'] as int,
      height: map['height'] as int,
    );
  }

  /// Create BlockHeader from API response
  factory BlockHeader.fromJson(Map<String, dynamic> json, int height) {
    return BlockHeader(
      hash: json['hash'] as String,
      version: json['version'] as int,
      previousBlockHash: json['previousblockhash'] as String? ?? '',
      merkleRoot: json['merkleroot'] as String,
      timestamp: json['time'] as int,
      bits: _parseBits(json['bits']),
      nonce: json['nonce'] as int,
      height: height,
    );
  }

  /// Parse bits from hex string or int
  static int _parseBits(dynamic bits) {
    if (bits is int) return bits;
    if (bits is String) {
      return int.parse(bits.startsWith('0x') ? bits.substring(2) : bits,
          radix: 16);
    }
    throw ArgumentError('Invalid bits format');
  }

  /// Calculate the target difficulty from compact bits representation
  BigInt getTarget() {
    final exponent = bits >> 24;
    final mantissa = bits & 0x00ffffff;

    if (exponent <= 3) {
      return BigInt.from(mantissa >> (8 * (3 - exponent)));
    } else {
      return BigInt.from(mantissa) << (8 * (exponent - 3));
    }
  }

  /// Verify Proof-of-Work for this block header
  /// Returns true if the block hash meets the difficulty target
  bool verifyPoW() {
    try {
      // Calculate block hash
      final headerBytes = _serializeHeader();
      final hash1 = QuickCrypto.sha256Hash(headerBytes);
      final hash2 = QuickCrypto.sha256Hash(hash1);

      // Convert hash to BigInt (little-endian)
      final hashBigInt =
          BigintUtils.fromBytes(hash2, sign: false, byteOrder: Endian.little);

      // Get target from bits
      final target = getTarget();

      // Hash must be less than or equal to target
      return hashBigInt <= target;
    } catch (e) {
      return false;
    }
  }

  /// Serialize block header to bytes for hashing
  Uint8List _serializeHeader() {
    final buffer = BytesBuilder();

    // Version (4 bytes, little-endian)
    buffer.add(_int32ToBytes(version));

    // Previous block hash (32 bytes, reversed)
    // Genesis block has empty previousBlockHash, use all zeros
    final prevHashBytes = previousBlockHash.isEmpty
        ? Uint8List(32) // 32 bytes of zeros
        : BytesUtils.fromHexString(previousBlockHash);
    buffer.add(prevHashBytes.reversed.toList());

    // Merkle root (32 bytes, reversed)
    buffer.add(BytesUtils.fromHexString(merkleRoot).reversed.toList());

    // Timestamp (4 bytes, little-endian)
    buffer.add(_int32ToBytes(timestamp));

    // Bits (4 bytes, little-endian)
    buffer.add(_int32ToBytes(bits));

    // Nonce (4 bytes, little-endian)
    buffer.add(_int32ToBytes(nonce));

    return buffer.toBytes();
  }

  /// Convert int32 to bytes (little-endian)
  Uint8List _int32ToBytes(int value) {
    return Uint8List(4)
      ..[0] = value & 0xff
      ..[1] = (value >> 8) & 0xff
      ..[2] = (value >> 16) & 0xff
      ..[3] = (value >> 24) & 0xff;
  }

  /// Calculate the hash of this block header
  String calculateHash() {
    final headerBytes = _serializeHeader();
    final hash1 = QuickCrypto.sha256Hash(headerBytes);
    final hash2 = QuickCrypto.sha256Hash(hash1);

    // Return hash in standard format (reversed, hex string)
    return BytesUtils.toHexString(hash2.reversed.toList());
  }

  @override
  String toString() {
    return 'BlockHeader(height: $height, hash: $hash, time: $timestamp)';
  }
}
