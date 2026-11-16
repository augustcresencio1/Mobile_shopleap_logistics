import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../core/theme/app_colors.dart';
import '../core/services/battery_settings.dart';
import '../core/services/navigation_service.dart';
import '../core/services/rider_location_service.dart';
import '../core/services/rider_tracking_service.dart';
import '../models/navigation.dart';
import '../models/order.dart';
import '../screens/navigation/rider_route_screen.dart';
import 'styled_parts.dart';

class RiderNavigationCard extends StatefulWidget {
  final Order order;
  final String role;
  final bool compact;
  const RiderNavigationCard({
    super.key,
    required this.order,
    required this.role,
    this.compact = false,
  });

  @override
  State<RiderNavigationCard> createState() => _RiderNavigationCardState();
}

class _RiderNavigationCardState extends State<RiderNavigationCard> {
  final _live = RiderTrackingService.instance;
  Position? _position;
  RiderRoute? _route;
  late NavigationStop _stop;
  bool _tracking = false, _starting = false, _arriving = false;
  String? _gpsError, _arrival;

  @override
  void initState() {
    super.initState();
    _live.addListener(_onTracking);
    final order = widget.order;
    final pickup = widget.role == 'pickup';
    final address = pickup ? order.pickupAddress : order.to;
    _stop = NavigationStop(
      id: order.id,
      name: pickup ? order.seller : order.buyer,
      address: address,
      phone: pickup ? order.sellerContact : order.buyerContact,
      pin: pickup ? order.pickupPin : order.deliveryPin,
    );
    _loadRoute();
    _onTracking();
  }

  Future<void> _loadRoute() async {
    try {
      final route = await NavigationService.route(widget.role);
      if (!mounted) return;
      setState(() {
        _route = route;
        for (final stop in route.stops) {
          if (stop.id == widget.order.id) _stop = stop;
        }
      });
    } catch (_) {
      /* Single-stop navigation still uses the order address. */
    }
  }

  @override
  void dispose() {
    _live.removeListener(_onTracking);
    super.dispose();
  }

  void _onTracking() {
    if (!mounted) return;
    setState(() {
      final matching = _live.matches(widget.order.id, widget.role);
      _tracking = matching && _live.tracking;
      _starting = _live.starting;
      if (matching) {
        _position = _live.position;
        _gpsError = _live.error;
      }
    });
  }

  String _message(Object error) =>
      error is FormatException ? error.message : error.toString();

