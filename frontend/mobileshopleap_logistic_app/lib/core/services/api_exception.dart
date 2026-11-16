class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? errors;
  final String? riderStatus; // pending | rejected | inactive | hub_unavailable
  final String? rejectionReason;
  DateTime? retryAt;

  ApiException(
    this.message, [
    this.statusCode,
    this.errors,
    this.riderStatus,
    this.rejectionReason,
  ]);

  bool get isUnauthorized => statusCode == 401;

  Duration get retryAfter {
    final remaining = retryAt?.difference(DateTime.now()) ?? Duration.zero;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  String toString() => message;
}
