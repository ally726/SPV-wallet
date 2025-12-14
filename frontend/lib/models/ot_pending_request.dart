// lib/models/ot_pending_request.dart
class OTPendingRequest {
  final String fromAid;
  final String toAid;
  final String amountBTC;
  final int amountSats;
  final int time;
  final String requestId;
  final String txid;
  OTPendingRequest({
    required this.fromAid,
    required this.toAid,
    required this.amountBTC,
    required this.amountSats,
    required this.time,
    required this.requestId,
    required this.txid,
  });

  factory OTPendingRequest.fromJson(Map<String, dynamic> json) {
    try {
      return OTPendingRequest(
        fromAid: json['from_aid'] as String? ?? '',
        toAid: json['to_aid'] as String? ?? '',
        amountBTC: json['amountBTC'] as String? ?? '0.0',
        amountSats: (json['amount'] as num? ?? 0).toInt(),
        time: (json['time'] as num? ?? 0).toInt(),
        requestId: json['request_id'] as String? ?? 'error_id',
        txid: json['txid'] as String? ?? 'error_txid',
      );
    } catch (e) {
      print('Error parsing OTPendingRequest.fromJson: $e');
      print('   Problematic JSON: $json');
      return OTPendingRequest(
        fromAid: 'PARSE_ERROR',
        toAid: '',
        amountBTC: '0.0',
        amountSats: 0,
        time: 0,
        requestId: 'PARSE_ERROR',
        txid: 'PARSE_ERROR',
      );
    }
  }
}
