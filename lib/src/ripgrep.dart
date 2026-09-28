import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'json.dart';
import 'release.dart';
import 'types.dart';

/// Runs the ripgrep binary bundled with the app.
class Ripgrep {
  /// Path of the bundled binary. Never falls back to an `rg` on PATH.
  final String executable;

  /// Locates the ripgrep bundled with the app.
  ///
  /// Throws a [StateError] if it isn't there, for example when the macOS
  /// setup step (`dart run dart_ripgrep:setup`) hasn't been run.
  Ripgrep() : executable = _locate();

  /// Runs the ripgrep at [executable] instead of the bundled one.
  @visibleForTesting
  Ripgrep.at(this.executable);

  /// Lists the files ripgrep would search under [root].
  ///
  /// Cancelling the subscription kills the process. Limit results with
  /// `.take(n)`, which cancels too.
  Stream<String> files(String root, {RgOptions? options}) async* {
    final rg = await _start([
      '--files',
      '--null',
      ..._filters(options),
      '--',
      root,
    ]);
    try {
      // NUL-separated because paths may contain newlines.
      var pending = <int>[];
      await for (final chunk in rg.process.stdout) {
        var start = 0;
        for (var i = 0; i < chunk.length; i++) {
          if (chunk[i] != 0) continue;
          pending.addAll(chunk.sublist(start, i));
          yield utf8.decode(pending, allowMalformed: true);
          pending = [];
          start = i + 1;
        }
        pending.addAll(chunk.sublist(start));
      }
      await _checkExit(rg);
    } finally {
      rg.process.kill();
    }
  }

  /// Searches the files under [root] for [pattern].
  ///
  /// Emits [RgMatch]es, plus [RgContext] lines when [RgOptions.context] is
  /// set. Cancelling the subscription kills the process, so a new query can
  /// simply supersede the old one. If ripgrep reports an error (for example
  /// an unreadable file), the results found so far are still emitted and the
  /// stream then ends with an [RgException].
  Stream<RgLine> search(
    String pattern,
    String root, {
    RgOptions? options,
  }) async* {
    final o = options ?? const RgOptions();
    final rg = await _start([
      '--json',
      ...switch (o.caseMode) {
        RgCase.sensitive => ['--case-sensitive'],
        RgCase.insensitive => ['--ignore-case'],
        RgCase.smart => ['--smart-case'],
        null => [],
      },
      if (o.fixedString) '--fixed-strings',
      if (o.wholeWord) '--word-regexp',
      if (o.context > 0) '--context=${o.context}',
      ..._filters(o),
      '--regexp=$pattern',
      '--',
      root,
    ]);
    try {
      final lines = rg.process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        final parsed = parseJsonLine(line);
        if (parsed != null) yield parsed;
      }
      await _checkExit(rg);
    } finally {
      rg.process.kill();
    }
  }

  List<String> _filters(RgOptions? o) => [
    if (o != null) ...[
      for (final glob in o.include) '--glob=$glob',
      for (final glob in o.exclude) '--glob=!$glob',
      if (o.hidden) '--hidden',
    ],
  ];

  Future<({Process process, Future<String> stderr})> _start(
    List<String> args,
  ) async {
    // --no-config: a user's RIPGREP_CONFIG_PATH must not change results.
    final process = await Process.start(executable, ['--no-config', ...args]);
    // Drained concurrently so a full stderr pipe can't block ripgrep.
    return (
      process: process,
      stderr: process.stderr.transform(utf8.decoder).join(),
    );
  }

  // 0 means results, 1 means none; 2 is an error, possibly after results.
  Future<void> _checkExit(({Process process, Future<String> stderr}) rg) async {
    final code = await rg.process.exitCode;
    if (code > 1) throw RgException(code, (await rg.stderr).trim());
  }

  static String _locate() {
    final dir = File(Platform.resolvedExecutable).parent.path;
    // Flutter bundles put the app next to lib/; `dart build cli` puts it in bin/.
    final candidates = switch (Platform.operatingSystem) {
      'macos' => ['$dir/../Helpers/rg'],
      'linux' => ['$dir/lib/rg', '$dir/../lib/rg'],
      'windows' => ['$dir\\rg.exe', '$dir\\..\\lib\\rg.exe'],
      final os => throw UnsupportedError('ripgrep is not bundled on $os'),
    };
    final file = candidates
        .map(File.new)
        .where((f) => f.existsSync())
        .firstOrNull;
    if (file == null) {
      throw StateError(
        'Bundled ripgrep not found at ${candidates.join(' or ')}',
      );
    }
    if (Platform.isLinux && file.statSync().mode & 0x49 == 0) {
      return _executableCopy(file);
    }
    return file.absolute.path;
  }

  // Flutter's Linux CMake template installs native assets without their
  // executable bit, and the bundle may be read-only, so run a private copy.
  static String _executableCopy(File bundled) {
    final cache =
        Platform.environment['XDG_CACHE_HOME'] ??
        '${Platform.environment['HOME']}/.cache';
    final copy = File('$cache/dart_ripgrep/$version/rg');
    if (!copy.existsSync() || copy.lengthSync() != bundled.lengthSync()) {
      copy.parent.createSync(recursive: true);
      final tmp = bundled.copySync('${copy.path}.$pid');
      Process.runSync('chmod', ['+x', tmp.path]);
      tmp.renameSync(copy.path);
    }
    return copy.path;
  }
}
