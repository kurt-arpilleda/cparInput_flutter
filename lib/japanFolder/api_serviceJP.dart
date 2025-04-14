import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:unique_identifier/unique_identifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiServiceJP {
  static const List<String> apiUrls = [
    "https://192.168.1.213/",
    "https://220.157.175.232/"
  ];

  static const Duration requestTimeout = Duration(seconds: 2);
  static const int maxRetries = 6;
  static const Duration initialRetryDelay = Duration(seconds: 1);

  late http.Client httpClient;

  ApiService() {
    httpClient = _createHttpClient();
  }

  http.Client _createHttpClient() {
    final HttpClient client = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    return IOClient(client);
  }
  void _showToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
    );
  }
  Future<String> fetchSoftwareLink(int linkID) async {
    String? deviceId = await UniqueIdentifier.serial;
    if (deviceId == null) {
      throw Exception("Unable to get device ID");
    }

    // First get the ID number associated with this device
    final deviceResponse = await checkDeviceId(deviceId);
    if (!deviceResponse['success']) {
      throw Exception("Device not registered or no ID number associated");
    }
    String? idNumber = deviceResponse['idNumber'];

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      for (int i = 0; i < apiUrls.length; i++) {
        String apiUrl = apiUrls[i];
        try {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLinkAPI/kurt_fetchLink.php?linkID=$linkID");
          final response = await http.get(uri).timeout(requestTimeout);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data.containsKey("softwareLink")) {
              String relativePath = data["softwareLink"];
              String fullUrl = Uri.parse(apiUrl).resolve(relativePath).toString();
              if (idNumber != null) {
                fullUrl += "?idNumber=$idNumber";
              }
              return fullUrl;
            } else {
              throw Exception(data["error"]);
            }
          }
        } catch (e) {
          String errorMessage = "Error accessing $apiUrl on attempt $attempt";
          print(errorMessage);

          if (i == 0 && apiUrls.length > 1) {
            print("Falling back to ${apiUrls[1]}");
          }
        }
      }

      if (attempt < maxRetries) {
        final delay = initialRetryDelay * (1 << (attempt - 1));
        print("Waiting for ${delay.inSeconds} seconds before retrying...");
        await Future.delayed(delay);
      }
    }

    String finalError = "All API URLs are unreachable after $maxRetries attempts";
    _showToast(finalError);
    throw Exception(finalError);
  }

  Future<bool> checkIdNumber(String idNumber) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      for (String apiUrl in apiUrls) {
        try {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLinkAPI/kurt_checkIdNumber.php");
          final response = await http.post(
            uri,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"idNumber": idNumber}),
          ).timeout(requestTimeout);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              return true;
            } else {
              throw Exception(data["message"]);
            }
          }
        } catch (e) {
          // print("Error accessing $apiUrl on attempt $attempt: $e");
        }
      }
      // If all servers fail, wait for an exponential backoff delay before retrying
      if (attempt < maxRetries) {
        final delay = initialRetryDelay * (1 << (attempt - 1)); // Exponential backoff
        // print("Waiting for ${delay.inSeconds} seconds before retrying...");
        await Future.delayed(delay);
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<Map<String, dynamic>> fetchProfile(String idNumber) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      for (String apiUrl in apiUrls) {
        try {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLinkAPI/kurt_fetchProfile.php?idNumber=$idNumber");
          final response = await http.get(uri).timeout(requestTimeout);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              return data;
            } else {
              throw Exception(data["message"]);
            }
          }
        } catch (e) {
          // print("Error accessing $apiUrl on attempt $attempt: $e");
        }
      }
      // If all servers fail, wait for an exponential backoff delay before retrying
      if (attempt < maxRetries) {
        final delay = initialRetryDelay * (1 << (attempt - 1)); // Exponential backoff
        // print("Waiting for ${delay.inSeconds} seconds before retrying...");
        await Future.delayed(delay);
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<void> updateLanguageFlag(String idNumber, int languageFlag) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      for (String apiUrl in apiUrls) {
        try {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLinkAPI/kurt_updateLanguage.php");
          final response = await http.post(
            uri,
            body: {
              'idNumber': idNumber,
              'languageFlag': languageFlag.toString(),
            },
          ).timeout(requestTimeout);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              return;
            } else {
              throw Exception(data["message"]);
            }
          }
        } catch (e) {
          // print("Error accessing $apiUrl on attempt $attempt: $e");
        }
      }
      // If all servers fail, wait for an exponential backoff delay before retrying
      if (attempt < maxRetries) {
        final delay = initialRetryDelay * (1 << (attempt - 1)); // Exponential backoff
        // print("Waiting for ${delay.inSeconds} seconds before retrying...");
        await Future.delayed(delay);
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }
  Future<Map<String, dynamic>> checkDeviceId(String deviceId) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      for (String apiUrl in apiUrls) {
        try {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLinkAPI/kurt_checkDeviceId.php?deviceID=$deviceId");
          final response = await http.get(uri).timeout(requestTimeout);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            // Store the idNumber if it exists
            if (data['success'] == true && data['idNumber'] != null) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('IDNumberJP', data['idNumber']);
            }
            return data;
          }
        } catch (e) {
          print("Error accessing $apiUrl on attempt $attempt: $e");
        }
      }
      if (attempt < maxRetries) {
        final delay = initialRetryDelay * (1 << (attempt - 1));
        await Future.delayed(delay);
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }
  static void setupHttpOverrides() {
    HttpOverrides.global = MyHttpOverrides();
  }
}
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}