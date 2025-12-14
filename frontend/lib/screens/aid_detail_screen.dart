import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/aid_certificate.dart';
import '../services/aid_service.dart';

/// AID Detail Screen
/// Displays certificate details and provides operations
class AIDDetailScreen extends StatefulWidget {
  final String aidId;
  final AIDService aidService;

  const AIDDetailScreen({
    super.key,
    required this.aidId,
    required this.aidService,
  });

  @override
  State<AIDDetailScreen> createState() => _AIDDetailScreenState();
}

class _AIDDetailScreenState extends State<AIDDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  AIDCertificate? _certificate;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCertificate();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCertificate() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final cert = await widget.aidService.getCertificate(widget.aidId);
      setState(() {
        _certificate = cert;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied to clipboard')),
    );
  }

  Future<void> _exportCertificate() async {
    if (_certificate == null) return;

    try {
      final publicKey =
          await widget.aidService.getPublicKey(_certificate!.aidId);
      final certData = '''
=== AID Certificate ===
AID: ${_certificate!.aidId}
Title: ${_certificate!.title}
Username: ${_certificate!.username}
Hash: ${_certificate!.certificateHash}
Bitcoin Address: ${_certificate!.btcAddress ?? 'None'}
Created: ${_certificate!.createdAt}
Registered: ${_certificate!.isRegistered ? 'Yes' : 'No'}

=== Public Key (PEM) ===
$publicKey
''';

      Clipboard.setData(ClipboardData(text: certData));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Certificate exported to clipboard'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteCertificate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Certificate'),
        content: Text(
          'Are you sure you want to delete "${_certificate!.title}"?\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await widget.aidService.deleteCertificate(widget.aidId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Certificate deleted'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true); // Return to list
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Delete failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_certificate?.title ?? 'Certificate'),
        actions: [
          if (_certificate != null && !_certificate!.isRegistered)
            IconButton(
              icon: const Icon(Icons.cloud_upload),
              tooltip: 'Register on Blockchain',
              onPressed: _registerCertificate,
            ),
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: 'Export',
            onPressed: _certificate != null ? _exportCertificate : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Delete',
            onPressed: _certificate != null ? _deleteCertificate : null,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.info), text: 'Info'),
            Tab(icon: Icon(Icons.key), text: 'Keys'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadCertificate,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildInfoTab(),
                    _buildKeysTab(),
                  ],
                ),
    );
  }

  Widget _buildInfoTab() {
    if (_certificate == null) return const SizedBox();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildInfoCard(
          title: 'Certificate Information',
          children: [
            _buildInfoRow('Title', _certificate!.title),
            if (_certificate!.description != null)
              _buildInfoRow('Description', _certificate!.description!),
            _buildInfoRow('Username', _certificate!.username),
            if (_certificate!.fullName != null)
              _buildInfoRow('Full Name', _certificate!.fullName!),
            if (_certificate!.email != null)
              _buildInfoRow('Email', _certificate!.email!),
          ],
        ),
        const SizedBox(height: 16),
        _buildInfoCard(
          title: 'Identification',
          children: [
            _buildCopyableRow('AID', _certificate!.aidId),
            _buildCopyableRow(
                'Certificate Hash', _certificate!.certificateHash),
            _buildPublicKeyPreview(),
          ],
        ),
        const SizedBox(height: 16),
        _buildInfoCard(
          title: 'Bitcoin Binding',
          children: [
            _buildCopyableRow(
              'BTC Address',
              _certificate!.btcAddress ?? 'Not bound',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildInfoCard(
          title: 'Status',
          children: [
            _buildStatusRow(
              'Registration',
              _certificate!.isRegistered ? 'Registered' : 'Not registered',
              _certificate!.isRegistered ? Colors.green : Colors.orange,
            ),
            _buildInfoRow(
              'Created',
              _certificate!.createdAt.toLocal().toString().split('.')[0],
            ),
            _buildInfoRow(
              'Updated',
              _certificate!.updatedAt.toLocal().toString().split('.')[0],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKeysTab() {
    return FutureBuilder<String>(
      future: widget.aidService.getPublicKey(widget.aidId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading public key: ${snapshot.error}'),
          );
        }

        final publicKey = snapshot.data!;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.vpn_key, color: Colors.blue),
                        const SizedBox(width: 8),
                        const Text(
                          'Public Key (RSA-2048)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: () =>
                              _copyToClipboard(publicKey, 'Public key'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        publicKey,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              color: Colors.yellow.shade50,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Private key is securely stored and cannot be exported',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSignTab() {
    final dataController = TextEditingController();
    String? signature;

    return StatefulBuilder(
      builder: (context, setState) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Sign Data',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sign arbitrary data with your private key',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: dataController,
              decoration: const InputDecoration(
                labelText: 'Data to sign',
                hintText: 'Enter text or paste data here',
                border: OutlineInputBorder(),
              ),
              maxLines: 5,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                if (dataController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter data to sign')),
                  );
                  return;
                }

                try {
                  final sig = await widget.aidService.signData(
                    widget.aidId,
                    dataController.text,
                  );
                  setState(() => signature = sig);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Signing failed: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.create),
              label: const Text('Sign Data'),
            ),
            if (signature != null) ...[
              const SizedBox(height: 24),
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green),
                          const SizedBox(width: 8),
                          const Text(
                            'Signature (Base64)',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            onPressed: () =>
                                _copyToClipboard(signature!, 'Signature'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        signature!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildInfoCard({
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCopyableRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _copyToClipboard(value, label),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Icon(Icons.circle, size: 10, color: color),
                const SizedBox(width: 8),
                Text(
                  value,
                  style: TextStyle(fontSize: 14, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPublicKeyPreview() {
    final publicKey = _certificate!.publicKey;
    // Extract first and last 20 characters
    final preview = publicKey.length > 60
        ? '${publicKey.substring(0, 30)}...${publicKey.substring(publicKey.length - 30)}'
        : publicKey;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 120,
            child: Text(
              'Public Key',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              preview,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _copyToClipboard(publicKey, 'Public key'),
            tooltip: 'Copy full public key',
          ),
        ],
      ),
    );
  }

  Future<void> _registerCertificate() async {
    if (_certificate == null) return;

    if (_certificate!.isRegistered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Certificate is already registered'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_certificate!.btcAddress == null || _certificate!.btcAddress!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot register: Bitcoin address is required'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Register Certificate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Register this certificate on the blockchain?'),
            const SizedBox(height: 16),
            Text(
              'AID: ${_certificate!.aid}',
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            Text(
              'BTC Address: ${_certificate!.btcAddress}',
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Register'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        // Show loading
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );

        final txId = await widget.aidService.registerCertificate(widget.aidId);

        if (mounted) {
          Navigator.pop(context); // Close loading
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Certificate registered! TxID: $txId'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
          _loadCertificate(); // Reload to update status
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // Close loading
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Registration failed: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }
}
