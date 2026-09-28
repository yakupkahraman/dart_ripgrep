/// How the pattern treats letter case.
enum RgCase {
  /// Letter case must match.
  sensitive,

  /// Letter case is ignored.
  insensitive,

  /// Insensitive unless the pattern contains an uppercase letter.
  smart,
}

/// Search options. `.gitignore` and friends are respected, as in ripgrep.
class RgOptions {
  /// How letter case is matched. When null, ripgrep's default applies,
  /// which is [RgCase.sensitive].
  final RgCase? caseMode;

  /// Treat the pattern as a literal string instead of a regex.
  final bool fixedString;

  /// Only match whole words.
  final bool wholeWord;

  /// Globs a path must match, like `*.dart`.
  final List<String> include;

  /// Globs that exclude a path, like `build/**`.
  final List<String> exclude;

  /// Include hidden files and directories. Note that this includes `.git`;
  /// add it to [exclude] to skip it.
  final bool hidden;

  /// Lines of context before and after each match, emitted as [RgContext].
  final int context;

  /// Creates search options. The defaults match ripgrep's defaults.
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
  /// Path of the file, starting with the root passed to the search.
  final String path;

  /// 1-based line number.
  final int lineNumber;

  /// The line without its line terminator.
  final String text;

  /// Creates a line.
  const RgLine(this.path, this.lineNumber, this.text);
}

/// A line that matches the pattern.
final class RgMatch extends RgLine {
  /// Ranges of the matched parts, as indices into [text] (UTF-16, like any
  /// Dart string), so `text.substring(r.start, r.end)` is the matched part.
  final List<({int start, int end})> submatches;

  /// Creates a match.
  const RgMatch(super.path, super.lineNumber, super.text, this.submatches);
}

/// A line around a match, emitted when [RgOptions.context] is set.
final class RgContext extends RgLine {
  /// Creates a context line.
  const RgContext(super.path, super.lineNumber, super.text);
}

/// ripgrep exited with an error. Results emitted before it are still valid.
class RgException implements Exception {
  /// ripgrep's exit code, 2 for errors.
  final int exitCode;

  /// What ripgrep wrote to stderr.
  final String message;

  /// Creates an exception.
  const RgException(this.exitCode, this.message);

  @override
  String toString() => 'RgException($exitCode): $message';
}
