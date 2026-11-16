import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshopleap_logistic_app/core/services/navigation_service.dart';
import 'package:mobileshopleap_logistic_app/models/navigation.dart';

void main() {
  test(
    'Maps prefers a valid pin and sends only an address when the pin is absent',
    () {
      const pinned = NavigationStop(
        id: '1',
        name: 'Customer Name',
        address: '15 Customer Road, Manila',
        pin: GeoPoint(14.6, 120.98),
      );
      expect(
        NavigationService.directions(pinned).queryParameters['destination'],
        '14.6,120.98',
      );
      const address = NavigationStop(
        id: '2',
        name: 'Name must not be searched',
        address: '25 Seller Road, Manila',
      );
      final uri = NavigationService.directions(address);
      expect(uri.queryParameters['destination'], '25 Seller Road, Manila');
      expect(uri.queryParameters['api'], '1');
      expect(uri.toString(), isNot(contains('Name')));
      expect(uri.queryParameters.containsKey('key'), isFalse);
    },
  );

  test(
    'Long full routes preserve every stop in order and finish at the assigned hub',
    () {
      final stops = List.generate(
        15,
        (index) => NavigationStop(
          id: '$index',
          name: 'Customer $index',
          address: 'Stop $index Road, Manila',
        ),
      );
      const hub = NavigationStop(
        id: 'hub',
        name: 'Assigned hub',
        address: '100 Hub Road, Manila',
      );
      final links = NavigationService.fullRoute(stops, hub);
      final destinations = <String>[];
      for (final uri in links) {
        final points = uri.queryParameters['waypoints']?.split('|') ?? [];
        expect(points.length, lessThanOrEqualTo(3));
        destinations.addAll([...points, uri.queryParameters['destination']!]);
        expect(uri.toString().length, lessThanOrEqualTo(2048));
      }
      expect(destinations, [...stops.map((stop) => stop.address), hub.address]);
      expect(links.last.queryParameters['destination'], hub.address);
    },
  );

  test(
    'Unavailable or oversized addresses are reported instead of dropping stops',
    () {
      const hub = NavigationStop(id: 'hub', name: '', address: 'Hub Road');
      expect(
        () => NavigationService.fullRoute([
          const NavigationStop(id: '1', name: 'Only a name', address: ''),
        ], hub),
        throwsFormatException,
      );
      expect(
        () => NavigationService.fullRoute([
          NavigationStop(id: '1', name: '', address: 'x' * 3000),
        ], hub),
        throwsFormatException,
      );
    },
  );

  test(
    'Coordinates and straight-line distance stay valid at zero and geographic limits',
    () {
      expect(GeoPoint.parse(0, 0), isNotNull);
      expect(GeoPoint.parse('NaN', 120), isNull);
      expect(GeoPoint.parse(91, 120), isNull);
      expect(GeoPoint.parse(14, -181), isNull);
      expect(
        const GeoPoint(0, 0).distanceTo(const GeoPoint(1, 0)),
        closeTo(111194.9, 1),
      );
      expect(
        const GeoPoint(14.6, 120.98).distanceTo(const GeoPoint(14.6, 120.98)),
        0,
      );
    },
  );

  test(
    'Phone links accept real phone numbers and reject arbitrary URI input',
    () {
      expect(
        NavigationService.phoneNumber('+63 917-123-4567'),
        '+639171234567',
      );
      expect(NavigationService.phoneNumber('09171234567'), '09171234567');
      expect(
        NavigationService.phoneNumber('tel:09171234567?body=text'),
        isNull,
      );
      expect(NavigationService.phoneNumber('*123#'), isNull);
      expect(NavigationService.phoneNumber(''), isNull);
    },
  );
}
