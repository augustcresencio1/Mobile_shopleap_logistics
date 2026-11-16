import 'package:flutter_test/flutter_test.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';
import 'package:mobileshopleap_logistic_app/core/services/live_refresh.dart';

void main() {
  testWidgets(
    'Disconnected polling invalidates cached reads and stops cleanly',
    (tester) async {
      final revision = ApiClient.revision;
      final push = LiveRefresh.lastPush;
      var ticks = 0;
      var polling = false;
      void onTick() {
        ticks++;
        polling = LiveRefresh.isPolling;
      }

      LiveRefresh.tick.addListener(onTick);
      LiveRefresh.start(0);
      await tester.pump(const Duration(seconds: 5));
      expect(ticks, 1);
      expect(polling, isTrue);
      expect(LiveRefresh.isPolling, isFalse);
      expect(ApiClient.revision, revision + 1);
      expect(LiveRefresh.lastPush, push);

      LiveRefresh.stop();
      await tester.pump(const Duration(seconds: 60));
      expect(ticks, 1);
      LiveRefresh.tick.removeListener(onTick);
    },
  );
}
