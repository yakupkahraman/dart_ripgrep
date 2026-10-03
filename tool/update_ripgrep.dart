// Moves the pinned ripgrep to its latest release: verifies every archive we
// ship against the release's official .sha256 files, rewrites
// lib/src/release.dart and README.md, and adds a patch release to pubspec.yaml
// and CHANGELOG.md. Run from the package root; does nothing when up to date.
//
// Used by .github/workflows/update-ripgrep.yml.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main() async {
  final release = File('lib/src/release.dart');
  var source = release.readAsStringSync();
  final current = RegExp(
    r"const version = '([^']+)';",
  ).firstMatch(source)!.group(1)!;
  final latest = await _latestRelease();
  if (!_isNewer(latest, current)) {
    stdout.writeln('ripgrep $current is up to date.');
    return;
  }

  // The targets we ship are the keys of the hash table.
  final targets = RegExp(
    r"'([^']+\.(?:tar\.gz|zip))':",
  ).allMatches(source).map((m) => m.group(1)!);
  for (final target in targets) {
    final name = 'ripgrep-$latest-$target';
    final base =
        'https://github.com/BurntSushi/ripgrep/releases/download/'
        '$latest/$name';
    final actual = sha256.convert(await _get(base)).toString();
    // The .sha256 file is "<hash>  <file name>".
    final official = utf8.decode(await _get('$base.sha256')).split(' ').first;
    if (actual != official) {
      throw StateError('$name: SHA-256 $actual does not match $official');
    }
    source = source.replaceFirstMapped(
      RegExp("('${RegExp.escape(target)}':\\s*')[0-9a-f]{64}'"),
      (m) => "${m[1]}$actual'",
    );
    stdout.writeln('$name: $actual');
  }
  release.writeAsStringSync(
    source.replaceFirst("version = '$current'", "version = '$latest'"),
  );

  final readme = File('README.md');
  readme.writeAsStringSync(
    readme.readAsStringSync().replaceAll('ripgrep $current', 'ripgrep $latest'),
  );

  final pubspec = File('pubspec.yaml');
  final pubspecSource = pubspec.readAsStringSync();
  final package = RegExp(
    r'^version: (\d+)\.(\d+)\.(\d+)$',
    multiLine: true,
  ).firstMatch(pubspecSource)!;
  final next = '${package[1]}.${package[2]}.${int.parse(package[3]!) + 1}';
  pubspec.writeAsStringSync(
    pubspecSource.replaceFirst(package[0]!, 'version: $next'),
  );

  final changelog = File('CHANGELOG.md');
  changelog.writeAsStringSync(
    '## $next\n\n- Update ripgrep to $latest.\n\n'
    '${changelog.readAsStringSync()}',
  );

  stdout.writeln('Updated ripgrep $current -> $latest, package -> $next.');
  final output = Platform.environment['GITHUB_OUTPUT'];
  if (output != null) {
    File(output).writeAsStringSync(
      'ripgrep=$latest\npackage=$next\n',
      mode: FileMode.append,
    );
  }
}

// /releases/latest skips pre-releases and drafts.
Future<String> _latestRelease() async {
  final body = await _get(
    'https://api.github.com/repos/BurntSushi/ripgrep/releases/latest',
  );
  return (jsonDecode(utf8.decode(body)) as Map)['tag_name'] as String;
}

bool _isNewer(String a, String b) {
  final x = a.split('.').map(int.parse).toList();
  final y = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i] > y[i];
  }
  return false;
}

Future<List<int>> _get(String url) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set('User-Agent', 'dart_ripgrep-updater');
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    return [for (final chunk in await response.toList()) ...chunk];
  } finally {
    client.close();
  }
}
