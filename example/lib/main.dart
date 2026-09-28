import 'dart:io';

import 'package:dart_ripgrep/dart_ripgrep.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  // CI sets this. Windows GUI apps have no reliable stdout, so the result also
  // goes to a file (inside the container when sandboxed on macOS).
  final resultFile = Platform.environment['DART_RIPGREP_RESULT'];
  if (resultFile != null) {
    WidgetsFlutterBinding.ensureInitialized();
    final (ok, out) = await _check();
    stdout.writeln(out);
    File(resultFile).writeAsStringSync(out);
    exit(ok ? 0 : 1);
  }
  runApp(const MaterialApp(home: Spike()));
}

/// Uses the bundled rg on a temp dir the app itself can read, even sandboxed.
Future<(bool, String)> _check() async {
  try {
    final rg = Ripgrep();
    final dir = Directory.systemTemp.createTempSync('dart_ripgrep');
    File('${dir.path}/a.txt').writeAsStringSync('one\nçay hello\n');
    final files = await rg.files(dir.path).toList();
    final match = await rg.search('hello', dir.path).first as RgMatch;
    dir.deleteSync(recursive: true);
    final hit = match.submatches.single;
    final ok =
        files.length == 1 &&
        match.lineNumber == 2 &&
        match.text.substring(hit.start, hit.end) == 'hello';
    return (
      ok,
      '${rg.executable}\n$files\n${match.path}:${match.lineNumber}: ${match.text}',
    );
  } catch (e) {
    return (false, 'ERROR: $e');
  }
}

class Spike extends StatelessWidget {
  const Spike({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: FutureBuilder(
      future: _check(),
      builder: (context, snapshot) => Padding(
        padding: const EdgeInsets.all(16),
        child: SelectableText(snapshot.data?.$2 ?? 'running...'),
      ),
    ),
  );
}
