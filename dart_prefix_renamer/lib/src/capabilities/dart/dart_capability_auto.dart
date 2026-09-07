import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../config.dart';
import '../../source_edit.dart';
import 'dart_capability_catalog.dart';
import 'dart_class_classifier.dart';
import 'dart_class_scanner.dart';

class DartCapabilityAutoConfig {
  DartCapabilityAutoConfig({
    required String projectRoot,
    required List<String> targetPaths,
    required this.scanOnly,
    required this.percentage,
    required this.seed,
    required this.suggestionsOutput,
    required this.selectionOutput,
    this.selectionInput,
  }) : projectRoot = p.normalize(p.absolute(projectRoot)),
       targetPaths = targetPaths
           .map((path) => p.normalize(p.absolute(projectRoot, path)))
           .toList(growable: false) {
    if (!Directory(this.projectRoot).existsSync()) {
      throw UsageException(
        'Project directory does not exist: ${this.projectRoot}',
      );
    }
    if (this.targetPaths.isEmpty ||
        this.targetPaths.any(
          (path) =>
              !Directory(path).existsSync() ||
              (path != this.projectRoot && !p.isWithin(this.projectRoot, path)),
        )) {
      throw UsageException(
        'Dart targets must be existing project directories.',
      );
    }
    if (percentage < 0 || percentage > 100) {
      throw UsageException('--dart-differentiation-percent must be 0..100.');
    }
    _validateProjectRelative(
      suggestionsOutput,
      '--dart-capability-suggestions-out',
    );
    _validateProjectRelative(
      selectionOutput,
      '--dart-capability-selection-out',
    );
  }

  factory DartCapabilityAutoConfig.fromArguments(List<String> arguments) {
    final parser = ArgParser()
      ..addFlag('scan-dart-capabilities', negatable: false)
      ..addFlag('auto-dart-capabilities', negatable: false)
      ..addOption('project', abbr: 'p', mandatory: true)
      ..addOption('target', abbr: 't', mandatory: true)
      ..addOption('dart-differentiation-percent', defaultsTo: '0')
      ..addOption('dart-capability-seed', defaultsTo: '0')
      ..addOption(
        'dart-capability-suggestions-out',
        defaultsTo: 'reports/dart-capability-suggestions.json',
      )
      ..addOption(
        'dart-capability-selection-out',
        defaultsTo: 'reports/dart-capability-selection.json',
      )
      ..addOption('dart-capability-selection')
      ..addFlag('help', abbr: 'h', negatable: false);
    late final ArgResults results;
    try {
      results = parser.parse(arguments);
    } on FormatException catch (error) {
      throw UsageException('${error.message}\n\n${parser.usage}');
    }
    if (results.flag('help')) throw UsageException(parser.usage, exitCode: 0);
    final percentage = double.tryParse(
      results.option('dart-differentiation-percent')!,
    );
    final seed = int.tryParse(results.option('dart-capability-seed')!);
    if (percentage == null) {
      throw UsageException('--dart-differentiation-percent must be numeric.');
    }
    if (seed == null) {
      throw UsageException('--dart-capability-seed must be an integer.');
    }
    return DartCapabilityAutoConfig(
      projectRoot: results.option('project')!,
      targetPaths: results
          .option('target')!
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      scanOnly: results.flag('scan-dart-capabilities'),
      percentage: percentage,
      seed: seed,
      suggestionsOutput: results.option('dart-capability-suggestions-out')!,
      selectionOutput: results.option('dart-capability-selection-out')!,
      selectionInput: results.option('dart-capability-selection'),
    );
  }

  final String projectRoot;
  final List<String> targetPaths;
  final bool scanOnly;
  final double percentage;
  final int seed;
  final String suggestionsOutput;
  final String selectionOutput;
  final String? selectionInput;

