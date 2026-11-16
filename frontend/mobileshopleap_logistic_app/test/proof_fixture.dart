import 'dart:typed_data';
import 'package:image/image.dart' as img;

final Uint8List proofPhoto = img.encodeJpg(img.Image(width: 640, height: 800));
