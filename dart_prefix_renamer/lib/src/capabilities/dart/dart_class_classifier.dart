import 'package:path/path.dart' as p;

import 'dart_class_scanner.dart';

enum DartClassKind {
  repository,
  service,
  controller,
  model,
  widget,
  utility,
  manager,
  logic,
  unclassified,
}

class ClassClassification {
  const ClassClassification({
    required this.kind,
    required this.confidence,
    required this.evidence,
  });

  final DartClassKind kind;
  final double confidence;
  final List<String> evidence;

  bool get canApply => kind != DartClassKind.unclassified && confidence >= 0.7;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'confidence': confidence,
    'evidence': evidence,
  };
}

class DartClassClassifier {
  const DartClassClassifier();

  static const _stablePriority = <DartClassKind>[
    DartClassKind.repository,
    DartClassKind.service,
    DartClassKind.controller,
    DartClassKind.model,
    DartClassKind.widget,
    DartClassKind.manager,
    DartClassKind.logic,
    DartClassKind.utility,
  ];

  ClassClassification classify(ClassInfo info) {
    final evidence = <String>[];
    final scores = <DartClassKind, double>{};

    void score(DartClassKind kind, double value, String reason) {
      if (value > (scores[kind] ?? 0)) scores[kind] = value;
      evidence.add(reason);
    }

    for (final annotation in info.annotations) {
      for (final kind in _kindsForText(annotation.name)) {
        score(kind, 1, 'annotation:${annotation.name}');
      }
    }

    final inherited = [
      if (info.superclass != null) info.superclass!,
      ...info.interfaces,
      ...info.mixins,
    ];
    for (final type in inherited) {
      final match = _kindForText(type);
      if (match != null) score(match, 0.9, 'inheritance:$type');
    }

    final pathParts = p.split(info.filePath.toLowerCase());
    for (final part in pathParts) {
      final match = _kindForText(part);
      if (match != null) score(match, 0.8, 'path:$part');
    }

    for (final kind in _kindsForText(info.name)) {
      score(kind, 0.75, 'name:${info.name}');
    }

    if (scores.isEmpty) {
      return const ClassClassification(
        kind: DartClassKind.unclassified,
        confidence: 0,
        evidence: ['no_supported_evidence'],
      );
    }
    final ordered = scores.entries.toList()
      ..sort((a, b) {
        final byScore = b.value.compareTo(a.value);
        if (byScore != 0) return byScore;
        return _stablePriority
            .indexOf(a.key)
            .compareTo(_stablePriority.indexOf(b.key));
      });
    return ClassClassification(
      kind: ordered.first.key,
      confidence: ordered.first.value,
      evidence: evidence,
    );
  }

  DartClassKind? _kindForText(String value) {
    final kinds = _kindsForText(value);
    return kinds.isEmpty ? null : kinds.first;
  }

  List<DartClassKind> _kindsForText(String value) {
    final tokens = _tokens(value);
    return _stablePriority
        .where((kind) {
          return switch (kind) {
            DartClassKind.utility =>
              tokens.contains('utility') ||
                  tokens.contains('util') ||
                  tokens.contains('helper'),
            _ => tokens.contains(kind.name),
          };
        })
        .toList(growable: false);
  }

  Set<String> _tokens(String value) {
    return value
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((token) => token.isNotEmpty)
        .map((token) => token.toLowerCase())
        .toSet();
  }
}
