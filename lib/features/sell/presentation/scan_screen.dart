import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/buttons.dart';

/// Full-screen camera scanner. Pops with the first barcode it reads.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final code = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (code == null || code.isEmpty) return;
    _done = true;
    context.pop(code);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = MediaQuery.sizeOf(context);
    final window = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 40),
      width: size.width * 0.75,
      height: size.width * 0.5,
    );
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            scanWindow: window,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.xxl),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Camera access is off. Enable it in system settings to scan barcodes.'
                      : 'Camera unavailable: ${error.errorDetails?.message ?? error.errorCode.name}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.onPrimary),
                ),
              ),
            ),
          ),
          Positioned.fromRect(
            rect: window,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: c.onPrimary, width: 2),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.screen),
              child: Row(
                children: [
                  CircleIconButton(icon: Icons.close, tooltip: 'Close scanner', onPressed: () => context.pop()),
                  const Spacer(),
                  CircleIconButton(
                    icon: Icons.flash_on,
                    tooltip: 'Toggle flash',
                    onPressed: () => _controller.toggleTorch(),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 60,
            child: Text(
              'Point the camera at a barcode',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.onPrimary, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}
