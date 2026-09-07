import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import '../model/capability_report.dart';
import 'dart_capability_catalog.dart';
import 'dart_capability_planner.dart';

class DartCapabilityValidator {
  DartCapabilityValidator({
    required this.projectRoot,
    this.catalog = const DartCapabilityCatalog(),
  });

  final String projectRoot;
  final DartCapabilityCatalog catalog;

  Future<DartCapabilityReport> validate(CapabilityPlan plan) async {
    final integrations = <IntegrationReport>[];
    var reachable = 0;
    var failed = 0;
    for (final entry in plan.readyEntries) {
      final template = catalog.lookup(entry.capability);
      if (template == null) continue;
      final path = p.normalize(p.join(projectRoot, entry.library));
      final source = await File(path).readAsString();
      final unit = parseString(content: source, path: path).unit;
      final classNode = unit.declarations
          .whereType<ClassDeclaration>()
          .where((node) => node.name.lexeme == entry.className)
          .firstOrNull;
      final defined =
          classNode?.members.whereType<MethodDeclaration>().any(
            (node) => template.methodNames.contains(node.name.lexeme),
          ) ??
          false;
      final callMethod = classNode?.members
          .whereType<MethodDeclaration>()
          .where((node) => node.name.lexeme == entry.callMethod)
          .firstOrNull;
      final visitor = _EffectVisitor(template.methodNames);
      callMethod?.body.accept(visitor);
      final passed = defined && visitor.calls > 0 && visitor.effectVerified;
      if (passed) {
        reachable++;
      } else {
        failed++;
      }
      integrations.add(
        IntegrationReport(
          className: entry.className,
          library: entry.library,
          capability: entry.capability,
          callSite: '${entry.callMethod}:${entry.callAnchor}',
          effect: entry.effect,
          defined: defined,
          productionCallCount: visitor.calls,
          effectVerified: visitor.effectVerified,
          failureCode: passed ? null : 'DART_CAPABILITY_UNREACHABLE',
        ),
      );
    }
    return DartCapabilityReport(
      classesAnalyzed: plan.classesAnalyzed,
      capabilitiesPlanned: plan.readyEntries.length,
      capabilitiesApplied: integrations.where((item) => item.defined).length,
      capabilitiesReachable: reachable,
      capabilitiesFailed: failed,
      integrations: integrations,
    );
  }
}

class _EffectVisitor extends RecursiveAstVisitor<void> {
  _EffectVisitor(this.methodNames);

  final List<String> methodNames;
  int calls = 0;
  bool effectVerified = false;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (methodNames.contains(node.methodName.name)) {
      calls++;
      AstNode? current = node.parent;
      while (current != null && current is! Statement) {
        if (current is ReturnStatement ||
            current is VariableDeclaration ||
            current is AssignmentExpression ||
            current is ArgumentList ||
            current is IfStatement) {
          effectVerified = true;
          break;
        }
        current = current.parent;
      }
      if (current is ReturnStatement || current is IfStatement) {
        effectVerified = true;
      }
    }
    super.visitMethodInvocation(node);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
