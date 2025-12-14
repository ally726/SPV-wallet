import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/wallet_provider.dart';
import 'home_screen.dart';

/// Wallet setup screen for creating or importing a wallet
class WalletSetupScreen extends StatefulWidget {
  const WalletSetupScreen({super.key});

  @override
  State<WalletSetupScreen> createState() => _WalletSetupScreenState();
}

class _WalletSetupScreenState extends State<WalletSetupScreen> {
  final _mnemonicController = TextEditingController();
  bool _isLoading = false;
  String? _generatedMnemonic;
  bool _showMnemonic = false;

  @override
  void dispose() {
    _mnemonicController.dispose();
    super.dispose();
  }

  Future<void> _createWallet() async {
    setState(() => _isLoading = true);

    try {
      final provider = context.read<WalletProvider>();
      final mnemonic = await provider.createWallet(wordCount: 12);

      setState(() {
        _generatedMnemonic = mnemonic;
        _showMnemonic = true;
        _isLoading = false;
      });

      // Show backup warning
      if (mounted) {
        _showBackupDialog(mnemonic);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        _showError('Failed to create wallet: $e');
      }
    }
  }

  Future<void> _importWallet() async {
    final mnemonic = _mnemonicController.text.trim();

    if (mnemonic.isEmpty) {
      _showError('Please enter your mnemonic phrase');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final provider = context.read<WalletProvider>();
      await provider.importWallet(mnemonic);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        _showError('Failed to import wallet: $e');
      }
    }
  }

  void _showBackupDialog(String mnemonic) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Backup Your Wallet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Write down these 12 words in order and keep them safe:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                mnemonic,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '⚠️ Anyone with these words can access your funds!',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: mnemonic));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
            child: const Text('Copy'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              );
            },
            child: const Text('I Have Saved It'),
          ),
        ],
      ),
    );
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
        title: const Text('SPV Wallet Setup'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.account_balance_wallet,
                    size: 80,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Welcome to SPV Wallet',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'A lightweight Bitcoin wallet using Simplified Payment Verification',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 48),
                  ElevatedButton.icon(
                    onPressed: _createWallet,
                    icon: const Icon(Icons.add),
                    label: const Text('Create New Wallet'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _mnemonicController,
                    decoration: const InputDecoration(
                      labelText: 'Enter 12-word mnemonic',
                      border: OutlineInputBorder(),
                      hintText: 'word1 word2 word3 ...',
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _importWallet,
                    icon: const Icon(Icons.download),
                    label: const Text('Import Existing Wallet'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
