import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({Key? key}) : super(key: key);

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> with WidgetsBindingObserver {
  late MobileScannerController cameraController;

  bool _screenOpened = false;
  bool _torchEnabled = false;
  bool _showCenterLine = false;
  StreamSubscription<BarcodeCapture>? _subscription;
  int _currentLanguageFlag = 1;
  String _phOrJp = "ph";

  final int _minScansRequired = 2;
  final int _maxScanHistory = 5;
  final Queue<String> _scanHistory = Queue<String>();
  final Map<String, int> _scanCounts = {};
  Timer? _scanResetTimer;
  Timer? _cooldownTimer;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lockOrientation();
    _initializeCamera();
    _loadPreferences();
  }

  void _lockOrientation() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  void _initializeCamera() {
    cameraController = MobileScannerController(
      torchEnabled: false,
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      formats: [
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.code93,
        BarcodeFormat.ean8,
        BarcodeFormat.ean13,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.itf,
        BarcodeFormat.codabar,
        BarcodeFormat.qrCode,
        BarcodeFormat.pdf417,
        BarcodeFormat.aztec,
        BarcodeFormat.dataMatrix,
      ],
    );
    _startListening();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lockOrientation();
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _phOrJp = prefs.getString('phorjp') ?? "ph";
      if (_phOrJp == "ph") {
        _currentLanguageFlag = prefs.getInt('languageFlag') ?? 1;
      } else {
        _currentLanguageFlag = prefs.getInt('languageFlagJP') ?? 1;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _subscription?.cancel();
    _scanResetTimer?.cancel();
    _cooldownTimer?.cancel();
    cameraController.dispose();
    super.dispose();
  }

  void _startListening() {
    _subscription = cameraController.barcodes.listen(
          (BarcodeCapture capture) {
        if (!_screenOpened && !_isProcessing && capture.barcodes.isNotEmpty) {
          for (final barcode in capture.barcodes) {
            final String? rawValue = barcode.rawValue;
            final String? displayValue = barcode.displayValue;
            String code = rawValue ?? displayValue ?? '';
            code = code.trim();
            if (code.isNotEmpty && code.length >= 1) {
              if (_isValidBarcode(code, barcode.format)) {
                _processScannedCode(code);
                break;
              }
            }
          }
        }
      },
    );
  }

  bool _isValidBarcode(String code, BarcodeFormat? format) {
    if (code.isEmpty) return false;

    if (format == BarcodeFormat.ean13 && code.length == 13) {
      return _validateEAN13(code);
    } else if (format == BarcodeFormat.ean8 && code.length == 8) {
      return _validateEAN8(code);
    } else if (format == BarcodeFormat.upcA && code.length == 12) {
      return _validateUPCA(code);
    } else if (format == BarcodeFormat.upcE && (code.length == 6 || code.length == 7 || code.length == 8)) {
      return true;
    }

    return true;
  }

  bool _validateEAN13(String code) {
    if (code.length != 13) return false;
    try {
      int sum = 0;
      for (int i = 0; i < 12; i++) {
        int digit = int.parse(code[i]);
        sum += (i % 2 == 0) ? digit : digit * 3;
      }
      int checkDigit = (10 - (sum % 10)) % 10;
      return checkDigit == int.parse(code[12]);
    } catch (e) {
      return false;
    }
  }

  bool _validateEAN8(String code) {
    if (code.length != 8) return false;
    try {
      int sum = 0;
      for (int i = 0; i < 7; i++) {
        int digit = int.parse(code[i]);
        sum += (i % 2 == 0) ? digit * 3 : digit;
      }
      int checkDigit = (10 - (sum % 10)) % 10;
      return checkDigit == int.parse(code[7]);
    } catch (e) {
      return false;
    }
  }

  bool _validateUPCA(String code) {
    if (code.length != 12) return false;
    try {
      int sum = 0;
      for (int i = 0; i < 11; i++) {
        int digit = int.parse(code[i]);
        sum += (i % 2 == 0) ? digit * 3 : digit;
      }
      int checkDigit = (10 - (sum % 10)) % 10;
      return checkDigit == int.parse(code[11]);
    } catch (e) {
      return false;
    }
  }

  void _processScannedCode(String code) {
    _scanResetTimer?.cancel();

    _scanHistory.addLast(code);
    _scanCounts[code] = (_scanCounts[code] ?? 0) + 1;

    while (_scanHistory.length > _maxScanHistory) {
      final removed = _scanHistory.removeFirst();
      _scanCounts[removed] = (_scanCounts[removed] ?? 1) - 1;
      if (_scanCounts[removed]! <= 0) {
        _scanCounts.remove(removed);
      }
    }

    _scanResetTimer = Timer(const Duration(milliseconds: 800), () {
      _scanHistory.clear();
      _scanCounts.clear();
    });

    String? bestCode;
    int maxCount = 0;
    _scanCounts.forEach((key, value) {
      if (value > maxCount) {
        maxCount = value;
        bestCode = key;
      }
    });

    if (bestCode != null && maxCount >= _minScansRequired && !_isProcessing) {
      _scanResetTimer?.cancel();
      _isProcessing = true;
      _screenOpened = true;
      _foundBarcode(bestCode!);
    }
  }

  void _foundBarcode(String code) async {
    setState(() {
      _showCenterLine = true;
    });

    final hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      Vibration.vibrate(duration: 100);
    }

    SystemSound.play(SystemSoundType.click);

    _cooldownTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted) {
        Navigator.of(context).pop(code);
      }
    });
  }

  Future<void> _toggleTorch() async {
    setState(() {
      _torchEnabled = !_torchEnabled;
    });
    await cameraController.toggleTorch();
  }

  String get _titleText => _currentLanguageFlag == 2 ? "スキャナー" : "Scanner";

  String get _instructionText => _currentLanguageFlag == 2
      ? "バーコードまたはQRコードをフレーム内に配置してください"
      : "Place the barcode or QR code inside the frame";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: cameraController,
            fit: BoxFit.cover,
          ),
          CustomScannerOverlay(
            showCenterLine: _showCenterLine,
          ),
          Positioned(
            top: 60,
            right: 16,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 32,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          Positioned(
            top: 80,
            left: 26,
            right: 26,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.qr_code_scanner,
                      color: Colors.white,
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      _titleText,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                Text(
                  _instructionText,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: IconButton(
                  icon: Icon(
                    _torchEnabled ? Icons.flash_on : Icons.flash_off,
                    color: _torchEnabled ? Colors.yellow : Colors.white,
                    size: 32,
                  ),
                  onPressed: _toggleTorch,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CustomScannerOverlay extends StatelessWidget {
  final bool showCenterLine;

  const CustomScannerOverlay({
    required this.showCenterLine,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: ScannerOverlayPainter(
        showCenterLine: showCenterLine,
      ),
    );
  }
}

class ScannerOverlayPainter extends CustomPainter {
  final bool showCenterLine;

  ScannerOverlayPainter({
    required this.showCenterLine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double frameWidth = size.width * 0.9;
    final double frameHeight = frameWidth * 0.8;
    final double centerX = (size.width - frameWidth) / 2;
    final double centerY = (size.height - frameHeight) / 2;


    final Paint dimPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.8);

    final Path dimPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(Rect.fromLTWH(centerX, centerY, frameWidth, frameHeight))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(dimPath, dimPaint);

    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRect(
      Rect.fromLTWH(centerX, centerY, frameWidth, frameHeight),
      borderPaint,
    );

    final double cornerLength = 30;
    final double cornerWidth = 4;

    final Paint cornerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = cornerWidth;

    canvas.drawLine(
      Offset(centerX, centerY),
      Offset(centerX + cornerLength, centerY),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(centerX, centerY),
      Offset(centerX, centerY + cornerLength),
      cornerPaint,
    );

    canvas.drawLine(
      Offset(centerX + frameWidth, centerY),
      Offset(centerX + frameWidth - cornerLength, centerY),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(centerX + frameWidth, centerY),
      Offset(centerX + frameWidth, centerY + cornerLength),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(centerX, centerY + frameHeight),
      Offset(centerX + cornerLength, centerY + frameHeight),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(centerX, centerY + frameHeight),
      Offset(centerX, centerY + frameHeight - cornerLength),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(centerX + frameWidth, centerY + frameHeight),
      Offset(centerX + frameWidth - cornerLength, centerY + frameHeight),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(centerX + frameWidth, centerY + frameHeight),
      Offset(centerX + frameWidth, centerY + frameHeight - cornerLength),
      cornerPaint,
    );
    if (showCenterLine) {
      final Paint centerLinePaint = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;

      final double centerLineY = centerY + frameHeight / 2;
      canvas.drawLine(
        Offset(centerX, centerLineY),
        Offset(centerX + frameWidth, centerLineY),
        centerLinePaint,
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}