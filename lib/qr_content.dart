/// Split by Unicode code point so Chinese and emoji stay intact.
List<String> splitQRContent(String text, {int maxChars = 500}) {
  if (maxChars < 1) {
    throw ArgumentError.value(maxChars, 'maxChars', 'Must be >= 1');
  }
  final pages = <String>[];
  var buffer = StringBuffer();
  var count = 0;
  for (final rune in text.runes) {
    if (count == maxChars) {
      pages.add(buffer.toString());
      buffer = StringBuffer();
      count = 0;
    }
    buffer.writeCharCode(rune);
    count++;
  }
  if (count > 0) pages.add(buffer.toString());
  return pages;
}
