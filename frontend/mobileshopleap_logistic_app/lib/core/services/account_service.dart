import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'api_client.dart';

class AccountService {
  AccountService._();

  static Future<Map<String, dynamic>> uploadPhoto(XFile photo) async {
    final body = await ApiClient.postMultipart(
      '/courier/account/avatar',
      fields: <String, String>{},
      files: [
        http.MultipartFile.fromBytes(
          'avatar',
          await photo.readAsBytes(),
          filename: photo.name,
        ),
      ],
    );
    return Map<String, dynamic>.from(body as Map);
  }

  static Future<Map<String, dynamic>> removePhoto() async {
    final body = await ApiClient.delete('/courier/account/avatar');
    return Map<String, dynamic>.from(body as Map);
  }
}
