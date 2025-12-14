// lib/services/ot_proof_service.dart
// Service for handling OT Proof

import 'dart:convert';
import 'dart:typed_data'; // For Uint8List
import 'package:bitcoin_base/bitcoin_base.dart' hide UTXO;
import 'package:blockchain_utils/blockchain_utils.dart';
import '../models/utxo.dart';
import '../database/database_helper.dart';
import '../utils/constants.dart';
import 'api_services.dart' as local_api;
import 'hd_wallet_service.dart';
import 'transaction_service.dart'; // For UTXOSelector

/// OT (Off-chain Transaction) Proof Service
class OTProofService {
  static final OTProofService instance = OTProofService._internal();

  final local_api.ApiService _api = local_api.ApiService.instance;
  final HDWalletService _walletService = HDWalletService.instance;
  final DatabaseHelper _db = DatabaseHelper.instance;

  OTProofService._internal();

  factory OTProofService() => instance;

  /// Send OT Proof
  Future<String> sendOTProof({
    required String requestTxid,
    required int balance,
    required int offsetAmount,
  }) async {
    try {
      print('Starting 2-stage OT Proof...');
      print('   Request TXID: $requestTxid');
      print('   Balance: $balance, Offset: $offsetAmount');

      // === Phase 1: Select UTXOs ===
      // We use 'offsetAmount' as the base amount to select UTXOs
      final inputs = await _selectUTXOsForProof(offsetAmount);
      print('   Selected ${inputs.length} UTXOs for proof');

      // === Phase 2: Prepare transaction data ===
      final changeAddressObj =
          await _walletService.getCurrentReceivingAddress();
      final changeAddress = changeAddressObj.address;

      final inputsJson = inputs.map((utxo) {
        return {
          'txid': utxo.txHash,
          'vout': utxo.vout,
          'value': utxo.value.toInt(),
          'scriptPubKey': utxo.scriptPubKey,
        };
      }).toList();

      // Prepare parameters for buildotproofsighashes
      final options = {
        'inputs': inputsJson,
        'request_txid': requestTxid,
        'balance': balance,
        'offset_amount': offsetAmount,
        'change_address': changeAddress,
      };

      print('   [DEBUG] Sending to buildotproofsighashes:');
      print('   ${jsonEncode(options)}');

      // === Phase 3: Request backend to calculate sighashes ===
      print('Calling backend "buildotproofsighashes" RPC...');

      // Call new API endpoint
      final sighashResponse = await _api.buildUnsignedOTProof(
        options: options,
      );

      print('Backend returned proof sighashes.');

      if (sighashResponse['sighashes'] == null) {
        throw OTProofException('Backend did not return sighashes');
      }

      final List<String> sighashesHex =
          List<String>.from(sighashResponse['sighashes']);
      final String unsignedTxHex = sighashResponse['unsigned_tx_hex'];

      if (unsignedTxHex == null || unsignedTxHex.isEmpty) {
        throw OTProofException('Backend did not return unsigned_tx_hex');
      }

      print('   [CRITICAL] Saved unsigned PROOF TX hex from backend');

      final double feeBTC = sighashResponse['fee'] ?? 0.0;
      print('   Backend calculated fee: ${feeBTC.toStringAsFixed(8)} BTC');
      print('   Received ${sighashesHex.length} sighashes from backend');

      // === Phase 4: Sign locally in frontend ===
      final List<String> signaturesHex = [];
      final List<String> pubkeysHex = [];

      print('\n   [DIRECT-SIGN] (Proof) Using BitcoinKeySigner...');

      for (int i = 0; i < inputs.length; i++) {
        print('\n   [Input $i] Processing...');

        final derivationInfo =
            await _walletService.getAddressDerivationInfo(inputs[i].address);
        if (derivationInfo == null) {
          throw OTProofException(
            'Cannot find derivation info for address: ${inputs[i].address}',
          );
        }

        final WalletAddress walletAddress;
        if (derivationInfo.isChange) {
          walletAddress = await _walletService.deriveChangeAddress(
            derivationInfo.index,
            addressType: derivationInfo.addressType,
          );
        } else {
          walletAddress = await _walletService.deriveAddress(
            derivationInfo.index,
            addressType: derivationInfo.addressType,
          );
        }

        final privateKeyHex = walletAddress.privateKey;
        final publicKeyHex = walletAddress.publicKey;

        // Address check
        print('   [ADDRESS-CHECK] (Proof) Verifying key matches UTXO...');
        final pubKeyObj = ECPublic.fromBytes(
          BytesUtils.fromHexString(publicKeyHex),
        );
        final legacyAddress = pubKeyObj.toAddress();
        final derivedAddr = legacyAddress.toAddress(BitcoinNetwork.testnet);
        print('   [ADDRESS-CHECK] UTXO address:    ${inputs[i].address}');
        print('   [ADDRESS-CHECK] Derived address: $derivedAddr');
        if (derivedAddr != inputs[i].address) {
          throw OTProofException('ADDRESS MISMATCH!\n'
              'UTXO address:    ${inputs[i].address}\n'
              'Derived address: $derivedAddr\n'
              'The private key does not match this UTXO!');
        }
        print('   [ADDRESS-CHECK] (Proof) Address match confirmed!');

        // Sign
        print('   [DIRECT-SIGN] (Proof) Signing with BitcoinKeySigner...');
        final privateKeyBytes = BytesUtils.fromHexString(privateKeyHex);
        final sighashBytes = BytesUtils.fromHexString(sighashesHex[i]);
        final signer = BitcoinKeySigner.fromKeyBytes(privateKeyBytes);
        final derSignature = signer.signECDSADerConst(sighashBytes);
        final signatureWithSighash =
            Uint8List.fromList([...derSignature, 0x01]); // SIGHASH_ALL
        final signatureHex = BytesUtils.toHexString(signatureWithSighash);

        // Format validation
        if (!signatureHex.startsWith('30')) {
          throw OTProofException(
              'Invalid signature: does not start with 0x30 (DER)');
        }
        if (!signatureHex.endsWith('01')) {
          throw OTProofException(
              'Invalid signature: does not end with 0x01 (SIGHASH_ALL)');
        }

        // Local verification
        print('   [VERIFY-TEST] (Proof) Testing signature locally...');
        final publicKey =
            ECPublic.fromBytes(BytesUtils.fromHexString(publicKeyHex));
        try {
          final verify = publicKey.verifyDerSignature(
            digest: sighashBytes,
            signature: derSignature,
          );
          print('   [VERIFY-TEST] Verify against sighash: $verify');

          if (!verify) {
            throw OTProofException('Local signature verification failed!');
          }

          print('   [VERIFY-TEST] (Proof) Signature is correct!');
        } catch (e) {
          print('   [VERIFY-TEST] Error: $e');
          throw OTProofException('Local signature verification error: $e');
        }

        signaturesHex.add(signatureHex);
        pubkeysHex.add(publicKeyHex);

        print('   (Proof) Input $i signed successfully');
      }

      print('\n   (Proof) All ${inputs.length} inputs signed');

      // === Phase 5: Send signatures back to backend for broadcast ===
      final optionsForBroadcast = {
        'unsigned_tx_hex': unsignedTxHex, // ← Critical!
        'inputs': inputsJson, // For validation
      };

      print('\n   [DEBUG] Sending to broadcastsignedotproof:');
      print('   - unsigned_tx_hex: ${unsignedTxHex.substring(0, 40)}...');
      print('   - inputs count: ${inputsJson.length}');
      print('   - signatures count: ${signaturesHex.length}');
      print('   - pubkeys count: ${pubkeysHex.length}');

      // Call new API endpoint
      final broadcastResult = await _api.broadcastSignedOTProof(
        options: optionsForBroadcast,
        signatures: signaturesHex,
        pubkeys: pubkeysHex,
      );

      // Handle return value
      final String txid;
      if (broadcastResult.containsKey('txid') &&
          broadcastResult['txid'] != null) {
        txid = broadcastResult['txid'].toString();
      } else if (broadcastResult is String) {
        txid = broadcastResult as String;
      } else {
        throw OTProofException('Broadcast failed: no txid returned');
      }

      print('Transaction broadcasted: $txid');

      print('   Cleaning up spent UTXOs from local DB...');
      for (final utxo in inputs) {
        await _db.deleteUTXO(utxo.txHash, utxo.vout);
      }
      print('   Local DB cleaned up.');

      return txid;
    } catch (e, stackTrace) {
      print('Error: $e');
      print('   Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Select UTXOs for OT Proof
  /// This is shared logic copied from ot_request_service.dart
  Future<List<UTXO>> _selectUTXOsForProof(int targetAmount) async {
    // 1. Get available UTXOs
    final List<UTXO> availableUTXOs = await _db.getSpendableUTXOs();

    if (availableUTXOs.isEmpty) {
      throw OTProofException('No spendable UTXOs available');
    }

    // 2. Use UTXOSelector
    try {
      final List<UTXO> selectedUTXOs = UTXOSelector.selectUTXOs(
        availableUTXOs: availableUTXOs,
        targetAmount: BigInt.from(targetAmount), // Convert to BigInt
        feeRate: AppConstants.defaultFeeRate,
      );

      if (selectedUTXOs.isEmpty) {
        throw OTProofException('UTXO selection returned empty list');
      }

      return selectedUTXOs;
    } catch (e) {
      // Catch exceptions thrown by UTXOSelector (e.g., insufficient funds)
      print('UTXO selection failed: $e');
      throw OTProofException('UTXO selection failed: $e');
    }
  }
}

/// OT Proof Exception
/// Copied and renamed from ot_request_service.dart
class OTProofException implements Exception {
  final String message;
  OTProofException(this.message);

  @override
  String toString() => 'OTProofException: $message';
}
