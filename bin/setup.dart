// Adds the "Embed ripgrep" Run Script phase to the app's macOS Runner target.
// Run once from the app root: dart run dart_ripgrep:setup
import 'dart:io';

const _marker = 'dart_ripgrep:embed_macos';
// Any id unique within the project works; a fixed one keeps setup idempotent.
const _id = 'D1A7B16E2E9A000000000001';

void main() {
  final project = File('macos/Runner.xcodeproj/project.pbxproj');
  if (!project.existsSync()) {
    stderr.writeln(
      'No ${project.path}; run this from the root of a Flutter app with macOS enabled.',
    );
    exitCode = 1;
    return;
  }
  var source = project.readAsStringSync();
  if (source.contains(_marker)) {
    stdout.writeln('The Embed ripgrep phase is already set up.');
    return;
  }

  // The app target is the one whose product is an application.
  final target = RegExp(
    r'buildPhases = \(\n((?:\t+\w+ /\* [^*]+ \*/,\n)*)(\t+)\);'
    r'(?:(?!isa = PBXNativeTarget)[\s\S])*?'
    r'productType = "com\.apple\.product-type\.application";',
  ).firstMatch(source);
  if (target == null) {
    stderr.writeln('Could not find the app target in ${project.path}.');
    exitCode = 1;
    return;
  }
  final indent = '${target.group(2)}\t';
  final insertAt =
      target.start + 'buildPhases = (\n'.length + target.group(1)!.length;
  source = source.replaceRange(
    insertAt,
    insertAt,
    '$indent$_id /* Embed ripgrep */,\n',
  );

  const section = '/* Begin PBXShellScriptBuildPhase section */\n';
  source = source.replaceFirst(
    section,
    '''$section\t\t$_id /* Embed ripgrep */ = {
\t\t\tisa = PBXShellScriptBuildPhase;
\t\t\talwaysOutOfDate = 1;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\tinputPaths = (
\t\t\t);
\t\t\tname = "Embed ripgrep";
\t\t\toutputPaths = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t\tshellPath = /bin/sh;
\t\t\tshellScript = "cd \\"\$SRCROOT/..\\" && \\"\$FLUTTER_ROOT/bin/dart\\" run $_marker\\n";
\t\t};
''',
  );
  project.writeAsStringSync(source);
  stdout.writeln('Added the Embed ripgrep phase to ${project.path}.');
}
