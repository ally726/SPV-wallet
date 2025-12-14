import 'dart:convert';
import 'package:bitcoin_base/bitcoin_base.dart' hide UTXO;
import 'package:blockchain_utils/blockchain_utils.dart';
import '../models/utxo.dart';
import '../database/database_helper.dart';
import '../utils/constants.dart';
import 'api_services.dart' as local_api;
import 'hd_wallet_service.dart';

/// OT (Off-chain Transaction) Request Service
class OTRequestService {
  static final OTRequestService instance = OTRequestService._internal();

  final local_api.ApiService _api = local_api.ApiService.instance;
  final HDWalletService _walletService = HDWalletService.instance;
  final DatabaseHelper _db = DatabaseHelper.instance;

  OTRequestService._internal();

  factory OTRequestService() => instance;

  // Send OT Request
  Future<String> sendOTRequest({
    required String fromAid,
    required String toAid,
    required int amount,
  }) async {
    try {
      print('Sending OT Request:');
      print('   From: $fromAid');
      print('   To: $toAid');
      print('   Amount: $amount satoshis');

      // === Phase 1: Select UTXOs ===
      final inputs = await _selectUTXOsForRequest(amount);
      print('   Selected ${inputs.length} UTXOs for request');

      // === Phase 2: Prepare transaction data ===
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Get change address
      final changeAddressObj =
          await _walletService.getCurrentReceivingAddress();
      final changeAddress = changeAddressObj.address;

      // Build inputs array for backend
      final inputsJson = inputs.map((utxo) {
        return {
          'txid': utxo.txHash,
          'vout': utxo.vout,
          'value': utxo.value.toInt(),
          'scriptPubKey': utxo.scriptPubKey,
        };
      }).toList();

      final options = {
        'inputs': inputsJson,
        'from_aid': fromAid,
        'to_aid': toAid,
        'amount': amount,
        'timestamp': timestamp,
        'change_address': changeAddress,
      };

      print('   [DEBUG] Sending to buildotrequestsighashes:');
      print('   ${jsonEncode(options)}');

      // === Phase 3: Request backend to calculate sighashes ===
      print('Calling backend "buildotrequestsighashes" RPC...');

      final sighashResponse = await _api.buildUnsignedOTRequest(
        options: options,
      );

      print('Backend returned sighashes.');

      if (sighashResponse['sighashes'] == null) {
        throw OTRequestException('Backend did not return sighashes');
      }

      final List<String> sighashesHex =
          List<String>.from(sighashResponse['sighashes']);

      final String unsignedTxHex = sighashResponse['unsigned_tx_hex'];

      if (unsignedTxHex == null || unsignedTxHex.isEmpty) {
        throw OTRequestException('Backend did not return unsigned_tx_hex');
      }

      print('   [CRITICAL] Saved unsigned TX hex from backend');
      print('   [CRITICAL] This TX will be used in broadcast stage');
      print('   [CRITICAL] TX hex length: ${unsignedTxHex.length} chars');

      final double feeBTC = sighashResponse['fee'] ?? 0.0;

      print('   Backend calculated fee: ${feeBTC.toStringAsFixed(8)} BTC');
      print('   Received ${sighashesHex.length} sighashes from backend');

      // === Phase 4: Sign locally in frontend ===
      final List<String> signaturesHex = [];
      final List<String> pubkeysHex = [];

      print('\n   [DIRECT-SIGN] Using BitcoinKeySigner...');

      for (int i = 0; i < inputs.length; i++) {
        print('\n   [Input $i] Processing...');

        // Get address derivation info
        final derivationInfo =
            await _walletService.getAddressDerivationInfo(inputs[i].address);

        if (derivationInfo == null) {
          throw OTRequestException(
            'Cannot find derivation info for address: ${inputs[i].address}',
          );
        }

        // Re-derive full WalletAddress using derivation info
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

        // ========================================
        // [!! Address Verification !!]
        // ========================================
        print('   [ADDRESS-CHECK] Verifying key matches UTXO...');

        final pubKeyObj = ECPublic.fromBytes(
          BytesUtils.fromHexString(publicKeyHex),
        );
        final legacyAddress = pubKeyObj.toAddress();
        final derivedAddr = legacyAddress.toAddress(BitcoinNetwork.testnet);

        print('   [ADDRESS-CHECK] UTXO address:    ${inputs[i].address}');
        print('   [ADDRESS-CHECK] Derived address: $derivedAddr');

        if (derivedAddr != inputs[i].address) {
          throw OTRequestException('ADDRESS MISMATCH!\n'
              'UTXO address:    ${inputs[i].address}\n'
              'Derived address: $derivedAddr\n'
              'The private key does not match this UTXO!');
        }

        print('   [ADDRESS-CHECK] Address match confirmed!');

        // ========================================
        // [!! Sign with BitcoinKeySigner !!]
        // ========================================
        print('   [DIRECT-SIGN] Signing with BitcoinKeySigner...');

        final privateKeyBytes = BytesUtils.fromHexString(privateKeyHex);
        final sighashBytes = BytesUtils.fromHexString(sighashesHex[i]);

        print('   [DIRECT-SIGN] Sighash: ${sighashesHex[i]}');

        final signer = BitcoinKeySigner.fromKeyBytes(privateKeyBytes);
        final derSignature = signer.signECDSADerConst(sighashBytes);

        print(
            '   [DIRECT-SIGN] DER signature: ${BytesUtils.toHexString(derSignature)}');

        // 5. Add SIGHASH_ALL
        final signatureWithSighash = [...derSignature, 0x01];
        final signatureHex = BytesUtils.toHexString(signatureWithSighash);

        print('   [DIRECT-SIGN] With SIGHASH_ALL: $signatureHex');

        // 6. Verify signature format
        if (!signatureHex.startsWith('30')) {
          throw OTRequestException(
              'Invalid signature: does not start with 0x30 (DER)');
        }

        if (!signatureHex.endsWith('01')) {
          throw OTRequestException(
              'Invalid signature: does not end with 0x01 (SIGHASH_ALL)');
        }

        // 7. Verify signature locally
        print('   [VERIFY-TEST] Testing signature locally...');
        final publicKey =
            ECPublic.fromBytes(BytesUtils.fromHexString(publicKeyHex));

        try {
          final verify = publicKey.verifyDerSignature(
            digest: sighashBytes,
            signature: derSignature,
          );
          print('   [VERIFY-TEST] Verify against sighash: $verify');

          if (!verify) {
            throw OTRequestException('Local signature verification failed!');
          }

          print('   [VERIFY-TEST] Signature is correct!');
        } catch (e) {
          print('   [VERIFY-TEST] Error: $e');
          throw OTRequestException('Local signature verification error: $e');
        }

        signaturesHex.add(signatureHex);
        pubkeysHex.add(publicKeyHex);

        print('   Input $i signed successfully');
      }

      print('\n   All ${inputs.length} inputs signed');

      // === Phase 5: Send signatures back to backend for broadcast ===

      final optionsForBroadcast = {
        'unsigned_tx_hex': unsignedTxHex,
        'inputs': inputsJson,
      };

      print('\n   [DEBUG] Sending to broadcastsignedotrequest:');
      print('   - unsigned_tx_hex: ${unsignedTxHex.substring(0, 40)}...');
      print('   - inputs count: ${inputsJson.length}');
      print('   - signatures count: ${signaturesHex.length}');
      print('   - pubkeys count: ${pubkeysHex.length}');

      final broadcastResult = await _api.broadcastSignedOTRequest(
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
        throw OTRequestException('Broadcast failed: no txid returned');
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

  /// Select UTXOs for OT Request (Restore your original version)
  Future<List<UTXO>> _selectUTXOsForRequest(int targetAmount) async {
    // 1. Get available UTXOs
    final List<UTXO> availableUTXOs = await _db.getSpendableUTXOs();

    if (availableUTXOs.isEmpty) {
      throw OTRequestException('No spendable UTXOs available');
    }

    // 2. Use UTXOSelector
    //    We use AppConstants.defaultFeeRate to estimate fees
    try {
      // Note: When estimating fees here, we usually need to add the transaction amount itself
      // But your original logic seems to use targetAmount as the total amount including fees?
      // Or targetAmount is just the amount to transfer (OT Request is actually just Data, the amount is written in OP_RETURN)
      // In the OT Request case, we only need enough to pay the "fee".
      // So passing in about 2000 sats here should be enough, instead of the large number in OP_RETURN.
      // But to keep it as is, I'll write it as you posted.
      final List<UTXO> selectedUTXOs = UTXOSelector.selectUTXOs(
        availableUTXOs: availableUTXOs,
        targetAmount: BigInt.from(targetAmount < 2000
            ? 2000
            : targetAmount), // Ensure at least fee is covered
        feeRate: AppConstants.defaultFeeRate,
      );

      if (selectedUTXOs.isEmpty) {
        throw OTRequestException('UTXO selection returned empty list');
      }

      return selectedUTXOs;
    } catch (e) {
      // Catch exceptions thrown by UTXOSelector (e.g., insufficient funds)
      print('UTXO selection failed: $e');
      throw OTRequestException('UTXO selection failed: $e');
    }
  }
}

/// OT Request Exception
class OTRequestException implements Exception {
  final String message;
  OTRequestException(this.message);

  @override
  String toString() => 'OTRequestException: $message';
}
