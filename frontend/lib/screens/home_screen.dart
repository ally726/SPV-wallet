import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/wallet_provider.dart';
import '../services/aid_service.dart';
import '../services/aid_crypto_service.dart';
import 'debug_screen.dart';
import 'aid_list_screen.dart';
import '../services/a2u_service.dart';

/// Main wallet home screen
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _sendAddressController = TextEditingController();
  final _sendAmountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeWallet();
  }

  Future<void> _initializeWallet() async {
    final provider = context.read<WalletProvider>();

    try {
      await provider.initializeWallet();
    } catch (e) {
      if (mounted) {
        _showError('Failed to initialize wallet: $e');
      }
    }
  }

  @override
  void dispose() {
    _sendAddressController.dispose();
    _sendAmountController.dispose();
    super.dispose();
  }

  Future<void> _syncWallet() async {
    final provider = context.read<WalletProvider>();

    try {
      await provider.startSync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync completed!')),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Sync failed: $e');
      }
    }
  }

  void _openDebugScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const DebugScreen(),
      ),
    );
  }

  void _openAIDScreen() {
    // Initialize AID service
    final aidService = AIDService(
      crypto: AIDCryptoService(),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AIDListScreen(
          aidService: aidService,
        ),
      ),
    );
  }

  Future<void> _getNewAddress() async {
    final provider = context.read<WalletProvider>();

    try {
      final address = await provider.getNewAddress();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('New address: $address')),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to generate address: $e');
      }
    }
  }

  Future<void> _sendTransaction() async {
    final address = _sendAddressController.text.trim();
    final amountStr = _sendAmountController.text.trim();

    if (address.isEmpty || amountStr.isEmpty) {
      _showError('Please enter address and amount');
      return;
    }

    final provider = context.read<WalletProvider>();

    try {
      final amount = provider.btcToSatoshi(amountStr);

      final txid = await provider.sendTransaction(
        recipientAddress: address,
        amount: amount,
        feeRate: 5,
      );

      if (mounted) {
        _sendAddressController.clear();
        _sendAmountController.clear();

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('✅ Transaction Sent'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Transaction ID:'),
                const SizedBox(height: 8),
                SelectableText(
                  txid,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to send transaction: $e');
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50], // Force light background
      appBar: AppBar(
        title: const Text('SPV Wallet'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.badge),
            onPressed: () => _openAIDScreen(),
            tooltip: 'AID Identity',
          ),
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () => _openDebugScreen(),
            tooltip: 'Debug Panel',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _syncWallet,
            tooltip: 'Sync blockchain',
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfoDialog(),
            tooltip: 'Info',
          ),
        ],
      ),
      body: Consumer<WalletProvider>(
        builder: (context, wallet, child) {
          if (!wallet.isInitialized) {
            return const Center(child: CircularProgressIndicator());
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Balance Card
                _buildBalanceCard(wallet),
                const SizedBox(height: 16),

                // Current Address Card
                _buildAddressCard(wallet),
                const SizedBox(height: 16),

                // Sync Status
                _buildSyncStatus(wallet),
                const SizedBox(height: 24),

                // // OT Request Section
                _buildMyActivitySection(),
                _buildOTRequestSection(),
                const SizedBox(height: 16),

                //a2u
                _buildA2UTestSection(),
                const SizedBox(height: 16),

                // OT Proof Section
                // _buildOTProofSection(),
                // const SizedBox(height: 24),

                // //scanner
                // _buildOTCycleListSection(),

                // Send Section
                _buildSendSection(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBalanceCard(WalletProvider wallet) {
    return Card(
      elevation: 4,
      color: Colors.white, // Force white background
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              'Balance',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${wallet.satoshiToBTC(wallet.balance)} BTC',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Confirmed: ${wallet.satoshiToBTC(wallet.confirmedBalance)} BTC',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
            // show pending change if any
            if (wallet.pendingChangeAmount > BigInt.zero)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Unconfirmed Change : ${wallet.satoshiToBTC(wallet.pendingChangeAmount)} BTC',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.orange[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressCard(WalletProvider wallet) {
    return Card(
      color: Colors.white, // Force white background
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Receiving Address',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: _getNewAddress,
                  tooltip: 'Get new address',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      wallet.currentAddress ?? 'No address',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () {
                      if (wallet.currentAddress != null) {
                        Clipboard.setData(
                          ClipboardData(text: wallet.currentAddress!),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied to clipboard')),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncStatus(WalletProvider wallet) {
    return Card(
      color: Colors.white, // Force white background
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              wallet.isSyncing ? Icons.sync : Icons.check_circle,
              color: wallet.isSyncing ? Colors.orange : Colors.green,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    wallet.isSyncing ? 'Syncing...' : 'Synced',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    'Block height: ${wallet.syncHeight}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSendSection() {
    return Card(
      color: Colors.white, // Force white background
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Send Bitcoin',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _sendAddressController,
              decoration: const InputDecoration(
                labelText: 'Recipient Address',
                border: OutlineInputBorder(),
                hintText: 'Enter recipient address',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _sendAmountController,
              decoration: const InputDecoration(
                labelText: 'Amount (BTC)',
                border: OutlineInputBorder(),
                hintText: '0.00000000',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _sendTransaction,
              icon: const Icon(Icons.send),
              label: const Text('Send Transaction'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ],
        ),
      ),
    );
  }

  //otrequest
  Widget _buildOTRequestSection() {
    return Card(
      color: Colors.white, // Force white background
      child: ListTile(
        leading: const Icon(Icons.description, color: Colors.purple),
        title: const Text(
          'OT Request ',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: () {
          // Navigate to the /ot_request route
          Navigator.of(context).pushNamed('/ot_request');
        },
      ),
    );
  }

  Widget _buildMyActivitySection() {
    return Card(
      color: Colors.white,
      child: ListTile(
        leading: const Icon(Icons.history_toggle_off, color: Colors.indigo),
        title: const Text(
          'My OT Activity', // New section for OT activities
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        subtitle: const Text('View pending requests and cycles'),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: () {
          // Navigate to the /ot_my_requests route
          Navigator.of(context).pushNamed('/ot_my_requests');
        },
      ),
    );
  }

  // otproof
  Widget _buildOTProofSection() {
    return Card(
      color: Colors.white, // Force white background
      child: ListTile(
        leading: const Icon(Icons.security, color: Colors.deepOrange),
        title: const Text(
          'OT Proof',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: () {
          // Navigate to the registered /ot_proof route
          Navigator.of(context).pushNamed('/ot_proof');
        },
      ),
    );
  }

  Widget _buildOTCycleListSection() {
    return Card(
      color: Colors.white,
      child: ListTile(
        leading: const Icon(Icons.list_alt, color: Colors.teal),
        title: const Text(
          'OT Cycle List',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: () {
          // Navigate to the registered /ot_cycle_list route
          Navigator.of(context).pushNamed('/ot_cycle_list');
        },
      ),
    );
  }

  Widget _buildA2UTestSection() {
    return Card(
      color: Colors.white,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.science, color: Colors.purple[700]),
                const SizedBox(width: 8),
                const Text(
                  'Experimental Features',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _testA2UTransaction,
              icon: const Icon(Icons.bug_report),
              label: const Text('Test A2U Transaction (0x84)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple[50],
                foregroundColor: Colors.purple[800],
                minimumSize: const Size.fromHeight(50),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.purple[200]!),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sends a small amount to yourself using SIGHASH_A2U | ANYONECANPAY signature.',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  // A2U Test Logic
  Future<void> _testA2UTransaction() async {
    final provider = context.read<WalletProvider>();

    // Check if there is an address
    if (provider.currentAddress == null) {
      _showError('No wallet address found. Please init wallet first.');
      return;
    }

    // show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Set test amount (e.g. 600 sats)
      const amount = 600;

      // Call A2U Service (send to self)
      final txid = await A2UService.instance.sendA2UTransaction(
        toAddress: provider.currentAddress!,
        amount: amount,
      );

      // Close loading
      if (mounted) Navigator.pop(context);

      // Show success message
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('A2U Success'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Transaction broadcasted using SIGHASH_A2U (0x84)!'),
                const SizedBox(height: 12),
                const Text('TXID:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                SelectableText(txid,
                    style:
                        const TextStyle(fontSize: 12, fontFamily: 'monospace')),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);

      // Show error
      if (mounted) {
        _showError('A2U Failed: $e');
      }
    }
  }

  Future<void> _showInfoDialog() async {
    final provider = context.read<WalletProvider>();
    final stats = await provider.getSyncStatistics();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wallet Info'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Network', 'Regtest'),
              _buildInfoRow('Sync Height', '${provider.syncHeight}'),
              _buildInfoRow('Balance', '${provider.balance} sats'),
              _buildInfoRow('Addresses', '${provider.addresses.length}'),
              const Divider(),
              const Text(
                'Sync Statistics:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                stats,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }
}
