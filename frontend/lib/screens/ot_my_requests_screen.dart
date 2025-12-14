// lib/screens/ot_my_requests_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/api_services.dart';
import '../services/aid_service.dart';
import '../models/aid_certificate.dart';
import '../models/ot_pending_request.dart';
import '../models/ot_cycle.dart';
import '../services/ot_proof_service.dart';
import '../providers/wallet_provider.dart';
import '../services/storage_service.dart';

class OtMyRequestsScreen extends StatefulWidget {
  const OtMyRequestsScreen({Key? key}) : super(key: key);

  @override
  _OtMyRequestsScreenState createState() => _OtMyRequestsScreenState();
}

class _RequestState {
  bool isChecking = false;
  String? errorMessage;
  List<OTCycle>? foundCycles;
  Map<String, String> cycleSendStatus = {};
  Map<String, String> cycleSendError = {};
}

class _OtMyRequestsScreenState extends State<OtMyRequestsScreen> {
  late Future<void> _initFuture;
  List<OTPendingRequest> _requests = [];
  bool _isInitialized = false;

  final ApiService _api = ApiService.instance;
  final AIDService _aidService = AIDService();

  final OTProofService _otProofService = OTProofService.instance;
  late WalletProvider _walletProvider;

  final StorageService _storage = StorageService.instance;
  Set<String> _submittedProofIds = <String>{};

  String? _myAid;
  final Map<String, _RequestState> _requestStates = {};

  @override
  void initState() {
    super.initState();
    _walletProvider = Provider.of<WalletProvider>(context, listen: false);
    _initFuture = _fetchMyAidAndRequests();
  }

  Future<void> _fetchMyAidAndRequests() async {
    try {
      final cert = await _aidService.getFirstCertificate();
      if (cert == null) {
        throw Exception("No local AID found. Please create an AID first.");
      }
      _myAid = cert.aid;

      final submittedIds = await _storage.getSubmittedProofCycleIds();
      print(
          '[MyRequests] Loaded ${submittedIds.length} submitted proof IDs from storage.');

      final List<dynamic> jsonList = await _api.listOTRequests(aid: _myAid);
      final pendingRequests = jsonList
          .map(
              (json) => OTPendingRequest.fromJson(json as Map<String, dynamic>))
          .where((req) => req.txid != 'PARSE_ERROR')
          .toList();

      final newStates = <String, _RequestState>{};
      for (var req in pendingRequests) {
        newStates[req.txid] = _RequestState();
      }

      pendingRequests.sort((a, b) => b.time.compareTo(a.time));

      setState(() {
        _submittedProofIds = submittedIds;
        _requests = pendingRequests;
        _requestStates.clear();
        _requestStates.addAll(newStates);
        _isInitialized = true;
      });
    } catch (e) {
      print('Failed to fetch my requests: $e');
      rethrow;
    }
  }

  void _refreshRequests() {
    setState(() {
      _isInitialized = false;
      _initFuture = _fetchMyAidAndRequests();
    });
  }

  Future<void> _checkCycleForRequest(OTPendingRequest req) async {
    final state = _requestStates[req.txid];
    if (state == null) return;

    setState(() {
      state.isChecking = true;
      state.errorMessage = null;
      state.foundCycles = null;
    });

    try {
      final result = await _api.getRequestCycles(req.fromAid, req.toAid);
      final cyclesJson = result['cycles'] as List<dynamic>? ?? [];
      final cycles = cyclesJson
          .map((j) => OTCycle.fromJson(j as Map<String, dynamic>))
          .toList();

      if (_requestStates.containsKey(req.txid)) {
        setState(() {
          _requestStates[req.txid]!.foundCycles = cycles;
        });
      }
    } catch (e) {
      if (_requestStates.containsKey(req.txid)) {
        setState(() {
          _requestStates[req.txid]!.errorMessage =
              'Failed to check cycle: ${e.toString()}';
        });
      }
    } finally {
      if (_requestStates.containsKey(req.txid)) {
        setState(() {
          _requestStates[req.txid]!.isChecking = false;
        });
      }
    }
  }

  Future<void> _sendProof(OTPendingRequest req, OTCycle cycle) async {
    final reqState = _requestStates[req.txid];
    if (reqState == null) return;

    reqState.cycleSendStatus[cycle.cycleId] = "SENDING";
    reqState.cycleSendError.remove(cycle.cycleId);
    setState(() {});

    try {
      final balanceSats = _walletProvider.balance.toInt();
      final offsetAmountSats =
          (double.tryParse(cycle.minAmountBTC) ?? 0.0 * 100000000).toInt();

      if (balanceSats <= 0) {
        throw Exception("Wallet balance is zero.");
      }
      if (offsetAmountSats <= 0) {
        throw Exception("Invalid cycle offset amount.");
      }
      if (offsetAmountSats > balanceSats) {
        throw Exception(
            "Wallet balance ($balanceSats) is less than offset amount ($offsetAmountSats).");
      }

      final txid = await _otProofService.sendOTProof(
        requestTxid: req.txid,
        balance: balanceSats,
        offsetAmount: offsetAmountSats,
      );

      reqState.cycleSendStatus[cycle.cycleId] = "SENT";

      _submittedProofIds.add(cycle.cycleId);
      await _storage.saveSubmittedProofCycleIds(_submittedProofIds);
      print('[MyRequests] Saved ${cycle.cycleId} to submitted proofs storage.');

      setState(() {});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Proof Sent! TXID: $txid'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      reqState.cycleSendStatus[cycle.cycleId] = "ERROR";
      reqState.cycleSendError[cycle.cycleId] = e.toString();
      setState(() {});
    }
  }

