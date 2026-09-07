import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../model/capability_manifest.dart';
import '../model/product_profile.dart';
import 'dart_class_classifier.dart';
import 'dart_class_scanner.dart';

class DartCapabilityPlanner {
  DartCapabilityPlanner({
    required this.projectRoot,
    required this.profile,
    required this.manifest,
    this.seed = 0,
    this.classifier = const DartClassClassifier(),
  });

  final String projectRoot;
  final ProductProfile profile;
  final DartCapabilityManifest manifest;
  final int seed;
  final DartClassClassifier classifier;

  CapabilityPlan createPlan(ScanResult scan) {
    final classes = scan.classes.where((info) => !info.isGenerated).toList()
      ..sort((a, b) => _identity(a).compareTo(_identity(b)));
    final entries = <CapabilityPlanEntry>[];
    final suggestions = <CapabilitySuggestion>[];
    final classSuggestions = <ClassCapabilitySuggestion>[];

    for (final integration in manifest.integrations) {
      final info = _findClass(classes, integration);
      final classification = info == null ? null : classifier.classify(info);
      final method = info == null
          ? null
          : _methodNamed(info, integration.callSite.method);
      final rule = classification == null
          ? null
          : manifest.rules[classification.kind.name];
      final reasons = <String>[];
      if (info == null) reasons.add('class_not_found');
      if (info != null && info.isGenerated) reasons.add('generated_code');
      if (classification != null && !classification.canApply) {
        reasons.add('classification_below_threshold');
      }
      if (method == null) reasons.add('method_not_found');
      if (rule == null || !rule.allowed.contains(integration.capability)) {
        reasons.add('capability_not_allowed_for_class');
      }
      if (integration.callSite.anchor == 'dynamic' ||
          integration.callSite.anchor.startsWith('nonexistent') ||
          integration.callSite.anchor == 'never_called' ||
          integration.callSite.anchor == 'no_usage') {
        reasons.add('unsupported_call_anchor');
      }
      if (integration.effect == 'none') reasons.add('missing_business_effect');
      if (integration.expected == 'rejected') reasons.add('expected_rejection');

      entries.add(
        CapabilityPlanEntry(
          className: integration.className,
          library: integration.library,
          capability: integration.capability,
          classKind: classification?.kind.name ?? 'unclassified',
          classificationEvidence: classification?.evidence ?? const [],
          callMethod: integration.callSite.method,
          callAnchor: integration.callSite.anchor,
          effect: integration.effect,
          status: reasons.isEmpty
              ? PlanEntryStatus.ready
              : PlanEntryStatus.rejected,
          reasons: reasons,
        ),
      );
    }

    for (final info in classes) {
      final classification = classifier.classify(info);
      final rule = classification.canApply
          ? manifest.rules[classification.kind.name]
          : null;
      final capabilities = rule == null ? <String>[] : [...rule.allowed]
        ..sort();
      classSuggestions.add(
        ClassCapabilitySuggestion(
          className: info.name,
          library: _relative(info.filePath),
          classKind: classification.kind.name,
          capabilities: capabilities,
          candidate: _isCandidate(info, classification),
          ineligibleReasons: _ineligibleReasons(info, classification),
        ),
      );
      if (!classification.canApply) continue;
      final hasExplicit = manifest.integrations.any(
        (integration) =>
            integration.className == info.name &&
            _normalize(integration.library) == _relative(info.filePath),
      );
      if (hasExplicit) continue;
      if (rule == null || rule.allowed.isEmpty || rule.min == 0) continue;
      final allowed = [...rule.allowed]..sort();
      final count = rule.min.clamp(0, allowed.length);
      final start = _stableIndex(info, allowed.length);
      final selected = <String>[];
      for (var index = 0; index < count; index++) {
        selected.add(allowed[(start + index) % allowed.length]);
      }
      suggestions.add(
        CapabilitySuggestion(
          className: info.name,
          library: _relative(info.filePath),
          classKind: classification.kind.name,
          capabilities: selected,
          evidence: classification.evidence,
          reason: 'requires_explicit_integration_anchor',
        ),
      );
    }

    entries.sort((a, b) => a.identity.compareTo(b.identity));
    suggestions.sort((a, b) => a.identity.compareTo(b.identity));
    classSuggestions.sort((a, b) => a.identity.compareTo(b.identity));
    return CapabilityPlan(
      schemaVersion: 1,
      productId: profile.product.id,
      seed: seed,
      classesAnalyzed: classes.length,
      entries: entries,
      suggestions: suggestions,
      classSuggestions: classSuggestions,
    );
  }

  bool _isCandidate(ClassInfo info, ClassClassification classification) =>
      classification.canApply &&
      info.methods.any(
        (method) =>
            !method.isStatic &&
            !method.isAbstract &&
            !method.isGetter &&
            !method.isSetter &&
            method.bodyOffset != null &&
            method.bodyLength != null,
      );

  List<String> _ineligibleReasons(
    ClassInfo info,
    ClassClassification classification,
  ) {
    final reasons = <String>[];
    if (!classification.canApply) reasons.add('classification_below_threshold');
    if (!info.methods.any(
      (method) =>
          !method.isStatic &&
          !method.isAbstract &&
          !method.isGetter &&
          !method.isSetter &&
          method.bodyOffset != null &&
          method.bodyLength != null,
    )) {
      reasons.add('no_instance_method_body');
    }
    return reasons;
  }

