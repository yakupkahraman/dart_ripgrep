import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

// Upgrading ripgrep means changing only this block.
const version = '16.0.0';
const _sha256 = {
  'aarch64-apple-darwin.tar.gz':
      '5a145656d5067144001bfce6648767fd3254599aa736f1ffdb7fb907760b8ca1',
  'x86_64-apple-darwin.tar.gz':
      'aa9183b0e0bfac03c5818895ad18b75001c402d230063898abfe5a58cd413caa',
  'aarch64-unknown-linux-gnu.tar.gz':
      '0b0bddcfaf42be1f3c56bf929d70defd1a2d96f2577aecbd7029a3734ddb4740',
  'x86_64-unknown-linux-musl.tar.gz':
      '54268ab4643c00a290a29b0086066d64b3f56236dd805ec64629a86f9bd29fd0',
  'aarch64-pc-windows-msvc.zip':
      '3302ede09745d33ca2b287bf3c6434c54cb35c3b408a7d3a265939961add5a1a',
  'x86_64-pc-windows-msvc.zip':
      'f418ae83e63046a94a7b5f3a44bf3a169f66e689164856ecee02547131c73931',
};

/// Downloads the archive for [target] (a key of the hash table), verifies it
/// and extracts the binary and license files into [dir], once.
Future<void> fetch(String target, Directory dir) async {
  final exe = target.endsWith('.zip') ? 'rg.exe' : 'rg';
  if (File('${dir.path}/$exe').existsSync()) return;

  final url = Uri.parse(
    'https://github.com/BurntSushi/ripgrep/releases/download/'
    '$version/ripgrep-$version-$target',
  );
  final client = HttpClient();
  final List<int> bytes;
  try {
    final response = await (await client.getUrl(url)).close();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    bytes = [for (final chunk in await response.toList()) ...chunk];
  } finally {
    client.close();
  }
  final actual = sha256.convert(bytes).toString();
  if (actual != _sha256[target]) {
    throw StateError('SHA-256 mismatch for $url: $actual');
  }

  final archive = target.endsWith('.zip')
      ? ZipDecoder().decodeBytes(bytes)
      : TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
  // Written to a temp dir and renamed so an interrupted fetch is never reused.
  final tmp = Directory('${dir.path}.tmp')..createSync(recursive: true);
  for (final entry in archive.files) {
    final name = entry.name.split('/').last;
    if (name == exe ||
        const {'LICENSE-MIT', 'UNLICENSE', 'COPYING'}.contains(name)) {
      File('${tmp.path}/$name').writeAsBytesSync(entry.content);
    }
  }
  if (exe == 'rg') await Process.run('chmod', ['+x', '${tmp.path}/rg']);
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  tmp.renameSync(dir.path);
}
