import 'dart:async';
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

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController cameraController = MobileScannerController(
    torchEnabled: false,
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

  bool _screenOpened = false;
  bool _torchEnabled = false;
  bool _isQrMode = false;
  bool _showCenterLine = false;
  CameraFacing _cameraFacing = CameraFacing.back;
  StreamSubscription<BarcodeCapture>? _subscription;
  int _currentLanguageFlag = 1;
  String _phOrJp = "ph";

  final int _requiredConsecutiveScans = 3;
  String? _lastScannedCode;
  int _consecutiveScanCount = 0;
  Timer? _scanResetTimer;
  Timer? _cooldownTimer;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _startListening();
    _torchEnabled = cameraController.torchEnabled;
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
          final String code = capture.barcodes.first.displayValue ?? '';
          if (code.isNotEmpty && code.trim().length > 3) {
            _processScannedCode(code.trim());
          }
        }
      },
    );
  }

  void _processScannedCode(String code) {
    _scanResetTimer?.cancel();

    if (_lastScannedCode == code) {
      _consecutiveScanCount++;
    } else {
      _lastScannedCode = code;
      _consecutiveScanCount = 1;
    }

    _scanResetTimer = Timer(const Duration(milliseconds: 300), () {
      _consecutiveScanCount = 0;
      _lastScannedCode = null;
    });

    if (_consecutiveScanCount >= _requiredConsecutiveScans && !_isProcessing) {
      _scanResetTimer?.cancel();
      _isProcessing = true;
      _screenOpened = true;
      _foundBarcode(code);
    }
  }

  void _foundBarcode(String code) async {
    setState(() {
      _showCenterLine = true;
    });

    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 100);
    }

    SystemSound.play(SystemSoundType.click);

    _cooldownTimer = Timer(const Duration(milliseconds: 150), () {
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

  void _toggleScanMode() {
    setState(() {
      _isQrMode = !_isQrMode;
      _showCenterLine = false;
      _consecutiveScanCount = 0;
      _lastScannedCode = null;
      _isProcessing = false;
      _screenOpened = false;
    });
    _scanResetTimer?.cancel();
    _cooldownTimer?.cancel();
  }

  String get _titleText => _isQrMode
      ? (_currentLanguageFlag == 2 ? "QRコードスキャン" : "Scan QR Code")
      : (_currentLanguageFlag == 2 ? "バーコードスキャン" : "Scan Barcode");

  String get _instructionText => _isQrMode
      ? (_currentLanguageFlag == 2
      ? "QRコードを正方形のフレーム内に配置してください。\n中央に配置し、ぼやけていないことを確認してください。"
      : "Place the QR code inside the square frame.\nEnsure it is centered and not blurry.")
      : (_currentLanguageFlag == 2
      ? "バーコードを長方形のフレーム内に配置してください。\n中央に配置し、ぼやけていないことを確認してください。"
      : "Place the barcode inside the rectangular frame.\nEnsure it is centered and not blurry.");

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
            isQrMode: _isQrMode,
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
                      _isQrMode ? Icons.qr_code_scanner : Icons.barcode_reader,
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Container(
                    padding: EdgeInsets.all(4),
                    child: IconButton(
                      icon: Icon(
                        _isQrMode ? Icons.barcode_reader : Icons.qr_code_scanner,
                        color: Colors.white,
                        size: 32,
                      ),
                      onPressed: _toggleScanMode,
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Container(
                    padding: EdgeInsets.all(4),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CustomScannerOverlay extends StatelessWidget {
  final bool isQrMode;
  final bool showCenterLine;

  const CustomScannerOverlay({
    required this.isQrMode,
    required this.showCenterLine,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: ScannerOverlayPainter(
        isQrMode: isQrMode,
        showCenterLine: showCenterLine,
      ),
    );
  }
}

class ScannerOverlayPainter extends CustomPainter {
  final bool isQrMode;
  final bool showCenterLine;

  ScannerOverlayPainter({
    required this.isQrMode,
    required this.showCenterLine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double frameWidth = isQrMode ? 250 : 330;
    final double frameHeight = isQrMode ? 250 : 80;
    final double centerX = (size.width - frameWidth) / 2;
    final double centerY = (size.height - frameHeight) / 2;

    final Paint dimPaint = Paint()
      ..color = Colors.black.withOpacity(0.8);

    final Path dimPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(Rect.fromLTWH(centerX, centerY, frameWidth, frameHeight))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(dimPath, dimPaint);

    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    final double cornerLength = 40;

    canvas.drawLine(
      Offset(centerX, centerY),
      Offset(centerX + cornerLength, centerY),
      borderPaint,
    );
    canvas.drawLine(
      Offset(centerX, centerY),
      Offset(centerX, centerY + cornerLength),
      borderPaint,
    );

    canvas.drawLine(
      Offset(centerX + frameWidth, centerY),
      Offset(centerX + frameWidth - cornerLength, centerY),
      borderPaint,
    );
    canvas.drawLine(
      Offset(centerX + frameWidth, centerY),
      Offset(centerX + frameWidth, centerY + cornerLength),
      borderPaint,
    );

    canvas.drawLine(
      Offset(centerX, centerY + frameHeight),
      Offset(centerX + cornerLength, centerY + frameHeight),
      borderPaint,
    );
    canvas.drawLine(
      Offset(centerX, centerY + frameHeight),
      Offset(centerX, centerY + frameHeight - cornerLength),
      borderPaint,
    );

    canvas.drawLine(
      Offset(centerX + frameWidth, centerY + frameHeight),
      Offset(centerX + frameWidth - cornerLength, centerY + frameHeight),
      borderPaint,
    );
    canvas.drawLine(
      Offset(centerX + frameWidth, centerY + frameHeight),
      Offset(centerX + frameWidth, centerY + frameHeight - cornerLength),
      borderPaint,
    );

    if (showCenterLine) {
      final Paint centerLinePaint = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6;

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