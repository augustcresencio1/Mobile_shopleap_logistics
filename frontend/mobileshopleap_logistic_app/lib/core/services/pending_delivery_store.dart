import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

import '../../models/order.dart';

class PendingDelivery {
  final int riderId;
  final Order order;
  final Uint8List photo;
  final String capturedAt;
  final String? amount, notes;
  final double? latitude, longitude;

  /// Once sent, an uncertain result must retry exactly the same request.
  final bool attempted;

  const PendingDelivery({
    required this.riderId,
    required this.order,
    required this.photo,
    required this.capturedAt,
    this.amount,
    this.notes,
    this.latitude,
    this.longitude,
    this.attempted = false,
  });

  PendingDelivery copyWith({
    String? amount,
    String? notes,
    double? latitude,
    double? longitude,
    bool? attempted,
  }) => PendingDelivery(
    riderId: riderId,
    order: order,
    photo: photo,
    capturedAt: capturedAt,
    amount: amount ?? this.amount,
    notes: notes ?? this.notes,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    attempted: attempted ?? this.attempted,
  );

  Map<String, dynamic> toJson() => {
    'rider_id': riderId,
    'order_id': order.id,
    'order_number': order.orderNumber,
    'buyer': order.buyer,
    'cod_amount': order.codAmount,
    'currency': order.currency,
    'photo': base64Encode(photo),
    'captured_at': capturedAt,
    'amount': amount,
    'notes': notes,
    'latitude': latitude,
    'longitude': longitude,
    'attempted': attempted,
  };

  factory PendingDelivery.fromJson(Map<String, dynamic> json) =>
      PendingDelivery(
        riderId: json['rider_id'] as int,
        order: Order(
          id: json['order_id'] as String,
          orderNumber: json['order_number'] as String,
          buyer: json['buyer'] as String,
          codAmount: json['cod_amount'] as String,
          currency: json['currency'] as String,
          item: '',
          seller: '',
          from: '',
          to: '',
          fee: null,
          status: OrderStatus.delivery,
        ),
        photo: base64Decode(json['photo'] as String),
        capturedAt: json['captured_at'] as String,
        amount: json['amount'] as String?,
        notes: json['notes'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        attempted: json['attempted'] == true,
      );
}

// AES-256-GCM authenticates the entire photo + request, bound to its rider/order.
Uint8List _crypt(Map<String, dynamic> input) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      input['encrypt'] as bool,
      AEADParameters(
        KeyParameter(input['key'] as Uint8List),
        128,
        input['nonce'] as Uint8List,
        Uint8List.fromList(utf8.encode(input['scope'] as String)),
      ),
    );
  return cipher.process(input['bytes'] as Uint8List);
}

class PendingDeliveryStore {
  final FlutterSecureStorage storage;
  final Future<Directory> Function() directory;
  PendingDeliveryStore({
    this.storage = const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.unlocked_this_device,
      ),
    ),
    Future<Directory> Function()? directory,
  }) : directory = directory ?? getApplicationSupportDirectory;

  String _scope(int riderId, String orderNumber) {
    if (riderId <= 0 || orderNumber.trim().isEmpty) {
      throw const FormatException(
        'Refresh your rider profile and order before uploading.',
      );
    }
    return 'pending_delivery_v1_${riderId}_${sha256.convert(utf8.encode(orderNumber))}';
  }

  Uint8List _random(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }

  Future<File> _file(String name) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(name)) {
      throw const FormatException('Invalid saved photo.');
    }
    final folder = Directory('${(await directory()).path}/pending_delivery');
    await folder.create(recursive: true);
    return File('${folder.path}/$name');
  }

  Future<void> save(PendingDelivery draft) async {
    final scope = _scope(draft.riderId, draft.order.orderNumber);
    final old = await storage.read(key: scope);
    final key = _random(32), nonce = _random(12);
    final encrypted = await compute(_crypt, {
      'encrypt': true,
      'key': key,
      'nonce': nonce,
      'scope': scope,
      'bytes': Uint8List.fromList(utf8.encode(jsonEncode(draft.toJson()))),
    });
    final name = _random(
      16,
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final file = await _file(name);
    await file.writeAsBytes(encrypted, flush: true);
    // Publish the pointer only after a durable encrypted file exists.
    await storage.write(
      key: scope,
      value: jsonEncode({
        'file': name,
        'key': base64Encode(key),
        'nonce': base64Encode(nonce),
      }),
    );
    if (old != null) await _deleteFile(jsonDecode(old)['file'] as String);
  }

  Future<PendingDelivery?> load(int riderId, String orderNumber) async {
    final scope = _scope(riderId, orderNumber);
    final pointer = await storage.read(key: scope);
    if (pointer == null) return null;
    if (jsonDecode(pointer)['confirmed'] == true) {
      await _clearScope(scope, pointer);
      return null;
    }
    return _read(scope, pointer);
  }

  Future<PendingDelivery> _read(String scope, String pointer) async {
    final info = jsonDecode(pointer) as Map;
    final bytes = await compute(_crypt, {
      'encrypt': false,
      'key': base64Decode(info['key'] as String),
      'nonce': base64Decode(info['nonce'] as String),
      'scope': scope,
      'bytes': await (await _file(info['file'] as String)).readAsBytes(),
    });
    return PendingDelivery.fromJson(
      Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map),
    );
  }

  Future<List<PendingDelivery>> list(int riderId) async {
    if (riderId <= 0) {
      throw const FormatException('Refresh your rider profile first.');
    }
    final all = await storage.readAll();
    final result = <PendingDelivery>[];
    for (final entry in all.entries) {
      if (entry.key.startsWith('pending_delivery_v1_${riderId}_')) {
        if (jsonDecode(entry.value)['confirmed'] == true) {
          await _clearScope(entry.key, entry.value);
        } else {
          result.add(await _read(entry.key, entry.value));
        }
      }
    }
    return result;
  }

  Future<void> clear(int riderId, String orderNumber) async {
    final scope = _scope(riderId, orderNumber);
    final pointer = await storage.read(key: scope);
    if (pointer == null) return;
    await _clearScope(scope, pointer);
  }

  Future<void> _clearScope(String scope, String pointer) async {
    final info = Map<String, dynamic>.from(jsonDecode(pointer) as Map);
    // A process death between deleting the file and its key must never make a
    // confirmed submission look like another upload waiting to be sent.
    if (info['confirmed'] != true) {
      await storage.write(
        key: scope,
        value: jsonEncode({...info, 'confirmed': true}),
      );
    }
    await _deleteFile(info['file'] as String);
    await storage.delete(key: scope);
  }

  Future<void> _deleteFile(String name) async {
    final file = await _file(name);
    if (await file.exists()) await file.delete();
  }
}
