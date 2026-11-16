import '../../models/earnings.dart';
import 'api_client.dart';
import 'financial_session.dart';

class EarningsService {
  EarningsService._();

  /// Compose the documented reads; no overview endpoint is required.
  static Future<EarningsOverview> overview(
    EarningsFilter filter, {
    bool forceRefresh = false,
  }) => financialRead(() async {
    final results = await Future.wait<Object>([
      summary(filter, forceRefresh: forceRefresh),
      rate(forceRefresh: forceRefresh),
      history(filter, forceRefresh: forceRefresh),
    ]);
    return EarningsOverview(
      summary: results[0] as Map<String, dynamic>,
      rate: results[1] as Map<String, dynamic>,
      history: results[2] as EarningsHistoryPage,
    );
  });

  static Future<Map<String, dynamic>> rate({bool forceRefresh = false}) =>
      financialRead(
        () async => Map<String, dynamic>.from(
          await ApiClient.get(
                '/courier/earnings/rate',
                cacheFor: const Duration(seconds: 30),
                forceRefresh: forceRefresh,
              )
              as Map,
        ),
      );

  static Future<Map<String, dynamic>> summary(
    EarningsFilter filter, {
    bool forceRefresh = false,
  }) => financialRead(
    () async => Map<String, dynamic>.from(
      await ApiClient.get(
            '/courier/earnings/summary',
            query: filter.query,
            cacheFor: const Duration(seconds: 30),
            forceRefresh: forceRefresh,
          )
          as Map,
    ),
  );

  static Future<EarningsHistoryPage> history(
    EarningsFilter filter, {
    int page = 1,
    bool forceRefresh = false,
  }) {
    if (page < 1) throw ArgumentError.value(page, 'page', 'Must be at least 1');
    return financialRead(
      () async => EarningsHistoryPage.fromJson(
        Map<String, dynamic>.from(
          await ApiClient.get(
                '/courier/earnings/history',
                query: {...filter.query, 'page': '$page'},
                cacheFor: const Duration(seconds: 30),
                forceRefresh: forceRefresh,
              )
              as Map,
        ),
      ),
    );
  }
}
