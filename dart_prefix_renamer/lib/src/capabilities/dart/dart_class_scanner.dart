import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:path/path.dart' as p;

import '../../project_layout.dart';

class DartClassScanner {
  DartClassScanner({
    required this.projectRoot,
    required this.targetPaths,
    this.projectLayout,
    this.packageConfigPath,
    this.onProgress,
  });

  final String projectRoot;
  final List<String> targetPaths;
  final ProjectLayout? projectLayout;
  final String? packageConfigPath;
  final void Function(int resolved, int total)? onProgress;

  Future<ScanResult> scan() async {
    // Restrict Analyzer discovery to the requested targets. Using projectRoot
    // here makes a small capability scan traverse every Pub Workspace member
    // before the visitor can discard out-of-scope declarations.
    final collection = AnalysisContextCollection(includedPaths: targetPaths);

    final sourcePaths = <String>{};
    for (final context in collection.contexts) {
      for (final path in context.contextRoot.analyzedFiles()) {
        if (!path.endsWith('.dart') || !_isProjectSource(path)) {
          continue;
        }
        sourcePaths.add(path);
      }
    }
    final orderedPaths = sourcePaths.toList()..sort();
    onProgress?.call(0, orderedPaths.length);

    final units = <ResolvedUnitResult>[];
    var resolved = 0;
    for (final context in collection.contexts) {
      for (final path in orderedPaths.where(
        (path) => context.contextRoot.isAnalyzed(path),
      )) {
        final result = await context.currentSession.getResolvedUnit(path);
        if (result is ResolvedUnitResult) {
          units.add(result);
        }
        resolved++;
        if (resolved == orderedPaths.length || resolved % 100 == 0) {
          onProgress?.call(resolved, orderedPaths.length);
        }
      }
    }

    final classInfos = <ClassInfo>[];
    final classRefsByElement = <String, List<ClassReference>>{};

    for (final unit in units) {
      final visitor = _ClassVisitor(
        unit: unit,
        projectRoot: projectRoot,
        targetPaths: targetPaths,
        projectLayout: projectLayout,
        classRefsByElement: classRefsByElement,
      );
      unit.unit.accept(visitor);
      classInfos.addAll(visitor.classInfos);
    }

    return ScanResult(
      classes: classInfos,
      classReferences: classRefsByElement,
      projectRoot: projectRoot,
    );
  }

  bool _isProjectSource(String path) {
    if (path != projectRoot && !p.isWithin(projectRoot, path)) {
      return false;
    }
    final relativeParts = p.split(p.relative(path, from: projectRoot));
    return !relativeParts.any(
      const {'.dart_tool', '.git', 'build', 'Pods', 'junk_code'}.contains,
    );
  }
}

class ScanResult {
  ScanResult({
    required this.classes,
    required this.classReferences,
    required this.projectRoot,
  });

  final List<ClassInfo> classes;
  final Map<String, List<ClassReference>> classReferences;
  final String projectRoot;
}

class ClassInfo {
  ClassInfo({
    required this.element,
    required this.name,
    required this.libraryUri,
    required this.libraryName,
    required this.filePath,
    required this.offset,
    required this.length,
    required this.superclass,
    required this.interfaces,
    required this.mixins,
    required this.annotations,
    required this.fields,
    required this.methods,
    required this.constructors,
    required this.isAbstract,
    required this.isPrivate,
    required this.isGenerated,
    required this.partOfUri,
    required this.enclosingClass,
    required this.typeParameters,
    required this.implementedInterfaces,
  });

  final ClassElement element;
  final String name;
  final String libraryUri;
  final String libraryName;
  final String filePath;
  final int offset;
  final int length;
  final String? superclass;
  final List<String> interfaces;
  final List<String> mixins;
  final List<AnnotationInfo> annotations;
  final List<FieldInfo> fields;
  final List<MethodInfo> methods;
  final List<ConstructorInfo> constructors;
  final bool isAbstract;
  final bool isPrivate;
  final bool isGenerated;
  final String? partOfUri;
  final String? enclosingClass;
  final List<String> typeParameters;
  final List<String> implementedInterfaces;

  Map<String, dynamic> toJson() => {
    'name': name,
    'library_uri': libraryUri,
    'library_name': libraryName,
    'file_path': filePath,
    'offset': offset,
    'length': length,
    'superclass': superclass,
    'interfaces': interfaces,
    'mixins': mixins,
    'annotations': annotations.map((a) => a.toJson()).toList(),
    'fields': fields.map((f) => f.toJson()).toList(),
    'methods': methods.map((m) => m.toJson()).toList(),
    'constructors': constructors.map((c) => c.toJson()).toList(),
    'is_abstract': isAbstract,
    'is_private': isPrivate,
    'is_generated': isGenerated,
    'part_of_uri': partOfUri,
    'enclosing_class': enclosingClass,
    'type_parameters': typeParameters,
    'implemented_interfaces': implementedInterfaces,
  };
}

