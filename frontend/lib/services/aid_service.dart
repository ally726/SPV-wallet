import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../models/aid_certificate.dart';
import 'aid_crypto_service.dart';
import 'contract_api_service.dart';

/// AID Service
/// Manages AID certificate creation, storage, and operations
class AIDService {
  final FlutterSecureStorage _secureStorage;
  final AIDCryptoService _crypto;
  final ContractApiService _contractApi;

  // Cache for loaded certificates
  List<AIDCertificate>? _cachedCertificates;

  AIDService({
    FlutterSecureStorage? secureStorage,
    AIDCryptoService? crypto,
    ContractApiService? contractApi,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _crypto = crypto ?? AIDCryptoService(),
        _contractApi = contractApi ?? ContractApiService();

  /// Create a new AID certificate
  Future<AIDCertificate> createCertificate({
    required String title,
    String? description,
    required String username,
    required String password,
    String? btcAddress,
    String? fullName,
    String? email,
  }) async {
    try {
      print('Creating AID certificate: $title');

      // 1. Generate UUID for AID
      final aid = const Uuid().v4();
      print('  Generated AID: $aid');

      // 2. Generate RSA-2048 key pair
      print('  Generating RSA-2048 key pair...');
      final keyPair = await _crypto.generateRSAKeyPair();
      final publicKey = keyPair['publicKey']!;
      final privateKey = keyPair['privateKey']!;

      // 3. Hash password
      final passwordHash = _crypto.sha256Hash(password);

      // 4. Calculate certificate hash
      final certificateHash = _crypto.calculateCertificateHash(
        version: '1.0',
        aid: aid,
        publicKey: publicKey,
        btcAddress: btcAddress,
        username: username,
        passwordHash: passwordHash,
        fullName: fullName,
        email: email,
      );
      print('  Certificate hash: $certificateHash');

      // 5. Create certificate object
      final certificate = AIDCertificate(
        aid: aid,
        title: title,
        description: description,
        createdAt: DateTime.now(),
        version: '1.0',
        publicKey: publicKey,
        privateKey: privateKey,
        btcAddress: btcAddress,
        username: username,
        passwordHash: passwordHash,
        fullName: fullName,
        email: email,
        isRegistered: false,
        certificateHash: certificateHash,
      );

      // 6. Save to storage
      await _saveCertificate(certificate);

      print(' AID certificate created successfully');
      return certificate;
    } catch (e) {
      print(' Failed to create AID certificate: $e');
      throw Exception('Failed to create AID certificate: $e');
    }
  }

  /// Get all certificates
  Future<List<AIDCertificate>> getAllCertificates() async {
    // Return cached if available
    if (_cachedCertificates != null) {
      return List.from(_cachedCertificates!);
    }

    try {
      final jsonString = await _secureStorage.read(key: AIDStorage.storageKey);

      if (jsonString == null || jsonString.isEmpty) {
        _cachedCertificates = [];
        return [];
      }

      final certificates = AIDStorage.certificatesFromJson(jsonString);
      _cachedCertificates = certificates;

      print(' Loaded ${certificates.length} AID certificates');
      return List.from(certificates);
    } catch (e) {
      print(' Failed to load certificates: $e');
      return [];
    }
  }

  /// Get certificate by AID
  Future<AIDCertificate?> getCertificate(String aid) async {
    final certificates = await getAllCertificates();
    try {
      return certificates.firstWhere((cert) => cert.aid == aid);
    } catch (e) {
      return null;
    }
  }

  /// Update certificate
  Future<void> updateCertificate(AIDCertificate certificate) async {
    final certificates = await getAllCertificates();
    final index = certificates.indexWhere((c) => c.aid == certificate.aid);

    if (index == -1) {
      throw Exception('Certificate not found: ${certificate.aid}');
    }

    certificates[index] = certificate;
    await _saveAllCertificates(certificates);

    print(' Certificate updated: ${certificate.aid}');
  }

  /// Delete certificate
  Future<void> deleteCertificate(String aid) async {
    final certificates = await getAllCertificates();
    certificates.removeWhere((cert) => cert.aid == aid);
    await _saveAllCertificates(certificates);

    print(' Certificate deleted: $aid');
  }

  /// Register certificate on blockchain
  /// Calls smart contract API to register the certificate
  Future<String> registerCertificate(String aid) async {
    final certificate = await getCertificate(aid);
    if (certificate == null) {
      throw Exception('Certificate not found: $aid');
    }

    if (certificate.isRegistered) {
      throw Exception('Certificate is already registered');
    }

    if (certificate.btcAddress == null || certificate.btcAddress!.isEmpty) {
      throw Exception('Cannot register: Bitcoin address is required');
    }

    // Call contract API
    final txId = await _contractApi.registerCertificate(
      aid: certificate.aid,
      publicKey: certificate.publicKey,
      bitcoinAddress: certificate.btcAddress!,
      certificateHash: certificate.certificateHash,
    );

    // Mark as registered
    final updated = certificate.copyWith(isRegistered: true);
    await updateCertificate(updated);

    print(' Certificate registered with txId: $txId');
    return txId;
  }

  /// Mark certificate as registered (internal use)
  Future<void> markAsRegistered(String aid) async {
    final certificate = await getCertificate(aid);
    if (certificate == null) {
      throw Exception('Certificate not found: $aid');
    }

    final updated = certificate.copyWith(isRegistered: true);
    await updateCertificate(updated);
  }

  /// Get public key for a certificate
  Future<String> getPublicKey(String aid) async {
    final certificate = await getCertificate(aid);
    if (certificate == null) {
      throw Exception('Certificate not found: $aid');
    }
    return certificate.publicKey;
  }

  /// Sign data with certificate's private key
  Future<String> signData(String aid, String data) async {
    final certificate = await getCertificate(aid);
    if (certificate == null) {
      throw Exception('Certificate not found: $aid');
    }

    return _crypto.signData(certificate.privateKey, data);
  }

  /// Verify signature with certificate's public key
  Future<bool> verifySignature(
    String aid,
    String data,
    String signature,
  ) async {
    final certificate = await getCertificate(aid);
    if (certificate == null) {
      throw Exception('Certificate not found: $aid');
    }

    return _crypto.verifySignature(
      certificate.publicKey,
      data,
      signature,
    );
  }

  /// Export all certificates as JSON
  Future<String> exportWallet() async {
    final certificates = await getAllCertificates();
    return AIDStorage.certificatesToJson(certificates);
  }

  /// Import certificates from JSON
  Future<void> importWallet(String jsonString) async {
    try {
      final certificates = AIDStorage.certificatesFromJson(jsonString);
      await _saveAllCertificates(certificates);
      print(' Imported ${certificates.length} certificates');
    } catch (e) {
      throw Exception('Failed to import wallet: $e');
    }
  }

  /// Clear all certificates
  Future<void> clearAllCertificates() async {
    await _secureStorage.delete(key: AIDStorage.storageKey);
    _cachedCertificates = [];
    print(' All certificates cleared');
  }

  /// Search certificates by title, username, or AID
  Future<List<AIDCertificate>> searchCertificates(String query) async {
    final certificates = await getAllCertificates();
    final lowerQuery = query.toLowerCase();

    return certificates.where((cert) {
      return cert.title.toLowerCase().contains(lowerQuery) ||
          cert.username.toLowerCase().contains(lowerQuery) ||
          cert.aid.toLowerCase().contains(lowerQuery) ||
          (cert.btcAddress?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();
  }

  /// Get certificates bound to a specific Bitcoin address
  Future<List<AIDCertificate>> getCertificatesByBtcAddress(
    String btcAddress,
  ) async {
    final certificates = await getAllCertificates();
    return certificates.where((cert) => cert.btcAddress == btcAddress).toList();
  }

  // ==================== Private Helper Methods ====================

  /// Save a single certificate
  Future<void> _saveCertificate(AIDCertificate certificate) async {
    final certificates = await getAllCertificates();

    // Check if already exists
    final index = certificates.indexWhere((c) => c.aid == certificate.aid);
    if (index != -1) {
      certificates[index] = certificate;
    } else {
      certificates.add(certificate);
    }

    await _saveAllCertificates(certificates);
  }

  /// Save all certificates to storage
  Future<void> _saveAllCertificates(List<AIDCertificate> certificates) async {
    final jsonString = AIDStorage.certificatesToJson(certificates);
    await _secureStorage.write(
      key: AIDStorage.storageKey,
      value: jsonString,
    );

    // Update cache
    _cachedCertificates = List.from(certificates);
  }
}
