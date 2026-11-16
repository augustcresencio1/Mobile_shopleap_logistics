import 'package:flutter/material.dart';
import '../core/services/rider_tracking_service.dart';

class RiderTrackingBanner extends StatelessWidget {
  const RiderTrackingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final tracking = RiderTrackingService.instance;
    return AnimatedBuilder(
      animation: tracking,
      builder: (context, _) {
        if (!tracking.tracking && !tracking.starting) {
          return const SizedBox.shrink();
        }
        return Material(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tracking.starting
                          ? 'Starting live trip...'
                          : '${tracking.live ? 'Live trip' : 'Reconnecting'} · Order #${tracking.orderId}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => tracking.stop(),
                    child: const Text('Stop'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
