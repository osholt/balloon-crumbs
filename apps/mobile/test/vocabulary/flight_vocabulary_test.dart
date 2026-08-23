import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production copy does not expose inherited motorcycle vocabulary', () {
    final lib = Directory('lib');
    final violations = <String>[];
    for (final file
        in lib
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      for (final literal in _dartStrings(file.readAsStringSync())) {
        if (!_forbidden.hasMatch(literal.value)) continue;
        if (_isDocumentedTechnicalLiteral(literal.value)) continue;
        violations.add(
          '${file.path}:${literal.line}: ${literal.value.replaceAll('\n', r'\n')}',
        );
      }
    }

    if (violations.isNotEmpty) {
      fail(
        'Use flight, crew member, pilot, balloon or chase vehicle in '
        'production-facing copy. Lower-case protocol fields, route paths and '
        'widget keys remain as documented compatibility identifiers.\n\n'
        '${violations.join('\n')}',
      );
    }
  });
}

final _forbidden = RegExp(
  r'\b(?:ride|rider|leader|bike|motorcycle)s?\b',
  caseSensitive: false,
);

final _technicalIdentifier = RegExp(r'^[a-z0-9_./:@?&=${}%-]+$');

bool _isDocumentedTechnicalLiteral(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return true;
  final withoutInterpolation = trimmed
      .replaceAll(r'${…}', 'value')
      .replaceAll(r'$…', 'value');
  if (_technicalIdentifier.hasMatch(withoutInterpolation)) return true;
  if (trimmed.startsWith('RideJoinPayload(')) return true;
  if (trimmed == 'Ride:') return true;
  if (trimmed.startsWith('tail-end-charlie-rider-v1')) return true;
  // Diagnostic palette names are developer-facing assertions, not copy.
  if (const {
    'own rider',
    'rider green',
    'rider orange',
    'rider yellow',
    'rider teal',
    'rider pink',
    'rider cyan',
    'rider amber',
    'rider crimson',
    'alerting rider',
    'leader trail',
  }.contains(trimmed.toLowerCase())) {
    return true;
  }
  return false;
}

class _DartString {
  const _DartString(this.value, this.line);

  final String value;
  final int line;
}

/// Extracts Dart string literals while skipping comments.
///
/// This deliberately small lexer is sufficient for the production sources and
/// catches adjacent/multiline copy that a line-based grep misses. Interpolation
/// is retained because its surrounding words are still user-visible copy.
Iterable<_DartString> _dartStrings(String source) sync* {
  var index = 0;
  var line = 1;
  while (index < source.length) {
    if (source.startsWith('//', index)) {
      final end = source.indexOf('\n', index + 2);
      if (end == -1) return;
      index = end;
      continue;
    }
    if (source.startsWith('/*', index)) {
      final end = source.indexOf('*/', index + 2);
      if (end == -1) return;
      line += '\n'.allMatches(source.substring(index, end + 2)).length;
      index = end + 2;
      continue;
    }

    final character = source[index];
    if (character == '\n') {
      line += 1;
      index += 1;
      continue;
    }
    if (character != "'" && character != '"') {
      index += 1;
      continue;
    }

    final startedAtLine = line;
    final quote = character;
    final triple = source.startsWith(quote * 3, index);
    final delimiter = triple ? quote * 3 : quote;
    final raw = index > 0 && source[index - 1] == 'r';
    index += delimiter.length;
    final value = StringBuffer();
    while (index < source.length) {
      if (source.startsWith(delimiter, index)) {
        index += delimiter.length;
        break;
      }
      final current = source[index];
      if (!raw && current == r'\' && index + 1 < source.length) {
        value
          ..write(current)
          ..write(source[index + 1]);
        index += 2;
        continue;
      }
      if (!raw && current == r'$' && index + 1 < source.length) {
        final next = source[index + 1];
        if (next == '{') {
          final skipped = _skipInterpolation(source, index + 2, line);
          index = skipped.index;
          line = skipped.line;
          value.write(r'${…}');
          continue;
        }
        if (RegExp(r'[A-Za-z_]').hasMatch(next)) {
          index += 2;
          while (index < source.length &&
              RegExp(r'[A-Za-z0-9_]').hasMatch(source[index])) {
            index += 1;
          }
          value.write(r'$…');
          continue;
        }
      }
      if (current == '\n') line += 1;
      value.write(current);
      index += 1;
    }
    yield _DartString(value.toString(), startedAtLine);
  }
}

({int index, int line}) _skipInterpolation(String source, int index, int line) {
  var depth = 1;
  while (index < source.length && depth > 0) {
    if (source.startsWith('//', index)) {
      final end = source.indexOf('\n', index + 2);
      if (end == -1) return (index: source.length, line: line);
      index = end;
      continue;
    }
    if (source.startsWith('/*', index)) {
      final end = source.indexOf('*/', index + 2);
      if (end == -1) return (index: source.length, line: line);
      line += '\n'.allMatches(source.substring(index, end + 2)).length;
      index = end + 2;
      continue;
    }
    final current = source[index];
    if (current == "'" || current == '"') {
      final delimiter = source.startsWith(current * 3, index)
          ? current * 3
          : current;
      index += delimiter.length;
      while (index < source.length && !source.startsWith(delimiter, index)) {
        if (source[index] == r'\' && index + 1 < source.length) {
          index += 2;
          continue;
        }
        if (source[index] == '\n') line += 1;
        index += 1;
      }
      index += delimiter.length;
      continue;
    }
    if (current == '{') depth += 1;
    if (current == '}') depth -= 1;
    if (current == '\n') line += 1;
    index += 1;
  }
  return (index: index, line: line);
}
