import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/aid_certificate.dart';
import '../services/aid_service.dart';
import 'aid_create_screen.dart';
import 'aid_detail_screen.dart';

/// AID List Screen
/// Display all AID certificates with search and filter
class AIDListScreen extends StatefulWidget {
  final AIDService aidService;

  const AIDListScreen({
    super.key,
    required this.aidService,
  });

  @override
  State<AIDListScreen> createState() => _AIDListScreenState();
}

class _AIDListScreenState extends State<AIDListScreen> {
  List<AIDCertificate> _certificates = [];
  List<AIDCertificate> _filteredCertificates = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCertificates();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCertificates() async {
    setState(() => _isLoading = true);

    try {
      final certificates = await widget.aidService.getAllCertificates();
      setState(() {
        _certificates = certificates;
        _applyFilter();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load certificates: $e')),
        );
      }
    }
  }

  void _applyFilter() {
    var filtered = List<AIDCertificate>.from(_certificates);

    // Apply search
    final query = _searchController.text.toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where((cert) {
        return cert.title.toLowerCase().contains(query) ||
            cert.username.toLowerCase().contains(query) ||
            cert.aid.toLowerCase().contains(query) ||
            (cert.btcAddress?.toLowerCase().contains(query) ?? false);
      }).toList();
    }

    // Sort by creation date (newest first)
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    setState(() {
      _filteredCertificates = filtered;
    });
  }

  Future<void> _createNewCertificate() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AIDCreateScreen(
          aidService: widget.aidService,
        ),
      ),
    );

    if (result == true) {
      _loadCertificates();
    }
  }

  Future<void> _viewCertificateDetails(AIDCertificate certificate) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AIDDetailScreen(
          aidId: certificate.aidId,
          aidService: widget.aidService,
        ),
      ),
    );

    if (result == true) {
      _loadCertificates();
    }
  }

  Future<void> _deleteCertificate(AIDCertificate certificate) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Certificate'),
        content: Text('Are you sure you want to delete "${certificate.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await widget.aidService.deleteCertificate(certificate.aid);
        _loadCertificates();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Certificate deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }

  Future<void> _registerCertificate(AIDCertificate certificate) async {
    if (certificate.isRegistered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Certificate is already registered'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (certificate.btcAddress == null || certificate.btcAddress!.isEmpty) {
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
              'Title: ${certificate.title}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'AID: ${certificate.aid}',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            Text(
              'BTC Address: ${certificate.btcAddress}',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
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

        final txId = await widget.aidService.registerCertificate(certificate.aid);

        if (mounted) {
          Navigator.pop(context); // Close loading
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Certificate registered! TxID: $txId'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
          _loadCertificates(); // Reload to update status
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

  Widget _buildCertificateCard(AIDCertificate certificate) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () => _viewCertificateDetails(certificate),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title and status
              Row(
                children: [
                  Expanded(
                    child: Text(
                      certificate.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (certificate.isRegistered)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified, size: 14, color: Colors.green),
                          SizedBox(width: 4),
                          Text(
                            'Registered',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!certificate.isRegistered)
                    ElevatedButton.icon(
                      onPressed: () => _registerCertificate(certificate),
                      icon: const Icon(Icons.cloud_upload, size: 16),
                      label: const Text('Register'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'delete') {
                        _deleteCertificate(certificate);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // AID (UUID) with copy button
              Row(
                children: [
                  const Icon(Icons.fingerprint, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      certificate.aid,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 14),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: certificate.aid));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('AID copied to clipboard'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    tooltip: 'Copy AID',
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Bitcoin address (if bound)
              if (certificate.btcAddress != null) ...[
                Row(
                  children: [
                    const Icon(Icons.link, size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        certificate.btcAddress!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: certificate.btcAddress!),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Address copied'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              // Username
              Row(
                children: [
                  const Icon(Icons.person, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    '@${certificate.username}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Creation date
              Text(
                'Created: ${_formatDate(certificate.createdAt)}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              ),

              // Description (if available)
              if (certificate.description != null &&
                  certificate.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  certificate.description!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AID Certificates'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCertificates,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by title, username, AID, or address...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _applyFilter();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (_) => _applyFilter(),
            ),
          ),

          // Certificate list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredCertificates.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.badge_outlined,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _certificates.isEmpty
                                  ? 'No AID certificates yet'
                                  : 'No matching certificates',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_certificates.isEmpty)
                              const Text(
                                'Tap + to create your first certificate',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadCertificates,
                        child: ListView.builder(
                          itemCount: _filteredCertificates.length,
                          itemBuilder: (context, index) {
                            return _buildCertificateCard(
                              _filteredCertificates[index],
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewCertificate,
        tooltip: 'Create New Certificate',
        child: const Icon(Icons.add),
      ),
    );
  }
}
