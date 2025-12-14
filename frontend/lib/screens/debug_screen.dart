import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/storage_service.dart';
import '../services/hd_wallet_service.dart';
import '../database/database_helper.dart';
import '../models/utxo.dart';
import '../models/wallet_transaction.dart';
import '../models/block_header.dart';
import 'wallet_setup_screen.dart';

/// Debug screen for viewing wallet data in Chrome
class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  final StorageService _storage = StorageService.instance;
  final DatabaseHelper _db = DatabaseHelper.instance;

  String? _mnemonic;
  String? _seed;
  int _lastExternalIndex = 0;
  int _lastInternalIndex = 0;
  List<UTXO> _utxos = [];
  List<WalletTransaction> _transactions = [];
  List<BlockHeader> _blockHeaders = [];
  bool _isLoading = true;

  // Toggle visibility for sensitive data
  bool _showMnemonic = false;
  bool _showSeed = false;

  @override
  void initState() {
    super.initState();
    _loadDebugData();
  }

  Future<void> _loadDebugData() async {
    setState(() => _isLoading = true);

    try {
      // Load SecureStorage data
      _mnemonic = await _storage.getMnemonic();
      _seed = await _storage.getSeed();
      _lastExternalIndex = await _storage.getLastExternalIndex();
      _lastInternalIndex = await _storage.getLastInternalIndex();

      // Load database data
      _utxos = await _db.getAllUTXOs();
      // Note: No getAllTransactions method exists yet
      _transactions = [];
      _blockHeaders =
          await _db.getBlockHeadersInRange(0, 100); // Get first 100 blocks

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error loading debug data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _resetWallet() async {
    // Show a confirmation dialog to prevent accidental clicks
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Hard Reset Wallet?'),
        content: const Text('This will permanently delete:\n\n'
            '• Your mnemonic phrase\n'
            '• Seed and private keys\n'
            '• All UTXOs and transactions\n'
            '• Block headers\n'
            '• All synced data\n\n'
            'This action CANNOT be undone!\n\n'
            'Make sure you have backed up your mnemonic phrase if you want to recover this wallet later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.red,
            ),
            child: const Text('Reset Wallet'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      debugPrint('Starting wallet reset...');

      // 1. clean HD wallet cache
      debugPrint('Clearing HD wallet cache...');
      HDWalletService.instance.clearCache();

      // 2. clean local database
      debugPrint('Clearing database...');
      await DatabaseHelper.instance.clearAllData();

      // 3. clean secure storage
      debugPrint('Clearing secure storage...');
      await StorageService.instance.deleteAllWalletData();

      debugPrint('Wallet reset complete!');

      // 4. Navigate back to the initial setup screen
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const WalletSetupScreen()),
          (route) => false,
        );
      }
    } catch (e, stackTrace) {
      debugPrint('Failed to reset wallet: $e');
      debugPrint('Stack trace: $stackTrace');

      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reset wallet: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50], // Force light background
      appBar: AppBar(
        title: const Text('🔍 Debug Panel'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDebugData,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever),
            onPressed: _resetWallet,
            tooltip: 'Reset Wallet',
            color: Colors.red[100],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSecureStorageSection(),
                  const SizedBox(height: 24),
                  // _buildUTXOsSection(),
                  // const SizedBox(height: 24),
                  // _buildTransactionsSection(),
                  // const SizedBox(height: 24),
                  // _buildBlockHeadersSection(),
                  // const SizedBox(height: 24),
                  _buildResetWalletSection(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildSecureStorageSection() {
    return Card(
      elevation: 2,
      color: Colors.white, // Force white background
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lock, color: Colors.red, size: 24),
                SizedBox(width: 8),
                Text(
                  'Secure Storage Data',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const Divider(thickness: 2),
            const SizedBox(height: 8),

            // Warning banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[300]!, width: 2),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '⚠️ Never share this data! Your funds will be stolen!',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Mnemonic with toggle
            _buildSensitiveDataRow(
              label: 'Mnemonic (12 words)',
              value: _mnemonic ?? 'Not set',
              isVisible: _showMnemonic,
              onToggle: () => setState(() => _showMnemonic = !_showMnemonic),
              onCopy: _mnemonic != null
                  ? () => _copyToClipboard(_mnemonic!, 'Mnemonic')
                  : null,
            ),

            const SizedBox(height: 16),

            // Seed with toggle
            _buildSensitiveDataRow(
              label: 'Seed (Hex)',
              value: _seed ?? 'Not set',
              isVisible: _showSeed,
              onToggle: () => setState(() => _showSeed = !_showSeed),
              onCopy:
                  _seed != null ? () => _copyToClipboard(_seed!, 'Seed') : null,
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // Address indices (not sensitive)
            _buildDataRow(
              'Last External Index',
              _lastExternalIndex.toString(),
              valueColor: Colors.blue[700],
            ),
            _buildDataRow(
              'Last Internal Index',
              _lastInternalIndex.toString(),
              valueColor: Colors.blue[700],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUTXOsSection() {
    final totalValue = _utxos.fold<BigInt>(
      BigInt.zero,
      (sum, utxo) => sum + utxo.value,
    );

    return Card(
      elevation: 2,
      color: Colors.white, // Force white background
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet,
                    color: Colors.green, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'UTXOs (Unspent Outputs)',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_utxos.length} outputs',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const Divider(thickness: 2),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[300]!, width: 2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance,
                      color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Total Balance: ',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey[800],
                    ),
                  ),
                  Text(
                    '$totalValue sats',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_utxos.isEmpty)
              Text(
                'No UTXOs found',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              )
            else
              ..._utxos.map((utxo) => _buildUTXOCard(utxo)),
          ],
        ),
      ),
    );
  }

  Widget _buildUTXOCard(UTXO utxo) {
    return Card(
      color: Colors.green[50],
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TxID: ${utxo.txHash.substring(0, 16)}...',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Output: ${utxo.vout}',
              style: const TextStyle(color: Colors.black87, fontSize: 13),
            ),
            Text(
              'Value: ${utxo.value} sats',
              style: const TextStyle(
                color: Colors.green,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Address: ${utxo.address}',
              style: TextStyle(
                color: Colors.blue[800],
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            Text(
              'Confirmations: ${utxo.confirmations}',
              style: const TextStyle(color: Colors.black87, fontSize: 13),
            ),
            Text(
              'Derivation: ${utxo.derivationIndex} (${utxo.isChange ? "change" : "external"})',
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsSection() {
    return Card(
      elevation: 2,
      color: Colors.white, // Force white background
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long, color: Colors.blue, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Transactions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_transactions.length} txs',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const Divider(thickness: 2),
            const SizedBox(height: 8),
            if (_transactions.isEmpty)
              Text(
                'No transactions found',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              )
            else
              ..._transactions.map((tx) => _buildTransactionCard(tx)),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionCard(WalletTransaction tx) {
    return Card(
      color: Colors.blue[50],
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TxID: ${tx.txHash.substring(0, 16)}...',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            if (tx.blockHeight != null)
              Text(
                'Block: ${tx.blockHeight}',
                style: const TextStyle(color: Colors.black87, fontSize: 13),
              ),
            Text(
              'Fee: ${tx.fee} sats',
              style: TextStyle(
                color: Colors.orange[700],
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (tx.confirmations != null)
              Text(
                'Confirmations: ${tx.confirmations}',
                style: const TextStyle(color: Colors.black87, fontSize: 13),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockHeadersSection() {
    return Card(
      elevation: 2,
      color: Colors.white, // Force white background
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.view_in_ar, color: Colors.purple, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Block Headers',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_blockHeaders.length} blocks',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const Divider(thickness: 2),
            const SizedBox(height: 8),
            if (_blockHeaders.isEmpty)
              Text(
                'No block headers found',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              )
            else
              ..._blockHeaders
                  .take(10)
                  .map((header) => _buildBlockHeaderCard(header)),
            if (_blockHeaders.length > 10)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '... and ${_blockHeaders.length - 10} more',
                  style: const TextStyle(
                      color: Colors.grey, fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockHeaderCard(BlockHeader header) {
    return Card(
      color: Colors.purple[50],
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Height: ${header.height}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Hash: ${header.hash.substring(0, 16)}...',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Timestamp: ${DateTime.fromMillisecondsSinceEpoch(header.timestamp * 1000)}',
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build sensitive data row with show/hide toggle
  Widget _buildSensitiveDataRow({
    required String label,
    required String value,
    required bool isVisible,
    required VoidCallback onToggle,
    VoidCallback? onCopy,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red[300]!, width: 2),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        isVisible ? value : '••••••••••••••••••••',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isVisible ? Colors.black87 : Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: onToggle,
                      icon: Icon(
                        isVisible ? Icons.visibility_off : Icons.visibility,
                        size: 18,
                      ),
                      label: Text(isVisible ? 'Hide' : 'Show'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.blue[700],
                      ),
                    ),
                    if (onCopy != null && isVisible) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: onCopy,
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.orange[700],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Build regular data row
  Widget _buildDataRow(
    String label,
    String value, {
    Color? valueColor,
    VoidCallback? onCopy,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
          Row(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: valueColor ?? Colors.black87,
                ),
              ),
              if (onCopy != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: onCopy,
                  tooltip: 'Copy',
                  color: Colors.grey[600],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResetWalletSection() {
    return Card(
      elevation: 3,
      color: Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.delete_forever, color: Colors.red, size: 24),
                SizedBox(width: 8),
                Text(
                  'Reset Wallet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const Divider(thickness: 2, color: Colors.red),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[300]!, width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 22),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Reset Wallet',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This will permanently delete all wallet data including your mnemonic phrase, private keys, UTXOs, transactions, and block headers. This action cannot be undone.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[800],
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _resetWallet,
                      icon: const Icon(Icons.delete_forever),
                      label: const Text(
                        'Reset Wallet',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
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
}
