/// How the pattern treats letter case.
enum RgCase {
  sensitive,
  insensitive,

  /// Insensitive unless the pattern contains an uppercase letter.
  smart,
}

/// Search options. `.gitignore` and friends are respected, as in ripgrep.
class RgOptions {
  final RgCase? caseMode;

  /// Treat the pattern as a literal string instead of a regex.
  final bool fixedString;
  final bool wholeWord;

  /// Globs a path must match, like `*.dart`.
  final List<String> include;

  /// Globs that exclude a path, like `build/**`.
  final List<String> exclude;
  final bool hidden;

  /// Lines of context before and after each match, emitted as [RgContext].
  final int context;

  const RgOptions({
    this.caseMode,
    this.fixedString = false,
    this.wholeWord = false,
    this.include = const [],
    this.exclude = const [],
    this.hidden = false,
    this.context = 0,
  });
}

/// A line reported by [Ripgrep.search]: either a match or a context line.
sealed class RgLine {
  final String path;

  /// 1-based.
  final int lineNumber;

  /// The line without its line terminator.
  final String text;

  const RgLine(this.path, this.lineNumber, this.text);
}

final class RgMatch extends RgLine {
  /// Ranges of the matched parts, as indices into [text] (UTF-16, like any
  /// Dart string), so `text.substring(r.start, r.end)` is the matched part.
  final List<({int start, int end})> submatches;

  const RgMatch(super.path, super.lineNumber, super.text, this.submatches);
}

final class RgContext extends RgLine {
  const RgContext(super.path, super.lineNumber, super.text);
}

/// ripgrep exited with an error. Results emitted before it are still valid.
class RgException implements Exception {
  final int exitCode;
  final String message;

  const RgException(this.exitCode, this.message);

  @override
  String toString() => 'RgException($exitCode): $message';
}
