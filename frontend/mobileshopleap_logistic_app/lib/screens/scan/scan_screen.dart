import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/services/order_service.dart';
import '../../models/order.dart';
import '../../core/utils/money.dart';
import '../orders/proof_delivery_screen.dart';

class ScanScreen extends StatefulWidget {
  /// Kapag may laman, "verify mode": ini-scan lang ang parcel ng order na ito.
  /// Kapag tugma, ipinapakita muna ang waybill; kapag pinindot ang
  /// "Confirm pickup", magpa-pop ang screen at ibabalik ang na-scan na code (String).
  /// Kapag null, normal na Scan waybill screen.
  final String? expectOrderId;
  final String? expectOrderReference;
  const ScanScreen({super.key, this.expectOrderId, this.expectOrderReference});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _cam = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const <BarcodeFormat>[],
  );
  final _manual = TextEditingController();
  late final AnimationController _line = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  bool _busy = false;
  bool _torchOn = false;
  Order? _order;
  String _status = '';
  String _role = '';
  String _code = '';

  bool get _verifyMode => widget.expectOrderId != null;

  @override
  void dispose() {
    _line.dispose();
    _cam.dispose();
    _manual.dispose();
    super.dispose();
  }

  // ---------- logic (same as before) ----------

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _lookup(String code) async {
    final c = code.trim();
    if (_busy || c.isEmpty) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await OrderService.scan(c);
      if (!mounted) return;

      if (_verifyMode) {
        if (r.order.id != widget.expectOrderId) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Wrong parcel. This is Order ${r.order.reference}, not ${widget.expectOrderReference ?? widget.expectOrderId}.',
              ),
            ),
          );
          return;
        }
        if (r.role != 'pickup') {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('You are not the pickup courier for this order.'),
            ),
          );
          return;
        }
        // Tugma ang parcel: ipakita muna ang waybill. Ang "Confirm pickup"
        // button sa result screen ang magbabalik ng code sa Pickup screen.
      }

      setState(() {
        _order = r.order;
        _status = r.status;
        _role = r.role;
        _code = c;
      });
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_friendly(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _act(
    Future<void> Function() action,
    String okMsg, {
    bool resetAfterSuccess = false,
  }) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    var succeeded = false;
    try {
      await action();
      succeeded = true;
      messenger.showSnackBar(SnackBar(content: Text(okMsg)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_friendly(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && succeeded) {
      if (resetAfterSuccess) {
        _rescan();
      } else {
        await _lookup(_code);
      }
    }
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('is not in your pickups or deliveries')) {
      return "This order isn't assigned to you.";
    }
    if (s.contains('This code is not recognized')) {
      return 'This code is not recognized.';
    }
    return 'Something went wrong. Please try again.';
  }

  void _rescan() {
    setState(() {
      _order = null;
      _status = '';
      _role = '';
      _code = '';
      _torchOn = false;
      _manual.clear();
    });
  }

  Future<void> _toggleTorch() async {
    try {
      await _cam.toggleTorch();
      if (mounted) setState(() => _torchOn = !_torchOn);
    } catch (_) {}
  }

  Future<void> _confirmPickup(Order o) async {
    final ok = await _confirm(
      title: 'Confirm pickup?',
      message:
          'You scanned Order ${o.reference}. Pick up the parcel from the seller now? This cannot be undone.',
      confirmLabel: 'Confirm pickup',
    );
    if (!ok || !mounted) return;
    await _act(
      () => OrderService.pickupOrder(o.orderNumber, scannedCode: _code),
      'Order ${o.reference} picked up.',
      resetAfterSuccess: true,
    );
  }

  Future<void> _confirmDelivered(Order o) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _cam.stop();
      if (!mounted) return;
      final delivered = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => ProofDeliveryScreen(order: o)),
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (delivered == true) {
        _rescan();
      } else {
        await _lookup(_code);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        try {
          await _cam.start();
        } catch (_) {}
      }
    }
  }

  // ---------- helpers ----------

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _prettyDay(String day) {
    final p = day.split('-');
    if (p.length != 3) return day;
    final m = int.tryParse(p[1]) ?? 0;
    if (m < 1 || m > 12) return day;
    return '${_months[m - 1]} ${p[2]}, ${p[0]}';
  }

  /// Tinatanggal ang " (2026-11-02 morning)" sa dulo ng `from`.
  String _sellerAddress(String from) {
    if (from == 'no schedule yet') return '';
    final i = from.lastIndexOf(' (');
    if (i > 0 && from.endsWith(')')) return from.substring(0, i);
    return from;
  }

  // ---------- UI pieces ----------

  Widget _actionButton(IconData icon, String label, VoidCallback? onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
        ),
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontSize: 16)),
        onPressed: onPressed,
      ),
    );
  }

  Widget _statusAction(Order o) {
    // Verify mode (galing sa Pickup screen): ang pindot dito ay ibabalik ang
    // na-scan na code, at ang Pickup screen na ang magko-confirm sa server.
    if (_verifyMode) {
      return _actionButton(
        Icons.check,
        'Confirm pickup',
        _busy ? null : () => Navigator.pop(context, _code),
      );
    }
    if (_role == 'pickup' && _status == 'READY_FOR_PICKUP') {
      return _actionButton(
        Icons.check,
        'Confirm pickup',
        _busy ? null : () => _confirmPickup(o),
      );
    }
    if (_status == 'ASSIGNED_TO_RIDER') {
      return _actionButton(
        Icons.local_shipping,
        'Start delivery',
        _busy
            ? null
            : () => _act(
                () => OrderService.startDelivery(o.orderNumber),
                'Delivery started.',
              ),
      );
    }
    if (_status == 'OUT_FOR_DELIVERY') {
      return _actionButton(
        Icons.check_circle,
        'Mark delivered',
        _busy ? null : () => _confirmDelivered(o),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'Status: $_status. No action available right now.',
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _box(String label, List<Widget> children) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outline),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 0.6,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }

  Widget _result(Order o) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // "DELIVER TO" block: municipality, province + barangay
    final parts = o.to.split(', ');
    var destTitle = o.to;
    var destSub = '';
    if (!o.to.startsWith('Hub:') && parts.length >= 3) {
      destTitle = '${parts[parts.length - 2]}, ${parts.last}'.toUpperCase();
      destSub = 'Brgy. ${parts[parts.length - 3]}';
    }

    final sellerName = o.shopName.isNotEmpty ? o.shopName : o.seller;
    final sellerAddr = _sellerAddress(o.from);
    final totalQty = o.lines.fold<int>(0, (s, l) => s + l.qty);
    final successBg = Color.alphaBlend(Colors.green.withAlpha(45), cs.surface);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Waybill found
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: successBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Colors.green,
                      child: Icon(Icons.check, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Waybill found', style: tt.titleMedium),
                          Text(
                            'The waybill has been successfully scanned.',
                            style: tt.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shopleap',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: cs.primary,
                          ),
                        ),
                        Text(
                          'Shipping Waybill',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Order #${o.reference}',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (o.waybillCode.isNotEmpty)
                          Text(o.waybillCode, textAlign: TextAlign.end),
                        if (o.day.isNotEmpty)
                          Text(
                            _prettyDay(o.day),
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Deliver to
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                color: cs.inverseSurface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DELIVER TO',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 0.8,
                        color: cs.onInverseSurface.withAlpha(190),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      destTitle,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: cs.onInverseSurface,
                      ),
                    ),
                    if (destSub.isNotEmpty)
                      Text(
                        destSub,
                        style: TextStyle(
                          fontSize: 15,
                          color: cs.onInverseSurface,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              _box('SHIP TO (BUYER)', [
                Text(
                  o.buyer,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (o.to.isNotEmpty) Text(o.to),
                if (o.buyerContact.isNotEmpty)
                  Text('Contact: ${o.buyerContact}'),
              ]),
              const SizedBox(height: 10),

              _box('SHIP FROM (SELLER)', [
                Text(
                  sellerName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (sellerAddr.isNotEmpty) Text(sellerAddr),
                if (o.sellerContact.isNotEmpty)
                  Text('Contact: ${o.sellerContact}'),
              ]),
              const SizedBox(height: 14),

              // Items
              Row(
                children: [
                  Expanded(
                    child: Text(
                      o.lines.isEmpty ? 'ITEMS' : 'ITEMS ($totalQty TOTAL)',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 0.6,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 12),
              if (o.lines.isEmpty)
                Text(o.item)
              else
                for (final l in o.lines) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (l.variant.isNotEmpty)
                                Text(
                                  l.variant,
                                  style: TextStyle(color: cs.onSurfaceVariant),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          '${l.qty}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              if (o.weightKg > 0) ...[
                const Divider(height: 16),
                Text('Parcel weight: ${o.weightKg.toStringAsFixed(2)} kg'),
              ],
              const SizedBox(height: 12),

              // Payment
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outline),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PAYMENT',
                            style: TextStyle(
                              fontSize: 12,
                              letterSpacing: 0.6,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const Text(
                            'Cash on Delivery',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'AMOUNT TO COLLECT',
                          style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 0.6,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          formatMoney(o.codAmount, currency: o.currency),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _statusAction(o),
                TextButton.icon(
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan again'),
                  onPressed: _busy ? null : _rescan,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _orderCard(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              color: cs.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 1,
            height: 40,
            color: cs.onSurface.withValues(alpha: 0.12),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Order #${widget.expectOrderReference ?? widget.expectOrderId}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Pickup Confirmation',
                  style: TextStyle(
                    fontSize: 14,
                    color: cs.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inventory_2_outlined, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  'To Pick Up',
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scanner() {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          width: double.infinity,
          color: kBrandBlue,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          child: Column(
            children: [
              Text(
                _verifyMode
                    ? 'Scan the waybill of the order to confirm the pickup.'
                    : 'Scan a waybill to look up the order.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 15,
                ),
              ),
              if (_verifyMode) ...[const SizedBox(height: 14), _orderCard(cs)],
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: MobileScanner(
                      controller: _cam,
                      onDetect: (capture) {
                        final v = capture.barcodes.isEmpty
                            ? null
                            : capture.barcodes.first.rawValue;
                        if (v != null && v.isNotEmpty) _lookup(v);
                      },
                      errorBuilder: (context, error) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Unable to open the camera (${error.errorCode.name}). Use manual entry below.',
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (ctx, box) {
                        final minSide = box.maxWidth < box.maxHeight
                            ? box.maxWidth
                            : box.maxHeight;
                        final w = (minSide * 0.72)
                            .clamp(120.0, 320.0)
                            .toDouble();
                        final h = w * 0.85;
                        return Center(
                          child: SizedBox(
                            width: w,
                            height: h,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.25,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: CustomPaint(painter: _CornerPainter()),
                                ),
                                Positioned.fill(
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: AnimatedBuilder(
                                      animation: _line,
                                      builder: (c, _) => Align(
                                        alignment: Alignment(
                                          0,
                                          _line.value * 2 - 1,
                                        ),
                                        child: Container(
                                          height: 3,
                                          decoration: BoxDecoration(
                                            color: Colors.lightBlueAccent,
                                            borderRadius: BorderRadius.circular(
                                              2,
                                            ),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Colors.lightBlueAccent,
                                                blurRadius: 10,
                                                spreadRadius: 1,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: IconButton.filled(
                      onPressed: _toggleTorch,
                      icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
                      style: IconButton.styleFrom(
                        backgroundColor: _torchOn ? cs.primary : Colors.black54,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  if (!_busy)
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 16,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.center_focus_weak,
                                color: Colors.white,
                                size: 22,
                              ),
                              SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  'Align the barcode or QR code\nwithin the frame',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_busy)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 36,
                                height: 36,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Scanning waybill...',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Text('Please wait'),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Divider(
                        color: cs.onSurface.withValues(alpha: 0.15),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'OR',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        color: cs.onSurface.withValues(alpha: 0.15),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _manual,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.keyboard_outlined),
                    hintText: 'Enter WB code or legacy numeric code',
                    filled: true,
                    fillColor: cs.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  onSubmitted: _lookup,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(shape: const StadiumBorder()),
                    icon: Icon(
                      _verifyMode ? Icons.check_circle_outline : Icons.search,
                    ),
                    label: Text(
                      _verifyMode ? 'Confirm Pickup' : 'Search',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: _busy ? null : () => _lookup(_manual.text),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBrandBlue,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: const Text(
          'Shopleap Scanner',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: o == null ? _scanner() : _result(o),
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const l = 28.0;
    const r = 14.0;
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(0, l)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..lineTo(l, 0)
      ..moveTo(w - l, 0)
      ..lineTo(w - r, 0)
      ..quadraticBezierTo(w, 0, w, r)
      ..lineTo(w, l)
      ..moveTo(w, h - l)
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h)
      ..lineTo(w - l, h)
      ..moveTo(l, h)
      ..lineTo(r, h)
      ..quadraticBezierTo(0, h, 0, h - r)
      ..lineTo(0, h - l);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
