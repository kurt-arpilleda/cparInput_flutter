import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'auto_update.dart';
import 'japanFolder/api_serviceJP.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:mime/mime.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:unique_identifier/unique_identifier.dart';

class SoftwareWebViewScreen extends StatefulWidget {
  final int linkID;

  SoftwareWebViewScreen({required this.linkID});

  @override
  _SoftwareWebViewScreenState createState() => _SoftwareWebViewScreenState();
}

class _SoftwareWebViewScreenState extends State<SoftwareWebViewScreen> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ApiService apiService = ApiService();
  final ApiServiceJP apiServiceJP = ApiServiceJP();

  InAppWebViewController? webViewController;
  PullToRefreshController? pullToRefreshController;

  String? _webUrl;
  String? _profilePictureUrl;
  String? _firstName;
  String? _surName;
  String? _idNumber;
  bool _isLoading = true;
  int? _currentLanguageFlag;
  double _progress = 0;
  String? _phOrJp;
  bool _isPhCountryPressed = false;
  bool _isJpCountryPressed = false;
  bool _isCountryDialogShowing = false;
  bool _isCountryLoadingPh = false;
  bool _isCountryLoadingJp = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _initializePullToRefresh();
    _fetchInitialData();
    _checkForUpdates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    webViewController?.stopLoading();
    pullToRefreshController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAllData();
      _checkForUpdates();
    }
  }

  void _initializePullToRefresh() {
    pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(
        color: Colors.blue,
      ),
      onRefresh: () async {
        if (webViewController != null) {
          _fetchAndLoadUrl();
        }
      },
    );
  }

  Future<void> _checkForUpdates() async {
    try {
      await AutoUpdate.checkForUpdate(context);
    } catch (e) {
      // Handle error if update check fails
      debugPrint('Update check failed: $e');
    }
  }

  Future<void> _fetchInitialData() async {
    await _fetchAndLoadUrl();
    await _fetchDeviceInfo();
    await _loadCurrentLanguageFlag();
    await _loadPhOrJp();
  }

  Future<bool> _shouldRefetchUrl() async {
    try {
      // Get the stored IDNumber from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      String? storedIdNumber = prefs.getString('IDNumber');

      // Get the latest IDNumber from the server
      String? deviceId = await UniqueIdentifier.serial;
      if (deviceId == null) {
        return true; // If we can't get device ID, refetch to be safe
      }

      final deviceResponse = await apiService.checkDeviceId(deviceId);
      String? serverIdNumber = deviceResponse['success'] == true ? deviceResponse['idNumber'] : null;

      // If either IDNumber is null or they don't match, we should refetch the URL
      if (storedIdNumber == null || serverIdNumber == null || storedIdNumber != serverIdNumber) {
        debugPrint("IDNumber changed: $storedIdNumber -> $serverIdNumber. Refetching URL.");
        return true;
      }

      return false; // IDNumbers match, no need to refetch URL
    } catch (e) {
      debugPrint("Error checking IDNumber: $e");
      return true; // On error, refetch to be safe
    }
  }

  Future<void> _refreshAllData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      // First check if IDNumber in SharedPreferences matches the one from the server
      bool shouldRefetchUrl = await _shouldRefetchUrl();

      // Always refresh basic data
      await _loadPhOrJp();
      await _loadCurrentLanguageFlag();
      await _fetchDeviceInfo();

      // If IDNumbers don't match, refetch the URL
      if (shouldRefetchUrl) {
        await _fetchAndLoadUrl();
      } else if (webViewController != null) {
        // If IDNumbers match, just reload the current page
        WebUri? currentUri = await webViewController!.getUrl();
        if (currentUri != null) {
          await webViewController!.loadUrl(urlRequest: URLRequest(url: currentUri));
        } else {
          _fetchAndLoadUrl();
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchDeviceInfo() async {
    try {
      String? deviceId = await UniqueIdentifier.serial;
      if (deviceId == null) {
        throw Exception("Unable to get device ID");
      }

      final deviceResponse = await apiService.checkDeviceId(deviceId);
      if (deviceResponse['success'] == true && deviceResponse['idNumber'] != null) {
        // Store the IDNumber in SharedPreferences (in case it's not already saved by the API)
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('IDNumber', deviceResponse['idNumber']);

        setState(() {
          _idNumber = deviceResponse['idNumber'];
        });
        await _fetchProfile(_idNumber!);
      }
    } catch (e) {
      print("Error fetching device info: $e");
    }
  }

  Future<void> _loadPhOrJp() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _phOrJp = prefs.getString('phorjp');
    });
  }

  Future<void> _fetchProfile(String idNumber) async {
    try {
      final profileData = await apiService.fetchProfile(idNumber);
      if (profileData["success"] == true) {
        String profilePictureFileName = profileData["picture"];

        String primaryUrl = "${ApiService.apiUrls[0]}V4/11-A%20Employee%20List%20V2/profilepictures/$profilePictureFileName";
        bool isPrimaryUrlValid = await _isImageAvailable(primaryUrl);

        String fallbackUrl = "${ApiService.apiUrls[1]}V4/11-A%20Employee%20List%20V2/profilepictures/$profilePictureFileName";
        bool isFallbackUrlValid = await _isImageAvailable(fallbackUrl);

        setState(() {
          _firstName = profileData["firstName"];
          _surName = profileData["surName"];
          _profilePictureUrl = isPrimaryUrlValid ? primaryUrl : isFallbackUrlValid ? fallbackUrl : null;
          _currentLanguageFlag = profileData["languageFlag"];
        });
      }
    } catch (e) {
      print("Error fetching profile: $e");
    }
  }

  Future<bool> _isImageAvailable(String url) async {
    try {
      final response = await http.head(Uri.parse(url)).timeout(Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<void> _fetchAndLoadUrl() async {
    try {
      String url = await apiService.fetchSoftwareLink(widget.linkID);
      if (mounted) {
        setState(() {
          _webUrl = url;
          _isLoading = true;
        });
        if (webViewController != null) {
          await webViewController!.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
        }
      }
    } catch (e) {
      debugPrint("Error fetching link: $e");
    }
  }

  Future<void> _loadCurrentLanguageFlag() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentLanguageFlag = prefs.getInt('languageFlag');
    });
  }

  Future<void> _updateLanguageFlag(int flag) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    if (_idNumber != null) {
      setState(() {
        _currentLanguageFlag = flag;
      });
      try {
        await apiService.updateLanguageFlag(_idNumber!, flag);
        await prefs.setInt('languageFlag', flag);

        if (webViewController != null) {
          WebUri? currentUri = await webViewController!.getUrl();
          if (currentUri != null) {
            await webViewController!.loadUrl(urlRequest: URLRequest(url: currentUri));
          } else {
            _fetchAndLoadUrl();
          }
        }
      } catch (e) {
        print("Error updating language flag: $e");
      }
    }
  }

  Future<void> _updatePhOrJp(String value) async {
    if ((value == 'ph' && _isCountryLoadingPh) || (value == 'jp' && _isCountryLoadingJp)) {
      return;
    }

    setState(() {
      if (value == 'ph') {
        _isCountryLoadingPh = true;
        _isPhCountryPressed = true;
      } else {
        _isCountryLoadingJp = true;
        _isJpCountryPressed = true;
      }
    });

    await Future.delayed(Duration(milliseconds: 100));

    try {
      String? deviceId = await UniqueIdentifier.serial;
      if (deviceId == null) {
        _showCountryLoginDialog(context, value);
        return;
      }

      // Get the appropriate service based on the selected country
      dynamic service = value == "jp" ? apiServiceJP : apiService;

      // Check device ID for the selected country
      final deviceResponse = await service.checkDeviceId(deviceId);

      if (deviceResponse['success'] != true || deviceResponse['idNumber'] == null) {
        _showCountryLoginDialog(context, value);
        return;
      }

      // If registered, proceed with the update
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('phorjp', value);
      setState(() {
        _phOrJp = value;
      });

      if (value == "ph") {
        Navigator.pushReplacementNamed(context, '/webView');
      } else if (value == "jp") {
        Navigator.pushReplacementNamed(context, '/webViewJP');
      }
    } catch (e) {
      print("Error updating country preference: $e");
      Fluttertoast.showToast(
        msg: "Error checking device registration: ${e.toString()}",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
      );
    } finally {
      setState(() {
        if (value == 'ph') {
          _isCountryLoadingPh = false;
          _isPhCountryPressed = false;
        } else {
          _isCountryLoadingJp = false;
          _isJpCountryPressed = false;
        }
      });
    }
  }
  void _showCountryLoginDialog(BuildContext context, String country) {
    if (_isCountryDialogShowing) return;

    _isCountryDialogShowing = true;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Image.asset(
                country == 'ph' ?  'assets/images/philippines.png' :  'assets/images/japan.png',
                width: 26,
                height: 26,
              ),
              SizedBox(width: 8),
              Text("Login Required",
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(fontSize: 20),
              ),
            ],
          ),
          content: Text(country == 'ph'
              ? "Please login to ARK LOG PH App first"
              : "Please login to ARK LOG JP App first"),
          actions: [
            TextButton(
              child: Text("OK"),
              onPressed: () {
                Navigator.of(context).pop();
                _isCountryDialogShowing = false;
              },
            ),
          ],
        );
      },
    ).then((_) {
      _isCountryDialogShowing = false;
    });
  }

  Future<bool> _onWillPop() async {
    if (webViewController != null && await webViewController!.canGoBack()) {
      webViewController!.goBack();
      return false;
    } else {
      return true;
    }
  }

  // Function to check if a URL is a download link
  bool _isDownloadableUrl(String url) {
    final mimeType = lookupMimeType(url);
    if (mimeType == null) return false;

    // List of common download file extensions
    const downloadableExtensions = [
      'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
      'zip', 'rar', '7z', 'tar', 'gz',
      'apk', 'exe', 'dmg', 'pkg',
      'jpg', 'jpeg', 'png', 'gif', 'bmp',
      'mp3', 'wav', 'ogg',
      'mp4', 'avi', 'mov', 'mkv',
      'txt', 'csv', 'json', 'xml'
    ];

    return downloadableExtensions.any((ext) => url.toLowerCase().contains('.$ext'));
  }

  // Function to launch URL in external browser
  Future<void> _launchInBrowser(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } else {
      Fluttertoast.showToast(
        msg: "Could not launch browser",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }
  Future<void> _showInputMethodPicker() async {
    try {
      if (Platform.isAndroid) {
        const MethodChannel channel = MethodChannel('input_method_channel');
        await channel.invokeMethod('showInputMethodPicker');
      } else {
        // iOS doesn't have this capability
        Fluttertoast.showToast(
          msg: "Keyboard selection is only available on Android",
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
        );
      }
    } catch (e) {
      debugPrint("Error showing input method picker: $e");
    }
  }
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        key: _scaffoldKey,
        resizeToAvoidBottomInset: false,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(kToolbarHeight - 20),
          child: SafeArea(
            child: AppBar(
              backgroundColor: Color(0xFF3452B4),
              centerTitle: true,
              toolbarHeight: kToolbarHeight - 20,
              leading: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 30,
                icon: Icon(
                  Icons.settings,
                  color: Colors.white,
                ),
                onPressed: () {
                  _scaffoldKey.currentState?.openDrawer();
                },
              ),
              title: _idNumber != null
                  ? Text(
                "ID: $_idNumber",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 2,
                      offset: Offset(1, 1),
                    ),
                  ],
                ),
              )
                  : null,
              actions: [
                IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 25,
                  icon: Container(
                    width: 25,
                    height: 25,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red,
                    ),
                    child: Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 25,
                    ),
                  ),
                  onPressed: () {
                    if (Platform.isIOS) {
                      exit(0);
                    } else {
                      SystemNavigator.pop();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        drawer: SizedBox(
          width: MediaQuery.of(context).size.width * 0.70,
          child: Drawer(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            color: Color(0xFF2053B3),
                            padding: EdgeInsets.only(top: 50, bottom: 20),
                            child: Column(
                              children: [
                                Align(
                                  alignment: Alignment.center,
                                  child: CircleAvatar(
                                    radius: 50,
                                    backgroundColor: Colors.white,
                                    backgroundImage: _profilePictureUrl != null
                                        ? NetworkImage(_profilePictureUrl!)
                                        : null,
                                    child: _profilePictureUrl == null
                                        ? FlutterLogo(size: 60)
                                        : null,
                                  ),
                                ),
                                SizedBox(height: 10),
                                Text(
                                  _firstName != null && _surName != null
                                      ? "$_firstName $_surName"
                                      : "User Name",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      overflow: TextOverflow.ellipsis,
                                      fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 5),
                                if (_idNumber != null)
                                  Text(
                                    "ID: $_idNumber",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,  // Medium weight
                                      letterSpacing: 0.5,          // Slightly spaced out letters
                                      shadows: [
                                        Shadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 2,
                                          offset: Offset(1, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              children: [
                                Text(
                                  "Language",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(width: 25),
                                GestureDetector(
                                  onTap: () => _updateLanguageFlag(1),
                                  child: Column(
                                    children: [
                                      Image.asset(
                                        'assets/images/americanFlag.gif',
                                        width: 40,
                                        height: 40,
                                      ),
                                      if (_currentLanguageFlag == 1)
                                        Container(
                                          height: 2,
                                          width: 40,
                                          color: Colors.blue,
                                        ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 30),
                                GestureDetector(
                                  onTap: () => _updateLanguageFlag(2),
                                  child: Column(
                                    children: [
                                      Image.asset(
                                        'assets/images/japaneseFlag.gif',
                                        width: 40,
                                        height: 40,
                                      ),
                                      if (_currentLanguageFlag == 2)
                                        Container(
                                          height: 2,
                                          width: 40,
                                          color: Colors.blue,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 20),
                          Padding(
                            padding: const EdgeInsets.only(left: 16.0),
                            child: Row(
                              children: [
                                Text(
                                  "Keyboard",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(width: 15), // Adjust this value as needed
                                IconButton(
                                  icon: Icon(Icons.keyboard, size: 28),
                                  iconSize: 28,
                                  onPressed: () {
                                    _showInputMethodPicker();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Text(
                          "Country",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 25),
                        GestureDetector(
                          onTapDown: (_) => setState(() => _isPhCountryPressed = true),
                          onTapUp: (_) => setState(() => _isPhCountryPressed = false),
                          onTapCancel: () => setState(() => _isPhCountryPressed = false),
                          onTap: () => _updatePhOrJp("ph"),
                          child: AnimatedContainer(
                            duration: Duration(milliseconds: 100),
                            transform: Matrix4.identity()..scale(_isPhCountryPressed ? 0.95 : 1.0),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Image.asset(
                                  'assets/images/philippines.png',
                                  width: 40,
                                  height: 40,
                                ),
                                // Subtle reload icon (only visible when PH is active and not loading)
                                if (_phOrJp == "ph" && !_isCountryLoadingPh)
                                  Opacity(
                                    opacity: 0.6, // Make it subtle
                                    child: Icon(Icons.refresh, size: 20, color: Colors.white),
                                  ),
                                // Loading indicator
                                if (_isCountryLoadingPh)
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                      strokeWidth: 2,
                                    ),
                                  ),
                                // Underline
                                if (_phOrJp == "ph")
                                  Positioned(
                                    bottom: 0,
                                    child: Container(
                                      height: 2,
                                      width: 40,
                                      color: Colors.blue,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: 30),
                        GestureDetector(
                          onTapDown: (_) => setState(() => _isJpCountryPressed = true),
                          onTapUp: (_) => setState(() => _isJpCountryPressed = false),
                          onTapCancel: () => setState(() => _isJpCountryPressed = false),
                          onTap: () => _updatePhOrJp("jp"),
                          child: AnimatedContainer(
                            duration: Duration(milliseconds: 100),
                            transform: Matrix4.identity()..scale(_isJpCountryPressed ? 0.95 : 1.0),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Image.asset(
                                  'assets/images/japan.png',
                                  width: 40,
                                  height: 40,
                                ),
                                // Subtle reload icon (only visible when JP is active and not loading)
                                if (_phOrJp == "jp" && !_isCountryLoadingJp)
                                  Opacity(
                                    opacity: 0.6, // Make it subtle
                                    child: Icon(Icons.refresh, size: 20, color: Colors.white),
                                  ),
                                // Loading indicator
                                if (_isCountryLoadingJp)
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                      strokeWidth: 2,
                                    ),
                                  ),
                                // Underline
                                if (_phOrJp == "jp")
                                  Positioned(
                                    bottom: 0,
                                    child: Container(
                                      height: 2,
                                      width: 40,
                                      color: Colors.blue,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Stack(
            children: [
              if (_webUrl != null)
                InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(_webUrl!)),
                  initialSettings: InAppWebViewSettings(
                    mediaPlaybackRequiresUserGesture: false,
                    javaScriptEnabled: true,
                    useHybridComposition: true,
                    allowsInlineMediaPlayback: true,
                    allowContentAccess: true,
                    allowFileAccess: true,
                    cacheEnabled: true,
                    javaScriptCanOpenWindowsAutomatically: true,
                    allowUniversalAccessFromFileURLs: true,
                    allowFileAccessFromFileURLs: true,
                    useOnDownloadStart: true,
                    transparentBackground: true,
                    thirdPartyCookiesEnabled: true,
                    domStorageEnabled: true,
                    databaseEnabled: true,
                    hardwareAcceleration: true,
                    supportMultipleWindows: false,
                    useWideViewPort: true,
                    loadWithOverviewMode: true,
                    mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                    verticalScrollBarEnabled: false,
                    horizontalScrollBarEnabled: false,
                    overScrollMode: OverScrollMode.NEVER,
                    forceDark: ForceDark.OFF,
                    forceDarkStrategy: ForceDarkStrategy.WEB_THEME_DARKENING_ONLY,
                    saveFormData: true,
                    userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36",
                  ),
                  pullToRefreshController: pullToRefreshController,
                  onWebViewCreated: (controller) {
                    webViewController = controller;
                  },
                  onLoadStart: (controller, url) {
                    setState(() {
                      _isLoading = true;
                      _progress = 0;
                    });
                  },
                  onLoadStop: (controller, url) {
                    pullToRefreshController?.endRefreshing();
                    setState(() {
                      _isLoading = false;
                      _progress = 1;
                    });
                  },
                  onProgressChanged: (controller, progress) {
                    setState(() {
                      _progress = progress / 100;
                    });
                  },
                  onReceivedServerTrustAuthRequest: (controller, challenge) async {
                    return ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.PROCEED);
                  },
                  onPermissionRequest: (controller, request) async {
                    List<Permission> permissionsToRequest = [];

                    if (request.resources.contains(PermissionResourceType.CAMERA)) {
                      permissionsToRequest.add(Permission.camera);
                    }
                    if (request.resources.contains(PermissionResourceType.MICROPHONE)) {
                      permissionsToRequest.add(Permission.microphone);
                    }

                    Map<Permission, PermissionStatus> statuses = await permissionsToRequest.request();
                    bool allGranted = statuses.values.every((status) => status.isGranted);

                    return PermissionResponse(
                      resources: request.resources,
                      action: allGranted ? PermissionResponseAction.GRANT : PermissionResponseAction.DENY,
                    );
                  },
                  // Handle download links by opening in external browser
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    final url = navigationAction.request.url?.toString() ?? '';

                    if (_isDownloadableUrl(url)) {
                      await _launchInBrowser(url);
                      return NavigationActionPolicy.CANCEL;
                    }
                    return NavigationActionPolicy.ALLOW;
                  },
                  // Also handle explicit download requests
                  onDownloadStartRequest: (controller, downloadStartRequest) async {
                    await _launchInBrowser(downloadStartRequest.url.toString());
                  },
                ),
              if (_isLoading)
                LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
            ],
          ),
        ),
      ),
    );
  }
}