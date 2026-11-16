import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_config.dart';

/// Only allowlisted response metadata reaches diagnostics. Never retain a body.
class DeliveryUploadDiagnostics {
  DeliveryUploadDiagnostics._();

  static Map<String, Object?>? last;

  static void record(String orderNumber, {int? statusCode, String? body}) {
    dynamic decoded;
    try {
      decoded = body == null ? null : jsonDecode(body);
    } on FormatException {
      // HTML, empty, and malformed responses cannot confirm proof storage.
    }
    final proof = decoded is Map ? decoded['proof'] : null;
    final uploaded = proof is Map ? proof['uploaded'] : null;
    final uri = Uri.parse(ApiConfig.baseUrl);
    last = Map.unmodifiable({
      'event': 'delivery_upload',
      'api_hostname': uri.host,
      'api_port': uri.port,
      'api_base_path': uri.path,
      'api_base_url_override': ApiConfig.hasBaseUrlOverride,
      'order_code': orderNumber,
      'http_status': statusCode,
      'response': {
        'format': decoded is Map ? 'json_object' : 'unconfirmed',
        'proof_present': decoded is Map && decoded.containsKey('proof'),
        'proof': {'uploaded': uploaded is bool ? uploaded : null},
      },
    });
    if (kDebugMode) debugPrint(jsonEncode(last));
  }
}
