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

  static const String versionPath = "V4/Others/Kurt/LatestVersionAPK/CparInput2/version.json";
  static const String apkPath = "V4/Others/Kurt/LatestVersionAPK/CparInput2/NGReport.apk";
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
              await _showAutomaticUpdateDialog(context, latestVersionName, releaseNotes, apiUrl);
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

  static Future<void> _showAutomaticUpdateDialog(BuildContext context, String versionName, String releaseNotes, String apiUrl) async {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent closing by tapping outside
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false, // Prevent closing by back button
          child: AlertDialog(
            title: Text("Updating Application"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("New Version: $versionName"),
                SizedBox(height: 10),
                Text("Release Notes:"),
                Text(releaseNotes),
                SizedBox(height: 20),
                StreamBuilder<int>(
                  stream: _downloadAndInstallApk(context, apiUrl),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      if (snapshot.data! == 100) {
                        return Column(
                          children: [
                            LinearProgressIndicator(
                              value: 1.0,
                              backgroundColor: Colors.grey[300],
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                            ),
                            SizedBox(height: 10),
                            Text("Installation in progress..."),
                          ],
                        );
                      } else if (snapshot.data! == -1) {
                        return Column(
                          children: [
                            Icon(Icons.error, color: Colors.red, size: 40),
                            SizedBox(height: 10),
                            Text("Update failed. Retrying..."),
                          ],
                        );
                      } else {
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
                      }
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
            ),
          ),
        );
      },
    );
  }

  static Stream<int> _downloadAndInstallApk(BuildContext context, String apiUrl) async* {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final Directory? externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          final String apkFilePath = "${externalDir.path}/NGReport.apk";
          final File apkFile = File(apkFilePath);

          final request = http.Request('GET', Uri.parse("$apiUrl$apkPath"));
          final http.StreamedResponse response = await request.send().timeout(requestTimeout);

          if (response.statusCode == 200) {
            int totalBytes = response.contentLength ?? 0;
            int downloadedBytes = 0;

            yield 0; // Start with 0%

            final fileSink = apkFile.openWrite();
            await for (var chunk in response.stream) {
              downloadedBytes += chunk.length;
              fileSink.add(chunk);
              int progress = ((downloadedBytes / totalBytes) * 100).round();
              yield progress; // Yield the progress percentage
            }
            await fileSink.close();

            if (await apkFile.exists()) {
              yield 100; // Download complete
              await _installApk(context, apkFilePath); // Install the APK after download
              return; // Exit the function if the download and installation is successful
            } else {
              yield -1; // Indicate error
              Fluttertoast.showToast(msg: "Failed to save the APK file.");
            }
          }
        }
      } catch (e) {
        print("Error downloading APK on attempt $attempt: $e");
        yield -1; // Indicate error
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1)); // Exponential backoff
          print("Waiting for ${delay.inSeconds} seconds before retrying...");
          await Future.delayed(delay);
        }
      }
    }
    Fluttertoast.showToast(msg: "Failed to download update after $maxRetries attempts.");
  }

  static Future<void> _installApk(BuildContext context, String apkPath) async {
    try {
      if (await Permission.requestInstallPackages.isGranted) {
        final result = await OpenFile.open(apkPath);
        if (result.type != ResultType.done) {
          Fluttertoast.showToast(msg: "Failed to open the installer. Retrying...");
          // Re-try the update check
          await Future.delayed(Duration(seconds: 2));
          PackageInfo packageInfo = await PackageInfo.fromPlatform();
          int currentVersionCode = int.parse(packageInfo.buildNumber);
          await checkForUpdate(context);
        }
      } else {
        final status = await Permission.requestInstallPackages.request();
        if (status.isGranted) {
          final result = await OpenFile.open(apkPath);
          if (result.type != ResultType.done) {
            Fluttertoast.showToast(msg: "Failed to open the installer. Retrying...");
            // Re-try the update check
            await Future.delayed(Duration(seconds: 2));
            PackageInfo packageInfo = await PackageInfo.fromPlatform();
            int currentVersionCode = int.parse(packageInfo.buildNumber);
            await checkForUpdate(context);
          }
        } else {
          Fluttertoast.showToast(msg: "Installation permission denied. Retrying...");
          // Re-try the update check
          await Future.delayed(Duration(seconds: 2));
          PackageInfo packageInfo = await PackageInfo.fromPlatform();
          int currentVersionCode = int.parse(packageInfo.buildNumber);
          await checkForUpdate(context);
        }
      }
    } catch (e) {
      print("Error installing APK: $e");
      Fluttertoast.showToast(msg: "Failed to install update. Retrying...");
      // Re-try the update check
      await Future.delayed(Duration(seconds: 2));
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      int currentVersionCode = int.parse(packageInfo.buildNumber);
      await checkForUpdate(context);
    }
  }
}