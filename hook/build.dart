import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:dart_ripgrep/src/release.dart';
import 'package:hooks/hooks.dart';

// Delivers rg on Linux and Windows. On macOS Flutter wraps every code asset in
// a framework, which fails for an executable, so there `bin/embed_macos.dart`
// runs from an Xcode build phase instead.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    final target = switch ((code.targetOS, code.targetArchitecture)) {
      (OS.linux, Architecture.arm64) => 'aarch64-unknown-linux-gnu.tar.gz',
      (OS.linux, Architecture.x64) => 'x86_64-unknown-linux-musl.tar.gz',
      (OS.windows, Architecture.arm64) => 'aarch64-pc-windows-msvc.zip',
      (OS.windows, Architecture.x64) => 'x86_64-pc-windows-msvc.zip',
      _ => null,
    };
    if (target == null) return;

    final dir = Directory.fromUri(
      input.outputDirectoryShared.resolve('ripgrep-$version-$target'),
    );
    await fetch(target, dir);
    final exe = code.targetOS == OS.windows ? 'rg.exe' : 'rg';
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'rg',
        linkMode: DynamicLoadingBundled(),
        file: File('${dir.path}/$exe').uri,
      ),
    );
  });
}
