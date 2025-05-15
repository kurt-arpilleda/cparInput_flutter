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

  // Cache for the last working server index
  int? _lastWorkingServerIndex;
  late http.Client httpClient;
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  ApiServiceJP() {
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

  // Helper method to make parallel requests and return the first successful response
  Future<T> _makeParallelRequest<T>(Future<T> Function(String apiUrl) requestFn) async {
    // Try the last working server first if available
    if (_lastWorkingServerIndex != null) {
      try {
        final result = await requestFn(apiUrls[_lastWorkingServerIndex!])
            .timeout(requestTimeout);
        return result;
      } catch (e) {
        // If the last working server fails, proceed with parallel requests
      }
    }

    // Create a list of futures for all API URLs
    final futures = apiUrls.map((apiUrl) => requestFn(apiUrl).timeout(requestTimeout));

    // Use Future.any to get the first successful response
    try {
      final result = await Future.any(futures);
      // Remember which server worked
      _lastWorkingServerIndex = apiUrls.indexOf((result as dynamic).apiUrlUsed ?? apiUrls[0]);
      return result;
    } catch (e) {
      // If all parallel requests fail, throw an exception
      throw Exception("All API URLs are unreachable");
    }
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
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLinkAPI/kurt_fetchLink.php?linkID=$linkID");
          final response = await httpClient.get(uri);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data.containsKey("softwareLink")) {
              String relativePath = data["softwareLink"];
              String fullUrl = Uri.parse(apiUrl).resolve(relativePath).toString();
              if (idNumber != null) {
                fullUrl += "?idNumber=$idNumber";
              }
              return _ApiResult(fullUrl, apiUrl);
            } else {
              throw Exception(data["error"] ?? "Invalid response format");
            }
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result.value;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          print("Waiting ${delay.inSeconds} seconds before retry...");
          await Future.delayed(delay);
        }
      }
    }

    String finalError = "All API URLs are unreachable after $maxRetries attempts";
    _showToast(finalError);
    throw Exception(finalError);
  }

  Future<bool> checkIdNumber(String idNumber) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLinkAPI/kurt_checkIdNumber.php");
          final response = await httpClient.post(
            uri,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"idNumber": idNumber}),
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              return _ApiResult(true, apiUrl);
            } else {
              throw Exception(data["message"] ?? "ID check failed");
            }
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result.value;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<Map<String, dynamic>> fetchProfile(String idNumber) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLinkAPI/kurt_fetchProfile.php?idNumber=$idNumber");
          final response = await httpClient.get(uri);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              return _ApiResult(data, apiUrl);
            } else {
              throw Exception(data["message"] ?? "Profile fetch failed");
            }
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result.value;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<void> updateLanguageFlag(String idNumber, int languageFlag) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLinkAPI/kurt_updateLanguage.php");
          final response = await httpClient.post(
            uri,
            body: {
              'idNumber': idNumber,
              'languageFlag': languageFlag.toString(),
            },
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              return _ApiResult(null, apiUrl);
            } else {
              throw Exception(data["message"] ?? "Update failed");
            }
          }
          throw Exception("HTTP ${response.statusCode}");
        });
        return; // Success
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<Map<String, dynamic>> checkDeviceId(String deviceId) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLinkAPI/kurt_checkDeviceId.php?deviceID=$deviceId");
          final response = await httpClient.get(uri);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data['success'] == true && data['idNumber'] != null) {
              final prefs = await _prefs;
              await prefs.setString('IDNumber', data['idNumber']);
            }
            return _ApiResult(data, apiUrl);
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result.value;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
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

// Helper class to track which API URL was used
class _ApiResult<T> {
  final T value;
  final String apiUrlUsed;

  _ApiResult(this.value, this.apiUrlUsed);
}