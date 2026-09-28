import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

// Upgrading ripgrep means changing only this block.
const version = '15.2.0';
const _sha256 = {
  'aarch64-apple-darwin.tar.gz':
      '3750b2e93f37e0c692657da574d7019a101c0084da05a790c83fd335bad973e4',
  'x86_64-apple-darwin.tar.gz':
      'af7825fcc69a2afc7a7aea55fc9af90e26421d8f20fe59df32e233c0b8a231c1',
  'aarch64-unknown-linux-gnu.tar.gz':
      'a740b91c82eaf9914cfedd353572f2791cbe0162c84101ee0951058f4dcbc90d',
  'x86_64-unknown-linux-musl.tar.gz':
      '33e15bcf1624b25cdd2a55813a47a2f95dbe126268203e76aa6a585d1e7b149c',
  'aarch64-pc-windows-msvc.zip':
      'e4abca10c3a64ebea742667dd7009449d49403db5460dd6873e389fa2945360f',
  'x86_64-pc-windows-msvc.zip':
      '71b2fef860abe467217a538ff31de02f5258807c0129f771846f87bd029aafc5',
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