class AnnotationInfo {
  AnnotationInfo({
    required this.name,
    required this.arguments,
    required this.offset,
  });

  final String name;
  final Map<String, dynamic> arguments;
  final int offset;

  Map<String, dynamic> toJson() => {
    'name': name,
    'arguments': arguments,
    'offset': offset,
  };
}

class FieldInfo {
  FieldInfo({
    required this.name,
    required this.type,
    required this.isStatic,
    required this.isFinal,
    required this.isPrivate,
    required this.initializer,
    required this.annotations,
  });

  final String name;
  final String? type;
  final bool isStatic;
  final bool isFinal;
  final bool isPrivate;
  final String? initializer;
  final List<String> annotations;

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'is_static': isStatic,
    'is_final': isFinal,
    'is_private': isPrivate,
    'initializer': initializer,
    'annotations': annotations,
  };
}

class MethodInfo {
  MethodInfo({
    required this.name,
    required this.returnType,
    required this.parameters,
    required this.isStatic,
    required this.isAbstract,
    required this.isPrivate,
    required this.bodyOffset,
    required this.bodyLength,
    required this.annotations,
    required this.isGetter,
    required this.isSetter,
  });

  final String name;
  final String? returnType;
  final List<ParameterInfo> parameters;
  final bool isStatic;
  final bool isAbstract;
  final bool isPrivate;
  final int? bodyOffset;
  final int? bodyLength;
  final List<String> annotations;
  final bool isGetter;
  final bool isSetter;

  Map<String, dynamic> toJson() => {
    'name': name,
    'return_type': returnType,
    'parameters': parameters.map((p) => p.toJson()).toList(),
    'is_static': isStatic,
    'is_abstract': isAbstract,
    'is_private': isPrivate,
    'body_offset': bodyOffset,
    'body_length': bodyLength,
    'annotations': annotations,
    'is_getter': isGetter,
    'is_setter': isSetter,
  };
}

class ConstructorInfo {
  ConstructorInfo({
    required this.name,
    required this.parameters,
    required this.initializers,
    required this.annotations,
    required this.isFactory,
    required this.isConst,
  });

  final String name;
  final List<ParameterInfo> parameters;
  final List<String> initializers;
  final List<String> annotations;
  final bool isFactory;
  final bool isConst;

  Map<String, dynamic> toJson() => {
    'name': name,
    'parameters': parameters.map((p) => p.toJson()).toList(),
    'initializers': initializers,
    'annotations': annotations,
    'is_factory': isFactory,
    'is_const': isConst,
  };
}

class ParameterInfo {
  ParameterInfo({
    required this.name,
    required this.type,
    required this.isNamed,
    required this.isOptional,
    required this.defaultValue,
  });

  final String name;
  final String? type;
  final bool isNamed;
  final bool isOptional;
  final String? defaultValue;

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'is_named': isNamed,
    'is_optional': isOptional,
    'default_value': defaultValue,
  };
}

class ClassReference {
  ClassReference({
    required this.referencingClass,
    required this.referencingClassElement,
    required this.referencingFile,
    required this.offset,
    required this.context,
    required this.referenceType,
  });

  final String referencingClass;
  final String referencingClassElement;
  final String referencingFile;
  final int offset;
  final String context;
  final ReferenceType referenceType;

  Map<String, dynamic> toJson() => {
    'referencing_class': referencingClass,
    'referencing_class_element': referencingClassElement,
    'referencing_file': referencingFile,
    'offset': offset,
    'context': context,
    'reference_type': referenceType.name,
  };
}

enum ReferenceType {
  instantiation,
  typeAnnotation,
  methodCall,
  fieldAccess,
  superclass,
  interface,
  mixin,
  annotation,
}

class _ClassVisitor extends RecursiveAstVisitor<void> {
  _ClassVisitor({
    required this.unit,
    required this.projectRoot,
    required this.targetPaths,
    required this.projectLayout,
    required this.classRefsByElement,
  });

  final ResolvedUnitResult unit;
  final String projectRoot;
  final List<String> targetPaths;
  final ProjectLayout? projectLayout;
  final Map<String, List<ClassReference>> classRefsByElement;

  final List<ClassInfo> classInfos = [];

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final element = node.declaredFragment?.element;
    if (element == null) {
      super.visitClassDeclaration(node);
      return;
    }

    final isInTarget = _isInTargets(unit.path);
    if (!isInTarget) {
      super.visitClassDeclaration(node);
      return;
    }

