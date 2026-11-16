import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobileshopleap_logistic_app/core/services/api_client.dart';
import 'package:mobileshopleap_logistic_app/core/services/chat_service.dart';
import 'package:mobileshopleap_logistic_app/core/services/live_refresh.dart';
import 'package:mobileshopleap_logistic_app/models/courier.dart';
import 'package:mobileshopleap_logistic_app/screens/chat/chat_list_screen.dart';
import 'package:mobileshopleap_logistic_app/screens/home/main_shell.dart';
import 'package:mobileshopleap_logistic_app/widgets/app_bottom_nav.dart';

class _ChatApi {
  int sellerUnread = 0;
  int buyerUnread = 0;
  int chatRequests = 0;
  bool failChats = false;
  bool failMessages = false;
  bool failSends = false;
  int _nextId = 3;
  final Map<String, List<Map<String, dynamic>>> _messages = {
    'seller': [
      {
        'id': 1,
        'body': 'Hello',
        'mine': false,
        'sender_name': 'Contact',
        'created_at': '2026-11-15T01:00:00Z',
      },
    ],
    'buyer': [
      {
        'id': 2,
        'body': 'Hello',
        'mine': false,
        'sender_name': 'Contact',
        'created_at': '2026-11-15T01:00:00Z',
      },
    ],
  };

  void reply(String party, String text) {
    _messages[party]!.add({
      'id': _nextId++,
      'body': text,
      'mine': false,
      'sender_name': 'Contact',
      'created_at': '2026-11-15T01:01:00Z',
    });
    if (party == 'seller') {
      sellerUnread++;
    } else {
      buyerUnread++;
    }
  }

  http.Response _response(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  Map<String, dynamic> _thread(String party, String name, int unread) => {
    'key': '$party-100',
    'with': party,
    'order_id': 100,
    'conversation_id': party == 'seller' ? 1 : 2,
    'name': name,
    'subtitle': '$party Order #100',
    'last_message': _messages[party]!.last['body'],
    'last_is_mine': _messages[party]!.last['mine'],
    'last_message_id': _messages[party]!.last['id'],
    'last_message_at': _messages[party]!.last['created_at'],
    'unread': unread,
  };

  late final client = MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/chats')) {
      chatRequests++;
      if (failChats) return _response({'message': 'Offline'}, 503);
      return _response({
        'data': [
          _thread('seller', 'Seller One', sellerUnread),
          _thread('buyer', 'Buyer One', buyerUnread),
        ],
      });
    }
    if (path.endsWith('/messages')) {
      final sent = request.method == 'POST';
      if (sent && failSends) return _response({'message': 'Failed'}, 503);
      if (!sent && failMessages) return _response({'message': 'Offline'}, 503);
      final data = sent ? jsonDecode(request.body) as Map : null;
      final party = sent
          ? data!['with'] as String
          : request.url.queryParameters['with']!;
      if (party == 'seller') {
        sellerUnread = 0;
      } else {
        buyerUnread = 0;
      }
      final conversationId = party == 'seller' ? 1 : 2;
      if (sent) {
        final message = <String, dynamic>{
          'id': _nextId++,
          'body': data!['body'],
          'mine': true,
          'sender_name': 'Rider',
          'created_at': '2026-11-15T01:00:30Z',
          'conversation_id': conversationId,
        };
        _messages[party]!.add(message);
        return _response({'id': message['id'], 'data': message}, 201);
      }
      return _response({
        'conversation_id': conversationId,
        'data': _messages[party],
      });
    }
    if (path.endsWith('/dashboard')) {
      return _response({
        'requests': [],
        'pickups': [],
        'deliveries': [],
        'in_progress': [],
        'recent': [],
        'earned_week': '0.00',
        'earned_today': '0.00',
      });
    }
    if (path.endsWith('/overview')) {
      return _response({
        'summary': {
          'total_earned': '0.00',
          'deliveries': 0,
          'recorded_earnings': 0,
          'daily': [],
        },
        'rate': {'amount': null},
        'history': {
          'data': [],
          'meta': {'current_page': 1, 'last_page': 1, 'total': 0},
        },
      });
    }
    if (path.endsWith('/me')) {
      return _response({
        'name': 'Rider',
        'courier': {'id': 0},
      });
    }
    return _response({
      'data': [],
      'meta': {'current_page': 1, 'last_page': 1, 'total': 0},
    });
  });
}

