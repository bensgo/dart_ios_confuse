import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:path/path.dart' as p;

import '../../source_edit.dart';
import 'dart_capability_catalog.dart';
import 'dart_capability_planner.dart';

class DartCapabilityGenerator {
  DartCapabilityGenerator({
    required this.projectRoot,
    this.catalog = const DartCapabilityCatalog(),
  });

  final String projectRoot;
  final DartCapabilityCatalog catalog;

  Future<DartCapabilityGenerationReport> apply(CapabilityPlan plan) async {
    final editsByFile = <String, List<SourceEdit>>{};
    final results = <CapabilityGenerationResult>[];

    for (final entry in plan.readyEntries) {
      final template = catalog.lookup(entry.capability);
      if (template == null) {
        results.add(
          CapabilityGenerationResult(
            identity: entry.identity,
            status: CapabilityGenerationStatus.skipped,
            reason: 'template_not_supported',
          ),
        );
        continue;
      }
      final filePath = p.normalize(p.join(projectRoot, entry.library));
      final file = File(filePath);
      if (!file.existsSync()) {
        throw StateError('Capability source file is missing: ${entry.library}');
      }
      final source = await file.readAsString();
      final unit = parseString(content: source, path: filePath).unit;
      final classNode = unit.declarations
          .whereType<ClassDeclaration>()
          .where((node) => node.name.lexeme == entry.className)
          .firstOrNull;
      if (classNode == null) {
        throw StateError('Capability class is missing: ${entry.identity}');
      }
      final callMethod = classNode.members
          .whereType<MethodDeclaration>()
          .where((node) => node.name.lexeme == entry.callMethod)
          .firstOrNull;
      if (callMethod == null) {
        throw StateError(
          'Capability call method is missing: ${entry.identity}',
        );
      }
      final invocationVisitor = _InvocationVisitor(template.methodNames);
      callMethod.body.accept(invocationVisitor);
      if (!invocationVisitor.called) {
        throw StateError(
          'Refusing to generate ${entry.identity}: the production method '
          '${entry.callMethod} does not call a supported capability method.',
        );
      }
      final existing = classNode.members.whereType<MethodDeclaration>().any(
        (node) => template.methodNames.contains(node.name.lexeme),
      );
      if (existing) {
        results.add(
          CapabilityGenerationResult(
            identity: entry.identity,
            status: CapabilityGenerationStatus.existing,
            reason: 'definition_and_call_already_exist',
          ),
        );
        continue;
      }
      editsByFile
          .putIfAbsent(filePath, () => [])
          .add(
            SourceEdit(
              offset: classNode.rightBracket.offset,
              length: 0,
              replacement: '\n${template.generatedMethod}',
              reason: 'generate ${entry.capability} capability definition',
            ),
          );
      results.add(
        CapabilityGenerationResult(
          identity: entry.identity,
          status: CapabilityGenerationStatus.generated,
          reason: 'production_call_preexisted',
        ),
      );
    }

    for (final entry in editsByFile.entries) {
      final file = File(entry.key);
      final source = await file.readAsString();
      await file.writeAsString(applySourceEdits(source, entry.value));
    }
    return DartCapabilityGenerationReport(results: results);
  }
}

class _InvocationVisitor extends RecursiveAstVisitor<void> {
  _InvocationVisitor(this.methodNames);

  final List<String> methodNames;
  bool called = false;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (methodNames.contains(node.methodName.name)) called = true;
    super.visitMethodInvocation(node);
  }
}

enum CapabilityGenerationStatus { existing, generated, skipped }

class CapabilityGenerationResult {
  const CapabilityGenerationResult({
    required this.identity,
    required this.status,
    required this.reason,
  });

  final String identity;
  final CapabilityGenerationStatus status;
  final String reason;
}

class DartCapabilityGenerationReport {
  const DartCapabilityGenerationReport({required this.results});

  final List<CapabilityGenerationResult> results;

  int get generated => results
      .where((result) => result.status == CapabilityGenerationStatus.generated)
      .length;
  int get existing => results
      .where((result) => result.status == CapabilityGenerationStatus.existing)
      .length;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