  ClassInfo? _findClass(List<ClassInfo> classes, IntegrationSpec integration) {
    for (final info in classes) {
      if (info.name == integration.className &&
          _relative(info.filePath) == _normalize(integration.library)) {
        return info;
      }
    }
    return null;
  }

  MethodInfo? _methodNamed(ClassInfo info, String name) {
    for (final method in info.methods) {
      if (method.name == name) return method;
    }
    return null;
  }

  int _stableIndex(ClassInfo info, int length) {
    final input = [
      profile.toJsonString(),
      info.libraryUri,
      info.name,
      manifest.schemaVersion,
      seed,
    ].join('|');
    final bytes = sha256.convert(utf8.encode(input)).bytes;
    return ((bytes[0] << 8) | bytes[1]) % length;
  }

  String _identity(ClassInfo info) =>
      '${_relative(info.filePath)}#${info.name}';

  String _relative(String path) =>
      _normalize(p.relative(path, from: projectRoot));

  String _normalize(String path) => p.posix.joinAll(p.split(p.normalize(path)));
}

enum PlanEntryStatus { ready, rejected }

class CapabilityPlanEntry {
  const CapabilityPlanEntry({
    required this.className,
    required this.library,
    required this.capability,
    required this.classKind,
    required this.classificationEvidence,
    required this.callMethod,
    required this.callAnchor,
    required this.effect,
    required this.status,
    required this.reasons,
  });

  final String className;
  final String library;
  final String capability;
  final String classKind;
  final List<String> classificationEvidence;
  final String callMethod;
  final String callAnchor;
  final String effect;
  final PlanEntryStatus status;
  final List<String> reasons;

  String get identity => '$library#$className#$capability';

  Map<String, dynamic> toJson() => {
    'class': className,
    'library': library,
    'capability': capability,
    'class_kind': classKind,
    'classification_evidence': classificationEvidence,
    'call_site': {'method': callMethod, 'anchor': callAnchor},
    'effect': effect,
    'status': status.name,
    'reasons': reasons,
  };
}

class CapabilitySuggestion {
  const CapabilitySuggestion({
    required this.className,
    required this.library,
    required this.classKind,
    required this.capabilities,
    required this.evidence,
    required this.reason,
  });

  final String className;
  final String library;
  final String classKind;
  final List<String> capabilities;
  final List<String> evidence;
  final String reason;

  String get identity => '$library#$className';

  Map<String, dynamic> toJson() => {
    'class': className,
    'library': library,
    'class_kind': classKind,
    'capabilities': capabilities,
    'classification_evidence': evidence,
    'reason': reason,
  };
}

class CapabilityPlan {
  const CapabilityPlan({
    required this.schemaVersion,
    required this.productId,
    required this.seed,
    required this.classesAnalyzed,
    required this.entries,
    required this.suggestions,
    this.classSuggestions = const [],
  });

  final int schemaVersion;
  final String productId;
  final int seed;
  final int classesAnalyzed;
  final List<CapabilityPlanEntry> entries;
  final List<CapabilitySuggestion> suggestions;
  final List<ClassCapabilitySuggestion> classSuggestions;

  List<CapabilityPlanEntry> get readyEntries =>
      entries.where((entry) => entry.status == PlanEntryStatus.ready).toList();

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'product_id': productId,
    'seed': seed,
    'classes_analyzed': classesAnalyzed,
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'suggestions': suggestions.map((entry) => entry.toJson()).toList(),
    'classes': classSuggestions.map((entry) => entry.toJson()).toList(),
    'classification_summary': _classificationSummary(),
  };

  List<Map<String, dynamic>> _classificationSummary() {
    final groups = <String, List<ClassCapabilitySuggestion>>{};
    for (final entry in classSuggestions) {
      (groups[entry.classKind] ??= []).add(entry);
    }
    return groups.entries.map((entry) {
        final total = entry.value.length;
        final eligible = entry.value.where((value) => value.candidate).length;
        final reasons = <String, int>{};
        for (final item in entry.value.where((value) => !value.candidate)) {
          for (final reason in item.ineligibleReasons) {
            reasons[reason] = (reasons[reason] ?? 0) + 1;
          }
        }
        return {
          'type': entry.key,
          'total': total,
          'eligible': eligible,
          'ineligible': total - eligible,
          'eligible_ratio': total == 0 ? 0 : eligible / total,
          'ineligible_reasons': reasons,
        };
      }).toList()
      ..sort((a, b) => (a['type']! as String).compareTo(b['type']! as String));
  }

  String toJsonString() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';
}

class ClassCapabilitySuggestion {
  const ClassCapabilitySuggestion({
    required this.className,
    required this.library,
    required this.classKind,
    required this.capabilities,
    required this.candidate,
    required this.ineligibleReasons,
  });

  final String className;
  final String library;
  final String classKind;
  final List<String> capabilities;
  final bool candidate;
  final List<String> ineligibleReasons;

  String get identity => '$library#$className';

  Map<String, dynamic> toJson() => {
    'class': className,
    'library': library,
    'type': classKind,
    'suggestions': capabilities,
    'candidate': candidate,
    'ineligible_reasons': ineligibleReasons,
  };
}
