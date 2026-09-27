import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:qrcodeapp/main.dart';
import 'package:qrcodeapp/raptor_transfer.dart';
import 'package:qrcodeapp/raptor_transfer_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const method = MethodChannel('dev.steenbakker.mobile_scanner/scanner/method');
  const event = MethodChannel('dev.steenbakker.mobile_scanner/scanner/event');
  final binary =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var received = 0;
  var saveCalls = 0;
  var generated = 0;
  var cimbarOpened = 0;
  final frame = Uint8List(356);

  setUp(() {
    received = 0;
    saveCalls = 0;
    generated = 0;
    cimbarOpened = 0;
    binary.setMockMethodCallHandler(method, (call) async {
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
    binary.setMockMethodCallHandler(event, (call) async => null);
    binary.setMockMethodCallHandler(RaptorTransfer.channel, (call) async {
      switch (call.method) {
        case 'openCimbar':
          cimbarOpened++;
          return null;
        case 'resetReceiver':
          received = 0;
          return null;
        case 'createText':
          return {
            'name': '文本.txt',
            'size': 20,
            'sourceSymbols': 1,
            'blocks': 1
          };
        case 'pickFile':
          return null; // system picker cancellation
        case 'nextFrame':
          generated++;
          return frame;
        case 'acceptFrame':
          received++;
          return {
            'status': received < 2 ? 'accepted' : 'complete',
            'received': received,
            'needed': 2,
            'progress': received / 2,
            'name': received < 2 ? null : '手机文件.bin',
            'size': 256
          };
        case 'saveReceived':
          saveCalls++;
          return saveCalls > 1;
      }
      return null;
    });
  });
  tearDown(() {
    for (final channel in [method, event, RaptorTransfer.channel]) {
      binary.setMockMethodCallHandler(channel, null);
    }
  });

  testWidgets('Cimbar opens from the title without changing ordinary QR text',
      (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.enterText(find.byType(TextField), '普通二维码保持不变');
    await tester.tap(find.text('二维码工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('高速流水码 · Cimbar'));
    await tester.pumpAndSettle();
    expect(cimbarOpened, 1);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '普通二维码保持不变');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Title opens RaptorQ; create, play, pause, cancel picker and return',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    await tester.enterText(find.byType(TextField), '保留普通二维码');
    await tester.tap(find.text('二维码工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('黑白流水码 · 兼容旧版'));
    await tester.pumpAndSettle();
    expect(find.byType(RaptorTransferPage), findsOneWidget);
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '手机文字传输');
    await tester.tap(find.text('创建文本流水码'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('每帧 480 字符'), findsOneWidget);
    await tester.ensureVisible(find.text('开始播放'));
    await tester.tap(find.text('开始播放'));
    await tester.pump(const Duration(seconds: 1));
    expect(generated, greaterThan(1));
    await tester.tap(find.text('暂停播放'));
    await tester.pumpAndSettle();
    final before = generated;
    await tester.pump(const Duration(seconds: 1));
    expect(generated, before);
    await tester.ensureVisible(find.text('选择文件'));
    await tester.tap(find.text('选择文件'));
    await tester.pumpAndSettle();
    expect(find.text('文本.txt'), findsOneWidget);
    await tester.tap(find.text('流水码创建'));
    await tester.pumpAndSettle();
    expect(find.byType(RaptorTransferPage), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '保留普通二维码');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Pause retains progress; completion saves and cancellation retains file',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RaptorTransferPage()));
    await tester.pumpAndSettle();
    void capture() => tester
        .widget<MobileScanner>(find.byType(MobileScanner))
        .onDetect(BarcodeCapture(barcodes: [
          Barcode(
              format: BarcodeFormat.qrCode,
              rawValue: RaptorTransfer.qrText(frame))
        ]));
    capture();
    await tester.pumpAndSettle();
    expect(find.textContaining('已接收 1 个'), findsOneWidget);
    await tester.tap(find.text('暂停接收'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileScanner), findsNothing);
    await tester.tap(find.text('继续接收'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已接收 1 个'), findsOneWidget);
    capture();
    await tester.pumpAndSettle();
    expect(find.text('文件已恢复，SHA-256 校验通过'), findsOneWidget);
    expect(find.byType(MobileScanner), findsNothing);
    await tester.tap(find.text('保存到手机'));
    await tester.pumpAndSettle();
    expect(find.text('手机文件.bin'), findsOneWidget);
    expect(find.text('文件已保存'), findsNothing);
    await tester.tap(find.text('保存到手机'));
    await tester.pumpAndSettle();
    expect(find.text('文件已保存'), findsOneWidget);
    await tester.tap(find.text('重新识别'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileScanner), findsOneWidget);
    expect(find.text('文件已保存'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
