// lib/models/my_ot_request.dart
import 'ot_pending_request.dart';
import 'ot_cycle.dart';

// Define request status
enum OTRequestStatus { pending, cycled }

class MyOTRequest {
  final String fromAid;
  final String toAid;
  final String amountBTC;
  final int amountSats;
  final int time;
  final String requestId;

  // Status information
  final OTRequestStatus status;
  final String? cycleId; // If already in cycle
  final String? cycleOffsetBTC; // If already in cycle

  MyOTRequest({
    required this.fromAid,
    required this.toAid,
    required this.amountBTC,
    required this.amountSats,
    required this.time,
    required this.requestId,
    required this.status,
    this.cycleId,
    this.cycleOffsetBTC,
  });

  // Create from pending request
  factory MyOTRequest.fromPending(OTPendingRequest pending) {
    return MyOTRequest(
      fromAid: pending.fromAid,
      toAid: pending.toAid,
      amountBTC: pending.amountBTC,
      amountSats: pending.amountSats,
      time: pending.time,
      requestId: pending.requestId,
      status: OTRequestStatus.pending,
    );
  }

  // Create from cycled request
  factory MyOTRequest.fromCycled(OTCycleRequest request, OTCycle cycle) {
    return MyOTRequest(
      fromAid: request.from,
      toAid: request.to,
      amountBTC: request.amountBTC,
      amountSats:
          (double.tryParse(request.amountBTC) ?? 0.0 * 100000000).toInt(),
      time: request.time,
      requestId: '${request.from} -> ${request.to}', // Ensure consistent format
      status: OTRequestStatus.cycled,
      cycleId: cycle.cycleId,
      cycleOffsetBTC: cycle.minAmountBTC,
    );
  }
}