  static void _validateProjectRelative(String value, String option) {
    final normalized = p.normalize(value);
    if (p.isAbsolute(normalized) ||
        normalized == '..' ||
        normalized.startsWith('../')) {
      throw UsageException('$option must be project-relative.');
    }
  }
}

class DartCapabilityAutoRunner {
  DartCapabilityAutoRunner(
    this.config, {
    this.classifier = const DartClassClassifier(),
    this.catalog = const DartCapabilityCatalog(),
    this.onProgress,
  });

  static const suggestionsByType = <String, List<String>>{
    'repository': [
      'cache_key',
      'cache_validation',
      'request_context',
      'response_normalizer',
    ],
    'service': ['input_validation', 'request_metadata', 'retry_context'],
    'controller': ['analytics_context', 'state_validation'],
    'model': ['debug_summary', 'input_validation', 'response_normalizer'],
    'widget': ['accessibility_context', 'presentation_metadata'],
    'utility': [],
    'manager': ['lifecycle_snapshot', 'operation_context'],
    'logic': ['decision_context', 'rule_validation'],
    'unclassified': [],
  };

  final DartCapabilityAutoConfig config;
  final DartClassClassifier classifier;
  final DartCapabilityCatalog catalog;
  final void Function(String message)? onProgress;

  Future<DartCapabilityAutoReport> run() async {
    final scan = await DartClassScanner(
      projectRoot: config.projectRoot,
      targetPaths: config.targetPaths,
      onProgress: (resolved, total) {
        onProgress?.call('  Analyzer files: $resolved/$total');
      },
    ).scan();
    final suggestions = await _buildSuggestions(scan);
    final suggestionsFile = await _writeJson(
      config.suggestionsOutput,
      suggestions.map((entry) => entry.toJson()).toList(),
    );
    if (config.scanOnly) {
      return DartCapabilityAutoReport(
        suggestionsFile: suggestionsFile.path,
        selectionFile: null,
        classesScanned: suggestions.length,
        candidates: suggestions.where((entry) => entry.candidate).length,
        selected: 0,
        inserted: 0,
      );
    }

    final selection = config.selectionInput == null
        ? _select(suggestions)
        : await _loadSelection(config.selectionInput!);
    _validateSelection(selection, suggestions);
    final selectionFile = await _writeJson(
      config.selectionOutput,
      selection.toJson(),
    );
    final inserted = await _apply(selection);
    return DartCapabilityAutoReport(
      suggestionsFile: suggestionsFile.path,
      selectionFile: selectionFile.path,
      classesScanned: suggestions.length,
      candidates: suggestions.where((entry) => entry.candidate).length,
      selected: selection.entries.length,
      inserted: inserted,
    );
  }

  Future<List<DartAutoSuggestion>> _buildSuggestions(ScanResult scan) async {
    final result = <DartAutoSuggestion>[];
    final classes = scan.classes.where((info) => !info.isGenerated).toList()
      ..sort((a, b) => _identity(a).compareTo(_identity(b)));
    for (final info in classes) {
      final classification = classifier.classify(info);
      final suggestions = [
        ...(suggestionsByType[classification.kind.name] ?? const <String>[]),
      ]..sort();
      final method = await _safeMethod(info);
      final reasons = <String>[
        if (!classification.canApply) 'classification_below_threshold',
        if (suggestions.isEmpty) 'no_capability_suggestions',
        if (method == null) 'no_safe_block_method',
      ];
      result.add(
        DartAutoSuggestion(
          className: info.name,
          library: _relative(info.filePath),
          classKind: classification.kind.name,
          suggestions: suggestions,
          candidate: reasons.isEmpty,
          method: method,
          ineligibleReasons: reasons,
        ),
      );
    }
    return result;
  }

