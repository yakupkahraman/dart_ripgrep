// Run from an Xcode "Run Script" build phase of the app target. It copies a
// verified rg into Contents/Helpers and signs it with the app's identity, so
// the app's own signature seals it and notarization passes.
import 'dart:io';

import 'package:dart_ripgrep/src/release.dart';

Future<void> main() async {
  final env = Platform.environment;
  String need(String key) =>
      env[key] ?? (throw StateError('$key not set; run this from Xcode.'));

  final cache = Directory('${need('PROJECT_TEMP_DIR')}/dart_ripgrep-$version');
  final slices = <String>[];
  for (final arch in need('ARCHS').split(' ')) {
    final target = switch (arch) {
      'arm64' => 'aarch64-apple-darwin.tar.gz',
      'x86_64' => 'x86_64-apple-darwin.tar.gz',
      _ => throw UnsupportedError('No ripgrep for $arch'),
    };
    final dir = Directory('${cache.path}/$arch');
    await fetch(target, dir);
    slices.add('${dir.path}/rg');
  }

  final contents =
      '${need('TARGET_BUILD_DIR')}/${need('CONTENTS_FOLDER_PATH')}';
  final rg = '$contents/Helpers/rg';
  Directory('$contents/Helpers').createSync(recursive: true);
  // Release builds are universal, so the slices are merged into one binary.
  await _run('lipo', ['-create', ...slices, '-output', rg]);

  final licenses = Directory('$contents/Resources/ripgrep')
    ..createSync(recursive: true);
  for (final name in ['LICENSE-MIT', 'UNLICENSE', 'COPYING']) {
    File('${cache.path}/${need('ARCHS').split(' ').first}/$name')
        .copySync('${licenses.path}/$name');
  }

  if (env['CODE_SIGNING_ALLOWED'] == 'NO') return;
  final identity = env['EXPANDED_CODE_SIGN_IDENTITY'];
  final args = [
    '--force',
    '--sign',
    (identity == null || identity.isEmpty) ? '-' : identity,
    if (env['ENABLE_HARDENED_RUNTIME'] == 'YES') ...['--options', 'runtime'],
    if (env['CONFIGURATION'] == 'Release' && identity != '-') '--timestamp',
  ];
  // A helper of a sandboxed app must inherit the sandbox or it is killed.
  final entitlements = env['CODE_SIGN_ENTITLEMENTS'];
  if (entitlements != null &&
      File('${env['SRCROOT']}/$entitlements')
          .readAsStringSync()
          .contains('com.apple.security.app-sandbox')) {
    final plist = File('${cache.path}/inherit.entitlements')
      ..writeAsStringSync(_inheritPlist);
    args.addAll(['--entitlements', plist.path]);
  }
  await _run('codesign', [...args, rg]);
}

Future<void> _run(String cmd, List<String> args) async {
  final result = await Process.run(cmd, args);
  if (result.exitCode != 0) {
    throw ProcessException(cmd, args, '${result.stderr}', result.exitCode);
  }
}

const _inheritPlist = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.inherit</key>
  <true/>
</dict>
</plist>
''';
