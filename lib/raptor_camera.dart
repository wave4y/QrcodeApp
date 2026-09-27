import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// The camera is mounted only while receiving. Disposing it stops the camera;
/// RaptorQ state remains in the transfer service across pauses and tab changes.
class RaptorCamera extends StatefulWidget {
  const RaptorCamera({super.key, required this.onCapture});
  final void Function(BarcodeCapture) onCapture;

  @override
  State<RaptorCamera> createState() => _RaptorCameraState();
}

class _RaptorCameraState extends State<RaptorCamera> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    cameraResolution: const Size(1920, 1080),
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 80,
  );
  double _zoom = 0;
  bool _busy = false;

  Future<void> _action(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('相机操作失败，请重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MobileScanner(
        controller: _controller,
        onDetect: widget.onCapture,
        errorBuilder: (context, error, child) => Center(
            child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
              error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? '请在系统设置中允许相机权限，再点击暂停、继续接收'
                  : '无法启动相机，请关闭占用相机的应用后重新接收',
              textAlign: TextAlign.center),
        )),
        overlay: Align(
          alignment: Alignment.bottomCenter,
          child: ColoredBox(
            color: Colors.black54,
            child: Row(children: [
              ValueListenableBuilder<bool?>(
                valueListenable: _controller.hasTorchState,
                builder: (context, hasTorch, child) =>
                    ValueListenableBuilder<TorchState>(
                  valueListenable: _controller.torchState,
                  builder: (context, torch, child) => IconButton(
                    tooltip: '补光灯',
                    icon: Icon(
                        torch == TorchState.on
                            ? Icons.flash_on
                            : Icons.flash_off,
                        color: Colors.white),
                    onPressed: hasTorch == true && !_busy
                        ? () => _action(_controller.toggleTorch)
                        : null,
                  ),
                ),
              ),
              Expanded(
                  child: Slider(
                value: _zoom,
                activeColor: Colors.white,
                onChanged:
                    _busy ? null : (value) => setState(() => _zoom = value),
                onChangeEnd: (value) =>
                    _action(() => _controller.setZoomScale(value)),
                semanticFormatterCallback: (value) =>
                    '缩放 ${(value * 100).round()}%',
              )),
              IconButton(
                tooltip: '切换摄像头',
                icon: const Icon(Icons.switch_camera, color: Colors.white),
                onPressed: _busy
                    ? null
                    : () => _action(() async {
                          await _controller.switchCamera();
                          await _controller.setZoomScale(0);
                          if (mounted) setState(() => _zoom = 0);
                        }),
              ),
            ]),
          ),
        ),
      );
}
