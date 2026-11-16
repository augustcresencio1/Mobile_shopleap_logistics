import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Ang oras sa server ay ISO8601 (UTC). Ginagawang Asia/Manila (UTC+8).
DateTime? chatTime(dynamic raw) {
  if (raw == null) return null;
  final dt = DateTime.tryParse(raw.toString());
  if (dt == null) return null;
  return dt.toUtc().add(const Duration(hours: 8));
}

/// Isang usapan sa listahan (seller / buyer / logistics hub).
class ChatThread {
  final String key;
  final String party; // seller | buyer | logistics
  final String orderId;
  final String name;
  final String subtitle;
  final String? lastMessage;
  final bool lastIsMine;
  final DateTime? lastAt; // oras sa Manila
  final int unread;
  final int? conversationId;
  final int lastMessageId;

  const ChatThread({
    required this.key,
    required this.party,
    required this.orderId,
    required this.name,
    required this.subtitle,
    this.lastMessage,
    this.lastIsMine = false,
    this.lastAt,
    this.unread = 0,
    this.conversationId,
    this.lastMessageId = 0,
  });

  factory ChatThread.fromJson(Map<String, dynamic> j) => ChatThread(
    key: '${j['key']}',
    party: '${j['with'] ?? 'seller'}',
    orderId: '${j['order_id']}',
    name: '${j['name'] ?? ''}',
    subtitle: '${j['subtitle'] ?? ''}',
    lastMessage: j['last_message']?.toString(),
    lastIsMine: j['last_is_mine'] == true,
    lastAt: chatTime(j['last_message_at']),
    unread: (num.tryParse('${j['unread']}') ?? 0).toInt(),
    conversationId: int.tryParse('${j['conversation_id']}'),
    lastMessageId: int.tryParse('${j['last_message_id']}') ?? 0,
  );

  ChatThread copyWith({
    String? lastMessage,
    bool? lastIsMine,
    DateTime? lastAt,
    int? unread,
    int? conversationId,
    int? lastMessageId,
  }) => ChatThread(
    key: key,
    party: party,
    orderId: orderId,
    name: name,
    subtitle: subtitle,
    lastMessage: lastMessage ?? this.lastMessage,
    lastIsMine: lastIsMine ?? this.lastIsMine,
    lastAt: lastAt ?? this.lastAt,
    unread: unread ?? this.unread,
    conversationId: conversationId ?? this.conversationId,
    lastMessageId: lastMessageId ?? this.lastMessageId,
  );
}

/// Isang mensahe sa loob ng chat room.
class ChatMessage {
  final int id;
  final String body;
  final bool mine;
  final String senderName;
  final DateTime? at; // oras sa Manila

  const ChatMessage({
    required this.id,
    required this.body,
    required this.mine,
    required this.senderName,
    this.at,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id: (num.tryParse('${j['id']}') ?? 0).toInt(),
    body: '${j['body'] ?? ''}',
    mine: j['mine'] == true,
    senderName: '${j['sender_name'] ?? ''}',
    at: chatTime(j['created_at']),
  );
}

class ChatService {
  // The list and navbar observe the same confirmed chat state.
  static final threadUpdates = ValueNotifier<List<ChatThread>>(const []);
  static final Map<String, int> _readThrough = {};
  static int _revision = 0;
  static int _session = 0;

  static void reset() {
    _session++;
    _revision++;
    _readThrough.clear();
    threadUpdates.value = const [];
  }

  /// GET /courier/chats
  static Future<List<ChatThread>> threads({bool forceRefresh = false}) async {
    final revision = _revision;
    final body = await ApiClient.get(
      '/courier/chats',
      forceRefresh: forceRefresh,
    );
    final list = (body is Map ? body['data'] as List? : null) ?? const [];
    // A response started before a read/send must not restore an old badge.
    if (revision != _revision) return threadUpdates.value;
    final threads = list
        .map((e) => ChatThread.fromJson(Map<String, dynamic>.from(e as Map)))
        .map((thread) {
          final seen =
              _readThrough[_readKey(
                thread.orderId,
                thread.party,
                thread.conversationId,
              )];
          return seen != null && thread.lastMessageId <= seen
              ? thread.copyWith(unread: 0)
              : thread;
        })
        .toList();
    threadUpdates.value = List.unmodifiable(threads);
    return threads;
  }

  /// GET /courier/orders/{id}/messages?with=seller|buyer|logistics
  static Future<List<ChatMessage>> messages(
    String orderId, {
    String party = 'seller',
  }) async {
    final session = _session;
    final body = await ApiClient.get(
      '/courier/orders/$orderId/messages',
      query: {'with': party},
      cacheFor: Duration.zero,
      forceRefresh: true,
    );
    final list = (body is Map ? body['data'] as List? : null) ?? const [];
    final messages = list
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    if (session == _session && messages.isNotEmpty) {
      _acknowledge(
        orderId,
        party,
        int.tryParse('${body['conversation_id']}'),
        messages.last,
      );
    }
    return messages;
  }

  /// POST /courier/orders/{id}/messages
  static Future<ChatMessage> send(
    String orderId,
    String text, {
    String party = 'seller',
  }) async {
    final session = _session;
    final body = await ApiClient.post(
      '/courier/orders/$orderId/messages',
      body: {'body': text, 'with': party},
    );
    final data = body['data'] is Map
        ? Map<String, dynamic>.from(body['data'] as Map)
        : <String, dynamic>{
            'id': body['id'],
            'body': text,
            'mine': true,
            'sender_name': 'You',
            'created_at': DateTime.now().toUtc().toIso8601String(),
          };
    final message = ChatMessage.fromJson(data);
    if (session == _session) {
      _acknowledge(
        orderId,
        party,
        int.tryParse('${data['conversation_id']}'),
        message,
      );
    }
    return message;
  }

  static String _readKey(String orderId, String party, int? conversationId) =>
      conversationId == null
      ? '$party-$orderId'
      : 'conversation-$conversationId';

  static void _acknowledge(
    String orderId,
    String party,
    int? conversationId,
    ChatMessage message,
  ) {
    final key = _readKey(orderId, party, conversationId);
    final previous = _readThrough[key] ?? 0;
    if (message.id <= previous) return;
    _readThrough[key] = message.id;
    _revision++;
    // Reading messages changes server state despite using a GET endpoint.
    ApiClient.invalidateCache();
    threadUpdates.value = List.unmodifiable(
      threadUpdates.value.map((thread) {
        final matches = conversationId != null && thread.conversationId != null
            ? thread.conversationId == conversationId
            : thread.orderId == orderId && thread.party == party;
        if (!matches || thread.lastMessageId > message.id) return thread;
        return thread.copyWith(
          unread: 0,
          conversationId: conversationId,
          lastMessageId: message.id,
          lastMessage: message.body,
          lastIsMine: message.mine,
          lastAt: message.at,
        );
      }),
    );
  }
}
