import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/services/account_service.dart';
import '../../core/services/order_service.dart';
import '../../models/courier.dart';
import '../../widgets/gradient_header.dart';

enum _PhotoAction { camera, gallery, remove }

class AccountScreen extends StatefulWidget {
  /// Back arrow sa header (galing sa MainShell).
  final VoidCallback? onBack;
  const AccountScreen({super.key, this.onBack});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  static const _vehicles = ['Trike', 'Motor', 'Van'];

  final _first = TextEditingController();
  final _last = TextEditingController();
  final _emailC = TextEditingController();
  final _phone = TextEditingController();
  final _plate = TextEditingController();
  final _barangay = TextEditingController();
  final _street = TextEditingController();

  String _displayName = '';
  String _province = '';
  String _municipality = '';
  String get _place =>
      [_municipality, _province].where((e) => e.isNotEmpty).join(', ');
  String _photoUrl = '';
  String? _vehicle;
  Uint8List? _preview;

  bool _loading = true;
  bool _hasData = false;
  bool _saving = false;
  bool _uploading = false;
  bool _vehicleOpen = true;
  bool _addressOpen = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (Courier.current.id > 0) {
      _fill(Courier.current);
      _hasData = true;
      _loading = false;
    }
    _load();
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _emailC.dispose();
    _phone.dispose();
    _plate.dispose();
    _barangay.dispose();
    _street.dispose();
    super.dispose();
  }

  String _err(Object e) {
    try {
      return (e as dynamic).message.toString();
    } catch (_) {
      return e.toString();
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _fill(Courier c) {
    var first = c.firstName;
    var last = c.lastName;
    if (first.isEmpty && last.isEmpty && c.name.trim().isNotEmpty) {
      final parts = c.name.trim().split(RegExp(r'\s+'));
      first = parts.first;
      last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    }
    _first.text = first;
    _last.text = last;
    _emailC.text = c.email;
    _displayName = c.name;
    _province = c.province;
    _municipality = c.municipality;
    _phone.text = c.phone;
    _plate.text = c.plate;
    _barangay.text = c.barangay;
    _street.text = c.street;
    _vehicle = _vehicles.contains(c.vehicle) ? c.vehicle : null;
    _photoUrl = c.photoUrl;
    if (c.photoUrl.isNotEmpty) _preview = null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = !_hasData;
      _error = null;
    });
    try {
      final c = Courier.fromJson(
        await OrderService.account(forceRefresh: true),
      );
      Courier.current = c;
      if (!mounted) return;
      setState(() {
        _fill(c);
        _hasData = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _err(e);
        _loading = false;
      });
    }
  }

  // ---------- photo ----------

  Future<void> _choosePhoto() async {
    final cs = Theme.of(context).colorScheme;
    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Profile photo',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: cs.primary),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, _PhotoAction.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: cs.primary),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, _PhotoAction.gallery),
            ),
            if (_photoUrl.isNotEmpty)
              ListTile(
                leading: Icon(Icons.delete_outline, color: cs.error),
                title: const Text('Remove photo'),
                onTap: () => Navigator.pop(ctx, _PhotoAction.remove),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == _PhotoAction.remove) {
      await _removePhoto();
    } else {
      await _pickAndUpload(
        action == _PhotoAction.camera
            ? ImageSource.camera
            : ImageSource.gallery,
      );
    }
  }

  Future<void> _pickAndUpload(ImageSource src) async {
    try {
      final x = await ImagePicker().pickImage(
        source: src,
        maxWidth: 900,
        imageQuality: 80,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      setState(() {
        _preview = bytes;
        _uploading = true;
      });
      final c = Courier.fromJson(
        await AccountService.uploadPhoto(x),
        fallback: Courier.current,
      );
      Courier.current = c;
      if (!mounted) return;
      setState(() {
        _photoUrl = c.photoUrl;
        _preview = null;
      });
      _snack('Profile photo updated.');
    } catch (e) {
      if (mounted) setState(() => _preview = null);
      _snack(_err(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removePhoto() async {
    setState(() => _uploading = true);
    try {
      await AccountService.removePhoto();
      Courier.current = Courier.fromJson({
        'courier': {'photo_url': null},
      }, fallback: Courier.current);
      if (!mounted) return;
      setState(() {
        _photoUrl = '';
        _preview = null;
      });
      _snack('Profile photo removed.');
    } catch (e) {
      _snack(_err(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ---------- save ----------

  Future<void> _save() async {
    final first = _first.text.trim();
    final last = _last.text.trim();
    final email = _emailC.text.trim().toLowerCase();
    final phone = _phone.text.trim().replaceAll(' ', '');
    final plate = _plate.text.trim();
    final barangay = _barangay.text.trim();
    final street = _street.text.trim();

    if (first.length < 2 || last.length < 2) {
      _snack('Please enter your first and last name.');
      return;
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _snack('Please enter a valid email address.');
      return;
    }
    if (!RegExp(r'^09\d{9}$').hasMatch(phone)) {
      _snack('Phone number must be 09xxxxxxxxx (11 digits).');
      return;
    }
    if (barangay.isEmpty || street.isEmpty) {
      _snack('Please complete the barangay and street address.');
      return;
    }

    final oldEmail = Courier.current.email;
    setState(() => _saving = true);
    try {
      await OrderService.updateAccount({
        'first_name': first,
        'last_name': last,
        'email': email,
        'contact_no': phone,
        if (_vehicle != null) 'vehicle_type': _vehicle,
        if (plate.isNotEmpty) 'plate_number': plate,
        'province': _province,
        'municipality': _municipality,
        'barangay': barangay,
        'street_address': street,
      });
      final c = Courier.fromJson(
        await OrderService.account(forceRefresh: true),
      );
      Courier.current = c;
      if (!mounted) return;
      setState(() => _fill(c));
      _snack(
        oldEmail.isNotEmpty && oldEmail != email
            ? 'Saved. Use your new email the next time you log in.'
            : 'Changes saved.',
      );
    } catch (e) {
      _snack(_err(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------- change password ----------

  Future<void> _changePassword() async {
    final cur = TextEditingController();
    final pw = TextEditingController();
    final cf = TextEditingController();
    String? err;
    bool busy = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Change password'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: cur,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Current password',
                  ),
                ),
                TextField(
                  controller: pw,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New password (min 8)',
                  ),
                ),
                TextField(
                  controller: cf,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
                  ),
                ),
                if (err != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      err!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (cur.text.isEmpty) {
                        setD(() => err = 'Enter your current password.');
                        return;
                      }
                      if (pw.text.length < 8) {
                        setD(
                          () => err =
                              'New password must be at least 8 characters.',
                        );
                        return;
                      }
                      if (pw.text != cf.text) {
                        setD(() => err = 'New passwords do not match.');
                        return;
                      }
                      setD(() {
                        busy = true;
                        err = null;
                      });
                      try {
                        await OrderService.changePassword(
                          cur.text,
                          pw.text,
                          cf.text,
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setD(() {
                          busy = false;
                          err = _err(e);
                        });
                      }
                    },
              child: Text(busy ? 'Saving...' : 'Update'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) _snack('Password updated.');
  }

  // ---------- widgets ----------

  InputDecoration _deco(ColorScheme cs, String label, IconData icon) {
    OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: c == Colors.transparent
          ? BorderSide.none
          : BorderSide(color: c, width: w),
    );
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        fontSize: 14,
        color: cs.onSurface.withValues(alpha: 0.6),
      ),
      floatingLabelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: cs.primary,
      ),
      prefixIcon: Padding(
        padding: const EdgeInsets.all(10),
        child: Container(
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 19, color: cs.primary),
        ),
      ),
      filled: true,
      fillColor: cs.primary.withValues(alpha: 0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: b(Colors.transparent, 0),
      enabledBorder: b(Colors.transparent, 0),
      focusedBorder: b(cs.primary, 1.5),
    );
  }

  Widget _field(
    ColorScheme cs,
    TextEditingController c,
    String label,
    IconData icon, {
    TextInputType? type,
    TextCapitalization cap = TextCapitalization.none,
  }) {
    return TextField(
      controller: c,
      keyboardType: type,
      textCapitalization: cap,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: cs.onSurface,
      ),
      decoration: _deco(cs, label, icon),
    );
  }

  String get _initial {
    final n = _displayName.trim();
    return n.isEmpty ? 'C' : n[0].toUpperCase();
  }

  Widget _initialBox(ColorScheme cs) => Container(
    color: cs.primaryContainer,
    alignment: Alignment.center,
    child: Text(
      _initial,
      style: TextStyle(
        fontSize: 40,
        fontWeight: FontWeight.w700,
        color: cs.primary,
      ),
    ),
  );

  Widget _avatar(ColorScheme cs) {
    const size = 112.0;
    Widget face;
    if (_preview != null) {
      face = Image.memory(_preview!, fit: BoxFit.cover);
    } else if (_photoUrl.isNotEmpty) {
      face = Image.network(
        _photoUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _initialBox(cs),
      );
    } else {
      face = _initialBox(cs);
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipOval(child: face),
            ),
          ),
          if (_uploading)
            Positioned.fill(
              child: ClipOval(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Material(
              color: cs.primary,
              shape: const CircleBorder(
                side: BorderSide(color: Colors.white, width: 3),
              ),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _uploading ? null : _choosePhoto,
                child: const Padding(
                  padding: EdgeInsets.all(9),
                  child: Icon(
                    Icons.photo_camera,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _nameBlock(ColorScheme cs) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
    child: Column(
      children: [
        Text(
          _displayName.isEmpty ? 'Courier' : _displayName,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
          ),
        ),
        if (_emailC.text.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            _emailC.text,
            style: TextStyle(
              fontSize: 13.5,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _uploading ? null : _choosePhoto,
          icon: const Icon(Icons.photo_camera_outlined, size: 18),
          label: const Text('Change photo'),
          style: OutlinedButton.styleFrom(
            foregroundColor: cs.primary,
            side: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ],
    ),
  );

  List<Widget> _body(ColorScheme cs) {
    if (_loading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    if (_error != null && !_hasData) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text('Unable to load: $_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      ];
    }

    return [
      _nameBlock(cs),
      SectionCard(
        title: 'Personal info',
        icon: Icons.person_outline,
        gap: 12,
        children: [
          _field(
            cs,
            _first,
            'First name',
            Icons.badge_outlined,
            cap: TextCapitalization.words,
          ),
          _field(
            cs,
            _last,
            'Last name',
            Icons.badge_outlined,
            cap: TextCapitalization.words,
          ),
          _field(
            cs,
            _emailC,
            'Email',
            Icons.mail_outline,
            type: TextInputType.emailAddress,
          ),
          _field(
            cs,
            _phone,
            'Phone (09xxxxxxxxx)',
            Icons.phone_outlined,
            type: TextInputType.phone,
          ),
        ],
      ),
      SectionCard(
        title: 'Vehicle',
        icon: Icons.local_shipping_outlined,
        gap: 12,
        collapsible: true,
        expanded: _vehicleOpen,
        onToggle: () => setState(() => _vehicleOpen = !_vehicleOpen),
        children: [
          DropdownButtonFormField<String>(
            value: _vehicle,
            isExpanded: true,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: cs.onSurface,
            ),
            decoration: _deco(cs, 'Vehicle', Icons.local_shipping_outlined),
            items: [
              for (final v in _vehicles)
                DropdownMenuItem(value: v, child: Text(v)),
            ],
            onChanged: (v) => setState(() => _vehicle = v),
          ),
          _field(
            cs,
            _plate,
            'Plate number',
            Icons.pin_outlined,
            cap: TextCapitalization.characters,
          ),
        ],
      ),
      SectionCard(
        title: 'Address',
        icon: Icons.location_on_outlined,
        gap: 12,
        collapsible: true,
        expanded: _addressOpen,
        onToggle: () => setState(() => _addressOpen = !_addressOpen),
        children: [
          if (_place.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.location_city_outlined,
                      size: 19,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'City / Province',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _place,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          _field(
            cs,
            _barangay,
            'Barangay',
            Icons.home_work_outlined,
            cap: TextCapitalization.words,
          ),
          _field(
            cs,
            _street,
            'Street address',
            Icons.signpost_outlined,
            cap: TextCapitalization.words,
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined, size: 20),
          label: Text(
            _saving ? 'Saving...' : 'Save changes',
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        child: OutlinedButton.icon(
          onPressed: _changePassword,
          icon: const Icon(Icons.lock_outline, size: 18),
          label: const Text(
            'Change password',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: cs.primary,
            minimumSize: const Size.fromHeight(52),
            side: BorderSide(color: cs.onSurface.withValues(alpha: 0.12)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pageBg = Theme.of(context).scaffoldBackgroundColor;

    return Container(
      color: pageBg,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            GradientPageHeader(
              plain: true,
              icon: Icons.person,
              title: 'Account',
              subtitle: 'Manage your personal information',
              onBack: widget.onBack,
              child: _hasData ? _avatar(cs) : null,
            ),
            ..._body(cs),
          ],
        ),
      ),
    );
  }
}