void main() {
  setUp(() {
    ApiClient.invalidateCache();
    ChatService.reset();
    FlutterSecureStorage.setMockInitialValues({
      'auth_token:${ApiClient.baseUrl}': 'courier-token',
    });
    Courier.current = Courier(name: '', phone: '', vehicle: '', plate: '');
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> showShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 870);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: MainShell()));
    await tester.pumpAndSettle();
  }

  Finder navText(String text) =>
      find.descendant(of: find.byType(AppBottomNav), matching: find.text(text));

  int unreadCount(WidgetTester tester) => tester
      .widget<AppBottomNav>(find.byType(AppBottomNav, skipOffstage: false))
      .chatBadge;

  testWidgets(
    'Unread badges refresh outside Chat and survive a failed refresh',
    (tester) async {
      final api = _ChatApi();
      await http.runWithClient(() async {
        await showShell(tester);
        expect(unreadCount(tester), 0);
        expect(navText('0'), findsNothing);

        api.sellerUnread = 2;
        api.buyerUnread = 3;
        LiveRefresh.pokeNow();
        await tester.pumpAndSettle();
        expect(unreadCount(tester), 5);
        expect(navText('5'), findsOneWidget);

        await tester.tap(navText('Pickup'));
        await tester.pumpAndSettle();
        api.sellerUnread = 101;
        LiveRefresh.pokeNow();
        await tester.pumpAndSettle();
        expect(unreadCount(tester), 104);
        expect(navText('99+'), findsOneWidget);

        api.failChats = true;
        LiveRefresh.pokeNow();
        await tester.pumpAndSettle();
        expect(unreadCount(tester), 104);

        api.failChats = false;
        api.sellerUnread = 0;
        api.buyerUnread = 0;
        LiveRefresh.pokeNow();
        await tester.pumpAndSettle();
        expect(unreadCount(tester), 0);
        expect(navText('99+'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => api.client);
    },
  );

  testWidgets(
    'Chat title aligns with its buttons and read chats reduce totals',
    (tester) async {
      final api = _ChatApi()
        ..sellerUnread = 2
        ..buyerUnread = 3;
      await http.runWithClient(() async {
        await showShell(tester);
        await tester.tap(navText('Chat'));
        await tester.pumpAndSettle();

        Finder inChat(Finder finder) =>
            find.descendant(of: find.byType(ChatListScreen), matching: finder);
        final titleY = tester.getCenter(inChat(find.text('Chat'))).dy;
        expect(
          titleY,
          closeTo(
            tester.getCenter(inChat(find.byIcon(Icons.arrow_back))).dy,
            0.1,
          ),
        );
        expect(
          titleY,
          closeTo(
            tester.getCenter(inChat(find.byTooltip('Notifications'))).dy,
            0.1,
          ),
        );

        await tester.enterText(inChat(find.byType(TextField)), 'Seller One');
        await tester.tap(find.text('Sellers'));
        await tester.pumpAndSettle();
        expect(find.text('Buyer One'), findsNothing);
        expect(unreadCount(tester), 5);

        await tester.tap(find.text('Seller One').last);
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(unreadCount(tester), 3);
        expect(navText('3'), findsOneWidget);

        await tester.enterText(inChat(find.byType(TextField)), '');
        await tester.tap(find.text('Customers'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Buyer One'));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(unreadCount(tester), 0);
        expect(navText('0'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => api.client);
    },
  );

  testWidgets('Chat polling pauses in the background and refreshes on resume', (
    tester,
  ) async {
    final api = _ChatApi()..sellerUnread = 1;
    await http.runWithClient(() async {
      await showShell(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final requests = api.chatRequests;
      api.sellerUnread = 4;
      await tester.pump(const Duration(seconds: 20));
      await tester.pumpAndSettle();
      expect(api.chatRequests, requests);
      expect(unreadCount(tester), 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(unreadCount(tester), 4);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => api.client);
  });

  testWidgets(
    'Seen and sent chats clear both badges; only unread replies highlight',
    (tester) async {
      final api = _ChatApi()..sellerUnread = 2;
      await http.runWithClient(() async {
        await showShell(tester);
        await tester.tap(navText('Chat'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Seller One'));
        await tester.pumpAndSettle();
        expect(unreadCount(tester), 0);

        // A successful POST remains confirmed even if the next GET fails.
        api.failMessages = true;
        await tester.enterText(find.byType(TextField), 'On my way');
        await tester.tap(find.byIcon(Icons.send));
        await tester.pumpAndSettle();
        expect(find.text('On my way'), findsOneWidget);
        expect(find.byIcon(Icons.check), findsOneWidget);
        expect(unreadCount(tester), 0);
        await tester.pageBack();
        await tester.pumpAndSettle();

        Finder sellerCard() => find
            .ancestor(
              of: find.text('Seller One'),
              matching: find.byType(ClipRRect),
            )
            .first;
        Finder status(IconData icon) =>
            find.descendant(of: sellerCard(), matching: find.byIcon(icon));
        Finder highlight() => find.descendant(
          of: sellerCard(),
          matching: find.byType(ColoredBox),
        );
        expect(status(Icons.check_circle_outline), findsOneWidget);
        expect(highlight(), findsNothing);
        expect(unreadCount(tester), 0);

        api.reply('seller', 'Thanks, see you');
        LiveRefresh.pokeNow();
        await tester.pumpAndSettle();
        expect(unreadCount(tester), 1);
        expect(status(Icons.check_circle_outline), findsNothing);
        expect(highlight(), findsOneWidget);
        expect(
          find.descendant(of: sellerCard(), matching: find.text('1')),
          findsOneWidget,
        );

        api.failMessages = false;
        await tester.tap(find.text('Seller One'));
        await tester.pumpAndSettle();
        expect(unreadCount(tester), 0);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(highlight(), findsNothing);
        expect(
          find.descendant(of: sellerCard(), matching: find.text('1')),
          findsNothing,
        );
        expect(unreadCount(tester), 0);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => api.client);
    },
  );

  testWidgets(
    'Failed reads keep unread counts and failed sends keep the draft without a sent check',
    (tester) async {
      final api = _ChatApi()
        ..sellerUnread = 2
        ..failMessages = true;
      await http.runWithClient(() async {
        await showShell(tester);
        await tester.tap(navText('Chat'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Seller One'));
        await tester.pumpAndSettle();
        expect(unreadCount(tester), 2);
        api.failSends = true;
        await tester.enterText(find.byType(TextField), 'Retry this');
        await tester.tap(find.byIcon(Icons.send));
        await tester.pumpAndSettle();
        expect(unreadCount(tester), 2);
        expect(find.byIcon(Icons.check), findsNothing);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'Retry this',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => api.client);
    },
  );
}
