import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/wallet_provider.dart';
import '../services/storage_service.dart';

/// Address information class
class AddressInfo {
  final String address;
  final int index;
  final BigInt balance;
  final int usageCount;
  final bool
      isChange; // true for change addresses, false for receiving addresses

  AddressInfo({
    required this.address,
    required this.index,
    required this.balance,
    required this.usageCount,
    required this.isChange,
  });
}

/// Complete address selector dialog
/// Display all used addresses (including receive and change addresses)
class AddressSelectorDialog extends StatefulWidget {
  const AddressSelectorDialog({
    super.key,
  });

  @override
  State<AddressSelectorDialog> createState() => _AddressSelectorDialogState();
}

class _AddressSelectorDialogState extends State<AddressSelectorDialog> {
  List<AddressInfo> _addresses = [];
  String? _selectedAddress;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final provider = context.read<WalletProvider>();
      final db = provider.databaseHelper;
      final hdWallet = provider.hdWalletService;
      final storage = StorageService.instance;

      // 1. Get last_external_index and last_internal_index
      final lastExternalIndex = await storage.getLastExternalIndex();
      final lastInternalIndex = await storage.getLastInternalIndex();

      debugPrint('Loading addresses:');
      debugPrint('   External (receive): 0 to $lastExternalIndex');
      debugPrint('   Internal (change): 0 to $lastInternalIndex');

      // 2. Generate all addresses and query balances
      final addresses = <AddressInfo>[];

      // Load external addresses (receiving addresses)
      for (int i = 0; i <= lastExternalIndex; i++) {
        try {
          // Derive address
          final walletAddr = await hdWallet.deriveAddress(i);

          // Query all UTXOs for this address
          final utxos = await db.getUTXOsByAddress(walletAddr.address);

          // Calculate balance
          final balance = utxos.fold<BigInt>(
            BigInt.zero,
            (sum, utxo) => sum + utxo.value,
          );

          addresses.add(AddressInfo(
            address: walletAddr.address,
            index: i,
            balance: balance,
            usageCount: utxos.length,
            isChange: false,
          ));

          debugPrint(
              '  [External $i] ${walletAddr.address} - $balance sats (${utxos.length} UTXOs)');
        } catch (e) {
          debugPrint('  Error loading external address at index $i: $e');
        }
      }

      // Load change addresses (internal addresses)
      for (int i = 0; i <= lastInternalIndex; i++) {
        try {
          // Derive change address
          final walletAddr = await hdWallet.deriveChangeAddress(i);

          // Query all UTXOs for this address
          final utxos = await db.getUTXOsByAddress(walletAddr.address);

          // Calculate balance
          final balance = utxos.fold<BigInt>(
            BigInt.zero,
            (sum, utxo) => sum + utxo.value,
          );

          addresses.add(AddressInfo(
            address: walletAddr.address,
            index: i,
            balance: balance,
            usageCount: utxos.length,
            isChange: true,
          ));

          debugPrint(
              '  [Change $i] ${walletAddr.address} - $balance sats (${utxos.length} UTXOs)');
        } catch (e) {
          debugPrint('  Error loading change address at index $i: $e');
        }
      }

      // 3. Sort by balance descending (addresses with balance first)
      addresses.sort((a, b) {
        // Sort by balance descending first
        final balanceCompare = b.balance.compareTo(a.balance);
        if (balanceCompare != 0) return balanceCompare;

        // If balance is same, sort by index ascending
        return a.index.compareTo(b.index);
      });

      setState(() {
        _addresses = addresses;
        _isLoading = false;
      });

