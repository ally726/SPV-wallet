// lib/screens/send_ot_proof_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/ot_proof_service.dart';
import '../providers/wallet_provider.dart';

/// OT Proof Sending Interface
///
/// Features:
/// 1. Input original OT Request TXID
/// 2. (Auto-load) User current balance (for ZK Proof)
/// 3. Input payment amount (for ZK Proof)
/// 4. Create and broadcast OT Proof transaction
class SendOTProofScreen extends StatefulWidget {
  final String? initialRequestTxid;
  final String? initialOffsetAmountBTC;

  const SendOTProofScreen({
    Key? key,
    this.initialRequestTxid,
    this.initialOffsetAmountBTC,
  }) : super(key: key);
  //const SendOTProofScreen({Key? key}) : super(key: key);

  @override
  State<SendOTProofScreen> createState() => _SendOTProofScreenState();
}

class _SendOTProofScreenState extends State<SendOTProofScreen> {
  final _formKey = GlobalKey<FormState>();
  final _requestTxidController = TextEditingController();
  final _offsetAmountController = TextEditingController();

  final _otProofService = OTProofService.instance;

  bool _isLoading = false;
  String? _errorMessage;
  String? _successTxid;

  BigInt _walletBalanceSats = BigInt.zero;
  double _walletBalanceBtc = 0.0;
  bool _isBalanceLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWalletBalance();
    if (widget.initialRequestTxid != null) {
      _requestTxidController.text = widget.initialRequestTxid!;
    }
    if (widget.initialOffsetAmountBTC != null) {
      _offsetAmountController.text = widget.initialOffsetAmountBTC!;
    }
  }

  Future<void> _loadWalletBalance() async {
    try {
      if (!mounted) return;

      final walletProvider =
          Provider.of<WalletProvider>(context, listen: false);
      if (!walletProvider.isInitialized) {
        await walletProvider.initializeWallet();
      }

      if (!mounted) return;

      final balanceSats = walletProvider.balance;

      setState(() {
        _walletBalanceSats = balanceSats;
        _walletBalanceBtc = balanceSats.toInt() / 100000000.0;

        _isBalanceLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = "Failed to load wallet balance: $e";
        _isBalanceLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _requestTxidController.dispose();
    _offsetAmountController.dispose();
    super.dispose();
  }

  /// Send OT Proof
  Future<void> _sendOTProof() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_isBalanceLoading || _walletBalanceSats <= BigInt.zero) {
      setState(() {
        _errorMessage =
            "Wallet balance is zero or not loaded. Cannot create proof.";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successTxid = null;
    });

    try {
      final requestTxid = _requestTxidController.text.trim();

      // Use actual balance from Provider (sats)
      final balance = _walletBalanceSats.toInt();

      final offsetAmountBtc = double.parse(_offsetAmountController.text.trim());
      final offsetAmount = (offsetAmountBtc * 100000000).toInt();

      print('Sending OT Proof:');
      print('   Request TXID: $requestTxid');
      print('   Balance (Actual): $balance satoshis');
      print('   Offset Amount: $offsetAmount satoshis');

      // Call OT Proof Service
      final txid = await _otProofService.sendOTProof(
        requestTxid: requestTxid,
        balance: balance, // Pass actual balance
        offsetAmount: offsetAmount,
      );

      setState(() {
        _successTxid = txid;
        _isLoading = false;
      });

      // Show success dialog
      _showSuccessDialog(txid);

      // Clear form
      _requestTxidController.clear();
      _offsetAmountController.clear();

      _loadWalletBalance();
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Show success dialog
  void _showSuccessDialog(String txid) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 32),
            SizedBox(width: 12),
            Text('Success'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('OT Proof transaction sent successfully!'),
            const SizedBox(height: 16),
            const Text(
              'Transaction ID:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                txid,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: txid));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('TXID copied to clipboard')),
              );
            },
            child: const Text('Copy TXID'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send OT Proof'),
        backgroundColor: Colors.blue[700],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Request TXID
                const Text(
                  'Original Request TXID',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _requestTxidController,
                  decoration: InputDecoration(
                    hintText: 'Enter the OT Request transaction ID',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.receipt_long),
                    filled: true,
                    fillColor: Colors.grey[100],
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter Request TXID';
                    }
                    if (!RegExp(r'^[0-9a-f]{64}$')
                        .hasMatch(value.toLowerCase())) {
                      return 'Invalid TXID format (must be 64 hex chars)';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 24),

                // 2. "Your Balance" Field
                const Text(
                  'Your Balance (for Proof)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),

                // Replace TextFormField with Card
                _isBalanceLoading
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Card(
                        color: Colors.grey[100],
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                            side: BorderSide(color: Colors.grey[300]!)),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Icon(Icons.account_balance_wallet_outlined,
                                  color: Colors.grey[700]),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  // Display calculated double
                                  '${_walletBalanceBtc.toStringAsFixed(8)} BTC',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                const SizedBox(height: 24),

                // 3. Offset Amount
                const Text(
                  'Offset Amount (BTC)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _offsetAmountController,
                  decoration: InputDecoration(
                    hintText: 'Enter the amount to be offset/paid',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.paid),
                    suffixText: 'BTC',
                    filled: true,
                    fillColor: Colors.grey[100],
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  // Modify validator
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter offset amount';
                    }
                    final amountBtc = double.tryParse(value);
                    if (amountBtc == null || amountBtc <= 0) {
                      return 'Amount must be greater than 0';
                    }

                    // Check if it exceeds balance loaded from Provider
                    if (amountBtc > _walletBalanceBtc) {
                      return 'Offset amount cannot exceed your balance (${_walletBalanceBtc.toStringAsFixed(8)} BTC)';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 32),

                // Error Message
                if (_errorMessage != null)
                  Card(
                    color: Colors.red[50],
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (_errorMessage != null) const SizedBox(height: 16),

                // Send Button
                ElevatedButton(
                  onPressed: _isLoading ? null : _sendOTProof,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.security), // Modify Icon
                            SizedBox(width: 8),
                            Text(
                              'Send OT Proof', // Modify Text
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),

                const SizedBox(height: 16),

                // Hint Text
                Text(
                  'Note: This will generate a ZK-SNARK proof and create a '
                  'Bitcoin transaction with a small fee.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
