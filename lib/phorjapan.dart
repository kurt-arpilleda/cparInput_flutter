import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unique_identifier/unique_identifier.dart';
import 'webview.dart';
import 'japanFolder/webviewJP.dart';
import 'api_service.dart';
import 'japanFolder/api_serviceJP.dart';

class PhOrJpScreen extends StatefulWidget {
  @override
  _PhOrJpScreenState createState() => _PhOrJpScreenState();
}

class _PhOrJpScreenState extends State<PhOrJpScreen> {
  bool _isLoadingPh = false;
  bool _isLoadingJp = false;
  bool _isDialogShowing = false;
  bool _isPhPressed = false;
  bool _isJpPressed = false;

  Future<void> _setPreference(String value, BuildContext context) async {
    if ((value == 'ph' && _isLoadingPh) || (value == 'jp' && _isLoadingJp)) {
      return;
    }

    setState(() {
      if (value == 'ph') {
        _isLoadingPh = true;
        _isPhPressed = true;
      } else {
        _isLoadingJp = true;
        _isJpPressed = true;
      }
    });

    await Future.delayed(Duration(milliseconds: 100)); // Short delay for button press effect

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('phorjp', value);

    try {
      String? deviceId = await UniqueIdentifier.serial;
      if (deviceId == null) {
        _showLoginDialog(context, value);
        return;
      }

      dynamic response;

      if (value == 'ph') {
        final apiService = ApiService();
        response = await apiService.checkDeviceId(deviceId);
      } else if (value == 'jp') {
        final apiServiceJP = ApiServiceJP();
        response = await apiServiceJP.checkDeviceId(deviceId);
      }

      if (response['success'] == true) {
        if (value == 'ph') {
          _navigateWithTransition(context, SoftwareWebViewScreen(linkID: 6));
        } else if (value == 'jp') {
          _navigateWithTransition(context, SoftwareWebViewScreenJP(linkID: 6));
        }
      } else {
        _showLoginDialog(context, value);
      }
    } catch (e) {
      _showLoginDialog(context, value);
    } finally {
      setState(() {
        if (value == 'ph') {
          _isLoadingPh = false;
          _isPhPressed = false;
        } else {
          _isLoadingJp = false;
          _isJpPressed = false;
        }
      });
    }
  }

  void _showLoginDialog(BuildContext context, String country) {
    if (_isDialogShowing) return;

    _isDialogShowing = true;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                country == 'ph' ? 'assets/images/philippines.png' : 'assets/images/japan.png',
                width: 26,
                height: 26,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  country == 'ph' ? "Login Required" : "ログインが必要です",
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(fontSize: 20),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              country == 'ph'
                  ? "Please login to ARK LOG PH App first"
                  : "まず、ARK LOG JPアプリにログインしてください。",
            ),
          ),
          actions: [
            TextButton(
              child: Text("OK"),
              onPressed: () {
                Navigator.of(context).pop();
                _isDialogShowing = false;
              },
            ),
          ],
        );
      },
    ).then((_) {
      _isDialogShowing = false;
    });
  }


  void _navigateWithTransition(BuildContext context, Widget screen) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => screen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOut;

          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);

          return SlideTransition(
            position: offsetAnimation,
            child: child,
          );
        },
        transitionDuration: Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'PH or JP',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // PH Flag with button-like animation
                GestureDetector(
                  onTapDown: (_) => setState(() => _isPhPressed = true),
                  onTapUp: (_) => setState(() => _isPhPressed = false),
                  onTapCancel: () => setState(() => _isPhPressed = false),
                  onTap: () => _setPreference('ph', context),
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: 100),
                    transform: Matrix4.identity()..scale(_isPhPressed ? 0.95 : 1.0),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.asset(
                          'assets/images/philippines.png',
                          width: 75,
                          height: 75,
                          fit: BoxFit.contain,
                        ),
                        if (_isLoadingPh)
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                            strokeWidth: 2,
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 40),
                // JP Flag with button-like animation
                GestureDetector(
                  onTapDown: (_) => setState(() => _isJpPressed = true),
                  onTapUp: (_) => setState(() => _isJpPressed = false),
                  onTapCancel: () => setState(() => _isJpPressed = false),
                  onTap: () => _setPreference('jp', context),
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: 100),
                    transform: Matrix4.identity()..scale(_isJpPressed ? 0.95 : 1.0),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.asset(
                          'assets/images/japan.png',
                          width: 75,
                          height: 75,
                          fit: BoxFit.contain,
                        ),
                        if (_isLoadingJp)
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                            strokeWidth: 2,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}