  Future<String?> _safeMethod(ClassInfo info) async {
    final source = await File(info.filePath).readAsString();
    final unit = parseString(content: source, path: info.filePath).unit;
    final classNode = unit.declarations
        .whereType<ClassDeclaration>()
        .where((node) => node.name.lexeme == info.name)
        .firstOrNull;
    if (classNode == null) return null;
    final methods =
        classNode.members
            .whereType<MethodDeclaration>()
            .where(
              (node) =>
                  !node.isStatic &&
                  !node.isAbstract &&
                  !node.isGetter &&
                  !node.isSetter &&
                  node.body is BlockFunctionBody,
            )
            .toList()
          ..sort((a, b) => a.offset.compareTo(b.offset));
    return methods.isEmpty ? null : methods.first.name.lexeme;
  }

  DartCapabilitySelection _select(List<DartAutoSuggestion> suggestions) {
    final candidates = suggestions.where((entry) => entry.candidate).toList()
      ..sort((a, b) => _rank(a.identity).compareTo(_rank(b.identity)));
    final count = (candidates.length * config.percentage / 100).round();
    final selected = candidates.take(count).map((entry) {
      final capabilityIndex = _index(
        '${entry.identity}|capability',
        entry.suggestions.length,
      );
      final file = File(p.join(config.projectRoot, entry.library));
      return DartCapabilitySelectionEntry(
        className: entry.className,
        library: entry.library,
        classKind: entry.classKind,
        capability: entry.suggestions[capabilityIndex],
        method: entry.method!,
        sourceSha256: sha256.convert(file.readAsBytesSync()).toString(),
      );
    }).toList();
    return DartCapabilitySelection(
      schemaVersion: 1,
      seed: config.seed,
      percentage: config.percentage,
      candidateCount: candidates.length,
      entries: selected,
    );
  }

  Future<DartCapabilitySelection> _loadSelection(String path) async {
    final file = File(_inputPath(path));
    if (!file.existsSync()) {
      throw UsageException('Selection file does not exist: $path');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw UsageException('Selection JSON must be an object.');
    }
    return DartCapabilitySelection.fromJson(decoded);
  }

  void _validateSelection(
    DartCapabilitySelection selection,
    List<DartAutoSuggestion> suggestions,
  ) {
    final available = {for (final entry in suggestions) entry.identity: entry};
    final seen = <String>{};
    for (final entry in selection.entries) {
      final identity = '${entry.library}#${entry.className}';
      if (!seen.add(identity)) {
        throw StateError('Duplicate selected class: $identity');
      }
      final suggestion = available[identity];
      if (suggestion == null || !suggestion.candidate) {
        throw StateError('Selected class is no longer eligible: $identity');
      }
      if (entry.classKind != suggestion.classKind ||
          entry.method != suggestion.method ||
          !suggestion.suggestions.contains(entry.capability)) {
        throw StateError(
          'Selection no longer matches source analysis: $identity',
        );
      }
    }
  }

