import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qrcodeapp/scan_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const method = MethodChannel('dev.steenbakker.mobile_scanner/scanner/method');
  const event = MethodChannel('dev.steenbakker.mobile_scanner/scanner/event');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(method, (call) async {
      if (call.method == 'state') return 1;
      if (call.method == 'request') return true;
      if (call.method == 'start') {
        return {
          'textureId': 1,
          'size': {'width': 1080.0, 'height': 1920.0},
          'torchable': true,
          'numberOfCameras': 2,
        };
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(event, (call) async => null);
  });
  tearDown(() {
    for (final channel in [method, event]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  testWidgets('Invalid frames do not stall scanning; valid result pops once',
      (tester) async {
    String? result;
    var results = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => TextButton(
                onPressed: () async {
                  result = await Navigator.push<String>(context,
                      MaterialPageRoute(builder: (_) => const ScanPage()));
                  results++;
                },
                child: const Text('scan'),
              )),
    ));
    await tester.tap(find.text('scan'));
    await tester.pumpAndSettle();
    final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
    scanner.onDetect(BarcodeCapture(barcodes: [
      const Barcode(format: BarcodeFormat.qrCode),
      const Barcode(format: BarcodeFormat.qrCode, rawValue: ''),
    ]));
    await tester.pump();
    expect(find.byType(ScanPage), findsOneWidget);
    scanner.onDetect(BarcodeCapture(barcodes: [
      const Barcode(format: BarcodeFormat.qrCode),
      const Barcode(format: BarcodeFormat.code128, rawValue: 'ignore'),
      const Barcode(format: BarcodeFormat.qrCode, rawValue: '中文 😀 '),
    ]));
    scanner.onDetect(BarcodeCapture(barcodes: [
      const Barcode(format: BarcodeFormat.qrCode, rawValue: 'duplicate'),
    ]));
    await tester.pumpAndSettle();
    expect(result, '中文 😀 ');
    expect(results, 1);
    expect(find.text('scan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
