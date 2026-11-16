/// Keeps API money exact and preserves the difference between missing and zero.
String? decimalMoney(Object? value) {
  if (value == null) return null;
  final match = RegExp(
    r'^(-?)(\d+)(?:\.(\d{1,2}))?$',
  ).firstMatch(value.toString().trim());
  if (match == null) return null;
  final whole = match[2]!.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  final fraction = (match[3] ?? '').padRight(2, '0');
  final sign = whole == '0' && fraction == '00' ? '' : match[1]!;
  return '$sign$whole.$fraction';
}

String formatMoney(
  Object? value, {
  String currency = 'PHP',
  String missing = '\u2014',
}) {
  final amount = decimalMoney(value);
  if (amount == null) return missing;
  final parts = amount.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\d(?=(\d{3})+$)'),
    (match) => '${match[0]},',
  );
  return '${currency == 'PHP' ? '\u20B1' : '$currency '}$whole.${parts[1]}';
}

/// Used only to combine legacy item and shipping totals for COD.
String addMoney(Object? first, Object? second) {
  BigInt cents(Object? value) =>
      BigInt.parse((decimalMoney(value) ?? '0.00').replaceAll('.', ''));
  final sum = cents(first) + cents(second);
  final digits = sum.abs().toString().padLeft(3, '0');
  return '${sum.isNegative ? '-' : ''}'
      '${digits.substring(0, digits.length - 2)}.${digits.substring(digits.length - 2)}';
}
