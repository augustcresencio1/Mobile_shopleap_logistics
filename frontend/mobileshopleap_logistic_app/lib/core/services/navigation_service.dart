import 'package:url_launcher/url_launcher.dart';
import '../../models/navigation.dart';
import 'api_client.dart';
import 'api_exception.dart';

class NavigationService {
  static Uri directions(
    NavigationStop destination, {
    List<NavigationStop> waypoints = const [],
    String? origin,
  }) {
    if (!destination.canNavigate ||
        waypoints.any((stop) => !stop.canNavigate)) {
      throw const FormatException('A stop is missing its address or pin.');
    }
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': destination.query,
      'travelmode': 'driving',
      'dir_action': 'navigate',
      'origin': ?origin,
      if (waypoints.isNotEmpty)
        'waypoints': waypoints.map((stop) => stop.query).join('|'),
    });
    if (uri.toString().length > 2048) {
      throw const FormatException('Route link is too long.');
    }
    return uri;
  }

  /// Mobile browser fallback supports three waypoints. Splitting also keeps
  /// every stop when a shift exceeds the Google Maps app's waypoint limit.
  static List<Uri> fullRoute(
    List<NavigationStop> stops,
    NavigationStop station,
  ) {
    final remaining = [...stops, station];
    if (remaining.any((stop) => !stop.canNavigate)) {
      throw const FormatException(
        'Every stop and the station need an address or pin.',
      );
    }
    final links = <Uri>[];
    String? origin;
    while (remaining.isNotEmpty) {
      var count = remaining.length > 4 ? 4 : remaining.length;
      Uri? link;
      while (count > 0) {
        try {
          link = directions(
            remaining[count - 1],
            waypoints: remaining.take(count - 1).toList(),
            origin: origin,
          );
          break;
        } on FormatException {
          count--;
        }
      }
      if (link == null) {
        throw const FormatException(
          'A stop address is too long for a Maps link.',
        );
      }
      links.add(link);
      origin = remaining[count - 1].query;
      remaining.removeRange(0, count);
    }
    return links;
  }

  static String? phoneNumber(String raw) {
    final number = raw.replaceAll(RegExp(r'[\s().-]'), '');
    return RegExp(r'^\+?\d{7,15}$').hasMatch(number) ? number : null;
  }

  static Future<void> open(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw ApiException('No app is available to open this action.');
    }
  }

  static Future<RiderRoute> route(String role) async => RiderRoute.fromJson(
    Map<String, dynamic>.from(
      await ApiClient.get(
            '/courier/navigation/route',
            query: {'role': role},
            cacheFor: const Duration(seconds: 10),
          )
          as Map,
    ),
  );

  static Future<Map<String, dynamic>> arrived(
    String orderId,
    String role, {
    required GeoPoint location,
    required double accuracy,
    required DateTime recordedAt,
  }) async => Map<String, dynamic>.from(
    await ApiClient.post(
          '/courier/orders/$orderId/arrived',
          body: {
            'role': role,
            'latitude': location.latitude,
            'longitude': location.longitude,
            'accuracy': accuracy,
            'recorded_at': recordedAt.toUtc().toIso8601String(),
          },
        )
        as Map,
  );
}
