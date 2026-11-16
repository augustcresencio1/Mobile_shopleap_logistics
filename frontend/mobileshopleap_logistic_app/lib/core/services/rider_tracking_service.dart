import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';

import 'api_client.dart';
import 'api_exception.dart';
import 'rider_location_service.dart';

/// One explicitly started trip per signed-in rider. Page navigation does not
/// own this stream: it stays alive while Google Maps is in the foreground.
class RiderTrackingService extends ChangeNotifier {
  static final instance = RiderTrackingService();
  static const interval = Duration(seconds: 5);
  final DateTime Function() _now;
  RiderTrackingService({DateTime Function()? now})
    : _now = now ?? DateTime.now {
    ApiClient.sessionExpired.addListener(reset);
  }

  String? orderId, role, error;
  Position? position;
  DateTime? lastSyncedAt;
  bool starting = false, tracking = false;
  String? _sessionId;
  int _generation = 0;
  DateTime? _lastAttempt;
  Timer? _timer;
  StreamSubscription<Position>? _subscription;
  Future<void>? _activation, _upload, _stoppingOperation;
  bool _stopping = false;

  bool matches(String id, String tripRole) => orderId == id && role == tripRole;
  bool get live =>
      tracking &&
      lastSyncedAt != null &&
      position != null &&
      _now().difference(lastSyncedAt!) < const Duration(seconds: 30) &&
      _now().difference(position!.timestamp) < const Duration(seconds: 30);

  String message(Object exception) =>
      exception is FormatException ? exception.message : exception.toString();

  Map<String, dynamic> _coordinates(Position fix) => {
    'latitude': fix.latitude,
    'longitude': fix.longitude,
    'accuracy': fix.accuracy,
    'recorded_at': fix.timestamp.toUtc().toIso8601String(),
    if (fix.speed.isFinite && fix.speed >= 0 && fix.speed <= 150)
      'speed': fix.speed,
    if (fix.heading.isFinite && fix.heading >= 0 && fix.heading <= 360)
      'heading': fix.heading,
  };

  Future<void> start(String id, String tripRole) {
    if (_activation != null) return _activation!;
    if (matches(id, tripRole) && tracking) return Future.value();
    return _activation = _start(
      id,
      tripRole,
    ).whenComplete(() => _activation = null);
  }

  Future<void> _start(String id, String tripRole) async {
    final generation = ++_generation;
    starting = true;
    error = null;
    notifyListeners();
    try {
      await _stoppingOperation;
      if (generation != _generation) return;
      await _closeSession();
      if (generation != _generation) return;
      orderId = id;
      role = tripRole;
      await RiderLocationService.prepareLiveTracking();
      if (generation != _generation) return;
      final fix = await RiderLocationService.current();
      if (generation != _generation) return;
      _requireForeground();
      final body =
          await ApiClient.post(
                '/courier/tracking/start',
                body: {'order_id': id, 'role': tripRole, ..._coordinates(fix)},
                refreshCache: false,
                requestTimeout: const Duration(seconds: 8),
              )
              as Map;
      if (generation != _generation) {
        // stop() waits for this operation, then closes the newly created session.
        if (_stopping) {
          _sessionId = (body['data'] as Map)['session_id'] as String;
        }
        return;
      }
      _sessionId = (body['data'] as Map)['session_id'] as String;
      _requireForeground();
      position = fix;
      lastSyncedAt = _lastAttempt = _now();
      tracking = true;
      _subscription = RiderLocationService.liveUpdates().listen(
        (fix) {
          if (generation != _generation || !tracking) return;
          if (position == null ||
              !fix.timestamp.isBefore(position!.timestamp)) {
            position = fix;
          }
          notifyListeners();
          _scheduleUpload(generation);
        },
        onError: (Object exception) {
          if (generation != _generation) return;
          error = message(exception);
          unawaited(stop(keepError: true));
        },
      );
      _timer = Timer.periodic(interval, (_) {
        notifyListeners();
        _scheduleUpload(generation);
      });
    } catch (exception) {
      if (generation == _generation) {
        error = message(exception);
        await _closeSession();
      }
      rethrow;
    } finally {
      starting = false;
      notifyListeners();
    }
  }

  void _requireForeground() {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) {
      throw const FormatException(
        'Return to ShopLeap to start live trip tracking.',
      );
    }
  }

  void _scheduleUpload(int generation) {
    if (!tracking ||
        _upload != null ||
        position == null ||
        (_lastAttempt != null && _now().difference(_lastAttempt!) < interval)) {
      return;
    }
    _lastAttempt = _now();
    _upload = _publish(generation).whenComplete(() => _upload = null);
  }

  Future<void> _publish(int generation) async {
    try {
      if (_now().difference(position!.timestamp) >
          const Duration(seconds: 25)) {
        final fresh = await RiderLocationService.current();
        if (generation != _generation || !tracking) return;
        if (!fresh.timestamp.isBefore(position!.timestamp)) position = fresh;
      }
      if (generation != _generation || !tracking) return;
      await ApiClient.put(
        '/courier/tracking/location',
        body: {'session_id': _sessionId, ..._coordinates(position!)},
        refreshCache: false,
        requestTimeout: const Duration(seconds: 8),
      );
      if (generation != _generation) return;
      lastSyncedAt = _now();
      error = null;
    } catch (exception) {
      if (generation != _generation) return;
      error = message(exception);
      if (exception is ApiException &&
          [401, 403, 409].contains(exception.statusCode)) {
        _generation++;
        _halt();
        _sessionId = null;
      }
      // A failed connection retries on the next tick without blocking the UI.
    } finally {
      notifyListeners();
    }
  }

  void _halt() {
    tracking = false;
    _timer?.cancel();
    _timer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  Future<void> _closeSession() async {
    _halt();
    final session = _sessionId;
    _sessionId = null;
    await _upload;
    if (session != null) {
      try {
        await ApiClient.post(
          '/courier/tracking/stop',
          body: {'session_id': session},
          refreshCache: false,
          requestTimeout: const Duration(seconds: 8),
        );
      } catch (_) {
        // If offline, the hub marks the last fix stale after 30 seconds.
      }
    }
  }

  Future<void> stop({bool keepError = false}) {
    _stopping = true;
    _generation++;
    _halt();
    notifyListeners();
    return _stoppingOperation ??= _stop(
      keepError: keepError,
    ).whenComplete(() => _stoppingOperation = null);
  }

  Future<void> _stop({required bool keepError}) async {
    try {
      await _activation;
    } catch (_) {
      /* The start screen shows its error. */
    }
    await _closeSession();
    orderId = role = null;
    position = null;
    lastSyncedAt = null;
    if (!keepError) error = null;
    _stopping = false;
    notifyListeners();
  }

  Future<void> finish(String id, String tripRole) async {
    if (matches(id, tripRole)) await stop();
  }

  /// Authentication expiry must immediately stop sensors without another request.
  void reset() {
    _generation++;
    _halt();
    _sessionId = orderId = role = null;
    position = null;
    lastSyncedAt = null;
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    ApiClient.sessionExpired.removeListener(reset);
    reset();
    super.dispose();
  }
}
