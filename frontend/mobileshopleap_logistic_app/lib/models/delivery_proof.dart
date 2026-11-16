class DeliveryProof {
  final bool uploaded;
  final String? capturedAt;

  const DeliveryProof({this.uploaded = false, this.capturedAt});

  factory DeliveryProof.fromJson(dynamic json) => json is Map
      ? DeliveryProof(
          uploaded: json['uploaded'] == true,
          capturedAt: json['captured_at']?.toString(),
        )
      : const DeliveryProof();
}