  String _formatTimestamp(int timestamp) {
    if (timestamp == 0) return 'In Mempool';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My OT Requests'),
        backgroundColor: Colors.blue[700],
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _refreshRequests,
            tooltip: 'Refresh List',
          ),
        ],
      ),
      body: _buildRequestList(),
    );
  }

  Widget _buildRequestList() {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting ||
            !_isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                '${snapshot.error}',
                style: TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (_requests.isEmpty) {
          return Center(
            child: Text(
              'No pending OT requests found from your AID.',
              style: TextStyle(color: Colors.grey[600]),
            ),
          );
        }

        return ListView.builder(
          itemCount: _requests.length,
          itemBuilder: (context, index) {
            final req = _requests[index];
            final state = _requestStates[req.txid];
            if (state == null) {
              return ListTile(
                  title: Text('Error: State mismatch for ${req.txid}'));
            }
            return _buildRequestCard(req, state);
          },
        );
      },
    );
  }

  Widget _buildRequestCard(OTPendingRequest req, _RequestState state) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${req.amountBTC} BTC',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.arrow_downward, 'To:', req.toAid, null),
            const SizedBox(height: 8),
            _buildInfoRow(Icons.access_time, 'Time:',
                _formatTimestamp(req.time), Colors.grey[700]),
            const Divider(height: 24),
            if (state.isChecking)
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            if (!state.isChecking &&
                state.foundCycles == null &&
                state.errorMessage == null)
              Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.sync, size: 18),
                  label: const Text('Check Cycle Status'),
                  onPressed: () => _checkCycleForRequest(req),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[100],
                    foregroundColor: Colors.blue[800],
                  ),
                ),
              ),
            if (state.errorMessage != null)
              Center(
                child: Text(
                  state.errorMessage!,
                  style: TextStyle(color: Colors.red[700]),
                ),
              ),
            if (state.foundCycles != null)
              _buildCycleResults(req, state.foundCycles!),
          ],
        ),
      ),
    );
  }

  Widget _buildCycleResults(OTPendingRequest req, List<OTCycle> cycles) {
    if (cycles.isEmpty) {
      return Center(
        child: Column(
          children: [
            Icon(Icons.info_outline, color: Colors.grey[600]),
            const SizedBox(height: 8),
            Text(
              'No cycles found for this request yet.',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              child: const Text('Check Again'),
              onPressed: () => _checkCycleForRequest(req),
            )
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Found ${cycles.length} Cycle(s):',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        ...cycles.map((cycle) => _buildCycleTile(req, cycle)),
      ],
    );
  }

  Widget _buildCycleTile(OTPendingRequest req, OTCycle cycle) {
    final reqState = _requestStates[req.txid];
    if (reqState == null) {
      return const ListTile(title: Text('Error: State mismatch'));
    }

    final status = reqState.cycleSendStatus[cycle.cycleId] ?? "IDLE";
    final error = reqState.cycleSendError[cycle.cycleId];

    bool isSending = status == "SENDING";
    bool isSent =
        (status == "SENT" || _submittedProofIds.contains(cycle.cycleId));

    Widget trailingButton;

    if (isSending) {
      trailingButton = const CircularProgressIndicator(strokeWidth: 2);
    } else if (isSent) {
      trailingButton = ElevatedButton.icon(
        icon: const Icon(Icons.check, size: 18),
        label: const Text('Submitted'),
        onPressed: null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey[300],
          foregroundColor: Colors.grey[700],
        ),
      );
    } else {
      trailingButton = ElevatedButton(
        child: Text(status == "ERROR" ? 'Retry Proof' : 'Send Proof'),
        onPressed: () => _sendProof(req, cycle),
        style: ElevatedButton.styleFrom(
          backgroundColor:
              status == "ERROR" ? Colors.red[700] : Colors.green[700],
          foregroundColor: Colors.white,
        ),
      );
    }

    return Card(
      elevation: 0,
      color: isSent ? Colors.grey[100] : Colors.green[50],
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(
                  isSent ? Icons.check_circle_outline : Icons.check_circle,
                  color: isSent ? Colors.grey[700] : Colors.green[700]),
              title: Text(
                'Cycle Found: ${cycle.cycleId}',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Offset Amount: ${cycle.minAmountBTC} BTC\n'
                'Participants: ${cycle.participantCount}',
              ),
              trailing: trailingButton,
            ),
            if (error != null)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: Text(
                  'Error: $error',
                  style: TextStyle(color: Colors.red[900], fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
      IconData icon, String label, String value, Color? valueColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey[700]),
        const SizedBox(width: 8),
        Text(
          label,
          style:
              TextStyle(fontWeight: FontWeight.w500, color: Colors.grey[800]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: valueColor,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
            softWrap: true,
          ),
        ),
      ],
    );
  }
}

extension AIDServiceGetFirst on AIDService {
  Future<AIDCertificate?> getFirstCertificate() async {
    final certificates = await getAllCertificates();
    if (certificates.isNotEmpty) {
      return certificates.first;
    }
    return null;
  }
}
