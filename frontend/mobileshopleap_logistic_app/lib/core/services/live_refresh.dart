import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api_client.dart';

class LiveRefresh {
  LiveRefresh._();

  static final ValueNotifier<int> tick = ValueNotifier<int>(0);
  static final ValueNotifier<int> deliveriesChanged = ValueNotifier<int>(0);
  static int activePage = 0;
  static bool _polling = false;
  static bool get isPolling => _polling;

  /// Oras ng huling REALTIME push mula sa server (hindi polling).
  /// Ginagamit ng mga screen para mag-reload agad kapag may bagong push
  /// pagkatapos ng huling load nila.
  static DateTime lastPush = DateTime.fromMillisecondsSinceEpoch(0);

  static Timer? _fallbackTimer;
  static Timer? _debounce;
  static RealtimeChannel? _channel;
  static Future<void> _cleanup = Future<void>.value();
  static int _generation = 0;

  /// riderId = CourierProfile id. Kapag 0 pa (hindi pa na-load ang profile),
  /// polling muna kada 5s hanggang may id na.
  static void start(int riderId) {
    stop();

    if (riderId <= 0) {
      debugPrint('LiveRefresh: no rider id yet, polling every 5s');
      _setFallback(const Duration(seconds: 5));
      return;
    }

    debugPrint('LiveRefresh: subscribing to rider:$riderId');
    _setFallback(const Duration(seconds: 5)); // hanggang makakonekta
    unawaited(_subscribe(riderId, _generation));
  }

  static Future<void> _subscribe(int riderId, int generation) async {
    // Finish removal before reusing a topic on resume or account changes.
    await _cleanup;
    if (generation != _generation) return;
    try {
      _channel = Supabase.instance.client
          .channel('rider:$riderId')
          .onBroadcast(
            event: 'refresh',
            callback: (payload) {
              if (generation != _generation) return;
              debugPrint('LiveRefresh: PUSH received $payload');
              _scheduleTick();
            },
          )
          .subscribe((status, [error]) {
            if (generation != _generation) return;
            debugPrint('LiveRefresh: status=$status error=$error');
            if (status == RealtimeSubscribeStatus.subscribed) {
              // Nakakonekta: bihira na lang ang fallback, para lang sa nalampasang mensahe.
              _setFallback(const Duration(seconds: 60));
              ApiClient.invalidateCache();
              pokeNow(); // kunin ang anumang nalampasan habang offline
            } else if (status == RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut ||
                status == RealtimeSubscribeStatus.closed) {
              // Walang realtime: bumalik muna sa mabilis na polling.
              _setFallback(const Duration(seconds: 5));
            }
          });
    } catch (_) {
      debugPrint('LiveRefresh: subscription unavailable, polling every 5s');
    }
  }

  static void stop() {
    _generation++;
    _fallbackTimer?.cancel();
    _debounce?.cancel();
    _fallbackTimer = null;
    _debounce = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      _cleanup = _cleanup.then((_) async {
        try {
          await Supabase.instance.client.removeChannel(channel);
        } catch (_) {
          debugPrint('LiveRefresh: channel removal failed');
        }
      });
    }
  }

  static void _setFallback(Duration every) {
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer.periodic(every, (_) {
      // A slow request must finish before a polling tick starts another copy.
      ApiClient.invalidateCache(keepPending: true);
      _polling = true;
      try {
        pokeNow();
      } finally {
        _polling = false;
      }
    });
  }

  /// Pinagsasama ang sunod-sunod na signal para hindi dumoble ang API calls.
  static void _scheduleTick() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ApiClient.invalidateCache();
      lastPush = DateTime.now();
      pokeNow();
    });
  }

  static void pokeNow() => tick.value++;

  /// Refresh saved totals on every successful response, including retries.
  static void deliveryCompleted() {
    ApiClient.invalidateCache();
    lastPush = DateTime.now();
    deliveriesChanged.value++;
    pokeNow();
  }
}
