import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../model/capability_manifest.dart';
import '../model/ios_library_pool.dart';

class DependencyPlanner {
  const DependencyPlanner({
    required this.productId,
    required this.seed,
    required this.manifest,
    required this.libraryPool,
  });

  final String productId;
  final int seed;
  final DependencyManifest manifest;
  final IosLibraryPool libraryPool;

  DependencySelectionPlan createPlan() {
    final selection = manifest.selection;
    if (selection == null || !selection.enabled) {
      return DependencySelectionPlan(
        productId: productId,
        seed: seed,
        requestedCount: 0,
        selected: const [],
        decisions: const [],
        resolvedManifest: manifest,
      );
    }
    if (manifest.schemaVersion != 2) {
      throw const FormatException(
        'E021: dependency selection requires schema_version 2',
      );
    }
    if (manifest.dependencies.isNotEmpty) {
      throw const FormatException(
        'E021: random selection cannot be mixed with explicit dependencies',
      );
    }
    if (selection.mode != 'deterministic_random' ||
        selection.count < 1 ||
        selection.count > 10 ||
        selection.execution != 'startup_background_once') {
      throw const FormatException(
        'E021: selection requires deterministic_random, count 1-10, and '
        'startup_background_once',
      );
    }
    if (selection.candidates.toSet().length != selection.candidates.length) {
      throw const FormatException('E022: duplicate dependency candidates');
    }

    final ranked = <_RankedCandidate>[];
    for (final requestedId in selection.candidates) {
      final entry = libraryPool.findEntry(requestedId);
      if (entry == null) {
        throw FormatException(
          'E022: unknown dependency candidate $requestedId',
        );
      }
      final candidate = entry.value;
      if (candidate.status != 'approved' ||
          candidate.packageManager != 'cocoapods' ||
          candidate.podName == null ||
          candidate.moduleName == null ||
          candidate.probeTemplate == null ||
          candidate.binaryTokens.isEmpty ||
          ((candidate.sourceGit == null) != (candidate.sourceTag == null))) {
        throw FormatException(
          'E022: dependency candidate ${entry.key} is not generation-ready',
        );
      }
      ranked.add(
        _RankedCandidate(
          id: entry.key,
          candidate: candidate,
          score: sha256
              .convert(utf8.encode('$productId|$seed|${entry.key}'))
              .toString(),
        ),
      );
    }
    ranked.sort((a, b) {
      final score = a.score.compareTo(b.score);
      return score != 0 ? score : a.id.compareTo(b.id);
    });

    final selected = <SelectedDependency>[];
    final decisions = <DependencySelectionDecision>[];
    final groups = <String>{};
    for (final rankedCandidate in ranked) {
      final group = rankedCandidate.candidate.conflictGroup;
      final conflict = group != null && groups.contains(group);
      final choose = !conflict && selected.length < selection.count;
      if (choose) {
        selected.add(
          SelectedDependency(
            id: rankedCandidate.id,
            candidate: rankedCandidate.candidate,
            score: rankedCandidate.score,
          ),
        );
        if (group != null) groups.add(group);
      }
      decisions.add(
        DependencySelectionDecision(
          id: rankedCandidate.id,
          score: rankedCandidate.score,
          selected: choose,
          reason: choose
              ? 'selected'
              : conflict
              ? 'conflict_group:$group'
              : 'selection_limit',
        ),
      );
    }
    if (selected.length != selection.count) {
      throw FormatException(
        'E023: only ${selected.length} eligible dependencies remain after conflicts; '
        '${selection.count} required',
      );
    }

    final podName = dependencyPodName(productId);
    final dependencies = <String, DependencySpec>{
      for (final item in selected)
        item.candidate.podName!: DependencySpec(
          version: item.candidate.selectedVersion,
          manager: 'cocoapods',
          capability: item.candidate.capability,
          reason: item.candidate.reason,
          productionCall:
              'ios/LocalPods/$podName/Sources/${probeClassName(item.id)}.swift',
        ),
    };
    return DependencySelectionPlan(
      productId: productId,
      seed: seed,
      requestedCount: selection.count,
      selected: selected,
      decisions: decisions,
      resolvedManifest: DependencyManifest(
        schemaVersion: 2,
        dependencies: dependencies,
        selection: selection,
      ),
    );
  }
}

class DependencySelectionPlan {
  const DependencySelectionPlan({
    required this.productId,
    required this.seed,
    required this.requestedCount,
    required this.selected,
    required this.decisions,
    required this.resolvedManifest,
  });

  final String productId;
  final int seed;
  final int requestedCount;
  final List<SelectedDependency> selected;
  final List<DependencySelectionDecision> decisions;
  final DependencyManifest resolvedManifest;

  bool get enabled => requestedCount > 0;

  Map<String, dynamic> toJson() => {
    'schema_version': 1,
    'product_id': productId,
    'seed': seed,
    'requested_count': requestedCount,
    'selected_count': selected.length,
    'selected': selected.map((item) => item.toJson()).toList(),
    'decisions': decisions.map((item) => item.toJson()).toList(),
  };
}

class SelectedDependency {
  const SelectedDependency({
    required this.id,
    required this.candidate,
    required this.score,
  });

  final String id;
  final IosLibraryCandidate candidate;
  final String score;

  Map<String, dynamic> toJson() => {
    'id': id,
    'score': score,
    'pod_name': candidate.podName,
    'module_name': candidate.moduleName,
    'version': candidate.selectedVersion,
    'capability': candidate.capability,
    'probe_template': candidate.probeTemplate,
    'binary_tokens': candidate.binaryTokens,
    if (candidate.conflictGroup != null)
      'conflict_group': candidate.conflictGroup,
    if (candidate.sourceGit != null) 'source_git': candidate.sourceGit,
    if (candidate.sourceTag != null) 'source_tag': candidate.sourceTag,
  };
}

class DependencySelectionDecision {
  const DependencySelectionDecision({
    required this.id,
    required this.score,
    required this.selected,
    required this.reason,
  });

  final String id;
  final String score;
  final bool selected;
  final String reason;

  Map<String, dynamic> toJson() => {
    'id': id,
    'score': score,
    'selected': selected,
    'reason': reason,
  };
}

String dependencyPodName(String productId) =>
    '${_pascalCase(productId)}ThirdPartyKit';

String probeClassName(String id) => '${_pascalCase(id)}Probe';

String _pascalCase(String value) => value
    .split(RegExp('[^A-Za-z0-9]+'))
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join();

class _RankedCandidate {
  const _RankedCandidate({
    required this.id,
    required this.candidate,
    required this.score,
  });

  final String id;
  final IosLibraryCandidate candidate;
  final String score;
}
