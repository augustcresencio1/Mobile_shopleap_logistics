import 'package:flutter/material.dart';
import '../core/services/api_client.dart';
import '../core/services/live_refresh.dart';
import '../models/receipt.dart';
import '../screens/money/receipt_screen.dart';

class ReceiptAction extends StatelessWidget {
  final ReceiptTarget target;
  const ReceiptAction({super.key, required this.target});

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: target.reference.isEmpty
        ? null
        : () => Navigator.of(context)
              .push(
                MaterialPageRoute<void>(
                  builder: (_) => ReceiptScreen(target: target),
                ),
              )
              .then((_) {
                ApiClient.invalidateCache();
                LiveRefresh.pokeNow();
              }),
    icon: const Icon(Icons.receipt_long_outlined),
    label: Text('View receipt ${target.reference}'),
  );
}
