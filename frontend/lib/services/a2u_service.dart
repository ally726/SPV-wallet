// lib/services/a2u_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:blockchain_utils/blockchain_utils.dart';
import '../models/utxo.dart';
import '../database/database_helper.dart';
import '../utils/constants.dart';
import 'api_services.dart' as local_api;
import 'hd_wallet_service.dart';

/// A2U (Any-to-User) Transaction Service
/// Used to create transactions signed with SIGHASH_A2U | SIGHASH_ANYONECANPAY (0x84)
class A2UService {
  static final A2UService instance = A2UService._internal();

  final local_api.ApiService _api = local_api.ApiService.instance;
  final HDWalletService _walletService = HDWalletService.instance;
  final DatabaseHelper _db = DatabaseHelper.instance;

  // Define A2U Sighash Type (0x04 | 0x80 = 0x84)
  static const int SIGHASH_A2U_ANYONECANPAY = 0x84;

  A2UService._internal();

  factory A2UService() => instance;

  /// Send A2U Transaction
  /// [toAddress]: Usually the App's own address, used to receive this output
  /// [amount]: Amount (usually small, e.g., dust limit)
  Future<String> sendA2UTransaction({
    required String toAddress,
    required int amount,
  }) async {
    try {
      print('Starting A2U Transaction...');
      print('   To: $toAddress');
      print('   Amount: $amount satoshis');

      // === Phase 1: Select UTXOs ===
      // A2U transactions are mainly to allow others to add Inputs, but the initiator usually needs to pay the initial fee
      // Here we select UTXOs sufficient to pay amount + estimated fee
      final inputs = await _selectUTXOsForA2U(amount);
      print('   Selected ${inputs.length} UTXOs for A2U');

      // === Phase 2: Prepare parameters for backend ===
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

      final options = {
        'inputs': inputsJson,
        'to_address': toAddress,
        'amount': amount,
        'change_address': changeAddress,
      };

      print('   [DEBUG] Sending to builda2usighashes:');
      print('   ${jsonEncode(options)}');

      // === Phase 3: Request backend to calculate sighashes (backend will use 0x84) ===
      print('Calling backend "builda2usighashes" RPC...');

      final sighashResponse = await _api.buildUnsignedA2U(
        options: options,
      );

      print('Backend returned A2U sighashes.');

      if (sighashResponse['sighashes'] == null) {
        throw A2UException('Backend did not return sighashes');
      }

      final List<String> sighashesHex =
          List<String>.from(sighashResponse['sighashes']);
      final String unsignedTxHex = sighashResponse['unsigned_tx_hex'];

      if (unsignedTxHex == null || unsignedTxHex.isEmpty) {
        throw A2UException('Backend did not return unsigned_tx_hex');
      }

      print('   [CRITICAL] Saved unsigned TX hex from backend');

      final double feeBTC = sighashResponse['fee'] ?? 0.0;
      print('   Backend calculated fee: ${feeBTC.toStringAsFixed(8)} BTC');

      // === Phase 4: Sign locally in frontend (Critical Step) ===
      final List<String> signaturesHex = [];
      final List<String> pubkeysHex = [];

      print('\n   [DIRECT-SIGN] (A2U) Signing with 0x84...');

      for (int i = 0; i < inputs.length; i++) {
        print('\n   [Input $i] Processing...');

        // 1. Get Private Key (Same process as OT Request)
        final derivationInfo =
            await _walletService.getAddressDerivationInfo(inputs[i].address);
        if (derivationInfo == null) {
          throw A2UException(
              'Cannot find derivation info for: ${inputs[i].address}');
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

        // 2. Sign
        print('   [DIRECT-SIGN] Signing with BitcoinKeySigner...');
        final privateKeyBytes = BytesUtils.fromHexString(privateKeyHex);
        final sighashBytes = BytesUtils.fromHexString(sighashesHex[i]);

        final signer = BitcoinKeySigner.fromKeyBytes(privateKeyBytes);
        final derSignature = signer.signECDSADerConst(sighashBytes);

        // [!!!! CRITICAL FIX !!!!]
        // Normal transaction appends 0x01 (SIGHASH_ALL)
        // A2U transaction MUST append 0x84 (SIGHASH_A2U | SIGHASH_ANYONECANPAY)
        // So backend broadcasta2u gets correct validation rule when reading last byte
        final signatureWithSighash =
            Uint8List.fromList([...derSignature, SIGHASH_A2U_ANYONECANPAY]);

        final signatureHex = BytesUtils.toHexString(signatureWithSighash);

        print('   [DIRECT-SIGN] Appending 0x84: $signatureHex');

        // Simple format check
        if (!signatureHex.endsWith('84')) {
          throw A2UException(
              'Signature creation failed: did not end with 0x84');
        }

        signaturesHex.add(signatureHex);
        pubkeysHex.add(publicKeyHex);

        print('   (A2U) Input $i signed successfully');
      }

      // === Phase 5: Broadcast (Call broadcasta2u) ===
      final optionsForBroadcast = {
        'unsigned_tx_hex': unsignedTxHex,
        'inputs': inputsJson,
      };

      print('\n   [DEBUG] Sending to broadcasta2u...');

      final broadcastResult = await _api.broadcastA2U(
        options: optionsForBroadcast,
        signatures: signaturesHex,
        pubkeys: pubkeysHex,
      );

      final String txid;
      if (broadcastResult.containsKey('txid') &&
          broadcastResult['txid'] != null) {
        txid = broadcastResult['txid'].toString();
      } else if (broadcastResult is String) {
        txid = broadcastResult as String;
      } else {
        throw A2UException('Broadcast failed: no txid returned');
      }

      print('Transaction broadcasted: $txid');

      // Clean up UTXO
      print('   Cleaning up spent UTXOs...');
      for (final utxo in inputs) {
        await _db.deleteUTXO(utxo.txHash, utxo.vout);
      }

      return txid;
    } catch (e, stackTrace) {
      print('Error: $e');
      print('   Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Select UTXO
  Future<List<UTXO>> _selectUTXOsForA2U(int targetAmount) async {
    final List<UTXO> availableUTXOs = await _db.getSpendableUTXOs();
    if (availableUTXOs.isEmpty) {
      throw A2UException('No spendable UTXOs available');
    }

    try {
      // Assume we need to pay a small fee, so add 2000 sats buffer
      // Actual logic depends on UTXOSelector implementation
      final List<UTXO> selectedUTXOs = UTXOSelector.selectUTXOs(
        availableUTXOs: availableUTXOs,
        targetAmount: BigInt.from(targetAmount + 2000),
        feeRate: AppConstants.defaultFeeRate,
      );

      if (selectedUTXOs.isEmpty) {
        throw A2UException('UTXO selection returned empty list');
      }
      return selectedUTXOs;
    } catch (e) {
      print('UTXO selection failed: $e');
      throw A2UException('UTXO selection failed: $e');
    }
  }
}

class A2UException implements Exception {
  final String message;
  A2UException(this.message);
  @override
  String toString() => 'A2UException: $message';
}
