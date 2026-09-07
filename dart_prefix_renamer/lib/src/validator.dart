import 'dart:io';

final class AnalyzerSnapshot {
  AnalyzerSnapshot(this.errors);

  final List<String> errors;

  Map<String, int> get errorCounts {
    final counts = <String, int>{};
    for (final error in errors) {
      counts.update(error, (count) => count + 1, ifAbsent: () => 1);
    }
    return counts;
  }
}

Future<AnalyzerSnapshot> captureAnalyzerErrors(String projectPath) async {
  final result = await Process.run(
    'fvm',
    const ['dart', 'analyze', '--format', 'machine'],
    workingDirectory: projectPath,
    runInShell: true,
  );
  final lines = '${result.stdout}\n${result.stderr}'.split('\n');
  final errors = <String>[];
  for (final line in lines) {
    if (!line.startsWith('ERROR|')) {
      continue;
    }
    final fields = line.split('|');
    if (fields.length >= 8) {
      errors.add('${fields[2]}|${fields.sublist(7).join('|')}');
    } else {
      errors.add(line);
    }
  }
  return AnalyzerSnapshot(errors);
}

List<String> findNewErrors(
  AnalyzerSnapshot baseline,
  AnalyzerSnapshot finalSnapshot,
) {
  final remainingBaseline = Map<String, int>.from(baseline.errorCounts);
  final added = <String>[];
  for (final error in finalSnapshot.errors) {
    final available = remainingBaseline[error] ?? 0;
    if (available > 0) {
      remainingBaseline[error] = available - 1;
    } else {
      added.add(error);
    }
  }
  return added;
}
