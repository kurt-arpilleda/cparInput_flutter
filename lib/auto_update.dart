import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';

class AutoUpdate {
  static const List<String> apiUrls = [
    "http://192.168.254.163/",
    "http://126.209.7.246/"
  ];

  static const String versionPath = "V4/Others/Kurt/LatestVersionAPK/CparInput/version.json";
  static const String apkPath = "V4/Others/Kurt/LatestVersionAPK/CparInput/cparInput.apk";
  static const Duration requestTimeout = Duration(seconds: 3);
  static const int maxRetries = 6;
  static const Duration initialRetryDelay = Duration(seconds: 1);

  static Future<void> checkForUpdate(BuildContext context) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      for (String apiUrl in apiUrls) {
        try {
          final response = await http.get(Uri.parse("$apiUrl$versionPath")).timeout(requestTimeout);

          if (response.statusCode == 200) {
            final Map<String, dynamic> versionInfo = jsonDecode(response.body);
            final int latestVersionCode = versionInfo["versionCode"];
            final String latestVersionName = versionInfo["versionName"];
            final String releaseNotes = versionInfo["releaseNotes"];

            PackageInfo packageInfo = await PackageInfo.fromPlatform();
            int currentVersionCode = int.parse(packageInfo.buildNumber);

            if (latestVersionCode > currentVersionCode) {
              _showUpdateDialog(context, latestVersionName, releaseNotes, apiUrl);
              return; // Exit the function if a successful response is received
            } else {
              // Fluttertoast.showToast(msg: "You are using the latest version.");
              return; // Exit if no update is needed
            }
          }
        } catch (e) {
          print("Error checking for update from $apiUrl on attempt $attempt: $e");
        }
      }
      if (attempt < maxRetries) {
        final delay = initialRetryDelay * (1 << (attempt - 1));
        print("Waiting for ${delay.inSeconds} seconds before retrying...");
        await Future.delayed(delay);
      }
    }
    Fluttertoast.showToast(msg: "Failed to check for updates after $maxRetries attempts.");
  }

  static void _showUpdateDialog(BuildContext context, String versionName, String releaseNotes, String apiUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Update Available"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("New Version: $versionName"),
              SizedBox(height: 10),
              Text("Release Notes:"),
              Text(releaseNotes),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text("Later"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showDownloadProgressDialog(context, apiUrl);
                _downloadAndInstallApk(context, apiUrl);
              },
              child: Text("Update"),
            ),
          ],
        );
      },
    );
  }

  static void _showDownloadProgressDialog(BuildContext context, String apiUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Downloading Update"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder<int>(
                stream: _downloadProgressStream(apiUrl),
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return Column(
                      children: [
                        LinearProgressIndicator(
                          value: snapshot.data! / 100,
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                        ),
                        SizedBox(height: 10),
                        Text("${snapshot.data}% Downloading"),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        LinearProgressIndicator(
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                        ),
                        SizedBox(height: 10),
                        Text("Starting download..."),
                      ],
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  static Stream<int> _downloadProgressStream(String apiUrl) async* {
    try {
      final request = http.Request('GET', Uri.parse("$apiUrl$apkPath"));
      final http.StreamedResponse response = await request.send().timeout(requestTimeout);

      int totalBytes = response.contentLength ?? 0;
      int downloadedBytes = 0;

      yield 0; // Start with 0%

      await for (var chunk in response.stream) {
        downloadedBytes += chunk.length;
        int progress = ((downloadedBytes / totalBytes) * 100).round();
        yield progress; // Yield the progress percentage
      }

      yield 100; // Complete at 100%
    } catch (e) {
      yield -1; // Indicate errors
    }
  }

  static Future<void> _downloadAndInstallApk(BuildContext context, String apiUrl) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final Directory? externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          final String apkFilePath = "${externalDir.path}/cparInput.apk";
          final File apkFile = File(apkFilePath);

          final request = http.Request('GET', Uri.parse("$apiUrl$apkPath"));
          final http.StreamedResponse response = await request.send().timeout(requestTimeout);

          if (response.statusCode == 200) {
            final fileSink = apkFile.openWrite();
            await response.stream.pipe(fileSink);
            await fileSink.close();

            if (await apkFile.exists()) {
              _installApk(context, apkFilePath); // Install the APK after download
              return; // Exit the function if the download is successful
            } else {
              Fluttertoast.showToast(msg: "Failed to save the APK file.");
            }
          }
        }
      } catch (e) {
        print("Error downloading APK on attempt $attempt: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1)); // Exponential backoff
          print("Waiting for ${delay.inSeconds} seconds before retrying...");
          await Future.delayed(delay);
        }
      }
    }
    Fluttertoast.showToast(msg: "Failed to download update after $maxRetries attempts.");
    Navigator.of(context).pop(); // Close the download progress dialog
  }

  static void _installApk(BuildContext context, String apkPath) async {
    try {
      if (await Permission.requestInstallPackages.isGranted) {
        final result = await OpenFile.open(apkPath);
        if (result.type != ResultType.done) {
          Fluttertoast.showToast(msg: "Failed to open the installer.");
        }
      } else {
        await Permission.requestInstallPackages.request();
        if (await Permission.requestInstallPackages.isGranted) {
          final result = await OpenFile.open(apkPath);
          if (result.type != ResultType.done) {
            Fluttertoast.showToast(msg: "Failed to open the installer.");
          }
        } else {
          Fluttertoast.showToast(msg: "Installation permission denied.");
        }
      }
    } catch (e) {
      print("Error installing APK: $e");
      Fluttertoast.showToast(msg: "Failed to install update.");
    }
  }
}