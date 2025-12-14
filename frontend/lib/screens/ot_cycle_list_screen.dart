// lib/screens/ot_cycle_list_screen.dart
import 'package:flutter/material.dart';
import '../services/api_services.dart';
import '../models/ot_cycle.dart';

class OTCycleListScreen extends StatefulWidget {
  const OTCycleListScreen({Key? key}) : super(key: key);

  @override
  _OTCycleListScreenState createState() => _OTCycleListScreenState();
}

class _OTCycleListScreenState extends State<OTCycleListScreen> {
  late Future<List<OTCycle>> _cyclesFuture;
  final ApiService _api = ApiService.instance;

  // Controllers for filtering
  final TextEditingController _aidController = TextEditingController();
  String? _filterAid;
  bool _showPaths = true; // Show paths by default

  @override
  void initState() {
    super.initState();
    // Initial load: fetch all recent cycles
    _cyclesFuture = _fetchCycles();
  }

  /// Call API to fetch cycles
  Future<List<OTCycle>> _fetchCycles() async {
    try {
      final options = {
        'show_paths': _showPaths,
        'group_by_structure': false, // Handle simple list first
        'include_analysis': false,
      };

      final List<dynamic> jsonList = await _api.listOTCycles(
        aid: _filterAid, // Optional AID filter
        options: options,
      );

      // Parse JSON
      final cycles = jsonList
          .map((json) => OTCycle.fromJson(json as Map<String, dynamic>))
          .where((cycle) =>
              cycle.cycleId != 'PARSE_ERROR') // Filter out parse failures
          .toList();

      return cycles;
    } catch (e) {
      print('Failed to fetch cycles: $e');
      // Convert API exception to UI-displayable exception
      throw Exception('Failed to load cycles: $e');
    }
  }

  /// Refresh or filter cycles
  void _refreshCycles() {
    setState(() {
      _filterAid = _aidController.text.trim().isEmpty
          ? null
          : _aidController.text.trim();
      _cyclesFuture = _fetchCycles();
    });
  }

  @override
  void dispose() {
    _aidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OT Cycles'),
        backgroundColor: Colors.blue[700],
      ),
      body: Column(
        children: [
          _buildFilterBar(), // Filter bar
          Expanded(child: _buildCycleList()), // List
        ],
      ),
    );
  }

  /// Build filter UI
  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _aidController,
                  decoration: InputDecoration(
                    hintText: 'Filter by AID',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.search, color: Colors.blue[700]),
                onPressed: _refreshCycles,
              ),
            ],
          ),
          CheckboxListTile(
            title: const Text('Show Cycle Paths'),
            value: _showPaths,
            onChanged: (bool? value) {
              setState(() {
                _showPaths = value ?? false;
              });
              _refreshCycles();
            },
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          ),
        ],
      ),
    );
  }

  /// Build cycle list UI
  Widget _buildCycleList() {
    return FutureBuilder<List<OTCycle>>(
      future: _cyclesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Error: ${snapshot.error}',
                style: TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final cycles = snapshot.data;
        if (cycles == null || cycles.isEmpty) {
          return Center(
            child: Text(
              'No OT cycles found.',
              style: TextStyle(color: Colors.grey[600]),
            ),
          );
        }

        // Display list
        return ListView.builder(
          itemCount: cycles.length,
          itemBuilder: (context, index) {
            final cycle = cycles[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title (Cycle ID + participants)
                    Text(
                      '${cycle.cycleId} (${cycle.title})',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.blue[800],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Amount information
                    _buildInfoRow(
                      Icons.paid_outlined,
                      'Offset Amount:',
                      '${cycle.minAmountBTC} BTC',
                    ),
                    const SizedBox(height: 4),
                    _buildInfoRow(
                      Icons.sync_alt,
                      'Total Amount:',
                      '${cycle.totalAmountBTC} BTC',
                    ),
                    const SizedBox(height: 4),
                    _buildInfoRow(
                      Icons.people_outline,
                      'Participants:',
                      '${cycle.participantCount}',
                    ),
                    const SizedBox(height: 12),

                    // Cycle path (if enabled)
                    if (_showPaths && cycle.cyclePath != null)
                      _buildPathInfo(cycle),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[700]),
        const SizedBox(width: 8),
        Text(
          '$label ',
          style:
              TextStyle(fontWeight: FontWeight.w500, color: Colors.grey[800]),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildPathInfo(OTCycle cycle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Text(
          'Cycle Path:',
          style:
              TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[800]),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Text(
            cycle.cyclePath ?? 'N/A',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Colors.deepPurple,
            ),
          ),
        ),
      ],
    );
  }
}
