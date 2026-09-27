import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:qrcodeapp/qr_content.dart';

void main() {
  test('Each QR holds at most 500 characters, including Chinese and emoji', () {
    for (final character in ['a', '中', '😀']) {
      expect(splitQRContent(character * 500), [character * 500]);
      expect(splitQRContent(character * 501), [character * 500, character]);
    }
  });

  test('Pagination preserves content and Unicode at boundaries', () {
    for (final text in ['', '${'a' * 499}😀中文\n  ', '中文😀' * 500]) {
      final pages = splitQRContent(text);
      expect(pages.join(), text);
      for (final page in pages) {
        expect(page.runes.length, lessThanOrEqualTo(500));
        expect(utf8.decode(utf8.encode(page)), page);
        expect(page, isNotEmpty);
      }
    }
  });
}