  Future<int> _apply(DartCapabilitySelection selection) async {
    final grouped = <String, List<DartCapabilitySelectionEntry>>{};
    for (final entry in selection.entries) {
      final path = p.normalize(p.join(config.projectRoot, entry.library));
      if (!p.isWithin(config.projectRoot, path)) {
        throw StateError('Selection path escapes project: ${entry.library}');
      }
      (grouped[path] ??= []).add(entry);
    }
    var inserted = 0;
    for (final group in grouped.entries) {
      final file = File(group.key);
      if (!file.existsSync()) {
        throw StateError('Selected source is missing: ${group.key}');
      }
      final bytes = await file.readAsBytes();
      final actualHash = sha256.convert(bytes).toString();
      for (final entry in group.value) {
        if (entry.sourceSha256 != actualHash) {
          throw StateError('Selected source changed: ${entry.library}');
        }
      }
      final source = utf8.decode(bytes);
      final unit = parseString(content: source, path: group.key).unit;
      final edits = <SourceEdit>[];
      for (final entry in group.value) {
        final template = catalog.lookup(entry.capability);
        if (template == null) {
          throw StateError('Unsupported capability: ${entry.capability}');
        }
        final classNode = unit.declarations
            .whereType<ClassDeclaration>()
            .where((node) => node.name.lexeme == entry.className)
            .firstOrNull;
        if (classNode == null) {
          throw StateError('Selected class is missing: ${entry.identity}');
        }
        final method = classNode.members
            .whereType<MethodDeclaration>()
            .where((node) => node.name.lexeme == entry.method)
            .firstOrNull;
        if (method == null || method.body is! BlockFunctionBody) {
          throw StateError(
            'Selected method is not a safe block body: ${entry.identity}',
          );
        }
        final body = method.body as BlockFunctionBody;
        final marker = '// dart-capability:${entry.capability}';
        if (!source.substring(body.offset, body.end).contains(marker)) {
          edits.add(
            SourceEdit(
              offset: body.block.leftBracket.end,
              length: 0,
              replacement: '\n    $marker\n    ${_call(entry.capability)};',
              reason: 'insert reachable ${entry.capability} capability call',
            ),
          );
        }
        final generatedMethodName = _generatedMethodName(entry.capability);
        final hasDefinition = classNode.members
            .whereType<MethodDeclaration>()
            .any((node) => node.name.lexeme == generatedMethodName);
        if (!hasDefinition) {
          edits.add(
            SourceEdit(
              offset: classNode.rightBracket.offset,
              length: 0,
              replacement: '\n${template.generatedMethod}',
              reason: 'generate ${entry.capability} capability definition',
            ),
          );
        }
        inserted++;
      }
      await file.writeAsString(applySourceEdits(source, edits));
    }
    return inserted;
  }

  String _call(String capability) => switch (capability) {
    'cache_key' => "buildCapabilityCacheKey('')",
    'cache_validation' => 'isCapabilityCacheValid(this)',
    'response_normalizer' => 'normalizeCapabilityResponse<Object?>(null)',
    'request_context' => 'buildCapabilityRequestContext()',
    'input_validation' => "validateCapabilityInput('')",
    'analytics_context' => 'buildCapabilityAnalyticsContext()',
    'state_validation' => 'validateCapabilityState(this)',
    'debug_summary' => 'buildCapabilityDebugSummary()',
    'request_metadata' => 'buildCapabilityRequestMetadata()',
    'retry_context' => "buildCapabilityRetryContext(0, StateError(''))",
    'operation_context' => "buildCapabilityOperationContext('')",
    'lifecycle_snapshot' => 'buildCapabilityLifecycleSnapshot()',
    'decision_context' => 'buildCapabilityDecisionContext(this)',
    'rule_validation' => 'validateCapabilityRule(this)',
    'presentation_metadata' => 'buildCapabilityPresentationMetadata()',
    'accessibility_context' => "buildCapabilityAccessibilityContext('')",
    _ => throw StateError('Unsupported capability call: $capability'),
  };

  String _generatedMethodName(String capability) => switch (capability) {
    'cache_key' => 'buildCapabilityCacheKey',
    'cache_validation' => 'isCapabilityCacheValid',
    'response_normalizer' => 'normalizeCapabilityResponse',
    'request_context' => 'buildCapabilityRequestContext',
    'input_validation' => 'validateCapabilityInput',
    'analytics_context' => 'buildCapabilityAnalyticsContext',
    'state_validation' => 'validateCapabilityState',
    'debug_summary' => 'buildCapabilityDebugSummary',
    'request_metadata' => 'buildCapabilityRequestMetadata',
    'retry_context' => 'buildCapabilityRetryContext',
    'operation_context' => 'buildCapabilityOperationContext',
    'lifecycle_snapshot' => 'buildCapabilityLifecycleSnapshot',
    'decision_context' => 'buildCapabilityDecisionContext',
    'rule_validation' => 'validateCapabilityRule',
    'presentation_metadata' => 'buildCapabilityPresentationMetadata',
    'accessibility_context' => 'buildCapabilityAccessibilityContext',
    _ => throw StateError('Unsupported capability method: $capability'),
  };

