import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshopleap_logistic_app/core/utils/money.dart';
import 'package:mobileshopleap_logistic_app/models/earnings.dart';

void main() {
  test('Money distinguishes missing, zero and fractional earnings exactly', () {
    expect(decimalMoney(null), isNull);
    expect(formatMoney(null), '\u2014');
    expect(formatMoney(null, missing: 'Not recorded'), 'Not recorded');
    expect(formatMoney('0.00'), '\u20B10.00');
    expect(formatMoney('20.25'), '\u20B120.25');
    expect(
      formatMoney('12345678901234567890.01'),
      '\u20B112,345,678,901,234,567,890.01',
    );
    expect(decimalMoney('00020.5'), '20.50');
    expect(decimalMoney('1.234'), isNull);
    expect(decimalMoney('Infinity'), isNull);
    expect(decimalMoney('NaN'), isNull);
    expect(addMoney('120.10', '19.90'), '140.00');
  });

  test('Filters support defaults, every period and preset precedence', () {
    expect(EarningsFilter().query, {'period': 'month'});
    for (final period in ['today', 'week', 'month', 'all', '7d', '30d']) {
      expect(EarningsFilter(period: period).query, {'period': period});
    }
    for (final preset in ['today', '7d', '30d']) {
      expect(EarningsFilter(period: 'all', preset: preset).query, {
        'preset': preset,
      });
    }
    expect(() => EarningsFilter(preset: 'all'), throwsArgumentError);
  });

  test(
    'Custom dates are inclusive, validated and capped at 366 calendar days',
    () {
      final from = DateTime(2026, 1, 1);
      expect(EarningsFilter(preset: 'custom', from: from, to: from).query, {
        'preset': 'custom',
        'from': '2026-01-01',
        'to': '2026-01-01',
      });
      expect(
        EarningsFilter(
          period: 'custom',
          from: from,
          to: from.add(const Duration(days: 365)),
        ).query['to'],
        '2027-01-01',
      );
      expect(
        () => EarningsFilter(
          period: 'custom',
          from: from,
          to: from.add(const Duration(days: 366)),
        ),
        throwsArgumentError,
      );
      expect(
        () => EarningsFilter(
          period: 'custom',
          from: from,
          to: from.subtract(const Duration(days: 1)),
        ),
        throwsArgumentError,
      );
      expect(
        () => EarningsFilter(period: 'custom', from: from),
        throwsArgumentError,
      );
    },
  );

  test('The Manila calendar day is independent of device timezone', () {
    expect(
      EarningsFilter.manilaToday(DateTime.parse('2026-11-07T15:59:59Z')),
      DateTime.utc(2026, 11, 7),
    );
    expect(
      EarningsFilter.manilaToday(DateTime.parse('2026-11-07T16:00:00Z')),
      DateTime.utc(2026, 11, 8),
    );
  });
}
