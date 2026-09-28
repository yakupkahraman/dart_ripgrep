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

/// Runs the bundled rg on a temp dir the app itself can read, even sandboxed.
Future<(bool, String)> _check() async {
  try {
    final rg = Ripgrep();
    final dir = Directory.systemTemp.createTempSync('dart_ripgrep');
    File('${dir.path}/a.txt').writeAsStringSync('one\nhello ripgrep\n');
    final version = await Process.run(rg.executable, ['--version']);
    final search = await Process.run(rg.executable, ['-n', 'hello', dir.path]);
    dir.deleteSync(recursive: true);
    final ok = search.exitCode == 0 && '${search.stdout}'.contains('2:hello');
    return (ok, '${rg.executable}\n${version.stdout}\n${search.stdout}${search.stderr}');
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
