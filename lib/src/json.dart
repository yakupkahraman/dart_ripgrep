import 'dart:convert';

import 'types.dart';

/// Parses one line of `rg --json` output. Returns null for messages that carry
/// no line (`begin`, `end`, `summary`).
RgLine? parseJsonLine(String line) {
  final message = jsonDecode(line) as Map<String, dynamic>;
  final type = message['type'];
  if (type != 'match' && type != 'context') return null;

  final data = message['data'] as Map<String, dynamic>;
  final path = utf8.decode(_bytes(data['path']), allowMalformed: true);
  final lineNumber = data['line_number'] as int;
  final bytes = _bytes(data['lines']);
  final text = _stripTerminator(utf8.decode(bytes, allowMalformed: true));
  if (type == 'context') return RgContext(path, lineNumber, text);

  // ripgrep reports UTF-8 byte offsets; Dart strings index UTF-16 code units.
  int index(int byteOffset) =>
      utf8.decode(bytes.sublist(0, byteOffset), allowMalformed: true).length;
  final submatches = [
    for (final m in data['submatches'] as List)
      (start: index(m['start'] as int), end: index(m['end'] as int)),
  ];
  return RgMatch(path, lineNumber, text, submatches);
}

// Non-UTF-8 data arrives as {"bytes": <base64>} instead of {"text": ...}.
List<int> _bytes(Object? field) {
  final map = field as Map<String, dynamic>;
  final text = map['text'];
  return text is String
      ? utf8.encode(text)
      : base64.decode(map['bytes'] as String);
}

String _stripTerminator(String line) => line.endsWith('\r\n')
    ? line.substring(0, line.length - 2)
    : line.endsWith('\n')
    ? line.substring(0, line.length - 1)
    : line;