  Future<void> _launch(Uri uri) async {
    try {
      await NavigationService.open(uri);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_message(error))));
      }
    }
  }

  Future<void> _navigate() async {
    try {
      final uri = NavigationService.directions(_stop);
      await _launch(uri);
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _startGps() async {
    if (_starting) return;
    await BatterySettings.explainLocationOnce(context);
    if (!mounted) return;
    final openedSettings = await BatterySettings.promptOnce(context);
    if (!mounted) return;
    if (openedSettings) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pagkatapos i-set ang battery, bumalik dito at pindutin ulit ang "Start live trip".',
          ),
        ),
      );
      return;
    }
    setState(() {
      _starting = true;
      _gpsError = null;
    });
    try {
      await _live.start(widget.order.id, widget.role);
    } catch (error) {
      if (mounted) setState(() => _gpsError = _message(error));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _arrived() async {
    setState(() => _arriving = true);
    try {
      final position = await RiderLocationService.current();
      if (!mounted) return;
      final result = await NavigationService.arrived(
        widget.order.id,
        widget.role,
        location: GeoPoint(position.latitude, position.longitude),
        accuracy: position.accuracy,
        recordedAt: position.timestamp,
      );
      if (!mounted) return;
      setState(() {
        _position = position;
        _arrival = [
          result['message'],
          result['warning'],
        ].whereType<String>().join(' ');
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_arrival!)));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_message(error))));
      }
    } finally {
      if (mounted) setState(() => _arriving = false);
    }
  }

  String get _distanceLabel {
    final position = _position;
    if (position == null || !_tracking) {
      if (widget.compact) {
        return 'Share live GPS with your hub; see distance & ETA.';
      }
      return 'Start a live trip to share location with your assigned hub and see straight-line distance and estimated ETA.';
    }
    if (_stop.pin == null) {
      return 'GPS ready. A destination pin is needed for distance and ETA.';
    }
    final distance = GeoPoint(
      position.latitude,
      position.longitude,
    ).distanceTo(_stop.pin!);
    final speed = position.speed.isFinite && position.speed >= 1
        ? position.speed
        : 20 / 3.6;
    final minutes = math.max(1, (distance / speed / 60).ceil());
    final length = distance < 1000
        ? '${distance.round()} m'
        : '${(distance / 1000).toStringAsFixed(1)} km';
    return '$length straight-line \u00B7 ~$minutes min\n'
        '${position.speed >= 1 ? 'Based on GPS speed' : 'Estimate at 20 km/h'}; road travel and traffic can take longer.';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final phone = NavigationService.phoneNumber(_stop.phone);
    final compact = widget.compact;
    final blue = compact ? kBrandBlue : cs.primary;

    final outlinedStyle = OutlinedButton.styleFrom(
      minimumSize: Size(0, compact ? 48 : 52),
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 12),
      shape: const StadiumBorder(),
      side: BorderSide(color: blue, width: compact ? 1 : 1.4),
      foregroundColor: blue,
      textStyle: TextStyle(
        fontSize: compact ? 12 : 16,
        fontWeight: FontWeight.w700,
      ),
    );

    final pillStyle = TextButton.styleFrom(
      backgroundColor: blue.withValues(alpha: 0.08),
      foregroundColor: blue,
      minimumSize: Size(0, compact ? 48 : 46),
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8),
      shape: const StadiumBorder(),
      textStyle: TextStyle(
        fontSize: compact ? 11 : 14,
        fontWeight: FontWeight.w600,
      ),
    );

    Widget contactAction(VoidCallback? onTap, IconData icon, String label) =>
        OutlinedButton(
          onPressed: onTap,
          style: outlinedStyle,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: compact ? 17 : 22),
                SizedBox(width: compact ? 4 : 8),
                Text(label),
              ],
            ),
          ),
        );

    Widget pill(VoidCallback? onTap, IconData icon, String label) => Expanded(
      child: TextButton(
        onPressed: onTap,
        style: pillStyle,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: compact ? 16 : 20),
              SizedBox(width: compact ? 4 : 6),
              Text(label),
            ],
          ),
        ),
      ),
    );

    return Container(
      margin: EdgeInsets.only(top: compact ? 8 : 6, bottom: compact ? 0 : 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(compact ? 16 : 22),
        border: Border.all(
          color: dark
              ? cs.onSurface.withValues(alpha: 0.1)
              : kBrandBlue.withValues(alpha: 0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: kBrandBlue.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header band
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14,
              vertical: compact ? 6 : 12,
            ),
            color: compact
                ? Color.alphaBlend(
                    kBrandBlue.withValues(alpha: 0.08),
                    cs.surface,
                  )
                : kBrandBlue,
            child: Row(
              children: [
                Container(
                  width: compact ? 22 : 36,
                  height: compact ? 22 : 36,
                  decoration: BoxDecoration(
                    color: compact ? Colors.transparent : kBrandBlue,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.navigation,
                    color: compact ? kBrandBlue : Colors.white,
                    size: compact ? 18 : 20,
                  ),
                ),
                SizedBox(width: compact ? 6 : 12),
                Flexible(
                  child: Text(
                    'Navigation & contact',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: compact ? 14 : 18,
                      color: compact ? kBrandBlue : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(compact ? 8 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: compact
                          ? contactAction(
                              _stop.canNavigate ? _navigate : null,
                              Icons.navigation_outlined,
                              'Navigate',
                            )
                          : GradientFilledButton(
                              label: 'Navigate',
                              icon: Icons.navigation_outlined,
                              expand: true,
                              onPressed: _stop.canNavigate ? _navigate : null,
                            ),
                    ),
                    if (widget.role != 'pickup') ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: contactAction(
                          phone == null
                              ? null
                              : () => _launch(Uri(scheme: 'tel', path: phone)),
                          Icons.call_outlined,
                          'Call',
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Expanded(
                      child: contactAction(
                        phone == null
                            ? null
                            : () => _launch(Uri(scheme: 'sms', path: phone)),
                        Icons.sms_outlined,
                        'Text',
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 6 : 12),
                Text(
                  _distanceLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: compact ? 11 : null,
                    height: compact ? 1.25 : null,
                  ),
                ),
                if (_gpsError != null) ...[
                  const SizedBox(height: 8),
                  Text(_gpsError!),
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: Geolocator.openAppSettings,
                        child: const Text('App settings'),
                      ),
                      TextButton(
                        onPressed: Geolocator.openLocationSettings,
                        child: const Text('Location settings'),
                      ),
                    ],
                  ),
                ],
                SizedBox(height: compact ? 6 : 12),
                Row(
                  children: [
                    pill(
                      _starting
                          ? null
                          : _tracking
                          ? () {
                              unawaited(_live.stop());
                            }
                          : _startGps,
                      Icons.my_location,
                      _starting
                          ? 'Getting GPS...'
                          : _tracking
                          ? 'Stop live trip'
                          : 'Start live trip',
                    ),
                    const SizedBox(width: 8),
                    pill(
                      _arriving ? null : _arrived,
                      Icons.flag_outlined,
                      _arriving ? 'Checking arrival...' : 'Arrived',
                    ),
                    const SizedBox(width: 8),
                    pill(
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RiderRouteScreen(
                            role: widget.role,
                            initialRoute: _route,
                          ),
                        ),
                      ),
                      Icons.alt_route,
                      'Full route',
                    ),
                  ],
                ),
                if (_tracking)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _live.live
                          ? 'Live location shared with your assigned hub. Continues while using Maps or when the phone is locked.'
                          : 'Waiting for a fresh GPS update or connection. Your hub sees the last known location.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (_arrival != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_arrival!),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}