import 'api_client.dart';
import 'api_exception.dart';

/// An old rider's in-flight response must never reach a new rider's screen.
Future<T> financialRead<T>(Future<T> Function() read) async {
  await ApiClient.getToken();
  final session = ApiClient.sessionChanged.value;
  if (!ApiClient.hasSession) {
    ApiClient.sessionExpired.value++;
    throw ApiException('Please sign in again.', 401);
  }
  final result = await read();
  if (session != ApiClient.sessionChanged.value) {
    throw ApiException('Your account changed. Refresh to continue.');
  }
  return result;
}
