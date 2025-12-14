import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/ot_request_service.dart';
import '../services/aid_service.dart';
import '../models/aid_certificate.dart';
import 'package:provider/provider.dart';
import '../providers/wallet_provider.dart';

/// OT Request Sending Interface
///
/// Features:
/// 1. Select sender AID (from local certificates)
/// 2. Input receiver AID
/// 3. Input amount (metadata only, not actual transfer)
/// 4. Create and broadcast OT Request transaction
class SendOTRequestScreen extends StatefulWidget {
  const SendOTRequestScreen({Key? key}) : super(key: key);

  @override
  State<SendOTRequestScreen> createState() => _SendOTRequestScreenState();
}

class _SendOTRequestScreenState extends State<SendOTRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _toAidController = TextEditingController();
  final _amountController = TextEditingController();

  final _otService = OTRequestService.instance;
  final _aidService = AIDService();

  List<AIDCertificate> _myCertificates = [];
  AIDCertificate? _selectedCertificate;
  bool _isLoading = false;
  String? _errorMessage;
  String? _successTxid;

  @override
  void initState() {
    super.initState();
    _loadCertificates();
  }

  @override
  void dispose() {
    _toAidController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  /// Load local AID certificates
  Future<void> _loadCertificates() async {
    try {
      final certificates = await _aidService.getAllCertificates();
      setState(() {
        _myCertificates = certificates;
        if (certificates.isNotEmpty) {
          _selectedCertificate = certificates.first;
        }
      });
    } catch (e) {
      print('Failed to load certificates: $e');
    }
  }

  /// Send OT Request
  Future<void> _sendOTRequest() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedCertificate == null) {
      setState(() {
        _errorMessage = 'Please select a sender AID';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successTxid = null;
    });

    try {
      print('OTRequest: Force syncing wallet before sending...');
      final walletProvider =
          Provider.of<WalletProvider>(context, listen: false);
      await walletProvider.startSync();
      print('OTRequest: Sync complete. Proceeding to send...');
      final fromAid = _selectedCertificate!.aid;
      final toAid = _toAidController.text.trim();
      //final amount = int.parse(_amountController.text.trim());
      final amountBtc = double.parse(_amountController.text.trim());
      final amount = (amountBtc * 100000000).toInt();
      print('Sending OT Request:');
      print('   From: $fromAid');
      print('   To: $toAid');
      print('   Amount: $amount satoshis');

      // Call OT Request Service
      final txid = await _otService.sendOTRequest(
        fromAid: fromAid,
        toAid: toAid,
        amount: amount,
      );

      setState(() {
        _successTxid = txid;
        _isLoading = false;
      });

      // Show success dialog
      _showSuccessDialog(txid);

      // Clear form
      _toAidController.clear();
      _amountController.clear();
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
            const Text('OT Request transaction sent successfully!'),
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
        title: const Text('Send OT Request'),
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
                const Text(
                  'From AID (Sender)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),

                if (_myCertificates.isEmpty)
                  Card(
                    color: Colors.orange[50],
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No AID certificates found. Please create one first.',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                  )
                else
                  DropdownButtonFormField<AIDCertificate>(
                    value: _selectedCertificate,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.account_circle),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    selectedItemBuilder: (BuildContext context) {
                      return _myCertificates.map<Widget>((AIDCertificate cert) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            cert.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList();
                    },
                    items: _myCertificates.map((cert) {
                      // *** Fix overflow issue ***
                      return DropdownMenuItem(
                        value: cert,
                        child: Container(
                          // 1. Wrap Column with Container
                          height: 70.0, // 2. Give sufficient height
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment
                                .center, // 3. Center vertically
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                cert.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              Text(
                                cert.aid,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                      // *** End fix ***
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedCertificate = value;
                      });
                    },
                    validator: (value) {
                      if (value == null) {
                        return 'Please select a sender AID';
                      }
                      return null;
                    },
                  ),

                const SizedBox(height: 24),

                // Receiver AID Input
                const Text(
                  'To AID (Receiver)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _toAidController,
                  decoration: InputDecoration(
                    hintText: 'Enter receiver\'s AID (UUID format)',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.person),
                    filled: true,
                    fillColor: Colors.grey[100],
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter receiver AID';
                    }
                    // Simple UUID format validation
                    if (!RegExp(
                            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
                        .hasMatch(value.toLowerCase())) {
                      return 'Invalid AID format (must be UUID)';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 24),

                // Amount Input
                const Text(
                  'Amount (BTC)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _amountController,
                  decoration: InputDecoration(
                    hintText: 'Enter amount',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.paid),
                    suffixText: 'BTC',
                    filled: true,
                    fillColor: Colors.grey[100],
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [],
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter amount';
                    }
                    final amountBtc = double.tryParse(value);
                    if (amountBtc == null || amountBtc <= 0) {
                      return 'Amount must be greater than 0';
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
                  onPressed: _isLoading ? null : _sendOTRequest,
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
                            Icon(Icons.send),
                            SizedBox(width: 8),
                            Text(
                              'Send OT Request',
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
                  'Note: This will create a Bitcoin transaction with a small fee. '
                  'Make sure you have sufficient balance for the transaction fee.',
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
