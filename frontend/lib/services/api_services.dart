// lib/services/api_services.dart (ID type error fixed)
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';
import '../models/block_header.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// API service for communicating with the Bitcoin backend
class ApiService {
  static final ApiService instance = ApiService._internal();

  final http.Client _client;
  final String _baseUrl;

  static const Duration _defaultTimeout = Duration(seconds: 30);

  ApiService._internal()
      : _client = http.Client(),
        _baseUrl = AppConstants.apiBaseUrl;

  ApiService.withClient(http.Client client, {String? baseUrl})
      : _client = client,
        _baseUrl = baseUrl ?? AppConstants.apiBaseUrl;

  // ==================== Block Headers, Filters, Blocks, Merkle APIs ====================
  // (getHeaders, getFilter, getBlock, getMerkleProof functions remain unchanged)

  Future<List<BlockHeader>> getHeaders({
    required String startHash,
    int count = AppConstants.blockHeadersPerBatch,
  }) async {
    try {
      final uri = Uri.parse(AppConstants.getHeadersEndpoint()).replace(
        queryParameters: {
          'start_hash': startHash,
          'count': count.toString(),
        },
      );
      final response = await _client.get(uri).timeout(_defaultTimeout);
      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        if (jsonData is! Map<String, dynamic>) {
          throw ApiException('Invalid response format');
        }
        final headersJson = jsonData['headers'] as List<dynamic>?;
        if (headersJson == null) {
          throw ApiException('No headers in response');
        }
        final startHeight = jsonData['start_height'] as int? ?? 0;
        final headers = <BlockHeader>[];
        for (int i = 0; i < headersJson.length; i++) {
          final headerMap = headersJson[i] as Map<String, dynamic>;
          final header = BlockHeader.fromJson(headerMap, startHeight + i);
          headers.add(header);
        }
        return headers;
      } else if (response.statusCode == 404) {
        throw ApiException('Block not found: $startHash');
      } else {
        throw ApiException(
          'Failed to fetch headers: ${response.statusCode} ${response.body}',
        );
      }
    } on http.ClientException catch (e) {
      throw ApiException('Network error: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to fetch headers: $e');
    }
  }

  // Filter-related methods removed - handled by backend SPV mode configuration

  Future<Map<String, dynamic>> getBlock(String blockHash) async {
    try {
      final uri = Uri.parse(AppConstants.getBlockEndpoint(blockHash));
      final response = await _client.get(uri).timeout(_defaultTimeout);
      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        if (jsonData is! Map<String, dynamic>) {
          throw ApiException('Invalid block response format');
        }
        return jsonData;
      } else if (response.statusCode == 404) {
        throw ApiException('Block not found: $blockHash');
      } else {
        throw ApiException(
          'Failed to fetch block: ${response.statusCode} ${response.body}',
        );
      }
    } on http.ClientException catch (e) {
      throw ApiException('Network error: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to fetch block: $e');
    }
  }

  // Merkle proof methods removed - not needed for current implementation

  // ==================== Transaction Broadcast API ====================

  Future<String> broadcastTransaction(String rawTx) async {
    try {
      final uri = Uri.parse(AppConstants.getBroadcastEndpoint());
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'raw_tx': rawTx}),
          )
          .timeout(_defaultTimeout);
      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        if (jsonData is! Map<String, dynamic>) {
          throw ApiException('Invalid broadcast response format');
        }
        final txid = jsonData['txid'] as String?;
        if (txid == null) {
          throw ApiException('No txid in broadcast response');
        }
        return txid;
      } else {
        throw ApiException('Transaction rejected: ${response.body}');
      }
    } on http.ClientException catch (e) {
      throw ApiException('Network error: $e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to broadcast transaction: $e');
    }
  }

  // ==================== UTXO Scanning ====================

  /// Scan UTXOs for given addresses within block range
  /// Backend automatically uses SPV mode (BIP158 filters) or direct scan based on .env configuration
  /// No need to specify mode - backend SPV_MODE setting controls the behavior
  Future<Map<String, dynamic>> scanUTXOs({
    required List<String> addresses,
    required int startHeight,
    required int endHeight,
  }) async {
    try {
      final uri = Uri.parse(AppConstants.getUTXOScanEndpoint());
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'addresses': addresses,
              'start_height': startHeight,
              'end_height': endHeight,
            }),
          )
          .timeout(_defaultTimeout);
      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        if (jsonData is! Map<String, dynamic>) {
          throw ApiException('Invalid UTXO scan response');
        }

        // Log scan statistics if available
        if (jsonData.containsKey('statistics')) {
          final stats = jsonData['statistics'];
          debugPrint('[API] UTXO Scan: mode=${stats['mode']}, '
              'filtered=${stats['blocks_filtered']}, '
              'scanned=${stats['blocks_scanned']}, '
              'time=${stats['scan_time_ms']}ms');
        }

        return jsonData;
      } else {
        throw ApiException('Failed to scan UTXOs: ${response.statusCode}');
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to scan UTXOs: $e');
    }
  }

  /// Get UTXOs for given addresses (alternative endpoint)
  Future<Map<String, dynamic>> getUTXOs(List<String> addresses) async {
    try {
      debugPrint('[API] Fetching UTXOs for ${addresses.length} addresses...');
      final uri = Uri.parse('$_baseUrl/utxos');
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'addresses': addresses}),
          )
          .timeout(_defaultTimeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('[API] Found ${data['count'] ?? 0} UTXOs');
        return data;
      } else {
        throw ApiException('UTXO fetch failed: ${response.statusCode}');
      }
    } catch (e) {
      throw ApiException('Failed to fetch UTXOs: $e');
    }
  }

  // ==================== Health Check ====================
  Future<bool> checkHealth() async {
    try {
      // Use empty hash to let backend provide starting point
      await getHeaders(startHash: '', count: 1);
      return true;
    } catch (e) {
      print('API health check failed: $e');
      return false;
    }
  }

  Future<ApiStatus> getStatus() async {
    try {
      final isHealthy = await checkHealth();
      return ApiStatus(
        isHealthy: isHealthy,
        baseUrl: _baseUrl,
        lastChecked: DateTime.now(),
      );
    } catch (e) {
      return ApiStatus(
        isHealthy: false,
        baseUrl: _baseUrl,
        lastChecked: DateTime.now(),
        error: e.toString(),
      );
    }
  }

  void dispose() {
    _client.close();
  }

  // ==================== OT Request (NEW 2-STAGE FLOW) ====================

  // [!! Old function removed !!]

  /// Call backend to create unsigned transaction and get sighashes
  Future<Map<String, dynamic>> buildUnsignedOTRequest({
    required Map<String, dynamic> options,
  }) async {
    try {
      print('Calling backend "buildotrequestsighashes" RPC...');
      final uri = Uri.parse('$_baseUrl/ot/build_sighashes');

      final rpcBody = {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'buildotrequestsighashes',
        'params': [options]
      };

      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(rpcBody),
          )
          .timeout(_defaultTimeout);

      final data = jsonDecode(response.body);

      if (data['error'] != null) {
        throw ApiException('Backend RPC error: ${data['error']['message']}');
      }

      if (response.statusCode == 200 && data['result'] != null) {
        print('Backend returned sighashes.');

        // Byte order conversion: little-endian -> big-endian
        final result = data['result'] as Map<String, dynamic>;

        if (result.containsKey('sighashes')) {
          final sighashes = result['sighashes'] as List;
          final correctedSighashes = sighashes.map((hexStr) {
            // Using BytesUtils requires importing blockchain_utils
            final bytes = BytesUtils.fromHexString(hexStr as String);
            final reversed = bytes.reversed.toList();
            return BytesUtils.toHexString(reversed);
          }).toList();

          result['sighashes'] = correctedSighashes;
          print('Converted ${correctedSighashes.length} sighash(es)');
        }

        return result;
      } else {
        final errorMsg =
            data['error']?['message'] as String? ?? 'Backend RPC error';
        throw ApiException(errorMsg);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to build unsigned request: $e');
    }
  }

  /// Call backend to broadcast signed transaction
  Future<Map<String, dynamic>> broadcastSignedOTRequest({
    required Map<String, dynamic> options,
    required List<String> signatures,
    required List<String> pubkeys,
  }) async {
    try {
      print('Calling backend "broadcastsignedotrequest" RPC...');
      final uri = Uri.parse('$_baseUrl/ot/broadcast_signed');

      final rpcBody = {
        'jsonrpc': '2.0',
        'id': 2, // [!! Fix !!] Changed from 'flutter_ot_broadcast' to 2 (int)
        'method': 'broadcastsignedotrequest',
        'params': [
          options,
          signatures,
          pubkeys,
        ]
      };

      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(rpcBody),
          )
          .timeout(_defaultTimeout);

      final data = jsonDecode(response.body);

      if (data['error'] != null) {
        throw ApiException('Backend RPC error: ${data['error']['message']}');
      }

      if (response.statusCode == 200 && data['result'] != null) {
        print('Backend broadcast successful.');
        return {'txid': data['result']};
      } else {
        final errorMsg =
            data['error']?['message'] as String? ?? 'Backend RPC error';
        throw ApiException(errorMsg);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to broadcast signed request: $e');
    }
  }

  Future<Map<String, dynamic>> buildUnsignedA2U({
    required Map<String, dynamic> options,
  }) async {
    try {
      print('Calling backend "builda2usighashes" RPC...');
      // Assuming your HTTP Middleware route is /ot/build_a2u_sighashes
      final uri = Uri.parse('$_baseUrl/ot/build_a2u_sighashes');

      final rpcBody = {
        'jsonrpc': '2.0',
        'id': 8,
        'method': 'builda2usighashes', // Corresponds to C++ RPC Command
        'params': [options]
      };

      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(rpcBody),
          )
          .timeout(_defaultTimeout);

      final data = jsonDecode(response.body);

      if (data['error'] != null) {
        throw ApiException('Backend RPC error: ${data['error']['message']}');
      }

      if (response.statusCode == 200 && data['result'] != null) {
        final result = data['result'] as Map<String, dynamic>;

        // [Critical Fix] Byte order conversion: Little-Endian (C++) -> Big-Endian (Dart Signer)
        if (result.containsKey('sighashes')) {
          final sighashes = result['sighashes'] as List;
          final correctedSighashes = sighashes.map((hexStr) {
            // Convert Hex to Bytes
            final bytes = BytesUtils.fromHexString(hexStr as String);
            // Reverse bytes (Little -> Big)
            final reversed = bytes.reversed.toList();
            // Convert back to Hex
            return BytesUtils.toHexString(reversed);
          }).toList();

          result['sighashes'] = correctedSighashes;
          print(
              'Converted ${correctedSighashes.length} A2U sighash(es) to Big-Endian');
        }

        // Ensure unsigned_tx_hex and fee are returned
        return result;
      } else {
        final errorMsg =
            data['error']?['message'] as String? ?? 'Backend RPC error';
        throw ApiException(errorMsg);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to build A2U: $e');
    }
  }

  /// Call backend to broadcast signed A2U transaction
  Future<Map<String, dynamic>> broadcastA2U({
    required Map<String, dynamic> options,
    required List<String> signatures,
    required List<String> pubkeys,
  }) async {
    try {
      print('Calling backend "broadcasta2u" RPC...');
      // Assuming your HTTP Middleware route is /ot/broadcast_a2u
      final uri = Uri.parse('$_baseUrl/ot/broadcast_a2u');

      final rpcBody = {
        'jsonrpc': '2.0',
        'id': 9,
        'method': 'broadcasta2u', // Corresponds to C++ RPC Command
        'params': [
          options, // Contains unsigned_tx_hex and inputs (for validation)
          signatures, // Signature list (Hex String)
          pubkeys, // Public key list (Hex String)
        ]
      };

      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(rpcBody),
          )
          .timeout(_defaultTimeout);

      final data = jsonDecode(response.body);

      if (data['error'] != null) {
        throw ApiException('Backend RPC error: ${data['error']['message']}');
      }

      if (response.statusCode == 200 && data['result'] != null) {
        print('Backend A2U broadcast successful.');
        // C++ RPC returns txid string directly, wrap it in Map to match Service layer expectation
        return {'txid': data['result']};
      } else {
        final errorMsg =
            data['error']?['message'] as String? ?? 'Backend RPC error';
        throw ApiException(errorMsg);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to broadcast A2U: $e');
    }
  }

  Future<Map<String, dynamic>> buildUnsignedOTProof({
    required Map<String, dynamic> options,
  }) async {
    try {
      print('Calling backend "buildotproofsighashes" RPC...');
      final uri = Uri.parse(
          '$_baseUrl/ot/build_proof_sighashes'); // <-- Changed endpoint

      final rpcBody = {
        'jsonrpc': '2.0',
        'id': 3, // New ID
        'method': 'buildotproofsighashes', // <-- Changed method
        'params': [options]
      };

      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(rpcBody),
          )
          .timeout(_defaultTimeout);

      final data = jsonDecode(response.body);

      if (data['error'] != null) {
        throw ApiException('Backend RPC error: ${data['error']['message']}');
      }

      if (response.statusCode == 200 && data['result'] != null) {
        print('Backend returned proof sighashes.');

        // Byte order conversion (Sighashes are always little-endian from C++)
        final result = data['result'] as Map<String, dynamic>;

        if (result.containsKey('sighashes')) {
          final sighashes = result['sighashes'] as List;
          final correctedSighashes = sighashes.map((hexStr) {
            // Using BytesUtils requires importing blockchain_utils
            final bytes = BytesUtils.fromHexString(hexStr as String);
            final reversed = bytes.reversed.toList();
            return BytesUtils.toHexString(reversed);
          }).toList();

          result['sighashes'] = correctedSighashes;
          print('Converted ${correctedSighashes.length} sighash(es)');
        }

        return result;
      } else {
        final errorMsg =
            data['error']?['message'] as String? ?? 'Backend RPC error';
        throw ApiException(errorMsg);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to build unsigned proof: $e');
    }
  }

  /// Call backend to broadcast signed OT Proof
  Future<Map<String, dynamic>> broadcastSignedOTProof({
    required Map<String, dynamic> options,
    required List<String> signatures,
    required List<String> pubkeys,
  }) async {
    try {
      print('Calling backend "broadcastsignedotproof" RPC...');
      final uri = Uri.parse(
          '$_baseUrl/ot/broadcast_proof_signed'); // <-- Changed endpoint

      final rpcBody = {
        'jsonrpc': '2.0',
        'id': 4, // New ID
        'method': 'broadcastsignedotproof', // <-- Changed method
        'params': [
          options,
          signatures,
          pubkeys,
        ]
      };

      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(rpcBody),
          )
          .timeout(_defaultTimeout);

      final data = jsonDecode(response.body);

      if (data['error'] != null) {
        throw ApiException('Backend RPC error: ${data['error']['message']}');
      }

      if (response.statusCode == 200 && data['result'] != null) {
        print('Backend proof broadcast successful.');
        return {'txid': data['result']};
      } else {
        final errorMsg =
            data['error']?['message'] as String? ?? 'Backend RPC error';
        throw ApiException(errorMsg);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to broadcast signed proof: $e');
    }
  }

  Future<List<dynamic>> listOTCycles({
    String? aid,
    int? minHeight,
    int? maxHeight,
    Map<String, dynamic>? options,
  }) async {
    try {
      print('Calling backend "listotcycles" RPC...');
      final uri = Uri.parse('$_baseUrl/ot/list_cycles'); // <-- New route

      // Build parameter list for C++ RPC
      // C++ accepts: ( "aid" minheight maxheight options )
      final List<dynamic> params = [];

      // 1. aid (If null or empty string, C++ treats it as "query all")
      params.add(aid ?? "");

      // 2. minHeight (C++ accepts null)
      params.add(minHeight);

      // 3. maxHeight (C++ accepts null)
      params.add(maxHeight);

      // 4. options (C++ accepts null)
      params.add(options);

      final rpcBody = {
        'jsonrpc': '2.0',
        'id': 5, // New ID
        'method': 'listotcycles',
        'params': params,
      };

      print('   [DEBUG] params: ${jsonEncode(params)}');

      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(rpcBody),
          )
          .timeout(_defaultTimeout);

      final data = jsonDecode(response.body);

      if (data['error'] != null) {
        throw ApiException('Backend RPC error: ${data['error']['message']}');
      }

      if (response.statusCode == 200 && data['result'] != null) {
        print('Backend returned ${data['result'].length} cycles.');
        // C++ RPC returns an array (VARR)
        return data['result'] as List<dynamic>;
      } else {
        final errorMsg =
            data['error']?['message'] as String? ?? 'Backend RPC error';
        throw ApiException(errorMsg);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to list OT cycles: $e');
    }
  }

  Future<List<dynamic>> listOTRequests({String? aid}) async {
    try {
      print('Calling backend "listotrequests" RPC... (AID: $aid)');
      final uri = Uri.parse('$_baseUrl/ot/list_requests');

      final List<dynamic> params = [];
      if (aid != null && aid.isNotEmpty) {
        params.add(aid); // C++ RPC expects an array
      }

      final rpcBody = {
        'jsonrpc': '2.0',
        'id': 6, // New ID
        'method': 'listotrequests',
        'params': params,
      };

      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(rpcBody),
          )
          .timeout(_defaultTimeout);

      final data = jsonDecode(response.body);

      if (data['error'] != null) {
        throw ApiException('Backend RPC error: ${data['error']['message']}');
      }

      if (response.statusCode == 200 && data['result'] != null) {
        print('Backend returned ${data['result'].length} pending requests.');
        return data['result'] as List<dynamic>;
      } else {
        final errorMsg =
            data['error']?['message'] as String? ?? 'Backend RPC error';
        throw ApiException(errorMsg);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to list OT requests: $e');
    }
  }

  Future<Map<String, dynamic>> getRequestCycles(
      String fromAid, String toAid) async {
    try {
      print('Calling backend "getrequestcycles" RPC for $fromAid -> $toAid');
      final uri = Uri.parse('$_baseUrl/ot/get_request_cycles');

      final rpcBody = {
        'jsonrpc': '2.0',
        'id': 7, // New ID
        'method': 'getrequestcycles',
        'params': [fromAid, toAid], //
      };

      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(rpcBody),
          )
          .timeout(_defaultTimeout);

      final data = jsonDecode(response.body);

      if (data['error'] != null) {
        throw ApiException('Backend RPC error: ${data['error']['message']}');
      }

      if (response.statusCode == 200 && data['result'] != null) {
        return data['result'] as Map<String, dynamic>;
      } else {
        final errorMsg =
            data['error']?['message'] as String? ?? 'Backend RPC error';
        throw ApiException(errorMsg);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to get request cycles: $e');
    }
  }
} // End ApiService class

class ApiStatus {
  final bool isHealthy;
  final String baseUrl;
  final DateTime lastChecked;
  final String? error;

  ApiStatus({
    required this.isHealthy,
    required this.baseUrl,
    required this.lastChecked,
    this.error,
  });

  @override
  String toString() {
    return 'ApiStatus(healthy: $isHealthy, url: $baseUrl, error: $error)';
  }
}

class ApiException implements Exception {
  final String message;

  ApiException(this.message);

  @override
  String toString() => 'ApiException: $message';
}
