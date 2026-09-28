import 'dart:async';
import 'dart:io';

import 'package:dart_ripgrep/dart_ripgrep.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  // CI smoke test; see .github/workflows/ci.yml.
  final resultFile = Platform.environment['DART_RIPGREP_RESULT'];
  if (resultFile != null) return _smokeTest(resultFile);
  runApp(const MaterialApp(home: SearchPage()));
}

/// A minimal search panel: type a folder and a pattern, see matches as they
/// stream in.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _rg = Ripgrep();
  final _root = TextEditingController(text: Directory.current.path);
  final _results = <RgMatch>[];
  StreamSubscription<RgLine>? _search;

  void _run(String pattern) {
    // Cancelling kills the previous ripgrep process, so the newest query wins.
    _search?.cancel();
    setState(_results.clear);
    if (pattern.isEmpty) return;
    _search = _rg
        .search(
          pattern,
          _root.text,
          options: const RgOptions(caseMode: RgCase.smart),
        )
        .take(500)
        .listen(
          (line) => setState(() => _results.add(line as RgMatch)),
          onError: (Object e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('$e')));
          },
        );
  }

  @override
  void dispose() {
    _search?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _root,
            decoration: const InputDecoration(labelText: 'Folder'),
          ),
          TextField(
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Search'),
            onChanged: _run,
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, i) => _MatchTile(_results[i]),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MatchTile extends StatelessWidget {
  const _MatchTile(this.match);

  final RgMatch match;

  @override
  Widget build(BuildContext context) {
    // Submatch ranges index straight into the Dart string.
    final spans = <TextSpan>[];
    var last = 0;
    for (final r in match.submatches) {
      spans
        ..add(TextSpan(text: match.text.substring(last, r.start)))
        ..add(
          TextSpan(
            text: match.text.substring(r.start, r.end),
            style: const TextStyle(backgroundColor: Colors.yellow),
          ),
        );
      last = r.end;
    }
    spans.add(TextSpan(text: match.text.substring(last)));
    return ListTile(
      dense: true,
      title: Text.rich(TextSpan(children: spans)),
      subtitle: Text('${match.path}:${match.lineNumber}'),
    );
  }
}

Future<void> _smokeTest(String resultFile) async {
  WidgetsFlutterBinding.ensureInitialized();
  var ok = false;
  String out;
  try {
    final rg = Ripgrep();
    // A temp dir, because a sandboxed macOS app can read it.
    final dir = Directory.systemTemp.createTempSync('dart_ripgrep');
    File('${dir.path}/a.txt').writeAsStringSync('one\nçay hello\n');
    final files = await rg.files(dir.path).toList();
    final match = await rg.search('hello', dir.path).first as RgMatch;
    dir.deleteSync(recursive: true);
    final hit = match.submatches.single;
    ok =
        files.length == 1 &&
        match.lineNumber == 2 &&
        match.text.substring(hit.start, hit.end) == 'hello';
    out =
        '${rg.executable}\n$files\n${match.path}:${match.lineNumber}: '
        '${match.text}';
  } catch (e) {
    out = 'ERROR: $e';
  }
  // Windows GUI apps have no reliable stdout, so the result also goes to a
  // file (inside the container when sandboxed on macOS).
  stdout.writeln(out);
  File(resultFile).writeAsStringSync(out);
  exit(ok ? 0 : 1);
}
