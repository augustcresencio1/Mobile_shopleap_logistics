enum ReceiptType {
  cashHandover('cash-handovers'),
  riderPayout('rider-payouts');

  final String path;
  const ReceiptType(this.path);
}

class ReceiptTarget {
  final ReceiptType type;
  final String reference;
  const ReceiptTarget(this.type, this.reference);

  String get path =>
      '/courier/receipts/${type.path}/${Uri.encodeComponent(reference)}';
}

class HtmlReceipt {
  final String html;
  final Uri baseUri;
  const HtmlReceipt(this.html, this.baseUri);
}
