import 'dart:convert';

/// AID Certificate data model
/// Represents a decentralized identity credential bound to a Bitcoin address
class AIDCertificate {
  final String aid; // UUID v4
  final String title;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String version;

  // RSA-2048 keys (PEM format)
  final String publicKey;
  final String privateKey;

  // Bitcoin address binding (optional)
  final String? btcAddress;

  // Credentials
  final String username;
  final String passwordHash; // SHA-256 hash

  // Optional disclosed information
  final String? fullName;
  final String? email;

  // Registration status
  final bool isRegistered;
  final String certificateHash;

  // Alias for compatibility
  String get aidId => aid;

  AIDCertificate({
    required this.aid,
    required this.title,
    this.description,
    required this.createdAt,
    DateTime? updatedAt,
    required this.version,
    required this.publicKey,
    required this.privateKey,
    this.btcAddress,
    required this.username,
    required this.passwordHash,
    this.fullName,
    this.email,
    this.isRegistered = false,
    required this.certificateHash,
  }) : updatedAt = updatedAt ?? createdAt;

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'aid': aid,
      'title': title,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'version': version,
      'publicKey': publicKey,
      'privateKey': privateKey,
      'btcAddress': btcAddress,
      'credentials': {
        'username': username,
        'passwordHash': passwordHash,
      },
      'disclosedInfo': {
        if (fullName != null) 'fullName': fullName,
        if (email != null) 'email': email,
      },
      'isRegistered': isRegistered,
      'certificateHash': certificateHash,
    };
  }

  /// Create from JSON map
  factory AIDCertificate.fromJson(Map<String, dynamic> json) {
    final credentials = json['credentials'] as Map<String, dynamic>;
    final disclosedInfo = json['disclosedInfo'] as Map<String, dynamic>?;

    return AIDCertificate(
      aid: json['aid'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] != null 
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.parse(json['createdAt'] as String),
      version: json['version'] as String,
      publicKey: json['publicKey'] as String,
      privateKey: json['privateKey'] as String,
      btcAddress: json['btcAddress'] as String?,
      username: credentials['username'] as String,
      passwordHash: credentials['passwordHash'] as String,
      fullName: disclosedInfo?['fullName'] as String?,
      email: disclosedInfo?['email'] as String?,
      isRegistered: json['isRegistered'] as bool? ?? false,
      certificateHash: json['certificateHash'] as String,
    );
  }

  /// Create a copy with modified fields
  AIDCertificate copyWith({
    String? aid,
    String? title,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? version,
    String? publicKey,
    String? privateKey,
    String? btcAddress,
    String? username,
    String? passwordHash,
    String? fullName,
    String? email,
    bool? isRegistered,
    String? certificateHash,
  }) {
    return AIDCertificate(
      aid: aid ?? this.aid,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      publicKey: publicKey ?? this.publicKey,
      privateKey: privateKey ?? this.privateKey,
      btcAddress: btcAddress ?? this.btcAddress,
      username: username ?? this.username,
      passwordHash: passwordHash ?? this.passwordHash,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      isRegistered: isRegistered ?? this.isRegistered,
      certificateHash: certificateHash ?? this.certificateHash,
    );
  }

  @override
  String toString() {
    return 'AIDCertificate(aid: $aid, title: $title, btcAddress: $btcAddress, registered: $isRegistered)';
  }
}

/// Storage helper for AID certificates
class AIDStorage {
  static const String storageKey = 'aid_certificates';

  /// Save certificates to JSON string (for flutter_secure_storage)
  static String certificatesToJson(List<AIDCertificate> certificates) {
    final jsonList = certificates.map((c) => c.toJson()).toList();
    return json.encode(jsonList);
  }

  /// Load certificates from JSON string
  static List<AIDCertificate> certificatesFromJson(String jsonString) {
    try {
      final jsonList = json.decode(jsonString) as List;
      return jsonList.map((json) => AIDCertificate.fromJson(json)).toList();
    } catch (e) {
      print('Error parsing certificates: $e');
      return [];
    }
  }
}
