import 'dart:io';

import 'release.dart';

/// Runs the ripgrep binary bundled with the app.
class Ripgrep {
  /// Path of the bundled binary. Never falls back to an `rg` on PATH.
  final String executable;

  Ripgrep() : executable = _locate();

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
