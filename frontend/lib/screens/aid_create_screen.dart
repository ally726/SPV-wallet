import 'package:flutter/material.dart';
import '../services/aid_service.dart';
import '../widgets/address_selector_dialog.dart' show showAddressSelectorDialog;

/// AID Create Screen
/// Wizard for creating new AID certificate with Bitcoin address binding
class AIDCreateScreen extends StatefulWidget {
  final AIDService aidService;

  const AIDCreateScreen({
    super.key,
    required this.aidService,
  });

  @override
  State<AIDCreateScreen> createState() => _AIDCreateScreenState();
}

class _AIDCreateScreenState extends State<AIDCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();

  String? _selectedBtcAddress;
  String _bindingOption = 'select'; // 'select', 'none'
  bool _isCreating = false;
  String _creationStatus = '';

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _selectAddress() async {
    try {
      final selectedAddress = await showAddressSelectorDialog(context);

      if (selectedAddress != null) {
        setState(() {
          _selectedBtcAddress = selectedAddress;
          _bindingOption = 'select';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load addresses: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _createCertificate() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isCreating = true;
      _creationStatus = 'Initializing...';
    });

    try {
      setState(() =>
          _creationStatus = 'Generating RSA keys (this may take a moment)...');

      final certificate = await widget.aidService.createCertificate(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        btcAddress: _bindingOption == 'select' ? _selectedBtcAddress : null,
        fullName: _fullNameController.text.trim().isNotEmpty
            ? _fullNameController.text.trim()
            : null,
        email: _emailController.text.trim().isNotEmpty
            ? _emailController.text.trim()
            : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Certificate "${certificate.title}" created'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      debugPrint('Error creating certificate: $e');
      if (mounted) {
        setState(() {
          _isCreating = false;
          _creationStatus = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create certificate: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create AID Certificate'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Basic Information Section
            const Text(
              'Basic Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title *',
                hintText: 'e.g., My Bitcoin Identity',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.title),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a title';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'Brief description of this certificate',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username *',
                hintText: 'Public username',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a username';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password *',
                hintText: 'Secure password',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a password';
                }
                if (value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
            ),

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),

            // Bitcoin Address Binding Section
            const Text(
              'Bitcoin Address Binding',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Bind this certificate to a Bitcoin address from your wallet',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            SwitchListTile(
              title: const Text('Bind Bitcoin Address'),
              subtitle: Text(
                _bindingOption == 'select'
                    ? 'Address binding is enabled'
                    : 'Create without Bitcoin address binding',
              ),
              value: _bindingOption == 'select',
              onChanged: (value) {
                setState(() {
                  _bindingOption = value ? 'select' : 'none';
                  if (!value) {
                    _selectedBtcAddress = null;
                  }
                });
              },
            ),

            if (_bindingOption == 'select') ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _selectAddress,
                      icon: const Icon(Icons.account_balance_wallet),
                      label: Text(
                        _selectedBtcAddress == null
                            ? 'Choose Address'
                            : 'Change Address',
                      ),
                    ),
                    if (_selectedBtcAddress != null) ...[
                      const SizedBox(height: 12),
                      Card(
                        color: Colors.blue.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.check_circle,
                                      color: Colors.green, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Selected Address',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _selectedBtcAddress!,
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
                ),
              ),
            ],

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),

            // Optional Disclosed Information
            const Text(
              'Disclosed Information (Optional)',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This information can be shared with services',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _fullNameController,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge),
              ),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value != null && value.isNotEmpty && !value.contains('@')) {
                  return 'Please enter a valid email';
                }
                return null;
              },
            ),

            const SizedBox(height: 32),

            // Create Button
            ElevatedButton(
              onPressed: _isCreating ? null : _createCertificate,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isCreating
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        if (_creationStatus.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _creationStatus,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ],
                    )
                  : const Text(
                      'Create Certificate',
                      style: TextStyle(fontSize: 16),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
