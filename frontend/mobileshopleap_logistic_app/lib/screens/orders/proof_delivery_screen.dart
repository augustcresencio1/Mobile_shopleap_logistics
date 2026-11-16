import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/services/delivery_photo.dart';
import '../../core/services/order_service.dart';
import '../../core/services/pending_delivery_store.dart';
import '../../core/services/rider_location_service.dart';
import '../../core/utils/money.dart';
import '../../models/courier.dart';
import '../../models/order.dart';
import '../../widgets/cod_amount_dialog.dart';

class ProofDeliveryScreen extends StatefulWidget {
  final Order order;
  final PendingDeliveryStore? store;
  const ProofDeliveryScreen({super.key, required this.order, this.store});

  @override
  State<ProofDeliveryScreen> createState() => _ProofDeliveryScreenState();
}

class _ProofDeliveryScreenState extends State<ProofDeliveryScreen> {
  late final _store = widget.store ?? PendingDeliveryStore();
  final _notes = TextEditingController();
  PendingDelivery? _draft;
  bool _busy = true, _uploading = false, _confirmed = false, _ready = false;
  int? _riderId;
  double? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      var riderId = Courier.current.id;
      if (riderId <= 0) {
        final profile = Courier.fromJson(await OrderService.account());
        Courier.current = profile;
        riderId = profile.id;
      }
      final draft = await _store.load(riderId, widget.order.orderNumber);
      if (!mounted) return;
      _riderId = riderId;
      _draft = draft;
      _notes.text = draft?.notes ?? '';
      _ready = true;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error =
          'Unable to open the saved delivery securely. Refresh your profile and try again.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _capture() async {
    if (_busy || !_ready || _draft?.attempted == true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    XFile? raw;
    try {
      // Camera only. Record capture time immediately, before processing or upload.
      raw = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        requestFullMetadata: false,
      );
      final capturedAt = DateTime.now().toUtc().toIso8601String();
      if (raw == null) return;
      final photo = await compute(prepareCapturedDeliveryPhoto, {
        'bytes': await raw.readAsBytes(),
        'received_at': capturedAt,
      });
      final draft = PendingDelivery(
        riderId: _riderId!,
        order: widget.order,
        photo: photo.bytes,
        capturedAt: photo.capturedAt,
        notes: _notes.text.trim(),
      );
      await _store.save(draft);
      if (mounted) setState(() => _draft = draft);
    } on FormatException catch (e) {
      _error = e.message;
    } catch (_) {
      _error =
          'Unable to take or securely save the photo. Allow camera access and try again.';
    } finally {
      // image_picker uses a private cache; remove its unencrypted temporary copy.
      if (raw != null) {
        try {
          await File(raw.path).delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attachLocation() async {
    if (_busy || _draft == null || _draft!.attempted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // This is the only proof flow action that requests location permission.
      final position = await RiderLocationService.current();
      final updated = _draft!.copyWith(
        latitude: position.latitude,
        longitude: position.longitude,
        notes: _notes.text.trim(),
      );
      await _store.save(updated);
      if (mounted) setState(() => _draft = updated);
    } catch (_) {
      _error = 'Location was not attached. You can still confirm delivery.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || _draft == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (Courier.current.id != _riderId) {
        throw const FormatException(
          'Sign in as the rider who saved this delivery.',
        );
      }
      var draft = _draft!;
      if (!draft.attempted) {
        if (_notes.text.trim().runes.length > 255) {
          throw const FormatException('Keep notes to at most 255 characters.');
        }
        final amount = await askCodAmount(
          context,
          widget.order,
          initialAmount: draft.amount,
        );
        if (amount == null || !mounted) return;
        draft = draft.copyWith(
          amount: amount,
          notes: _notes.text.trim(),
          attempted: true,
        );
        // Persist the exact request BEFORE the first byte is sent.
        await _store.save(draft);
        _draft = draft;
      }
      if (!mounted) return;
      setState(() {
        _uploading = true;
        _progress = 0;
      });
      Future<void> uploadProof() async {
        await OrderService.deliverOrder(
          draft.order.orderNumber,
          trackingOrderId: draft.order.id,
          amount: draft.amount!,
          proofImage: draft.photo,
          capturedAt: draft.capturedAt,
          latitude: draft.latitude,
          longitude: draft.longitude,
          notes: draft.notes,
          onProgress: (sent, total) {
            if (mounted) {
              setState(() => _progress = total == 0 ? null : sent / total);
            }
          },
        );
      }

      // The delivered endpoint requires proof_image on every request, including retries.
      await uploadProof();
      _confirmed = true;
      widget.order.status = OrderStatus.done;
      await _finish();
    } on ApiException catch (e) {
      _error = e.message;
      if (e.statusCode == 422 || e.statusCode == 413) {
        // Definitive validation rejection: allow correction/retake.
        final updated = _draft!.copyWith(attempted: false);
        try {
          await _store.save(updated);
          _draft = updated;
        } catch (_) {}
      } else if (e.statusCode == null ||
          e.statusCode == 503 ||
          (e.statusCode != null && e.statusCode! >= 500)) {
        _error =
            '${e.message}\nThe server may have recorded this delivery. Your photo and details are saved; Retry will check safely.';
      }
    } on FormatException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = _confirmed
          ? 'Delivery confirmed. Tap Finish to clear the saved photo.'
          : 'Unable to complete the upload. Your saved photo and details are available for Retry.';
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _uploading = false;
        });
      }
    }
  }

  Future<void> _finish() async {
    await _store.clear(_riderId!, widget.order.orderNumber);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Proof uploaded')));
    Navigator.pop(context, true);
  }

  Future<void> _finishOnly() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _finish();
    } catch (_) {
      _error = 'Delivery confirmed. Tap Finish to clear the saved photo.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Proof of delivery')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Order ${widget.order.reference}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Take a clear photo of the parcel at the buyer’s place before confirming delivery.',
            ),
            const SizedBox(height: 16),
            if (draft != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  draft.photo,
                  height: 280,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
              ),
              const SizedBox(height: 12),
              if (!draft.attempted && !_confirmed)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _capture,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Retake'),
                ),
              if (draft.attempted && !_confirmed) ...[
                const Text(
                  'This submission is saved. Retry sends the same photo, capture time, and cash amount.',
                ),
                Text(
                  'Cash collected: ${formatMoney(draft.amount, currency: draft.order.currency)}',
                ),
              ],
              TextField(
                controller: _notes,
                enabled: !_busy && !draft.attempted && !_confirmed,
                maxLength: 255,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
              if (!_confirmed)
                TextButton.icon(
                  onPressed: _busy || draft.attempted ? null : _attachLocation,
                  icon: const Icon(Icons.location_on_outlined),
                  label: Text(
                    draft.latitude == null
                        ? 'Attach location (optional)'
                        : 'Location attached',
                  ),
                ),
            ] else if (_ready)
              FilledButton.icon(
                onPressed: _busy ? null : _capture,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Take parcel photo'),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_busy) ...[
              LinearProgressIndicator(value: _uploading ? _progress : null),
              const SizedBox(height: 8),
              Text(
                _uploading
                    ? (_progress == 1
                          ? 'Waiting for server confirmation…'
                          : 'Uploading photo… ${((_progress ?? 0) * 100).floor()}%')
                    : 'Please wait…',
              ),
            ],
            if (draft != null)
              FilledButton.icon(
                onPressed: _busy ? null : (_confirmed ? _finishOnly : _submit),
                icon: const Icon(Icons.check_circle_outline),
                label: Text(
                  _confirmed
                      ? 'Finish'
                      : (draft.attempted
                            ? 'Retry'
                            : 'Confirm photo and delivery'),
                ),
              ),
            if (!_ready && !_busy)
              TextButton(
                onPressed: () {
                  setState(() {
                    _busy = true;
                    _error = null;
                  });
                  _restore();
                },
                child: const Text('Try again'),
              ),
          ],
        ),
      ),
    );
  }
}
