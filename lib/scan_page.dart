import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final MobileScannerController controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 250,
    cameraResolution: const Size(1920, 1080),
  );
  bool _hasResult = false;
  bool _cameraBusy = false;
  double _zoom = 0;

  void _onDetect(BarcodeCapture capture) {
    if (!mounted || _hasResult || _cameraBusy) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (barcode.format != BarcodeFormat.qrCode ||
          code == null ||
          code.isEmpty) {
        continue;
      }
      // Lock only after a valid result, before navigation to ignore late frames.
      _hasResult = true;
      Navigator.pop(context, code);
      return;
    }
  }

  Future<void> _cameraAction(Future<void> Function() action) async {
    if (_cameraBusy || _hasResult) return;
    setState(() => _cameraBusy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('相机操作失败，请重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _cameraBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫描二维码'),
        actions: [
          ValueListenableBuilder<bool?>(
            valueListenable: controller.hasTorchState,
            builder: (context, hasTorch, child) =>
                ValueListenableBuilder<TorchState>(
              valueListenable: controller.torchState,
              builder: (context, state, child) => IconButton(
                tooltip: state == TorchState.on ? '关闭补光灯' : '打开补光灯',
                icon: Icon(
                    state == TorchState.on ? Icons.flash_on : Icons.flash_off),
                onPressed: hasTorch == true && !_cameraBusy
                    ? () => _cameraAction(controller.toggleTorch)
                    : null,
              ),
            ),
          ),
          IconButton(
            tooltip: '切换摄像头',
            icon: const Icon(Icons.switch_camera),
            onPressed: _cameraBusy
                ? null
                : () => _cameraAction(() async {
                      await controller.switchCamera();
                      await controller.setZoomScale(0);
                      if (mounted) setState(() => _zoom = 0);
                    }),
          ),
        ],
      ),
      body: MobileScanner(
        controller: controller,
        onDetect: _onDetect,
        errorBuilder: (context, error, child) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.no_photography_outlined, size: 48),
                const SizedBox(height: 16),
                Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? '请在系统设置中允许相机权限，然后重新进入扫描页面'
                      : '无法启动相机，请检查相机是否被占用后重新进入',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('返回'),
                ),
              ],
            ),
          ),
        ),
        // This is a visual guide only; retain full-frame detection for codes
        // near the edge. The plugin hides it when camera startup fails.
        overlay: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: ShapeDecoration(
                      shape: ScannerOverlay(
                        borderColor: Colors.white,
                        borderWidth: 3,
                        borderRadius: 10,
                        borderLength: 30,
                        cutOutSize: constraints.biggest.shortestSide * 0.7,
                      ),
                      color: Colors.black.withOpacity(0.5),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '对准二维码并保持稳定，小二维码可适当放大',
                          style: TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                        Row(
                          children: [
                            const Icon(Icons.zoom_out, color: Colors.white),
                            Expanded(
                              child: Slider(
                                value: _zoom,
                                activeColor: Colors.white,
                                semanticFormatterCallback: (value) =>
                                    '缩放 ${(value * 100).round()}%',
                                onChanged: _cameraBusy
                                    ? null
                                    : (value) {
                                        setState(() => _zoom = value);
                                      },
                                onChangeEnd: (value) => _cameraAction(() async {
                                  try {
                                    await controller.setZoomScale(value);
                                  } catch (_) {
                                    if (mounted) {
                                      setState(() => _zoom = controller
                                          .zoomScaleState.value
                                          .clamp(0.0, 1.0));
                                    }
                                    rethrow;
                                  }
                                }),
                              ),
                            ),
                            const Icon(Icons.zoom_in, color: Colors.white),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // mobile_scanner 3.5.7 disposes its supplied controller with the widget.
}

class ScannerOverlay extends ShapeBorder {
  final Color borderColor;
  final double borderWidth;
  final double borderRadius;
  final double borderLength;
  final double cutOutSize;

  const ScannerOverlay({
    required this.borderColor,
    required this.borderWidth,
    required this.borderRadius,
    required this.borderLength,
    required this.cutOutSize,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: rect.center,
            width: cutOutSize,
            height: cutOutSize,
          ),
          Radius.circular(borderRadius),
        ),
      );
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..addRect(rect)
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: rect.center,
            width: cutOutSize,
            height: cutOutSize,
          ),
          Radius.circular(borderRadius),
        ),
      )
      ..fillType = PathFillType.evenOdd;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final cutOutRect = Rect.fromCenter(
      center: rect.center,
      width: cutOutSize,
      height: cutOutSize,
    );

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    // 绘制四个角
    final topLeft = cutOutRect.topLeft;
    final topRight = cutOutRect.topRight;
    final bottomLeft = cutOutRect.bottomLeft;
    final bottomRight = cutOutRect.bottomRight;

    // 左上角
    canvas.drawPath(
      Path()
        ..moveTo(topLeft.dx, topLeft.dy + borderLength)
        ..lineTo(topLeft.dx, topLeft.dy)
        ..lineTo(topLeft.dx + borderLength, topLeft.dy),
      borderPaint,
    );

    // 右上角
    canvas.drawPath(
      Path()
        ..moveTo(topRight.dx - borderLength, topRight.dy)
        ..lineTo(topRight.dx, topRight.dy)
        ..lineTo(topRight.dx, topRight.dy + borderLength),
      borderPaint,
    );

    // 左下角
    canvas.drawPath(
      Path()
        ..moveTo(bottomLeft.dx, bottomLeft.dy - borderLength)
        ..lineTo(bottomLeft.dx, bottomLeft.dy)
        ..lineTo(bottomLeft.dx + borderLength, bottomLeft.dy),
      borderPaint,
    );

    // 右下角
    canvas.drawPath(
      Path()
        ..moveTo(bottomRight.dx - borderLength, bottomRight.dy)
        ..lineTo(bottomRight.dx, bottomRight.dy)
        ..lineTo(bottomRight.dx, bottomRight.dy - borderLength),
      borderPaint,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return ScannerOverlay(
      borderColor: borderColor,
      borderWidth: borderWidth * t,
      borderRadius: borderRadius * t,
      borderLength: borderLength * t,
      cutOutSize: cutOutSize * t,
    );
  }
}
