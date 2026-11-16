import 'package:flutter/material.dart';

import '../core/utils/money.dart';
import '../models/order.dart';

Future<String?> askCodAmount(
  BuildContext context,
  Order order, {
  String? initialAmount,
}) => showDialog<String>(
  context: context,
  builder: (_) => _CodAmountDialog(order: order, initialAmount: initialAmount),
);

class _CodAmountDialog extends StatefulWidget {
  final Order order;
  final String? initialAmount;
  const _CodAmountDialog({required this.order, this.initialAmount});

  @override
  State<_CodAmountDialog> createState() => _CodAmountDialogState();
}

class _CodAmountDialogState extends State<_CodAmountDialog> {
  late final _controller = TextEditingController(
    text: widget.initialAmount ?? widget.order.codAmount,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = decimalMoney(_controller.text.trim().replaceAll(',', ''));
    final valid = amount != null && !amount.startsWith('-');
    final differs = valid && amount != widget.order.codAmount;
    return AlertDialog(
      title: const Text('Mark delivered?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order ${widget.order.reference}\nBuyer: ${widget.order.buyer}\n\n'
              'COD to collect: ${formatMoney(widget.order.codAmount)}',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Cash collected',
                prefixText: '\u20B1 ',
                border: const OutlineInputBorder(),
                errorText: valid
                    ? null
                    : 'Enter 0 or more, with up to 2 decimal places',
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (differs)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'This differs from the COD amount. The hub will see it as a flag. '
                  'Make sure the amount is correct.',
                  style: TextStyle(color: Colors.deepOrange),
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'Confirm the actual cash collected, including items and shipping. '
              'This is separate from your earning.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: valid ? () => Navigator.pop(context, amount) : null,
          child: const Text('Yes, delivered'),
        ),
      ],
    );
  }
}
