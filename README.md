# dart_ripgrep

Fast file listing and search for Dart and Flutter desktop apps, powered by a
bundled [ripgrep](https://github.com/BurntSushi/ripgrep).

- **Bundled:** ripgrep ships inside your app. It never uses an `rg` from the
  user's system.
- **Pinned and verified:** ripgrep 15.2.0, checked against a SHA-256 hash at
  build time.
- **Lean:** only the binary for the target platform goes into your build.

> **Work in progress:** the search API isn't implemented yet.

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
print(rg.executable); // path to the bundled binary
```

## License

ripgrep is dual-licensed under MIT and the Unlicense. Its license files are
shipped with your app.
