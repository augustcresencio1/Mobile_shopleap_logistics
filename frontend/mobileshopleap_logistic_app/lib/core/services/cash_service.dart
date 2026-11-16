import '../../models/cash.dart';
import 'api_client.dart';
import 'financial_session.dart';

class CashService {
  CashService._();

  static Future<CashSummary> summary({bool forceRefresh = false}) =>
      financialRead(
        () async => CashSummary.fromJson(
          Map<String, dynamic>.from(
            await ApiClient.get(
                  '/courier/cash/summary',
                  cacheFor: const Duration(seconds: 30),
                  forceRefresh: forceRefresh,
                )
                as Map,
          ),
        ),
      );

  static Future<CashHistoryPage> history({
    int page = 1,
    bool forceRefresh = false,
  }) {
    if (page < 1) throw ArgumentError.value(page, 'page', 'Must be at least 1');
    return financialRead(
      () async => CashHistoryPage.fromJson(
        Map<String, dynamic>.from(
          await ApiClient.get(
                '/courier/cash/history',
                query: {'page': '$page'},
                cacheFor: const Duration(seconds: 30),
                forceRefresh: forceRefresh,
              )
              as Map,
        ),
      ),
    );
  }
}
