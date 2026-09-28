import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:dart_ripgrep/dart_ripgrep.dart';
import 'package:dart_ripgrep/src/release.dart';
import 'package:test/test.dart';

// Runs against the pinned release, fetched and verified like the bundled one.
Future<Ripgrep> _pinnedRipgrep() async {
  final arch = Abi.current().toString().split('_').last;
  final target = switch ((Platform.operatingSystem, arch)) {
    ('macos', 'arm64') => 'aarch64-apple-darwin.tar.gz',
    ('macos', 'x64') => 'x86_64-apple-darwin.tar.gz',
    ('linux', 'arm64') => 'aarch64-unknown-linux-gnu.tar.gz',
    ('linux', 'x64') => 'x86_64-unknown-linux-musl.tar.gz',
    ('windows', 'arm64') => 'aarch64-pc-windows-msvc.zip',
    ('windows', 'x64') => 'x86_64-pc-windows-msvc.zip',
    final host => throw UnsupportedError('No ripgrep for $host'),
  };
  final dir = Directory('.dart_tool/dart_ripgrep_test/$version-$target');
  await fetch(target, dir);
  final exe = Platform.isWindows ? 'rg.exe' : 'rg';
  return Ripgrep.at(File('${dir.path}/$exe').absolute.path);
}

void main() {
  late Ripgrep rg;
  late Directory root;
  String p(String relative) =>
      '${root.path}${Platform.pathSeparator}'
      '${relative.replaceAll('/', Platform.pathSeparator)}';

  setUpAll(() async => rg = await _pinnedRipgrep());

  setUp(() {
    root = Directory.systemTemp.createTempSync('dart_ripgrep_test');
    for (final (path, content) in [
      ('.git/HEAD', ''), // makes .gitignore apply
      ('.gitignore', 'ignored.txt\n'),
      ('ignored.txt', 'needle\n'),
      ('.hidden.txt', 'needle\n'),
      ('lib/a.dart', 'one\nNeedle needles needle\nthree\n'),
      ('lib/b.txt', 'a.b needle\n'),
    ]) {
      File(p(path))
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<List<String>> files([RgOptions? options]) async =>
      (await rg.files(root.path, options: options).toList())..sort();

  Future<List<String>> matchedFiles(String pattern, [RgOptions? o]) async {
    final lines = await rg.search(pattern, root.path, options: o).toList();
    return {for (final l in lines.whereType<RgMatch>()) l.path}.toList()
      ..sort();
  }

  test('files respects .gitignore and skips hidden files', () async {
    expect(await files(), [p('lib/a.dart'), p('lib/b.txt')]);
  });

  test('files includes hidden files and honors globs', () async {
    // --hidden also enters .git, as in ripgrep, so UIs exclude it explicitly.
    expect(
      await files(const RgOptions(hidden: true, exclude: ['*.dart', '.git'])),
      [p('.gitignore'), p('.hidden.txt'), p('lib/b.txt')],
    );
    expect(await files(const RgOptions(include: ['*.dart'])), [
      p('lib/a.dart'),
    ]);
  });

  test('search reports matches with ranges into the line', () async {
    final m = (await rg.search('need', root.path).toList())
        .cast<RgMatch>()
        .firstWhere((m) => m.path == p('lib/a.dart'));
    expect(m.lineNumber, 2);
    expect(m.text, 'Needle needles needle');
    expect(m.submatches, [(start: 7, end: 11), (start: 15, end: 19)]);
  });

  test('search options', () async {
    expect(
      await matchedFiles(
        'needle',
        const RgOptions(caseMode: RgCase.insensitive),
      ),
      [p('lib/a.dart'), p('lib/b.txt')],
    );
    expect(
      await matchedFiles('Needle', const RgOptions(caseMode: RgCase.smart)),
      [p('lib/a.dart')],
    );
    expect(await matchedFiles('a.b'), [p('lib/b.txt')]);
    expect(await matchedFiles('a.b', const RgOptions(fixedString: true)), [
      p('lib/b.txt'),
    ]);
    expect(await matchedFiles('a.d', const RgOptions(fixedString: true)), []);

    final word =
        await rg
                .search(
                  'needle',
                  root.path,
                  options: const RgOptions(
                    wholeWord: true,
                    include: ['*.dart'],
                  ),
                )
                .single
            as RgMatch;
    expect(word.submatches, [(start: 15, end: 21)]);
  });

  test('search emits context lines', () async {
    final lines = await rg
        .search('Needle', root.path, options: const RgOptions(context: 1))
        .toList();
    expect(lines.map((l) => '${l.runtimeType}:${l.lineNumber}'), [
      'RgContext:1',
      'RgMatch:2',
      'RgContext:3',
    ]);
  });

  test('no matches is an empty stream, not an error', () async {
    expect(await rg.search('absent', root.path).toList(), isEmpty);
  });

  test('errors surface as RgException', () async {
    expect(
      rg.search('x', p('missing')).toList(),
      throwsA(isA<RgException>().having((e) => e.exitCode, 'exitCode', 2)),
    );
    expect(rg.search('(', root.path).toList(), throwsA(isA<RgException>()));
  });

  test('an error still delivers the results found before it', () async {
    final unreadable = File(p('lib/secret.txt'))..writeAsStringSync('needle');
    Process.runSync('chmod', ['000', unreadable.path]);
    final results = <RgLine>[];
    Object? error;
    try {
      await for (final line in rg.search('needle', root.path)) {
        results.add(line);
      }
    } catch (e) {
      error = e;
    }
    expect(results, isNotEmpty);
    expect(error, isA<RgException>());
  }, testOn: '!windows');

  test('cancelling the subscription kills ripgrep', () async {
    // Pausing after the first result stops reading stdout, so once the pipe
    // fills ripgrep blocks on write and is still alive at cancel time.
    final big = List.filled(2000, 'cancelme ${'x' * 100}').join('\n');
    for (var i = 0; i < 200; i++) {
      File(p('big/$i.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync(big);
    }
    const pattern = 'cancelme_unique_4f2a|cancelme';
    final first = Completer<void>();
    late final StreamSubscription<RgLine> sub;
    sub = rg.search(pattern, root.path).listen((_) {
      if (first.isCompleted) return;
      sub.pause();
      first.complete();
    });
    await first.future;
    expect(await _isRunning(pattern), isTrue);
    await sub.cancel();

    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (await _isRunning(pattern) && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(await _isRunning(pattern), isFalse);
  });
}

Future<bool> _isRunning(String arg) async {
  if (Platform.isWindows) {
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      "(Get-CimInstance Win32_Process -Filter \"Name='rg.exe'\" | "
          "Where-Object { \$_.CommandLine -like '*cancelme_unique_4f2a*' }).Count",
    ]);
    return (int.tryParse('${r.stdout}'.trim()) ?? 0) > 0;
  }
  final r = await Process.run('pgrep', ['-f', arg.split('|').first]);
  return r.exitCode == 0;
}
