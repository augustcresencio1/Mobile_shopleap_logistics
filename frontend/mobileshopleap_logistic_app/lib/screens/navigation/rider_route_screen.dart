import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'package:flutter/services.dart';
import '../../core/services/navigation_service.dart';
import '../../models/navigation.dart';

class FullRouteButton extends StatelessWidget {
  final String role;
  const FullRouteButton({super.key, required this.role});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: OutlinedButton.icon(
      icon: const Icon(Icons.alt_route),
      label: const Text('Full route to assigned hub'),
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RiderRouteScreen(role: role)),
      ),
    ),
  );
}

class RiderRouteScreen extends StatefulWidget {
  final String role;
  final RiderRoute? initialRoute;
  const RiderRouteScreen({super.key, required this.role, this.initialRoute});
  @override
  State<RiderRouteScreen> createState() => _RiderRouteScreenState();
}

class _RiderRouteScreenState extends State<RiderRouteScreen> {
  RiderRoute? _route;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _route = widget.initialRoute;
    _load();
  }

  Future<void> _load() async {
    try {
      final route = await NavigationService.route(widget.role);
      if (mounted) {
        setState(() {
          _route = route;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _open(Uri uri) async {
    try {
      await NavigationService.open(uri);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _navigate(NavigationStop stop) async {
    try {
      await _open(NavigationService.directions(stop));
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _fullRoute() async {
    final station = _route?.station;
    if (station == null) return;
    try {
      final links = NavigationService.fullRoute(_route!.stops, station);
      if (links.length == 1) {
        await _open(links.single);
        return;
      }
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Open each route section in order. The last section ends at your assigned hub.',
                ),
              ),
              for (var index = 0; index < links.length; index++)
                ListTile(
                  leading: const Icon(Icons.navigation_outlined),
                  title: Text('Route ${index + 1} of ${links.length}'),
                  onTap: () => _open(links[index]),
                ),
            ],
          ),
        ),
      );
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  // ---------- UI ----------

  Widget _header() {
    final top = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Container(
        width: double.infinity,
        color: kBrandBlue,
        padding: EdgeInsets.fromLTRB(8, top + 4, 16, 48),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back),
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              'Full route',
              style: TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _iconTile(IconData icon, {double size = 46, double iconSize = 24}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: cs.primary, size: iconSize),
    );
  }

  /// Tinted rounded row na may icon sa kaliwa at chevron sa kanan.
  Widget _actionRow({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool accent = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: cs.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 35,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: cs.primary, size: 21),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: accent ? cs.primary : cs.onSurface,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: cs.primary, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stop(NavigationStop stop, String label, {bool isHub = false}) {
    final cs = Theme.of(context).colorScheme;
    final phone = NavigationService.phoneNumber(stop.phone);
    return _card(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _iconTile(
                isHub ? Icons.warehouse_outlined : Icons.location_on_outlined,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stop.name,
                      style: TextStyle(
                        fontSize: 17.5,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 16,
                          color: cs.onSurface.withValues(alpha: 0.55),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            stop.address.isEmpty
                                ? 'No address saved'
                                : stop.address,
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _actionRow(
            icon: Icons.navigation_outlined,
            label: 'Navigate',
            onTap: stop.canNavigate ? () => _navigate(stop) : null,
          ),
          const SizedBox(height: 8),
          _actionRow(
            icon: Icons.call_outlined,
            label: 'Call',
            onTap: phone == null
                ? null
                : () => _open(Uri(scheme: 'tel', path: phone)),
          ),
          const SizedBox(height: 8),
          _actionRow(
            icon: Icons.sms_outlined,
            label: 'Text',
            onTap: phone == null
                ? null
                : () => _open(Uri(scheme: 'sms', path: phone)),
          ),
        ],
      ),
    );
  }

  Widget _summary(RiderRoute route) {
    final cs = Theme.of(context).colorScheme;
    final n = route.stops.length;
    return _card(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          _iconTile(Icons.route_outlined),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$n ${n == 1 ? 'stop' : 'stops'}',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  'Finish at your assigned hub',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: cs.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stateMessage() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$_error', textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _load, child: const Text('Try again')),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final route = _route;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            _header(),
            if (route == null)
              _stateMessage()
            else ...[
              Transform.translate(
                offset: const Offset(0, -28),
                child: Column(
                  children: [
                    _summary(route),
                    _card(
                      padding: const EdgeInsets.all(10),
                      child: _actionRow(
                        icon: Icons.location_on_outlined,
                        label: 'Open full route in Google Maps',
                        accent: true,
                        onTap: route.station?.canNavigate == true
                            ? _fullRoute
                            : null,
                      ),
                    ),
                    for (var index = 0; index < route.stops.length; index++)
                      _stop(route.stops[index], 'Stop ${index + 1}'),
                    if (route.station != null)
                      _stop(
                        route.station!,
                        'Finish: assigned hub',
                        isHub: true,
                      ),
                    if (route.station?.canNavigate != true)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        child: Text(
                          'The assigned hub needs an address or pin before a full route can be opened.',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
