import 'dart:convert';
import 'package:http/http.dart' as http;

/// Contract API Service
/// Communicates with smart contract backend for certificate registration
class ContractApiService {
  final String baseUrl;

  ContractApiService({
    this.baseUrl = 'http://127.0.0.1:3000',
  });

  /// Register certificate on smart contract
  Future<String> registerCertificate({
    required String aid,
    required String publicKey,
    required String bitcoinAddress,
    required String certificateHash,
  }) async {
    try {
      print('  Registering certificate on blockchain...');
      print('  AID: $aid');
      print('  BTC Address: $bitcoinAddress');
      print('  Hash: $certificateHash');

      final url = Uri.parse('$baseUrl/contract/call');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'method': 'register',
          'params': [
            aid,
            publicKey,
            bitcoinAddress,
            certificateHash,
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data['result'] as String;
        print(' Certificate registered successfully: $result');
        return result;
      } else {
        final errorBody = response.body;
        print(' Registration failed: ${response.statusCode} - $errorBody');
        throw Exception(
            'Registration failed: ${response.statusCode} - $errorBody');
      }
    } catch (e) {
      print(' Error during registration: $e');
      throw Exception('Failed to register certificate: $e');
    }
  }

  /// Query certificate data from smart contract (future feature)
  Future<Map<String, dynamic>?> queryCertificate(String aid) async {
    try {
      final url = Uri.parse('$baseUrl/contract/query');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'method': 'getCertificate',
          'params': [aid],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['result'] as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      print(' Query failed: $e');
      return null;
    }
  }
}
