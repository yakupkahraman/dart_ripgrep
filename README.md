# dart_ripgrep

Fast file listing and search for Dart and Flutter desktop apps, powered by a
bundled [ripgrep](https://github.com/BurntSushi/ripgrep).

- **Bundled:** ripgrep ships inside your app. It never uses an `rg` from the
  user's system.
- **Pinned and verified:** ripgrep 15.2.0, checked against a SHA-256 hash at
  build time.
- **Lean:** only the binary for the target platform goes into your build.

## Platforms

| | x64 | arm64 |
|---|---|---|
| macOS | ✅ | ✅ |
| Linux | ✅ | ✅ |
| Windows | ✅ | ✅ |

## Getting started

```sh
dart pub add dart_ripgrep
```

Linux and Windows need no further setup.

**macOS:** run this once from your app's root:

```sh
dart run dart_ripgrep:setup
```

It adds a build phase to your Xcode project that bundles and code-signs
ripgrep with your app.

## Usage

```dart
import 'package:dart_ripgrep/dart_ripgrep.dart';

final rg = Ripgrep();

// List files, respecting .gitignore.
await for (final path in rg.files('/path/to/project')) {
  print(path);
}

// Search.
final results = rg.search(
  'TODO',
  '/path/to/project',
  options: const RgOptions(caseMode: RgCase.smart, include: ['*.dart']),
);
await for (final match in results.whereType<RgMatch>().take(100)) {
  for (final r in match.submatches) {
    print('${match.path}:${match.lineNumber} '
        '${match.text.substring(r.start, r.end)}');
  }
}
```

- `submatches` are indices into `text`, safe for highlighting non-ASCII lines.
- Cancelling a subscription (including via `.take(n)`) kills the ripgrep
  process, so a new query can simply replace the old one.
- With `RgOptions(context: n)`, `search` also emits `RgContext` lines.
- If ripgrep hits an error (such as an unreadable file), the results found so
  far are still delivered and the stream then ends with an `RgException`.

## License

ripgrep is dual-licensed under MIT and the Unlicense. Its license files are
shipped with your app.
