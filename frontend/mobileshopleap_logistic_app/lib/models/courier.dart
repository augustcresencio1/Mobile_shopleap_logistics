import 'package:flutter/foundation.dart';

class Courier {
  /// CourierProfile id (kapareho ng orders.pickup_rider_id / delivery_rider_id).
  int id;
  String name,
      email,
      phone,
      vehicle,
      plate,
      barangay,
      street,
      municipality,
      province;
  String firstName, lastName, photoUrl;

  Courier({
    this.id = 0,
    required this.name,
    this.email = '',
    required this.phone,
    required this.vehicle,
    required this.plate,
    this.barangay = '',
    this.street = '',
    this.municipality = '',
    this.province = '',
    this.firstName = '',
    this.lastName = '',
    this.photoUrl = '',
  });

  static String _s(dynamic v) => (v ?? '').toString().trim();

  static Map<String, dynamic> _m(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  /// j = {email, name?, user?:{...}, courier:{...}} galing sa GET /courier/me
  factory Courier.fromJson(Map<String, dynamic> j, {Courier? fallback}) {
    final c = _m(j['courier']);
    final u = _m(j['user']);
    String field(String key, String? previous) =>
        c.containsKey(key) ? _s(c[key]) : previous ?? '';

    final email = _s(j['email']).isNotEmpty
        ? _s(j['email'])
        : _s(u['email']).isNotEmpty
        ? _s(u['email'])
        : fallback?.email ?? '';
    final first = field('first_name', fallback?.firstName);
    final last = field('last_name', fallback?.lastName);

    var name = _s(c['name']);
    if (name.isEmpty) name = _s(j['name']);
    if (name.isEmpty) name = _s(u['name']);
    if (name.isEmpty) {
      name = [
        'first_name',
        'middle_initial',
        'last_name',
      ].map((k) => _s(c[k])).where((e) => e.isNotEmpty).join(' ');
    }
    if (name.isEmpty) name = fallback?.name ?? email;

    const photoKeys = ['avatar_url', 'photo_url', 'profile_photo_url'];
    final hasPhoto = [c, j, u].any((map) => photoKeys.any(map.containsKey));
    final photo =
        [
              for (final map in [c, j, u])
                for (final key in photoKeys) map[key],
            ]
            .map(_s)
            .firstWhere(
              (x) => x.isNotEmpty,
              orElse: () => hasPhoto ? '' : fallback?.photoUrl ?? '',
            );

    return Courier(
      id: int.tryParse(_s(c['id'])) ?? fallback?.id ?? 0,
      name: name,
      email: email,
      phone: field('contact_no', fallback?.phone),
      vehicle: field('vehicle_type', fallback?.vehicle),
      plate: field('plate_number', fallback?.plate),
      barangay: field('barangay', fallback?.barangay),
      street: field('street_address', fallback?.street),
      municipality: field('municipality', fallback?.municipality),
      province: field('province', fallback?.province),
      firstName: first,
      lastName: last,
      photoUrl: photo,
    );
  }

  static Courier _current = Courier(
    name: '',
    phone: '',
    vehicle: '',
    plate: '',
  );

  /// Tumataas/nagbabago kapag may bagong `current` (para malaman ng MainShell
  /// kung kailan pwede nang mag-subscribe sa realtime channel).
  static final ValueNotifier<int> idChanged = ValueNotifier<int>(0);

  /// Napupunan pagkatapos ma-load ang /courier/me.
  static Courier get current => _current;
  static set current(Courier c) {
    _current = c;
    idChanged.value = c.id;
  }
}
