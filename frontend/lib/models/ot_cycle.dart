class OTCycle {
  final String cycleId;
  final int participantCount;
  final String minAmountBTC;
  final String totalAmountBTC;
  final int timestamp;
  final String? blockHash;
  final List<String> participants;
  final List<OTCycleRequest> requests;
  final String? cyclePath; // optional

  OTCycle({
    required this.cycleId,
    required this.participantCount,
    required this.minAmountBTC,
    required this.totalAmountBTC,
    required this.timestamp,
    this.blockHash,
    required this.participants,
    required this.requests,
    this.cyclePath,
  });

  factory OTCycle.fromJson(Map<String, dynamic> json) {
    try {
      final requestsList = (json['requests'] as List<dynamic>? ?? [])
          .map((req) => OTCycleRequest.fromJson(req as Map<String, dynamic>))
          .toList();

      final participantsList = (json['participants'] as List<dynamic>? ?? [])
          .map((p) => p.toString())
          .toList();

      return OTCycle(
        cycleId: json['cycle No.'] as String? ?? 'unknown_id',
        participantCount: (json['participantCount'] as num? ?? 0).toInt(),
        minAmountBTC: json['minAmountBTC'] as String? ?? '0.0',
        totalAmountBTC: json['totalAmountBTC'] as String? ?? '0.0',
        timestamp: (json['timestamp'] as num? ?? 0).toInt(),
        blockHash: json['blockHash'] as String?,
        participants: participantsList,
        requests: requestsList,
        cyclePath: json['cycle_path'] as String?, //
      );
    } catch (e) {
      print('Error parsing OTCycle.fromJson: $e');
      print('   Problematic JSON: $json');
      // Return a default OTCycle object on error
      return OTCycle(
        cycleId: 'PARSE_ERROR',
        participantCount: 0,
        minAmountBTC: '0.0',
        totalAmountBTC: '0.0',
        timestamp: 0,
        participants: [],
        requests: [],
      );
    }
  }

  /// Get a human-readable title
  String get title {
    if (participants.isNotEmpty) {
      return participants.take(2).join(' ↔ ') +
          (participants.length > 2 ? '...' : '');
    }
    return cycleId;
  }
}

class OTCycleRequest {
  final String from;
  final String to;
  final String amountBTC;
  final int time;

  OTCycleRequest({
    required this.from,
    required this.to,
    required this.amountBTC,
    required this.time,
  });

  factory OTCycleRequest.fromJson(Map<String, dynamic> json) {
    return OTCycleRequest(
      from: json['from'] as String? ?? '',
      to: json['to'] as String? ?? '',
      amountBTC: json['amountBTC'] as String? ?? '0.0',
      time: (json['time'] as num? ?? 0).toInt(),
    );
  }
}
