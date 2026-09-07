final class SourceEdit {
  const SourceEdit({
    required this.offset,
    required this.length,
    required this.replacement,
    required this.reason,
  });

  final int offset;
  final int length;
  final String replacement;
  final String reason;

  String get identity => '$offset:$length:$replacement';
}

String applySourceEdits(String source, Iterable<SourceEdit> sourceEdits) {
  final unique = <String, SourceEdit>{};
  for (final edit in sourceEdits) {
    unique[edit.identity] = edit;
  }
  final edits = unique.values.toList()
    ..sort((left, right) {
      final byOffset = right.offset.compareTo(left.offset);
      return byOffset != 0 ? byOffset : right.length.compareTo(left.length);
    });

  var lastStart = source.length;
  var result = source;
  for (final edit in edits) {
    final end = edit.offset + edit.length;
    if (edit.offset < 0 || end > source.length) {
      throw StateError('Invalid ${edit.reason} edit at ${edit.offset}..$end.');
    }
    if (end > lastStart) {
      throw StateError(
        'Overlapping source edits near offset ${edit.offset}: ${edit.reason}.',
      );
    }
    result = result.replaceRange(edit.offset, end, edit.replacement);
    lastStart = edit.offset;
  }
  return result;
}
