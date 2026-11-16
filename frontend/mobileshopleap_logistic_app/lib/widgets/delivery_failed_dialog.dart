import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Nagbabalik ng (reason, note), o null kapag kinansela.
/// May `reasons` (v4): dropdown + optional note.
/// Walang `reasons` (lokal): free text lang, walang note.
Future<({String reason, String note})?> showDeliveryFailedDialog(
  BuildContext context, {
  List<String> reasons = const [],
}) => showDialog<({String reason, String note})>(
  context: context,
  builder: (_) => _DeliveryFailedDialog(reasons: reasons),
);

class _DeliveryFailedDialog extends StatefulWidget {
  final List<String> reasons;
  const _DeliveryFailedDialog({required this.reasons});

  @override
  State<_DeliveryFailedDialog> createState() => _DeliveryFailedDialogState();
}

class _DeliveryFailedDialogState extends State<_DeliveryFailedDialog> {
  final _text = TextEditingController();
  final _note = TextEditingController();
  String? _picked;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _note.dispose();
    super.dispose();
  }

  String get _reason =>
      widget.reasons.isEmpty ? _text.text.trim() : (_picked ?? '');

  InputDecoration _decoration(String hint, {double radius = 999}) =>
      InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: kBrandBlue.withValues(alpha: 0.08),
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: kBrandBlue, width: 1.4),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: cs.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: kBrandBlue,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.priority_high,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Delivery Failed',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tell us why this order could not be delivered.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: cs.onSurface.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 18),
            if (widget.reasons.isEmpty)
              TextField(
                controller: _text,
                maxLength: 200,
                decoration: _decoration('Reason'),
              )
            else ...[
              DropdownButtonFormField<String>(
                initialValue: _picked,
                isExpanded: true,
                borderRadius: BorderRadius.circular(20),
                decoration: _decoration('Reason'),
                items: [
                  for (final r in widget.reasons)
                    DropdownMenuItem(value: r, child: Text(r)),
                ],
                onChanged: (v) => setState(() => _picked = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                maxLength: 200,
                maxLines: 2,
                decoration: _decoration('Note (optional)', radius: 22),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      shape: const StadiumBorder(),
                      side: const BorderSide(color: kBrandBlue, width: 1.4),
                      foregroundColor: kBrandBlue,
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _reason.isEmpty
                        ? null
                        : () => Navigator.pop(context, (
                            reason: _reason,
                            note: _note.text.trim(),
                          )),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      shape: const StadiumBorder(),
                      backgroundColor: kBrandBlue,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: const Text('Submit'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}