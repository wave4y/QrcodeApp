import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:qrcodeapp/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Paste generates QR and clear removes it without floating controls',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': '中文 QR 😀'} : null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(const MyApp());
    expect(find.byType(FloatingActionButton), findsNothing);
    final scan = find.byTooltip('扫描二维码');
    final paste = find.byTooltip('粘贴');
    final clear = find.byTooltip('清空');
    expect(tester.getCenter(scan).dx, lessThan(tester.getCenter(paste).dx));
    expect(tester.getCenter(paste).dx, lessThan(tester.getCenter(clear).dx));
    await tester.tap(paste);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '中文 QR 😀');
    expect(tester.takeException(), isNull);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
    await tester.enterText(find.byType(TextField), '再次输入');
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Empty clipboard keeps existing content', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(const MyApp());
    await tester.enterText(find.byType(TextField), '保留内容');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('粘贴'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '保留内容');
    expect(find.text('剪贴板中没有可粘贴的文本'), findsOneWidget);
  });

  testWidgets('Editing a later page resets pagination on a narrow display',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    await tester.enterText(find.byType(TextField), 'a' * 501);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(PageView));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-350, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 1);
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '新内容');
    await tester.pumpAndSettle();
    expect(find.text('第 1/1 页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
