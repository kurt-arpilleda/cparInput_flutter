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
  static const String apkPath = "V4/Others/Kurt/LatestVersionAPK/CparInput/NGReport.apk";
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
              _showMandatoryUpdateDialog(context, latestVersionName, releaseNotes, apiUrl);
              return; // Exit the function if a successful response is received
            } else {
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

  static void _showMandatoryUpdateDialog(BuildContext context, String versionName, String releaseNotes, String apiUrl) {
    bool isDownloading = false;

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent closing by tapping outside
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false, // Prevent closing by back button
          child: AlertDialog(
            title: Text("Update Available"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("New Version: $versionName"),
                SizedBox(height: 10),
                Text("Release Notes:"),
                Text(releaseNotes),
                if (isDownloading) ...[
                  SizedBox(height: 20),
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
                            Text("${snapshot.data}% Downloaded"),
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
                            Text("Preparing download..."),
                          ],
                        );
                      }
                    },
                  ),
                ],
              ],
            ),
            actions: [
              if (!isDownloading)
                TextButton(
                  onPressed: () {
                    isDownloading = true;
                    (context as Element).markNeedsBuild(); // Force rebuild to show progress
                    _downloadAndInstallApk(context, apiUrl);
                  },
                  child: Text("UPDATE NOW"),
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
          final String apkFilePath = "${externalDir.path}/NGReport.apk";
          final File apkFile = File(apkFilePath);

          final request = http.Request('GET', Uri.parse("$apiUrl$apkPath"));
          final http.StreamedResponse response = await request.send().timeout(requestTimeout);

          if (response.statusCode == 200) {
            final fileSink = apkFile.openWrite();
            await response.stream.pipe(fileSink);
            await fileSink.close();

            if (await apkFile.exists()) {
              Navigator.of(context).pop(); // Close the dialog before installation
              await _installApk(context, apkFilePath); // Install the APK after download
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
    // Don't close the dialog - user must keep trying to update
  }

  static Future<void> _installApk(BuildContext context, String apkPath) async {
    try {
      if (await Permission.requestInstallPackages.isGranted) {
        final result = await OpenFile.open(apkPath);
        if (result.type != ResultType.done) {
          Fluttertoast.showToast(msg: "Failed to open the installer. Please try again.");
          // Re-show the update dialog since installation failed
          await Future.delayed(Duration(seconds: 2));
          PackageInfo packageInfo = await PackageInfo.fromPlatform();
          int currentVersionCode = int.parse(packageInfo.buildNumber);
          checkForUpdate(context);
        }
      } else {
        final status = await Permission.requestInstallPackages.request();
        if (status.isGranted) {
          final result = await OpenFile.open(apkPath);
          if (result.type != ResultType.done) {
            Fluttertoast.showToast(msg: "Failed to open the installer. Please try again.");
            // Re-show the update dialog since installation failed
            await Future.delayed(Duration(seconds: 2));
            PackageInfo packageInfo = await PackageInfo.fromPlatform();
            int currentVersionCode = int.parse(packageInfo.buildNumber);
            checkForUpdate(context);
          }
        } else {
          Fluttertoast.showToast(msg: "Installation permission denied. The app cannot update without this permission.");
          // Re-show the update dialog since permission was denied
          await Future.delayed(Duration(seconds: 2));
          PackageInfo packageInfo = await PackageInfo.fromPlatform();
          int currentVersionCode = int.parse(packageInfo.buildNumber);
          checkForUpdate(context);
        }
      }
    } catch (e) {
      print("Error installing APK: $e");
      Fluttertoast.showToast(msg: "Failed to install update. Please try again.");
      // Re-show the update dialog since installation failed
      await Future.delayed(Duration(seconds: 2));
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      int currentVersionCode = int.parse(packageInfo.buildNumber);
      checkForUpdate(context);
    }
  }
}