  String _rank(String identity) =>
      sha256.convert(utf8.encode('${config.seed}|$identity')).toString();
  int _index(String identity, int length) =>
      int.parse(_rank(identity).substring(0, 8), radix: 16) % length;
  String _identity(ClassInfo info) =>
      '${_relative(info.filePath)}#${info.name}';
  String _relative(String path) =>
      p.posix.joinAll(p.split(p.relative(path, from: config.projectRoot)));
  String _inputPath(String path) => p.isAbsolute(path)
      ? p.normalize(path)
      : p.normalize(p.join(config.projectRoot, path));

  Future<File> _writeJson(String relativePath, Object value) async {
    final file = File(p.join(config.projectRoot, relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(value)}\n',
    );
    return file;
  }
}

class DartAutoSuggestion {
  const DartAutoSuggestion({
    required this.className,
    required this.library,
    required this.classKind,
    required this.suggestions,
    required this.candidate,
    required this.method,
    required this.ineligibleReasons,
  });
  final String className;
  final String library;
  final String classKind;
  final List<String> suggestions;
  final bool candidate;
  final String? method;
  final List<String> ineligibleReasons;
  String get identity => '$library#$className';
  Map<String, dynamic> toJson() => {
    'class': className,
    'library': library,
    'type': classKind,
    'suggestions': suggestions,
    'candidate': candidate,
    'method': method,
    'ineligible_reasons': ineligibleReasons,
  };
}

class DartCapabilitySelection {
  const DartCapabilitySelection({
    required this.schemaVersion,
    required this.seed,
    required this.percentage,
    required this.candidateCount,
    required this.entries,
  });
  factory DartCapabilitySelection.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != 1 || json['entries'] is! List) {
      throw UsageException('Unsupported Dart capability selection schema.');
    }
    return DartCapabilitySelection(
      schemaVersion: 1,
      seed: json['seed'] as int,
      percentage: (json['percentage'] as num).toDouble(),
      candidateCount: json['candidate_count'] as int,
      entries: (json['entries'] as List<dynamic>)
          .map(
            (entry) => DartCapabilitySelectionEntry.fromJson(
              entry as Map<String, dynamic>,
            ),
          )
          .toList(growable: false),
    );
  }
  final int schemaVersion;
  final int seed;
  final double percentage;
  final int candidateCount;
  final List<DartCapabilitySelectionEntry> entries;
  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'seed': seed,
    'percentage': percentage,
    'candidate_count': candidateCount,
    'selected_count': entries.length,
    'entries': entries.map((entry) => entry.toJson()).toList(),
  };
}

class DartCapabilitySelectionEntry {
  const DartCapabilitySelectionEntry({
    required this.className,
    required this.library,
    required this.classKind,
    required this.capability,
    required this.method,
    required this.sourceSha256,
  });
  factory DartCapabilitySelectionEntry.fromJson(Map<String, dynamic> json) =>
      DartCapabilitySelectionEntry(
        className: json['class'] as String,
        library: json['library'] as String,
        classKind: json['type'] as String,
        capability: json['capability'] as String,
        method: json['method'] as String,
        sourceSha256: json['source_sha256'] as String,
      );
  final String className;
  final String library;
  final String classKind;
  final String capability;
  final String method;
  final String sourceSha256;
  String get identity => '$library#$className#$capability';
  Map<String, dynamic> toJson() => {
    'class': className,
    'library': library,
    'type': classKind,
    'capability': capability,
    'method': method,
    'source_sha256': sourceSha256,
  };
}

class DartCapabilityAutoReport {
  const DartCapabilityAutoReport({
    required this.suggestionsFile,
    required this.selectionFile,
    required this.classesScanned,
    required this.candidates,
    required this.selected,
    required this.inserted,
  });
  final String suggestionsFile;
  final String? selectionFile;
  final int classesScanned;
  final int candidates;
  final int selected;
  final int inserted;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