    final libraryUri = element.firstFragment.libraryFragment.source.uri
        .toString();
    final libraryName = element.library.name ?? '';
    final superclass = element.supertype?.getDisplayString();
    final interfaces = element.interfaces
        .map((type) => type.getDisplayString())
        .toList(growable: false);
    final mixins = element.mixins
        .map((type) => type.getDisplayString())
        .toList(growable: false);
    final typeParameters = element.typeParameters
        .map((t) => t.displayName)
        .toList(growable: false);

    final annotations = <AnnotationInfo>[];
    for (final annotation in node.metadata) {
      final annElement = annotation.element;
      annotations.add(
        AnnotationInfo(
          name: annElement?.displayName ?? annotation.name.name,
          arguments: _extractAnnotationArguments(annotation),
          offset: annotation.offset,
        ),
      );
    }

    final fields = <FieldInfo>[];
    for (final field in node.members.whereType<FieldDeclaration>()) {
      for (final variable in field.fields.variables) {
        fields.add(
          FieldInfo(
            name: variable.name.lexeme,
            type: field.fields.type?.toSource(),
            isStatic: field.isStatic,
            isFinal: variable.isFinal || variable.isConst,
            isPrivate: variable.name.lexeme.startsWith('_'),
            initializer: variable.initializer?.toSource(),
            annotations: field.metadata.map((a) => a.name.name).toList(),
          ),
        );
      }
    }

    final methods = <MethodInfo>[];
    for (final method in node.members.whereType<MethodDeclaration>()) {
      methods.add(
        MethodInfo(
          name: method.name.lexeme,
          returnType: method.returnType?.toSource(),
          parameters:
              method.parameters?.parameters
                  .map(_parameterInfo)
                  .toList(growable: false) ??
              const [],
          isStatic: method.isStatic,
          isAbstract: method.isAbstract,
          isPrivate: method.name.lexeme.startsWith('_'),
          bodyOffset: method.body.offset,
          bodyLength: method.body.length,
          annotations: method.metadata.map((a) => a.name.name).toList(),
          isGetter: method.isGetter,
          isSetter: method.isSetter,
        ),
      );
    }

    final constructors = <ConstructorInfo>[];
    for (final ctor in node.members.whereType<ConstructorDeclaration>()) {
      constructors.add(
        ConstructorInfo(
          name: ctor.name?.lexeme ?? '',
          parameters: ctor.parameters.parameters
              .map(_parameterInfo)
              .toList(growable: false),
          initializers: ctor.initializers.map((i) => i.toSource()).toList(),
          annotations: ctor.metadata.map((a) => a.name.name).toList(),
          isFactory: ctor.factoryKeyword != null,
          isConst: ctor.constKeyword != null,
        ),
      );
    }

    final isGenerated = _isGeneratedCode(unit.path);
    final partOfUri = _getPartOfUri(node);

    classInfos.add(
      ClassInfo(
        element: element,
        name: node.name.lexeme,
        libraryUri: libraryUri,
        libraryName: libraryName,
        filePath: unit.path,
        offset: node.name.offset,
        length: node.name.length,
        superclass: superclass,
        interfaces: interfaces,
        mixins: mixins,
        annotations: annotations,
        fields: fields,
        methods: methods,
        constructors: constructors,
        isAbstract: node.abstractKeyword != null,
        isPrivate: node.name.lexeme.startsWith('_'),
        isGenerated: isGenerated,
        partOfUri: partOfUri,
        enclosingClass: _getEnclosingClass(node),
        typeParameters: typeParameters,
        implementedInterfaces: interfaces,
      ),
    );

    // Visit references
    final refVisitor = _ReferenceVisitor(
      currentClass: node.name.lexeme,
      currentClassElement: _elementKey(element),
      currentFile: unit.path,
      classRefsByElement: classRefsByElement,
    );
    node.accept(refVisitor);

