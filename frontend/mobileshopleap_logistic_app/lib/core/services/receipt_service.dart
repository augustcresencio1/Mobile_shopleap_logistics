import '../../models/receipt.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'financial_session.dart';

class ReceiptService {
  ReceiptService._();

  static Future<HtmlReceipt> fetch(ReceiptTarget target) => financialRead(
    () async {
      if (target.reference.trim().isEmpty) {
        throw ApiException('Receipt reference unavailable.', 404);
      }
      final html = await ApiClient.getHtml(target.path);
      return HtmlReceipt(html, Uri.parse('${ApiClient.baseUrl}${target.path}'));
    },
  );
}
