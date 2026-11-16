import 'package:flutter/material.dart';

import '../../core/services/order_service.dart';
import '../../core/services/pending_delivery_store.dart';
import '../../models/courier.dart';
import 'proof_delivery_screen.dart';

/// Available even if a timed-out request removed the order from active deliveries.
class PendingDeliveryScreen extends StatefulWidget {
  const PendingDeliveryScreen({super.key});

  @override
  State<PendingDeliveryScreen> createState() => _PendingDeliveryScreenState();
}

class _PendingDeliveryScreenState extends State<PendingDeliveryScreen> {
  late Future<List<PendingDelivery>> _pending;

  @override
  void initState() {
    super.initState();
    _pending = _load();
  }

  Future<List<PendingDelivery>> _load() async {
    if (Courier.current.id <= 0) {
      Courier.current = Courier.fromJson(await OrderService.account());
    }
    return PendingDeliveryStore().list(Courier.current.id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pending delivery uploads')),
    body: FutureBuilder<List<PendingDelivery>>(
      future: _pending,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() => _pending = _load()),
              child: const Text('Unable to open saved deliveries. Try again'),
            ),
          );
        }
        final drafts = snapshot.data!;
        if (drafts.isEmpty) {
          return const Center(child: Text('No pending delivery uploads.'));
        }
        return ListView(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'An interrupted upload may already be recorded by the server. Open the saved submission and Retry to confirm.',
              ),
            ),
            for (final draft in drafts)
              ListTile(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: Text('Order ${draft.order.reference}'),
                subtitle: Text(
                  draft.attempted
                      ? 'Awaiting confirmation • Retry available'
                      : 'Photo saved • Confirm delivery',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProofDeliveryScreen(order: draft.order),
                    ),
                  );
                  if (mounted) setState(() => _pending = _load());
                },
              ),
          ],
        );
      },
    ),
  );
}
