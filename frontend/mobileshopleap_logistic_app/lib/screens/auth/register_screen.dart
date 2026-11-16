import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import 'otp_screen.dart';

const Color _kBrand = kBrandBlue;
const Color _kFieldBorder = Color(0xFFD3E5FA);
const Color _kMuted = Color(0xFF6B7A90);
const Color _kText = Color(0xFF1B2A41);

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const _psgc = 'https://psgc.gitlab.io/api';
  static const _vehicles = ['Trike', 'Motor', 'Van'];
  static const _stepLabels = ['Personal', 'Address', 'Vehicle', 'Documents'];

  static const Color _kHint = Color(0xFFA0AEC0);
  static const Color _kFieldFill = Color(0xFFF7FAFE);
  static const Color _kRequired = Color(0xFFE5484D);

  final _formKeys = List.generate(4, (_) => GlobalKey<FormState>());
  final _picker = ImagePicker();
  int _step = 0;

  // Personal
  final _last = TextEditingController();
  final _first = TextEditingController();
  final _mi = TextEditingController();
  final _email = TextEditingController();
  final _contact = TextEditingController();
  final _birthdayCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  String? _sex;
  DateTime? _birthday;

  // Address
  final _street = TextEditingController();
  final _house = TextEditingController();
  List<Map<String, dynamic>> _provinces = [],
      _municipalities = [],
      _barangays = [];
  Map<String, dynamic>? _province, _municipality, _barangay;
  List<Map<String, dynamic>> _hubs = [];
  Map<String, dynamic>? _hub;

  // Vehicle
  String? _vehicle;
  final _plate = TextEditingController();

  // Documents + password
  XFile? _orCr, _idLicense;
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _hidePass = true;

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load('$_psgc/provinces/').then((v) {
      if (mounted) setState(() => _provinces = v);
    });
    _loadHubs();
  }

  @override
  void dispose() {
    for (final c in [
      _last,
      _first,
      _mi,
      _email,
      _contact,
      _birthdayCtrl,
      _ageCtrl,
      _street,
      _house,
      _plate,
      _pass,
      _pass2,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------- data ----------

  Future<void> _loadHubs() async {
    try {
      final v = await AuthService.hubs();
      if (mounted) setState(() => _hubs = v);
    } on AuthException catch (e) {
      _snack(e.message);
    }
  }

  Future<List<Map<String, dynamic>>> _load(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      final list = List<Map<String, dynamic>>.from(jsonDecode(res.body));
      list.sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));
      return list;
    } catch (_) {
      _snack('Failed to load address data');
      return [];
    }
  }

  int? get _age {
    if (_birthday == null) return null;
    final t = DateTime.now();
    var a = t.year - _birthday!.year;
    if (t.month < _birthday!.month ||
        (t.month == _birthday!.month && t.day < _birthday!.day)) {
      a--;
    }
    return a;
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _pickBirthday() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(2000),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
    );
    if (d != null) {
      setState(() {
        _birthday = d;
        _birthdayCtrl.text = DateFormat('MMMM d, yyyy').format(d);
        _ageCtrl.text = _age?.toString() ?? '';
      });
    }
  }

  Future<XFile?> _pickImage() =>
      _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);

  // ---------- navigation / submit ----------

  void _back() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _step--);
    }
  }

  Future<void> _next() async {
    FocusScope.of(context).unfocus();
    if (!(_formKeys[_step].currentState?.validate() ?? false)) return;
    if (_step < _stepLabels.length - 1) {
      setState(() => _step++);
      return;
    }
    await _submit();
  }

  Future<void> _submit() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final err = await AuthService.register(
        fields: {
          'last_name': _last.text.trim(),
          'first_name': _first.text.trim(),
          'middle_initial': _mi.text.trim(),
          'sex': _sex!,
          'email': _email.text.trim(),
          'contact_no': _contact.text.trim(),
          'birthday': DateFormat('yyyy-MM-dd').format(_birthday!),
          'province': _province!['name'],
          'municipality': _municipality!['name'],
          'barangay': _barangay!['name'],
          'street_address': [
            _house.text.trim(),
            _street.text.trim(),
          ].where((s) => s.isNotEmpty).join(', '),
          'vehicle_type': _vehicle!,
          'plate_number': _plate.text.trim(),
          'hub_id': _hub!['id'].toString(),
          'password': _pass.text,
          'password_confirmation': _pass2.text,
        },
        orCr: _orCr!,
        license: _idLicense!,
      );
      if (!mounted) return;
      if (err != null) return _snack(err);

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OtpScreen(email: _email.text.trim())),
      );
    } catch (_) {
      _snack('Registration could not be submitted. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- field helpers ----------

  OutlineInputBorder _border(Color c, [double w = 1.2]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(28),
    borderSide: BorderSide(color: c, width: w),
  );

  InputDecoration _dec(String label, {IconData? icon, Widget? suffix}) =>
      InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _kMuted),
        prefixIcon: icon == null ? null : Icon(icon, color: _kBrand, size: 22),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: _border(_kFieldBorder),
        enabledBorder: _border(_kFieldBorder),
        disabledBorder: _border(_kFieldBorder),
        focusedBorder: _border(_kBrand, 1.8),
        errorBorder: _border(Colors.red.shade400),
        focusedErrorBorder: _border(Colors.red.shade600, 1.8),
      );

  /// Label-above style: placeholder lang ang nasa loob ng field.
  InputDecoration _decHint(String hint, {IconData? icon, Widget? suffix}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _kHint),
        prefixIcon: icon == null ? null : Icon(icon, color: _kBrand, size: 22),
        suffixIcon: suffix,
        filled: true,
        fillColor: _kFieldFill,
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        border: _border(_kFieldBorder),
        enabledBorder: _border(_kFieldBorder),
        disabledBorder: _border(_kFieldBorder),
        focusedBorder: _border(_kBrand, 1.8),
        errorBorder: _border(Colors.red.shade400),
        focusedErrorBorder: _border(Colors.red.shade600, 1.8),
      );

  Widget _label(String text, {bool required = false}) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text.rich(
      TextSpan(
        text: text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: _kText,
        ),
        children: [
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: _kRequired),
            ),
        ],
      ),
    ),
  );

  Widget _personalHeader() => Row(
    children: [
      Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: _kBrand.withOpacity(0.08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.person_outline, color: _kBrand),
      ),
      const SizedBox(width: 16),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'STEP 01',
              style: TextStyle(
                color: _kBrand,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Personal Information',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _kText,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Tell us a little about yourself.',
              style: TextStyle(color: _kMuted),
            ),
          ],
        ),
      ),
    ],
  );

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  Widget _gap() => const SizedBox(height: 14);

  Widget _field(
    TextEditingController c,
    String label, {
    IconData? icon,
    bool required = true,
    TextInputType? type,
    TextCapitalization caps = TextCapitalization.words,
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: c,
      keyboardType: type,
      textCapitalization: caps,
      maxLength: maxLength,
      decoration: _dec(required ? '$label*' : label, icon: icon),
      validator: validator ?? (required ? _req : null),
    );
  }

  Widget _drop(
    String label,
    IconData icon,
    Map<String, dynamic>? value,
    List<Map<String, dynamic>> items,
    ValueChanged<Map<String, dynamic>?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: value?['code']?.toString(),
      decoration: _dec('$label*', icon: icon),
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      items: items
          .map(
            (e) => DropdownMenuItem<String>(
              value: e['code'].toString(),
              child: Text(
                e['name'].toString(),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: items.isEmpty
          ? null
          : (c) =>
                onChanged(items.firstWhere((e) => e['code'].toString() == c)),
      validator: (v) => v == null ? 'Required' : null,
    );
  }

  String _hubLabel(Map<String, dynamic> e) {
    final name = (e['name'] ?? e['hub_name']).toString();
    final areas = e['service_areas'];
    if (areas is List && areas.isNotEmpty) {
      return '$name (${areas.join(', ')})';
    }
    return name;
  }

  Widget _hubDrop() {
    final noHubs = _hubs.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<int>(
          isExpanded: true,
          value: _hub == null ? null : (_hub!['id'] as num).toInt(),
          decoration: _dec('Logistics hub*', icon: Icons.warehouse_outlined),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          items: _hubs
              .map(
                (e) => DropdownMenuItem<int>(
                  value: (e['id'] as num).toInt(),
                  child: Text(_hubLabel(e), overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: noHubs
              ? null
              : (id) => setState(
                  () => _hub = _hubs.firstWhere(
                    (e) => (e['id'] as num).toInt() == id,
                  ),
                ),
          validator: (v) => v == null ? 'Required' : null,
        ),
        if (noHubs)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _loadHubs,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('No hubs loaded. Tap to reload'),
            ),
          ),
      ],
    );
  }

  Widget _uploadTile(String label, String hint, XFile? file, bool isOrCr) {
    return FormField<XFile>(
      validator: (_) => file == null ? '$label is required' : null,
      builder: (state) {
        final done = file != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                final f = await _pickImage();
                if (f != null) {
                  setState(() => isOrCr ? _orCr = f : _idLicense = f);
                  state.didChange(f);
                }
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: state.hasError
                        ? Colors.red.shade400
                        : (done ? _kBrand : _kFieldBorder),
                    width: done ? 1.6 : 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: done
                            ? _kBrand.withOpacity(0.1)
                            : const Color(0xFFF1F5FB),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        done ? Icons.check_circle : Icons.upload_file_outlined,
                        color: _kBrand,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$label*',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _kText,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            done ? file.name : hint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _kMuted,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      done ? 'Change' : 'Upload',
                      style: const TextStyle(
                        color: _kBrand,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 6),
                child: Text(
                  state.errorText!,
                  style: TextStyle(color: Colors.red.shade600, fontSize: 12),
                ),
              ),
          ],
        );
      },
    );
  }

  // ---------- steps ----------

  static const _stepPadding = EdgeInsets.fromLTRB(20, 8, 20, 16);

  Widget _personalStep() {
    return Form(
      key: _formKeys[0],
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: _stepPadding,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: _kFieldBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _personalHeader(),

                _label('First Name', required: true),
                TextFormField(
                  controller: _first,
                  textCapitalization: TextCapitalization.words,
                  decoration: _decHint('', icon: Icons.person_outline),
                  validator: _req,
                ),

                _label('Middle Initial'),
                TextFormField(
                  controller: _mi,
                  maxLength: 1,
                  textCapitalization: TextCapitalization.characters,
                  decoration: _decHint(''),
                ),

                _label('Last Name', required: true),
                TextFormField(
                  controller: _last,
                  textCapitalization: TextCapitalization.words,
                  decoration: _decHint(''),
                  validator: _req,
                ),

                _label('Sex', required: true),
                DropdownButtonFormField<String>(
                  value: _sex,
                  decoration: _decHint('Select sex'),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  items: const [
                    DropdownMenuItem(value: 'male', child: Text('Male')),
                    DropdownMenuItem(value: 'female', child: Text('Female')),
                  ],
                  onChanged: (v) => setState(() => _sex = v),
                  validator: (v) => v == null ? 'Required' : null,
                ),

                _label('E-mail', required: true),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textCapitalization: TextCapitalization.none,
                  decoration: _decHint('', icon: Icons.mail_outline),
                  validator: (v) => (v == null || !v.contains('@'))
                      ? 'Enter a valid email'
                      : null,
                ),

                _label('Contact No.', required: true),
                TextFormField(
                  controller: _contact,
                  keyboardType: TextInputType.phone,
                  textCapitalization: TextCapitalization.none,
                  decoration: _decHint('', icon: Icons.phone_outlined),
                  validator: (v) => RegExp(r'^09\d{9}$').hasMatch(v ?? '')
                      ? null
                      : 'Format: 09XXXXXXXXX',
                ),

                _label('Birthday', required: true),
                TextFormField(
                  controller: _birthdayCtrl,
                  readOnly: true,
                  onTap: _pickBirthday,
                  decoration: _decHint(
                    'Select birthday',
                    icon: Icons.calendar_today_outlined,
                    suffix: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  validator: (v) {
                    if (_birthday == null) return 'Please select your birthday';
                    if ((_age ?? 0) < 18) {
                      return 'You must be at least 18 years old';
                    }
                    return null;
                  },
                ),

                _label('Age'),
                TextFormField(
                  controller: _ageCtrl,
                  readOnly: true,
                  enabled: false,
                  decoration: _decHint(
                    'Automatically calculated',
                    icon: Icons.cake_outlined,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Automatically calculated from your birthday.',
                    style: TextStyle(color: _kMuted, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text.rich(
                TextSpan(
                  text: 'Already registered? ',
                  style: TextStyle(color: _kMuted),
                  children: [
                    TextSpan(
                      text: 'Sign in',
                      style: TextStyle(
                        color: _kText,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addressStep() {
    return Form(
      key: _formKeys[1],
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: _stepPadding,
        children: [
          _drop('Province', Icons.map_outlined, _province, _provinces, (
            v,
          ) async {
            setState(() {
              _province = v;
              _municipality = null;
              _barangay = null;
              _municipalities = [];
              _barangays = [];
            });
            final m = await _load(
              '$_psgc/provinces/${v!['code']}/cities-municipalities/',
            );
            if (mounted) setState(() => _municipalities = m);
          }),
          _gap(),
          _drop(
            'Municipality / City',
            Icons.location_city,
            _municipality,
            _municipalities,
            (v) async {
              setState(() {
                _municipality = v;
                _barangay = null;
                _barangays = [];
              });
              final b = await _load(
                '$_psgc/cities-municipalities/${v!['code']}/barangays/',
              );
              if (mounted) setState(() => _barangays = b);
            },
          ),
          _gap(),
          _drop(
            'Barangay',
            Icons.location_on_outlined,
            _barangay,
            _barangays,
            (v) => setState(() => _barangay = v),
          ),
          _gap(),
          _field(
            _street,
            'Street',
            icon: Icons.signpost_outlined,
            required: false,
          ),
          _gap(),
          _field(
            _house,
            'House number, etc.',
            icon: Icons.home_outlined,
            required: false,
          ),
          _gap(),
          _hubDrop(),
        ],
      ),
    );
  }

  Widget _vehicleStep() {
    return Form(
      key: _formKeys[2],
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: _stepPadding,
        children: [
          DropdownButtonFormField<String>(
            value: _vehicle,
            decoration: _dec(
              'Choose vehicle*',
              icon: Icons.two_wheeler_outlined,
            ),
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            items: _vehicles
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) => setState(() => _vehicle = v),
            validator: (v) => v == null ? 'Required' : null,
          ),
          _gap(),
          _field(
            _plate,
            'Plate number',
            icon: Icons.pin_outlined,
            caps: TextCapitalization.characters,
          ),
        ],
      ),
    );
  }

  Widget _documentsStep() {
    return Form(
      key: _formKeys[3],
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: _stepPadding,
        children: [
          const Text(
            'Upload clear photos. Your account will be reviewed before you can log in.',
            style: TextStyle(color: _kMuted, height: 1.4),
          ),
          const SizedBox(height: 16),
          _uploadTile(
            'OR/CR',
            'Official receipt and certificate of registration',
            _orCr,
            true,
          ),
          _gap(),
          _uploadTile(
            "ID / Driver's license",
            'Front side, valid and not expired',
            _idLicense,
            false,
          ),
          const SizedBox(height: 24),
          const Text(
            'Create password',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: _kText,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _pass,
            obscureText: _hidePass,
            decoration: _dec(
              'Password*',
              icon: Icons.lock_outline,
              suffix: IconButton(
                icon: Icon(
                  _hidePass ? Icons.visibility : Icons.visibility_off,
                  color: _kMuted,
                ),
                onPressed: () => setState(() => _hidePass = !_hidePass),
              ),
            ),
            validator: (v) =>
                (v ?? '').length < 8 ? 'At least 8 characters' : null,
          ),
          _gap(),
          TextFormField(
            controller: _pass2,
            obscureText: _hidePass,
            decoration: _dec('Confirm password*', icon: Icons.lock_outline),
            validator: (v) => v != _pass.text ? 'Passwords do not match' : null,
          ),
        ],
      ),
    );
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    final isLast = _step == _stepLabels.length - 1;
    final steps = [
      _personalStep(),
      _addressStep(),
      _vehicleStep(),
      _documentsStep(),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        canPop: _step == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _step--);
        },
        child: Scaffold(
          backgroundColor: kBrandBlue,
          body: Container(
            color: kBrandBlue,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    8,
                    MediaQuery.of(context).padding.top + 8,
                    16,
                    20,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _loading ? null : _back,
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Courier Registration',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: kBrandPaleBlue,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
                          child: _RegistrationProgress(
                            current: _step,
                            labels: _stepLabels,
                          ),
                        ),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: KeyedSubtree(
                              key: ValueKey(_step),
                              child: steps[_step],
                            ),
                          ),
                        ),
                        SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                            child: Opacity(
                              opacity: _loading ? 0.7 : 1,
                              child: Container(
                                width: double.infinity,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: kBrandBlue,
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x331B6FD8),
                                      blurRadius: 12,
                                      offset: Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(30),
                                    onTap: _loading ? null : _next,
                                    child: Center(
                                      child: _loading
                                          ? const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.4,
                                                color: Colors.white,
                                              ),
                                            )
                                          : Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  isLast
                                                      ? 'Submit Registration'
                                                      : 'Next',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 17,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Icon(
                                                  isLast
                                                      ? Icons.check
                                                      : Icons.arrow_forward,
                                                  size: 20,
                                                  color: Colors.white,
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Completion bar: numbered circles joined by lines that fill as you go.
class _RegistrationProgress extends StatelessWidget {
  const _RegistrationProgress({required this.current, required this.labels});

  final int current;
  final List<String> labels;

  Widget _node(int i) {
    final done = i < current;
    final active = i == current;
    return SizedBox(
      width: 64,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (done || active) ? _kBrand : Colors.white,
              border: Border.all(
                color: (done || active) ? _kBrand : _kFieldBorder,
                width: 1.6,
              ),
            ),
            child: done
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: active ? Colors.white : _kMuted,
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            labels[i],
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: (done || active) ? _kBrand : _kMuted,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < labels.length; i++) {
      children.add(_node(i));
      if (i < labels.length - 1) {
        children.add(
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 15),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 2,
                color: i < current ? _kBrand : _kFieldBorder,
              ),
            ),
          ),
        );
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
