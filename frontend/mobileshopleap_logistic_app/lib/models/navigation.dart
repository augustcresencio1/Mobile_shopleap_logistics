import 'dart:math' as math;

class GeoPoint {
  final double latitude, longitude;
  const GeoPoint(this.latitude, this.longitude);

  static GeoPoint? parse(Object? latitude, Object? longitude) {
    final lat = double.tryParse('$latitude');
    final lng = double.tryParse('$longitude');
    if (lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180) {
      return null;
    }
    return GeoPoint(lat, lng);
  }

  String get query => '$latitude,$longitude';

  double distanceTo(GeoPoint other) {
    double radians(double degrees) => degrees * math.pi / 180;
    final dLat = radians(other.latitude - latitude);
    final dLng = radians(other.longitude - longitude);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(radians(latitude)) *
            math.cos(radians(other.latitude)) *
            math.pow(math.sin(dLng / 2), 2);
    return 6371000 * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
  }
}

class NavigationStop {
  final String id, name, address, phone;
  final GeoPoint? pin;
  const NavigationStop({
    required this.id,
    required this.name,
    required this.address,
    this.phone = '',
    this.pin,
  });

  factory NavigationStop.fromJson(Map<String, dynamic> json) => NavigationStop(
    id: '${json['order_id'] ?? json['id'] ?? ''}',
    name: '${json['name'] ?? ''}',
    address: '${json['address'] ?? ''}'.trim(),
    phone: '${json['phone'] ?? ''}',
    pin: GeoPoint.parse(json['latitude'], json['longitude']),
  );

  bool get canNavigate => pin != null || address.isNotEmpty;
  // Never append a person's name, pickup schedule, or order number to Maps.
  String get query => pin?.query ?? address;
}

class RiderRoute {
  final NavigationStop? station;
  final List<NavigationStop> stops;
  RiderRoute.fromJson(Map<String, dynamic> json)
    : station = json['station'] is Map
          ? NavigationStop.fromJson(
              Map<String, dynamic>.from(json['station'] as Map),
            )
          : null,
      stops = [
        for (final stop in (json['stops'] as List? ?? const []))
          NavigationStop.fromJson(Map<String, dynamic>.from(stop as Map)),
      ];
}
