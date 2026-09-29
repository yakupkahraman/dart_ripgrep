import 'dart:io';

import 'package:dart_ripgrep/dart_ripgrep.dart';
import 'package:dart_ripgrep/src/json.dart';
import 'package:test/test.dart';

void main() {
  // Recorded with ripgrep 15.2.0: `rg --json -C1 --sort path hello src`,
  // plus a hand-written match whose path is not valid UTF-8.
  final lines = File(
    'test/fixtures/search.jsonl',
  ).readAsLinesSync().map(parseJsonLine).nonNulls.toList();

  String matched(RgMatch m) =>
      m.submatches.map((r) => m.text.substring(r.start, r.end)).join(',');

  test('skips begin, end and summary messages', () {
    expect(lines, hasLength(8));
  });

  test('parses context lines', () {
    final c = lines.first as RgContext;
    expect((c.path, c.lineNumber, c.text), ('src/bin.txt', 1, 'a'));
  });

  test('decodes non-UTF-8 lines sent as bytes', () {
    final m = lines[1] as RgMatch;
    expect(m.text, '\u{FFFD}\u{FFFD} hello bytes');
    expect(matched(m), 'hello');
  });

  test('converts byte offsets to UTF-16 indices (emoji)', () {
    final m = lines[3] as RgMatch;
    expect(m.text, '😀 hello');
    expect(m.submatches.single, (start: 3, end: 8));
    expect(matched(m), 'hello');
  });

  test('converts byte offsets for multiple submatches (accents)', () {
    final m = lines[5] as RgMatch;
    expect(m.text, 'çay hello dünya hello');
    expect(m.submatches, [(start: 4, end: 9), (start: 16, end: 21)]);
    expect(matched(m), 'hello,hello');
    expect((lines[6] as RgContext).text, 'omega');
  });

  test('decodes non-UTF-8 paths sent as bytes', () {
    final m = lines.last as RgMatch;
    expect(m.path, 'src/caf\u{FFFD}.txt');
    expect(matched(m), 'hello');
  });

  test('strips CRLF line terminators', () {
    final m = parseJsonLine(
      '{"type":"match","data":{"path":{"text":"a"},"lines":{"text":"hi\\r\\n"},'
      '"line_number":1,"absolute_offset":0,"submatches":'
      '[{"match":{"text":"hi"},"start":0,"end":2}]}}',
    )!;
    expect(m.text, 'hi');
  });
}
