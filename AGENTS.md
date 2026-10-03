# AGENTS.md

`dart_ripgrep` ships a pinned ripgrep binary inside Dart and Flutter desktop
apps and exposes file listing and content search as typed Dart streams.

## Rules

- Never use an `rg` from the user's system or PATH. The binary always ships
  with the app.
- ripgrep's version and per-target SHA-256 hashes live only in
  `lib/src/release.dart`. Don't bump them by hand: the daily
  `update-ripgrep.yml` workflow runs `tool/update_ripgrep.dart` and opens a PR.
- Only the target platform's binary goes into a build.
- The package stays pure Dart (no Flutter plugin).
- Write the fewest lines that solve the problem, with no speculative options.
- Code, comments and docs are in English. Comments explain why, not what.
- Use conventional commits. Don't commit or push; the maintainer does.
- Out of scope: search-and-replace, indexing or caching, file watching, UI.

## API notes

- There is no `maxResults` option: ripgrep's `--max-count` is per file, and
  `.take(n)` on the stream gives a global limit while also killing the process.
- Context lines need their own type, so `search` returns `Stream<RgLine>`:
  a sealed class that is either `RgMatch` or `RgContext`.
- ripgrep reports UTF-8 byte offsets. `json.dart` converts them to UTF-16
  indices so ranges work directly on Dart strings.
- `files()` uses `--null`, because paths can contain newlines.
- Every run passes `--no-config`, so a user's `RIPGREP_CONFIG_PATH` can't
  change results.
- Tests run against the pinned release, fetched with the same SHA-256 check
  (`Ripgrep.at`, which is `@visibleForTesting`).

## Architecture

How the ripgrep binary gets into the app, and why.

The package is pure Dart (no Flutter plugin). How `rg` gets into the app:

| Platform | Mechanism | App developer does |
|---|---|---|
| Linux, Windows | `hook/build.dart` (build hooks) | nothing |
| macOS | Xcode Run Script phase running `bin/embed_macos.dart` | `dart run dart_ripgrep:setup` once |

### Build hooks: work on Linux and Windows, not on Flutter macOS

Tested with Flutter 3.47.1 / Dart 3.13.1, `hooks` 2.2.0, `code_assets` 2.1.0.

- `hook/build.dart` downloads the pinned archive, verifies its SHA-256 and
  extracts `rg`. This part works.
- `code_assets` has no link mode for executables, so `rg` has to be declared as
  a `DynamicLoadingBundled` library. The asset validator accepts it because it
  only checks the CPU architecture.
- `flutter build macos` then crashes in `getInstallNamesDylib`
  (`flutter_tools/.../macos/native_assets_host.dart`). Flutter reads the
  library's install name with `otool -D` so it can wrap it in a `.framework`,
  and an executable has no install name.
- Finding the file at runtime through `dart:ffi` also fails, because macOS
  refuses to `dlopen` an executable.

Build hooks can't ship an executable into a Flutter macOS app without
patching Flutter, so on macOS the hook does nothing.

On Linux and Windows, Flutter just copies code assets into the bundle, so the
hook works there. Verified in CI with Flutter release builds:

- Windows: `rg.exe` lands next to the app's `.exe` and runs.
- Linux: `rg` lands in `bundle/lib/`, but Flutter's CMake template installs it
  with `install(DIRECTORY)`, which drops the executable bit (`-rw-r--r--`).
  At runtime `Ripgrep` then runs a private executable copy from
  `$XDG_CACHE_HOME/dart_ripgrep/<version>/`, which works.
- `dart build cli --target-os=linux` puts `rg` in `bundle/lib/` with its
  executable bit intact.

Pure Dart CLIs on macOS get no `rg` for now.

### CocoaPods plugin: rejected

Flutter 3.47 uses Swift Package Manager for plugins by default, and SwiftPM
has no build phases that can download or copy files into the app bundle. A
podspec `script_phase` would force every user back onto CocoaPods. Shipping a
prebuilt binary inside the package was also rejected: pub.dev downloads should
stay small.

### macOS: an Xcode Run Script phase in the app (chosen)

The app's Runner target gets one extra build phase:

```sh
cd "$SRCROOT/.." && "$FLUTTER_ROOT/bin/dart" run dart_ripgrep:embed_macos
```

`bin/embed_macos.dart` downloads and verifies the archive for each arch in
`ARCHS` (cached in `PROJECT_TEMP_DIR`), merges the slices with `lipo`, copies
the result to `Contents/Helpers/rg` together with the license files, and signs
it with the app's identity. If the app is sandboxed, it also adds the
`app-sandbox` and `inherit` entitlements. Xcode signs the app after all build
phases run, so the app's signature seals `rg`. This works the same with
SwiftPM and CocoaPods.

Verified in `example/` (sandboxed, ad-hoc signed):

- Debug: `rg` is arm64 only, runs from the app and reads files in the bundle.
- Release: `rg` is universal (x86_64 + arm64) and
  `codesign --verify --deep --strict` passes.

The app adds the phase once, from its root:

```sh
dart run dart_ripgrep:setup
```

This was tested on a freshly created Flutter app: setup, then a release build,
then launching the app. Running setup twice leaves the project unchanged.

The same pattern is used in production by FlClash, which ships its Go core as
an executable in `Contents/MacOS` via a Run Script and Copy Files phase.

Not verified yet: notarization with a real Developer ID.

### Windows note

The official `rg.exe` binaries have no Authenticode signature. Windows Smart
App Control may block unsigned executables, so apps that sign their own `.exe`
should sign `rg.exe` too.
