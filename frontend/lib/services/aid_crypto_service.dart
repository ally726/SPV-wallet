import 'dart:convert';
import 'dart:math' show Random;
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:asn1lib/asn1lib.dart';

/// Cryptographic utilities for AID
/// Handles RSA key generation, hashing, and signing
class AIDCryptoService {
  /// Generate RSA-2048 key pair (simplified version without isolate)
  /// Returns: Map with 'publicKey' and 'privateKey' in PEM format
  Future<Map<String, String>> generateRSAKeyPair() async {
    try {
      debugPrint(' Starting RSA key generation...');

      // Initialize secure random
      final secureRandom = FortunaRandom();
      final random = Random.secure();
      final seeds = List<int>.generate(32, (_) => random.nextInt(256));
      secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));

      // Generate RSA key pair (2048 bits)
      final keyGen = RSAKeyGenerator()
        ..init(ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
          secureRandom,
        ));

      final pair = keyGen.generateKeyPair();
      final publicKey = pair.publicKey as RSAPublicKey;
      final privateKey = pair.privateKey as RSAPrivateKey;

      // Convert to PEM format
      final publicPem = _encodePublicKeyToPem(publicKey);
      final privatePem = _encodePrivateKeyToPem(privateKey);

      debugPrint(' RSA key pair generated');

      return {
        'publicKey': publicPem,
        'privateKey': privatePem,
      };
    } catch (e) {
      debugPrint(' Failed to generate RSA key pair: $e');
      throw Exception('Failed to generate RSA key pair: $e');
    }
  }

  /// Calculate SHA-256 hash of input string
  String sha256Hash(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Calculate certificate hash
  /// Includes: version, aid, publicKey, btcAddress, credentials, disclosedInfo
  /// Fields are sorted alphabetically before hashing
  String calculateCertificateHash({
    required String version,
    required String aid,
    required String publicKey,
    String? btcAddress,
    required String username,
    required String passwordHash,
    String? fullName,
    String? email,
  }) {
    // Build hash input with sorted keys
    final hashInput = <String, dynamic>{
      'aid': aid,
      'version': version,
      'publicKey': publicKey,
      'credentials': {
        'username': username,
        'passwordHash': passwordHash,
      },
    };

    // Add optional fields
    if (btcAddress != null) {
      hashInput['btcAddress'] = btcAddress;
    }

    if (fullName != null || email != null) {
      hashInput['disclosedInfo'] = <String, dynamic>{};
      if (fullName != null) {
        hashInput['disclosedInfo']['fullName'] = fullName;
      }
      if (email != null) {
        hashInput['disclosedInfo']['email'] = email;
      }
    }

    // Sort keys and convert to JSON
    final sortedJson = _sortedJsonEncode(hashInput);

    // Calculate hash
    return sha256Hash(sortedJson);
  }

  /// Sign data with RSA private key (PSS padding with SHA-256)
  /// Returns: Base64 encoded signature
  String signData(String privateKeyPem, String data) {
    try {
      final privateKey = _parsePrivateKeyFromPem(privateKeyPem);
      final signer = RSASigner(SHA256Digest(), '0609608648016503040201');

      // Initialize signer
      signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));

      // Sign data
      final dataBytes = utf8.encode(data);
      final signature = signer.generateSignature(Uint8List.fromList(dataBytes));

      return base64.encode(signature.bytes);
    } catch (e) {
      throw Exception('Failed to sign data: $e');
    }
  }

  /// Verify RSA signature
  bool verifySignature(
    String publicKeyPem,
    String data,
    String signatureBase64,
  ) {
    try {
      final publicKey = _parsePublicKeyFromPem(publicKeyPem);
      final signer = RSASigner(SHA256Digest(), '0609608648016503040201');

      // Initialize verifier
      signer.init(false, PublicKeyParameter<RSAPublicKey>(publicKey));

      // Verify signature
      final dataBytes = utf8.encode(data);
      final signatureBytes = base64.decode(signatureBase64);

      return signer.verifySignature(
        Uint8List.fromList(dataBytes),
        RSASignature(signatureBytes),
      );
    } catch (e) {
      print('Signature verification error: $e');
      return false;
    }
  }

  // ==================== Private Helper Methods ====================

  /// Encode RSA public key to PEM format
  String _encodePublicKeyToPem(RSAPublicKey publicKey) {
    final algorithmSeq = ASN1Sequence();
    final algorithmAsn1Obj = ASN1Object.fromBytes(Uint8List.fromList(
        [0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01]));
    final paramsAsn1Obj =
        ASN1Object.fromBytes(Uint8List.fromList([0x05, 0x00]));
    algorithmSeq.add(algorithmAsn1Obj);
    algorithmSeq.add(paramsAsn1Obj);

    final publicKeySeq = ASN1Sequence();
    publicKeySeq.add(ASN1Integer(publicKey.modulus!));
    publicKeySeq.add(ASN1Integer(publicKey.exponent!));
    final publicKeySeqBitString =
        ASN1BitString(Uint8List.fromList(publicKeySeq.encodedBytes));

    final topLevelSeq = ASN1Sequence();
    topLevelSeq.add(algorithmSeq);
    topLevelSeq.add(publicKeySeqBitString);

    final dataBase64 = base64.encode(topLevelSeq.encodedBytes);
    return '-----BEGIN PUBLIC KEY-----\n${_formatPem(dataBase64)}\n-----END PUBLIC KEY-----';
  }

  /// Encode RSA private key to PEM format
  String _encodePrivateKeyToPem(RSAPrivateKey privateKey) {
    final version = ASN1Integer(BigInt.from(0));
    final modulus = ASN1Integer(privateKey.n!);
    final publicExponent = ASN1Integer(BigInt.from(65537));
    final privateExponent = ASN1Integer(privateKey.privateExponent!);
    final p = ASN1Integer(privateKey.p!);
    final q = ASN1Integer(privateKey.q!);
    final dP = privateKey.privateExponent! % (privateKey.p! - BigInt.one);
    final dQ = privateKey.privateExponent! % (privateKey.q! - BigInt.one);
    final iQ = privateKey.q!.modInverse(privateKey.p!);

    final seq = ASN1Sequence();
    seq.add(version);
    seq.add(modulus);
    seq.add(publicExponent);
    seq.add(privateExponent);
    seq.add(p);
    seq.add(q);
    seq.add(ASN1Integer(dP));
    seq.add(ASN1Integer(dQ));
    seq.add(ASN1Integer(iQ));

    final dataBase64 = base64.encode(seq.encodedBytes);
    return '-----BEGIN PRIVATE KEY-----\n${_formatPem(dataBase64)}\n-----END PRIVATE KEY-----';
  }

  /// Parse RSA public key from PEM
  RSAPublicKey _parsePublicKeyFromPem(String pem) {
    final rows = pem
        .split('\n')
        .where((row) => !row.contains('BEGIN') && !row.contains('END'))
        .join('');
    final bytes = base64.decode(rows);

    final asn1Parser = ASN1Parser(Uint8List.fromList(bytes));
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    final publicKeyBitString = topLevelSeq.elements[1] as ASN1BitString;

    final publicKeyAsn = ASN1Parser(publicKeyBitString.contentBytes());
    final publicKeySeq = publicKeyAsn.nextObject() as ASN1Sequence;
    final modulus = publicKeySeq.elements[0] as ASN1Integer;
    final exponent = publicKeySeq.elements[1] as ASN1Integer;

    return RSAPublicKey(modulus.valueAsBigInteger, exponent.valueAsBigInteger);
  }

  /// Parse RSA private key from PEM
  RSAPrivateKey _parsePrivateKeyFromPem(String pem) {
    final rows = pem
        .split('\n')
        .where((row) => !row.contains('BEGIN') && !row.contains('END'))
        .join('');
    final bytes = base64.decode(rows);

    final asn1Parser = ASN1Parser(Uint8List.fromList(bytes));
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

    final modulus = topLevelSeq.elements[1] as ASN1Integer;
    final privateExponent = topLevelSeq.elements[3] as ASN1Integer;
    final p = topLevelSeq.elements[4] as ASN1Integer;
    final q = topLevelSeq.elements[5] as ASN1Integer;

    return RSAPrivateKey(
      modulus.valueAsBigInteger,
      privateExponent.valueAsBigInteger,
      p.valueAsBigInteger,
      q.valueAsBigInteger,
    );
  }

  /// Format base64 string for PEM (64 chars per line)
  String _formatPem(String base64String) {
    final chunks = <String>[];
    for (int i = 0; i < base64String.length; i += 64) {
      final end = (i + 64 < base64String.length) ? i + 64 : base64String.length;
      chunks.add(base64String.substring(i, end));
    }
    return chunks.join('\n');
  }

  /// Sort JSON object keys recursively and encode
  String _sortedJsonEncode(dynamic obj) {
    if (obj is Map) {
      final sortedMap = <String, dynamic>{};
      final sortedKeys = obj.keys.toList()..sort();
      for (final key in sortedKeys) {
        sortedMap[key] = obj[key];
      }
      return json.encode(sortedMap);
    }
    return json.encode(obj);
  }
}
