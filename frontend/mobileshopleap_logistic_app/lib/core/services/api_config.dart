/// Deployed courier API by default; API_BASE_URL preserves local development.
class ApiConfig {
  ApiConfig._();

  static const bool useProduction = true;

  static const String localBaseUrl = 'http://127.0.0.1:8000/api';

  // Rider-only Laravel API deployed in the August Render account.
  static const String productionBaseUrl =
      'https://shopleap-rider-api-august.onrender.com/api';

  static const String configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: useProduction ? productionBaseUrl : localBaseUrl,
  );

  static final String baseUrl = normalizeBaseUrl(configuredBaseUrl);

  /// Accept an origin or API base, including overrides with a trailing slash.
  static String normalizeBaseUrl(String value) {
    final uri = Uri.parse(value.trim());
    if (!uri.hasAuthority ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError('API_BASE_URL must be an HTTP(S) backend URL.');
    }
    if (uri.host.toLowerCase() == 'logistics.shopleap.shop') {
      throw ArgumentError('Use the rider API address, not the logistics portal.');
    }
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    while (segments.isNotEmpty && segments.last == 'api') {
      segments.removeLast();
    }
    return uri.replace(pathSegments: [...segments, 'api']).toString();
  }

  static const bool hasBaseUrlOverride = bool.hasEnvironment('API_BASE_URL');

  /// true = gamitin ang v4 na mga endpoint at body.
  static const bool useV4 = true;

  /// Alias para sa mga file na gumagamit na ng ApiConfig.v4.
  static const bool v4 = useV4;
}
