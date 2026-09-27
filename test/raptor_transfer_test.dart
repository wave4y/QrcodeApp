import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:qrcodeapp/raptor_transfer.dart';

void main() {
  test('Binary RaptorQ transport survives text QR with 500-character limit',
      () {
    final frame = Uint8List.fromList(List.generate(356, (i) => i % 256));
    final text = RaptorTransfer.qrText(frame);
    expect(text.length, 480);
    expect(RaptorTransfer.parseQr(text), orderedEquals(frame));
    expect(RaptorTransfer.parseQr('普通二维码'), isNull);
    expect(RaptorTransfer.parseQr('RQ1:bad'), isNull);
    expect(RaptorTransfer.parseQr('$text extra'), isNull);
  });
}