      debugPrint('Loaded ${addresses.length} addresses');
    } catch (e) {
      debugPrint('Error loading addresses: $e');
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  String _formatSatoshis(BigInt sats) {
    if (sats == BigInt.zero) return '0 BTC';
    final btc = sats.toDouble() / 100000000;
    if (btc >= 1) {
      return '${btc.toStringAsFixed(8)} BTC';
    } else if (btc >= 0.001) {
      return '${(btc * 1000).toStringAsFixed(5)} mBTC';
    } else {
      return '$sats sats';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title bar
            Row(
              children: [
                const Icon(Icons.account_balance_wallet,
                    size: 28, color: Colors.blue),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Select Bitcoin Address',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),

            // Information text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Showing all receive and change addresses used in your wallet',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Address statistics
            if (!_isLoading && _addresses.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  'Found ${_addresses.length} addresses '
                  '(${_addresses.where((a) => !a.isChange).length} receive, '
                  '${_addresses.where((a) => a.isChange).length} change, '
                  '${_addresses.where((a) => a.balance > BigInt.zero).length} with balance)',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

            // Address list
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Loading addresses...'),
                        ],
                      ),
                    )
                  : _errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline,
                                  size: 64, color: Colors.red),
                              const SizedBox(height: 16),
                              Text(
                                'Error: $_errorMessage',
                                style: const TextStyle(color: Colors.red),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _loadAddresses,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : _addresses.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.inbox,
                                      size: 64, color: Colors.grey),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'No addresses found',
                                    style: TextStyle(
                                        fontSize: 16, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Your wallet has no transaction history yet',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _addresses.length,
                              itemBuilder: (context, index) {
                                final addr = _addresses[index];
                                final isSelected =
                                    _selectedAddress == addr.address;
                                final hasBalance = addr.balance > BigInt.zero;

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                      vertical: 4, horizontal: 4),
                                  color: isSelected
                                      ? Colors.blue.shade50
                                      : hasBalance
                                          ? Colors.green.shade50
                                          : Colors.white,
                                  elevation: isSelected ? 4 : 1,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    leading: CircleAvatar(
                                      backgroundColor: isSelected
                                          ? Colors.blue
                                          : hasBalance
                                              ? Colors.green
                                              : Colors.grey.shade300,
                                      child: Text(
                                        '${addr.index}',
                                        style: TextStyle(
                                          color: isSelected || hasBalance
                                              ? Colors.white
                                              : Colors.black,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            addr.address,
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 11,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        IconButton(
                                          icon:
                                              const Icon(Icons.copy, size: 16),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () {
                                            Clipboard.setData(ClipboardData(
                                                text: addr.address));
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'Address copied to clipboard'),
                                                duration: Duration(seconds: 1),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Row(
                                        children: [
                                          // Address type
                                          Text(
                                            addr.isChange
                                                ? 'Change'
                                                : 'Receive',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          // Balance
                                          Icon(
                                            Icons.account_balance,
                                            size: 14,
                                            color: hasBalance
                                                ? Colors.green
                                                : Colors.grey.shade600,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _formatSatoshis(addr.balance),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: hasBalance
                                                  ? Colors.green
                                                  : Colors.grey.shade600,
                                              fontWeight: hasBalance
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          // UTXO count
                                          Icon(
                                            Icons.filter_list,
                                            size: 14,
                                            color: Colors.grey.shade600,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${addr.usageCount} UTXO${addr.usageCount != 1 ? 's' : ''}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    trailing: isSelected
                                        ? const Icon(Icons.check_circle,
                                            color: Colors.blue, size: 28)
                                        : null,
                                    onTap: () {
                                      setState(() {
                                        _selectedAddress = addr.address;
                                      });
                                    },
                                  ),
                                );
                              },
                            ),
            ),

            // Bottom buttons
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _loadAddresses,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _selectedAddress == null
                          ? null
                          : () {
                              Navigator.of(context).pop(_selectedAddress);
                            },
                      child: const Text('Confirm Selection'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper function to show address selector dialog
Future<String?> showAddressSelectorDialog(BuildContext context) async {
  return await showDialog<String>(
    context: context,
    builder: (context) => const AddressSelectorDialog(),
  );
}
