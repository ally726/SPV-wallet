import '../database/database_helper.dart';
import '../models/utxo.dart';
import '../utils/constants.dart';
import 'hd_wallet_service.dart';

/// Address information for AID binding
class UsedAddress {
  final String address;
  final int derivationIndex;
  final AddressType addressType;
  final int
      usageCount; // Number of times this address has been used (UTXO count)
  final BigInt totalReceived; // Total amount received by this address
  final BigInt currentBalance; // Current balance

  UsedAddress({
    required this.address,
    required this.derivationIndex,
    required this.addressType,
    required this.usageCount,
    required this.totalReceived,
    required this.currentBalance,
  });

  @override
  String toString() {
    return 'UsedAddress(address: $address, index: $derivationIndex, '
        'usage: $usageCount, balance: $currentBalance sats)';
  }
}

/// Address Selector Service
/// Used to get used receiving addresses (excluding change addresses)
class AddressSelectorService {
  final DatabaseHelper _db;
  final HDWalletService _hdWallet;

  AddressSelectorService({
    required DatabaseHelper databaseHelper,
    required HDWalletService walletService,
  })  : _db = databaseHelper,
        _hdWallet = walletService;

  /// Get all used receiving addresses (excluding change addresses)
  /// Sorted by usage frequency and amount
  Future<List<UsedAddress>> getUsedReceiveAddresses() async {
    try {
      // 1. Get all non-change address UTXOs from database
      final db = await _db.database;
      final results = await db.query(
        'utxos',
        where: 'is_change = ?',
        whereArgs: [0], // 0 = Receive address, 1 = Change address
      );

      if (results.isEmpty) {
        print('No receive addresses have been used yet');
        return [];
      }

      // 2. Group by address and count
      final Map<String, List<UTXO>> addressUtxoMap = {};
      for (final row in results) {
        final utxo = UTXO.fromMap(row);
        if (!addressUtxoMap.containsKey(utxo.address)) {
          addressUtxoMap[utxo.address] = [];
        }
        addressUtxoMap[utxo.address]!.add(utxo);
      }

      // 3. Create UsedAddress object for each address
      final List<UsedAddress> usedAddresses = [];

      for (final entry in addressUtxoMap.entries) {
        final address = entry.key;
        final utxos = entry.value;

        // Calculate statistics
        final usageCount = utxos.length;
        final totalReceived = utxos.fold<BigInt>(
          BigInt.zero,
          (sum, utxo) => sum + utxo.value,
        );
        final currentBalance =
            totalReceived; // Assuming all in UTXO table are unspent

        // Get info from first UTXO (UTXOs of same address have same derivationIndex and addressType)
        final firstUtxo = utxos.first;

        usedAddresses.add(UsedAddress(
          address: address,
          derivationIndex: firstUtxo.derivationIndex,
          addressType: firstUtxo.addressType,
          usageCount: usageCount,
          totalReceived: totalReceived,
          currentBalance: currentBalance,
        ));
      }

      // 4. Sort: Prioritize addresses with high usage and large balance
      usedAddresses.sort((a, b) {
        // First sort by balance descending
        final balanceCompare = b.currentBalance.compareTo(a.currentBalance);
        if (balanceCompare != 0) return balanceCompare;

        // If balance same, sort by usage count descending
        final usageCompare = b.usageCount.compareTo(a.usageCount);
        if (usageCompare != 0) return usageCompare;

        // If all same, sort by derivation index ascending (earlier generated addresses first)
        return a.derivationIndex.compareTo(b.derivationIndex);
      });

      print('Found ${usedAddresses.length} used receive addresses');
      return usedAddresses;
    } catch (e) {
      print('Error getting used addresses: $e');
      return [];
    }
  }

  /// Get all receiving addresses within specified range (including unused)
  /// Used to display complete address list
  Future<List<UsedAddress>> getAllReceiveAddressesUpToIndex(
      int maxIndex) async {
    try {
      final List<UsedAddress> addresses = [];

      // Get UTXO info from database (for statistics)
      final usedAddresses = await getUsedReceiveAddresses();
      final usedAddressMap = {
        for (var addr in usedAddresses) addr.address: addr
      };

      // Generate all receiving addresses from 0 to maxIndex
      for (int i = 0; i <= maxIndex; i++) {
        final walletAddr = await _hdWallet.deriveAddress(i);
        final address = walletAddr.address;

        // If address used, use statistics; otherwise use default values
        if (usedAddressMap.containsKey(address)) {
          addresses.add(usedAddressMap[address]!);
        } else {
          addresses.add(UsedAddress(
            address: address,
            derivationIndex: i,
            addressType: walletAddr.addressType,
            usageCount: 0,
            totalReceived: BigInt.zero,
            currentBalance: BigInt.zero,
          ));
        }
      }

      return addresses;
    } catch (e) {
      print('Error getting all addresses: $e');
      return [];
    }
  }

  /// Get current latest receiving address index
  Future<int> getLastExternalIndex() async {
    try {
      final db = await _db.database;
      final result = await db.rawQuery(
        'SELECT MAX(derivation_index) as maxIndex FROM utxos WHERE is_change = 0',
      );

      if (result.isNotEmpty && result.first['maxIndex'] != null) {
        return result.first['maxIndex'] as int;
      }
      return 0;
    } catch (e) {
      print('Error getting last external index: $e');
      return 0;
    }
  }

  /// Get wallet master address (index 0)
  Future<UsedAddress?> getMasterAddress() async {
    try {
      final walletAddr = await _hdWallet.deriveAddress(0);
      final allUsed = await getUsedReceiveAddresses();

      // Find address statistics for index 0
      final masterUsed = allUsed.firstWhere(
        (addr) => addr.derivationIndex == 0,
        orElse: () => UsedAddress(
          address: walletAddr.address,
          derivationIndex: 0,
          addressType: walletAddr.addressType,
          usageCount: 0,
          totalReceived: BigInt.zero,
          currentBalance: BigInt.zero,
        ),
      );

      return masterUsed;
    } catch (e) {
      print('Error getting master address: $e');
      return null;
    }
  }

  /// Validate if address belongs to current wallet's receiving addresses
  Future<bool> isOwnReceiveAddress(String address) async {
    try {
      final lastIndex = await getLastExternalIndex();

      // Check all receiving addresses from 0 to lastIndex
      for (int i = 0; i <= lastIndex; i++) {
        final walletAddr = await _hdWallet.deriveAddress(i);
        if (walletAddr.address == address) {
          return true;
        }
      }

      return false;
    } catch (e) {
      print('Error validating address: $e');
      return false;
    }
  }

  /// Filter by address type
  Future<List<UsedAddress>> getUsedAddressesByType(
      AddressType addressType) async {
    final allAddresses = await getUsedReceiveAddresses();
    return allAddresses
        .where((addr) => addr.addressType == addressType)
        .toList();
  }

  /// Get addresses with balance
  Future<List<UsedAddress>> getAddressesWithBalance() async {
    final allAddresses = await getUsedReceiveAddresses();
    return allAddresses
        .where((addr) => addr.currentBalance > BigInt.zero)
        .toList();
  }
}
