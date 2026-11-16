import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class RiderLocationService {
  static const settings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10,
  );

  static Future<void> ensurePermission({bool background = false}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const FormatException(
        'Turn on phone location services, then try again.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (background &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.always) {
        throw const FormatException(
          'Allow Always location access in app settings to share an active trip while using Maps.',
        );
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw const FormatException(
        'Allow location access in the phone app settings.',
      );
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw const FormatException(
        'Location permission is needed to use GPS and confirm arrival.',
      );
    }
  }

  static Future<Position> current() async {
    await ensurePermission();
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  }

  static Stream<Position> updates() =>
      Geolocator.getPositionStream(locationSettings: settings);

  static Future<void> prepareLiveTracking() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final allowed = await const MethodChannel(
          'shopleap/rider_tracking',
        ).invokeMethod<bool>('requestNotificationPermission');
        if (allowed == false) {
          throw const FormatException(
            'Allow notifications in app settings so live trip tracking can stay visible while using Maps.',
          );
        }
      } on MissingPluginException {
        // Tests and unsupported desktop platforms do not have this channel.
      }
    }
    await ensurePermission(background: true);
  }

  static Stream<Position> liveUpdates() {
    final LocationSettings liveSettings;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      liveSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'ShopLeap live trip',
          notificationText:
              'Ibinabahagi ang lokasyon ng trip. Buksan ang ShopLeap para itigil.',
          notificationChannelName: 'Live trip location',
          notificationIcon: AndroidResource(
            name: 'ic_stat_shopleap',
            defType: 'drawable',
          ),
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      liveSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    } else {
      liveSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );
    }
    return Geolocator.getPositionStream(locationSettings: liveSettings);
  }
}