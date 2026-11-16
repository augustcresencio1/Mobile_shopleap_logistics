import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:http_parser/http_parser.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'rider_tracking_service.dart';
import '../../models/courier.dart';

export 'api_exception.dart';

class AuthException implements Exception {
  final String message;
  final String? courierStatus;
  final int? statusCode;
  final Map<String, dynamic>? errors;
  final DateTime? retryAt;
  AuthException(
    this.message, {
    this.courierStatus,
    this.statusCode,
    this.errors,
    this.retryAt,
  });
  @override
  String toString() => message;
}

class LoginResult {
  final String courierStatus; // pending | approved | rejected
  final Map<String, dynamic> courier;
  const LoginResult(this.courierStatus, [this.courier = const {}]);
}

class AuthService {
  static String get baseUrl => ApiClient.baseUrl;
  static Future<String?> getToken() => ApiClient.getToken();

  static Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on ApiException catch (e) {
      var msg = e.message;
      final reason = e.rejectionReason;
      if (reason != null && reason.isNotEmpty && reason != 'null') {
        msg = '$msg Reason: $reason';
      }
      throw AuthException(
        msg,
        courierStatus: e.riderStatus,
        statusCode: e.statusCode,
        errors: e.errors,
        retryAt: e.retryAt,
      );
    }
  }

  // Para sa mga method na nagbabalik ng String? (null = success)
  static Future<String?> _asMessage(Future<void> Function() run) async {
    try {
      await run();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  // ---------- Hubs ----------
  /// Accept a plain array or {data: [...]} and surface API errors to the UI.
  static Future<List<Map<String, dynamic>>> hubs({String? q}) =>
      _guard(() async {
        final b = await ApiClient.get(
          '/hubs',
          query: {if (q != null && q.trim().isNotEmpty) 'q': q.trim()},
          auth: false,
        );
        final list = b is List ? b : (b is Map ? b['data'] : null);
        if (list is! List) {
          throw AuthException('The server returned an invalid hub list.');
        }
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });

  static Future<List<dynamic>> hubBarangays(String hub) => _guard(() async {
    final b = await ApiClient.get(
      '/hubs/${Uri.encodeComponent(hub)}/barangays',
      auth: false,
    );
    final list = b is List ? b : (b is Map ? b['data'] : null);
    if (list is! List) {
      throw AuthException('The server returned an invalid barangay list.');
    }
    return List<dynamic>.from(list);
  });

  // ---------- Register + OTP ----------
  static Future<http.MultipartFile> _document(String field, XFile file) async {
    const maxBytes = 5 * 1024 * 1024;
    try {
      if (await file.length() > maxBytes) {
        throw ApiException('Each registration photo must be at most 5 MB.');
      }
      final bytes = await file.readAsBytes();
      final type = switch (img.findDecoderForData(bytes)?.format) {
        img.ImageFormat.jpg => 'jpeg',
        img.ImageFormat.png => 'png',
        img.ImageFormat.webp => 'webp',
        img.ImageFormat.gif => 'gif',
        img.ImageFormat.bmp => 'bmp',
        _ => null,
      };
      if (bytes.isEmpty || bytes.length > maxBytes || type == null) {
        throw ApiException(
          'Choose a JPG, PNG, WebP, GIF, or BMP registration photo of at most 5 MB.',
        );
      }
      return http.MultipartFile.fromBytes(
        field,
        bytes,
        filename: '$field.${type == 'jpeg' ? 'jpg' : type}',
        contentType: MediaType('image', type),
      );
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        'Cannot read the selected photo. Please select it again.',
      );
    }
  }

  static Future<String?> register({
    required Map<String, String> fields,
    required XFile orCr,
    required XFile license,
  }) => _asMessage(() async {
    final f = Map<String, String>.from(fields);
    // Huwag magpadala ng walang laman na optional na field
    f.removeWhere((k, v) => v.isEmpty && k != 'password');

    await ApiClient.postMultipart(
      '/courier/register',
      auth: false,
      fields: f,
      files: [
        await _document('or_cr_upload', orCr),
        await _document('license_upload', license),
      ],
    );
  });

  /// Hindi nagse-save ng token; mag-login pagkatapos.
  static Future<String?> verifyOtp(String email, String otp) =>
      _asMessage(() async {
        await ApiClient.post(
          '/courier/verify-otp',
          auth: false,
          body: {'email': email.trim(), 'otp': otp.trim()},
        );
        await ApiClient.clearToken();
      });

  static Future<String?> resendOtp(String email) => _asMessage(() async {
    await ApiClient.post(
      '/courier/resend-otp',
      auth: false,
      body: {'email': email.trim()},
    );
  });

  // ---------- Login / session ----------
  static Future<LoginResult> login(
    String email,
    String password, {
    String? deviceName,
  }) => _guard(() async {
    final b =
        await ApiClient.post(
              '/courier/login',
              auth: false,
              body: {
                'email': email.trim(),
                'password': password,
                if (deviceName != null) 'device_name': deviceName,
              },
            )
            as Map;

    final token = b['token']?.toString();
    if (token == null || token.isEmpty) {
      throw AuthException('Login failed. Please try again.');
    }
    final courier = b['courier'] is Map
        ? Map<String, dynamic>.from(b['courier'] as Map)
        : <String, dynamic>{};
    await ApiClient.saveToken(token);

    final status = (b['courier_status'] ?? courier['status'] ?? 'pending')
        .toString();
    return LoginResult(status, courier);
  });

  /// GET /courier/me. null kung walang/invalid na token.
  static Future<Map<String, dynamic>?> me() async {
    if (await getToken() == null) return null;
    try {
      final b = await ApiClient.get(
        '/courier/me',
        cacheFor: const Duration(minutes: 2),
      );
      final m = Map<String, dynamic>.from(b as Map);
      final c = m['courier'];
      if (c is Map && m['courier_status'] == null) {
        m['courier_status'] = c['status'];
      }
      return m;
    } on ApiException catch (e) {
      if (e.statusCode == 401) return null; // na-clear na ng ApiClient
      throw AuthException(
        e.message,
        courierStatus: e.riderStatus,
        statusCode: e.statusCode,
        errors: e.errors,
        retryAt: e.retryAt,
      );
    }
  }

  static Future<void> logout() async {
    await RiderTrackingService.instance.stop();
    try {
      await ApiClient.post('/courier/logout');
    } catch (_) {
      // Kahit pumalya, buburahin pa rin ang token sa device.
    } finally {
      await ApiClient.clearToken();
      Courier.current = Courier(name: '', phone: '', vehicle: '', plate: '');
    }
  }

  static Future<Map<String, dynamic>> reapply({
    Map<String, dynamic> data = const {},
  }) => _guard(() async {
    final body = await ApiClient.post('/courier/reapply', body: data);
    return Map<String, dynamic>.from(body as Map);
  });

  // ---------- Forgot password ----------
  // Reset submits the email, OTP and new password in one public request.
  static Future<Map<String, dynamic>> _postPublic(
    String path,
    Map<String, dynamic> payload,
  ) => _guard(() async {
    final b = await ApiClient.post(
      '/courier/$path',
      auth: false,
      body: payload,
    );
    return b is Map ? Map<String, dynamic>.from(b) : <String, dynamic>{};
  });

  static Future<void> forgotPassword(String email) async {
    await _postPublic('forgot-password', {'email': email.trim()});
  }

  static Future<String> verifyResetCode(String email, String otp) async {
    // The backend validates the OTP when resetPassword submits it.
    final code = otp.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw AuthException('Enter the 6-digit code.');
    }
    return code;
  }

  static Future<void> resetPassword(
    String email,
    String token,
    String password,
    String confirm,
  ) async {
    await _postPublic('reset-password', {
      'email': email.trim(),
      'otp': token.trim(),
      'password': password,
      'password_confirmation': confirm,
    });
  }
}