    super.visitClassDeclaration(node);
  }

  bool _isInTargets(String path) {
    return targetPaths.any(
      (target) => path == target || p.isWithin(target, path),
    );
  }

  bool _isGeneratedCode(String path) {
    final fileName = p.basename(path);
    if (fileName.endsWith('.g.dart') || fileName.endsWith('.freezed.dart')) {
      return true;
    }
    // Check for generated file comment
    try {
      final lines = File(path).readAsLinesSync();
      for (final line in lines.take(5)) {
        if (line.contains('GENERATED') || line.contains('generated')) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  String? _getPartOfUri(ClassDeclaration node) {
    final root = node.root;
    if (root is! CompilationUnit) return null;
    if (root.directives.isNotEmpty) {
      for (final directive in root.directives.whereType<PartOfDirective>()) {
        return directive.uri?.stringValue;
      }
    }
    return null;
  }

  ParameterInfo _parameterInfo(FormalParameter parameter) {
    final element = parameter.declaredFragment?.element;
    return ParameterInfo(
      name: parameter.name?.lexeme ?? '',
      type: element?.type.getDisplayString(),
      isNamed: parameter.isNamed,
      isOptional: parameter.isOptional,
      defaultValue: parameter is DefaultFormalParameter
          ? parameter.defaultValue?.toSource()
          : null,
    );
  }

  String? _getEnclosingClass(ClassDeclaration node) {
    var parent = node.parent;
    while (parent != null) {
      if (parent is ClassDeclaration) {
        return parent.name.lexeme;
      }
      parent = parent.parent;
    }
    return null;
  }

  Map<String, dynamic> _extractAnnotationArguments(Annotation annotation) {
    final args = <String, dynamic>{};
    final argList = annotation.arguments?.arguments;
    if (argList != null) {
      for (int i = 0; i < argList.length; i++) {
        args['arg$i'] = argList[i].toSource();
      }
    }
    return args;
  }

  String _elementKey(InterfaceElement element) {
    final libraryKey = _libraryKey(element);
    return '$libraryKey#${element.displayName}';
  }

  String _libraryKey(InterfaceElement element) {
    final uri = element.firstFragment.libraryFragment.source.uri.toString();
    return Platform.isMacOS || Platform.isWindows ? uri.toLowerCase() : uri;
  }
}

class _ReferenceVisitor extends RecursiveAstVisitor<void> {
  _ReferenceVisitor({
    required this.currentClass,
    required this.currentClassElement,
    required this.currentFile,
    required this.classRefsByElement,
  });

  final String currentClass;
  final String currentClassElement;
  final String currentFile;
  final Map<String, List<ClassReference>> classRefsByElement;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final element = node.constructorName.element;
    if (element != null) {
      final enclosingElement = element.enclosingElement;
      _addReference(enclosingElement, 'instantiation', node.offset);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitNamedType(NamedType node) {
    final element = node.element;
    if (element is InterfaceElement) {
      _addReference(element, 'typeAnnotation', node.offset);
    }
    super.visitNamedType(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final element = node.methodName.element;
    if (element is ExecutableElement) {
      final enclosingElement = element.enclosingElement;
      if (enclosingElement is InterfaceElement &&
          enclosingElement.displayName != currentClass) {
        _addReference(enclosingElement, 'methodCall', node.offset);
      }
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    final element = node.identifier.element;
    if (element != null) {
      var enclosing = element.enclosingElement;
      while (enclosing != null && enclosing is! InterfaceElement) {
        enclosing = enclosing.enclosingElement;
      }
      if (enclosing is InterfaceElement &&
          enclosing.displayName != currentClass) {
        _addReference(enclosing, 'fieldAccess', node.offset);
      }
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitExtendsClause(ExtendsClause node) {
    final supertype = node.superclass.element;
    if (supertype is InterfaceElement) {
      _addReference(supertype, 'superclass', node.offset);
    }
    super.visitExtendsClause(node);
  }

  @override
  void visitImplementsClause(ImplementsClause node) {
    for (final interface in node.interfaces) {
      final element = interface.element;
      if (element is InterfaceElement) {
        _addReference(element, 'interface', interface.offset);
      }
    }
    super.visitImplementsClause(node);
  }

  @override
  void visitWithClause(WithClause node) {
    for (final mixin in node.mixinTypes) {
      final element = mixin.element;
      if (element is InterfaceElement) {
        _addReference(element, 'mixin', mixin.offset);
      }
    }
    super.visitWithClause(node);
  }

  @override
  void visitAnnotation(Annotation node) {
    final annElement = _interfaceElement(node.element);
    if (annElement != null) {
      _addReference(annElement, 'annotation', node.offset);
    }
    super.visitAnnotation(node);
  }

  void _addReference(
    InterfaceElement targetElement,
    String refType,
    int offset,
  ) {
    final targetKey = _elementKey(targetElement);
    final ref = ClassReference(
      referencingClass: currentClass,
      referencingClassElement: currentClassElement,
      referencingFile: currentFile,
      offset: offset,
      context: 'see visitor methods',
      referenceType: ReferenceType.values.firstWhere(
        (e) => e.name == refType,
        orElse: () => ReferenceType.typeAnnotation,
      ),
    );
    classRefsByElement.putIfAbsent(targetKey, () => []).add(ref);
  }

  String _elementKey(InterfaceElement element) {
    final libraryKey = _libraryKey(element);
    return '$libraryKey#${element.displayName}';
  }

  String _libraryKey(InterfaceElement element) {
    final uri = element.firstFragment.libraryFragment.source.uri.toString();
    return Platform.isMacOS || Platform.isWindows ? uri.toLowerCase() : uri;
  }

  InterfaceElement? _interfaceElement(Element? element) {
    if (element is InterfaceElement) return element;
    if (element is ConstructorElement) return element.enclosingElement;
    return null;
  }
}
