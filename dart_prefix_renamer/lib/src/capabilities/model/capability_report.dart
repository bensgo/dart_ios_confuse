import 'dart:convert';

class CapabilityReport {
  CapabilityReport({
    required this.schemaVersion,
    required this.toolVersion,
    required this.inputHashes,
    required this.generatedAt,
    required this.dartCapabilities,
    required this.nativeCapabilities,
    required this.dependencies,
    required this.releaseValidation,
    required this.status,
    required this.failureCodes,
  });

  factory CapabilityReport.fromJson(Map<String, dynamic> json) {
    return CapabilityReport(
      schemaVersion: json['schema_version'] as int? ?? 1,
      toolVersion: json['tool_version'] as String? ?? '',
      inputHashes:
          (json['input_hashes'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v as String),
          ) ??
          {},
      generatedAt: json['generated_at'] as String? ?? '',
      dartCapabilities: DartCapabilityReport.fromJson(
        json['dart_capabilities'] as Map<String, dynamic>,
      ),
      nativeCapabilities: NativeCapabilityReport.fromJson(
        json['native_capabilities'] as Map<String, dynamic>,
      ),
      dependencies: DependencyReport.fromJson(
        json['dependencies'] as Map<String, dynamic>,
      ),
      releaseValidation: ReleaseValidationReport.fromJson(
        json['release_validation'] as Map<String, dynamic>,
      ),
      status: json['status'] as String? ?? 'unknown',
      failureCodes:
          (json['failure_codes'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList(growable: false) ??
          const [],
    );
  }

  final int schemaVersion;
  final String toolVersion;
  final Map<String, String> inputHashes;
  final String generatedAt;
  final DartCapabilityReport dartCapabilities;
  final NativeCapabilityReport nativeCapabilities;
  final DependencyReport dependencies;
  final ReleaseValidationReport releaseValidation;
  final String status;
  final List<String> failureCodes;

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'tool_version': toolVersion,
    'input_hashes': inputHashes,
    'generated_at': generatedAt,
    'dart_capabilities': dartCapabilities.toJson(),
    'native_capabilities': nativeCapabilities.toJson(),
    'dependencies': dependencies.toJson(),
    'release_validation': releaseValidation.toJson(),
    'status': status,
    'failure_codes': failureCodes,
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}

class DartCapabilityReport {
  DartCapabilityReport({
    required this.classesAnalyzed,
    required this.capabilitiesPlanned,
    required this.capabilitiesApplied,
    required this.capabilitiesReachable,
    required this.capabilitiesFailed,
    required this.integrations,
  });

  factory DartCapabilityReport.fromJson(Map<String, dynamic> json) {
    return DartCapabilityReport(
      classesAnalyzed: json['classes_analyzed'] as int? ?? 0,
      capabilitiesPlanned: json['capabilities_planned'] as int? ?? 0,
      capabilitiesApplied: json['capabilities_applied'] as int? ?? 0,
      capabilitiesReachable: json['capabilities_reachable'] as int? ?? 0,
      capabilitiesFailed: json['capabilities_failed'] as int? ?? 0,
      integrations:
          (json['integrations'] as List<dynamic>?)
              ?.map(
                (e) => IntegrationReport.fromJson(e as Map<String, dynamic>),
              )
              .toList(growable: false) ??
          const [],
    );
  }

  final int classesAnalyzed;
  final int capabilitiesPlanned;
  final int capabilitiesApplied;
  final int capabilitiesReachable;
  final int capabilitiesFailed;
  final List<IntegrationReport> integrations;

  Map<String, dynamic> toJson() => {
    'classes_analyzed': classesAnalyzed,
    'capabilities_planned': capabilitiesPlanned,
    'capabilities_applied': capabilitiesApplied,
    'capabilities_reachable': capabilitiesReachable,
    'capabilities_failed': capabilitiesFailed,
    'integrations': integrations.map((e) => e.toJson()).toList(),
  };
}

class IntegrationReport {
  IntegrationReport({
    required this.className,
    required this.library,
    required this.capability,
    required this.callSite,
    required this.effect,
    required this.defined,
    required this.productionCallCount,
    required this.effectVerified,
    this.failureCode,
  });

  factory IntegrationReport.fromJson(Map<String, dynamic> json) {
    return IntegrationReport(
      className: json['class'] as String,
      library: json['library'] as String,
      capability: json['capability'] as String,
      callSite: json['call_site'] as String,
      effect: json['effect'] as String,
      defined: json['defined'] as bool? ?? false,
      productionCallCount: json['production_call_count'] as int? ?? 0,
      effectVerified: json['effect_verified'] as bool? ?? false,
      failureCode: json['failure_code'] as String?,
    );
  }

  final String className;
  final String library;
  final String capability;
  final String callSite;
  final String effect;
  final bool defined;
  final int productionCallCount;
  final bool effectVerified;
  final String? failureCode;

  Map<String, dynamic> toJson() => {
    'class': className,
    'library': library,
    'capability': capability,
    'call_site': callSite,
    'effect': effect,
    'defined': defined,
    'production_call_count': productionCallCount,
    'effect_verified': effectVerified,
    if (failureCode != null) 'failure_code': failureCode,
  };
}

class NativeCapabilityReport {
  NativeCapabilityReport({
    required this.enabledCount,
    required this.registeredCount,
    required this.calledCount,
    required this.capabilities,
  });

  factory NativeCapabilityReport.fromJson(Map<String, dynamic> json) {
    return NativeCapabilityReport(
      enabledCount: json['enabled_count'] as int? ?? 0,
      registeredCount: json['registered_count'] as int? ?? 0,
      calledCount: json['called_count'] as int? ?? 0,
      capabilities: (json['capabilities'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(
          k,
          NativeCapabilityStatus.fromJson(v as Map<String, dynamic>),
        ),
      ),
    );
  }

  final int enabledCount;
  final int registeredCount;
  final int calledCount;
  final Map<String, NativeCapabilityStatus> capabilities;

  Map<String, dynamic> toJson() => {
    'enabled_count': enabledCount,
    'registered_count': registeredCount,
    'called_count': calledCount,
    'capabilities': capabilities.map((k, v) => MapEntry(k, v.toJson())),
  };
}

class NativeCapabilityStatus {
  NativeCapabilityStatus({
    required this.enabled,
    required this.bridgeCalled,
    this.provider,
  });

  factory NativeCapabilityStatus.fromJson(Map<String, dynamic> json) {
    return NativeCapabilityStatus(
      enabled: json['enabled'] as bool? ?? false,
      bridgeCalled: json['bridge_called'] as bool? ?? false,
      provider: json['provider'] as String?,
    );
  }

  final bool enabled;
  final bool bridgeCalled;
  final String? provider;

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'bridge_called': bridgeCalled,
    if (provider != null) 'provider': provider,
  };
}

class DependencyReport {
  DependencyReport({
    required this.total,
    required this.justified,
    required this.dependencies,
  });

  factory DependencyReport.fromJson(Map<String, dynamic> json) {
    return DependencyReport(
      total: json['total'] as int? ?? 0,
      justified: json['justified'] as int? ?? 0,
      dependencies:
          (json['dependencies'] as List<dynamic>?)
              ?.map((e) => DependencyStatus.fromJson(e as Map<String, dynamic>))
              .toList(growable: false) ??
          const [],
    );
  }

  final int total;
  final int justified;
  final List<DependencyStatus> dependencies;

  int get selected => dependencies.length;
  int get declared => dependencies.where((item) => item.declared).length;
  int get locked => dependencies.where((item) => item.locked).length;
  int get called => dependencies.where((item) => item.called).length;
  int get linked => dependencies.where((item) => item.linked).length;

  DependencyReport withDependencies(List<DependencyStatus> value) =>
      DependencyReport(
        total: value.length,
        justified: value.where((item) => item.used).length,
        dependencies: value,
      );

  Map<String, dynamic> toJson() => {
    'total': total,
    'justified': justified,
    'selected': selected,
    'declared': declared,
    'locked': locked,
    'called': called,
    'linked': linked,
    'dependencies': dependencies.map((e) => e.toJson()).toList(),
  };
}

class DependencyStatus {
  DependencyStatus({
    required this.name,
    required this.version,
    required this.reason,
    required this.used,
    this.declared = false,
    this.locked = false,
    this.called = false,
    this.linked = false,
    this.binaryTokens = const [],
    this.sourcePath,
    this.failureCode,
  });

  factory DependencyStatus.fromJson(Map<String, dynamic> json) {
    return DependencyStatus(
      name: json['name'] as String,
      version: json['version'] as String,
      reason: json['reason'] as String,
      used: json['used'] as bool? ?? false,
      declared: json['declared'] as bool? ?? false,
      locked: json['locked'] as bool? ?? false,
      called: json['called'] as bool? ?? false,
      linked: json['linked'] as bool? ?? false,
      binaryTokens:
          (json['binary_tokens'] as List<dynamic>?)?.cast<String>() ?? const [],
      sourcePath: json['source_path'] as String?,
      failureCode: json['failure_code'] as String?,
    );
  }

  final String name;
  final String version;
  final String reason;
  final bool used;
  final bool declared;
  final bool locked;
  final bool called;
  final bool linked;
  final List<String> binaryTokens;
  final String? sourcePath;
  final String? failureCode;

  DependencyStatus copyWith({bool? linked, String? failureCode}) =>
      DependencyStatus(
        name: name,
        version: version,
        reason: reason,
        used: used,
        declared: declared,
        locked: locked,
        called: called,
        linked: linked ?? this.linked,
        binaryTokens: binaryTokens,
        sourcePath: sourcePath,
        failureCode: failureCode ?? this.failureCode,
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'version': version,
    'reason': reason,
    'used': used,
    'declared': declared,
    'locked': locked,
    'called': called,
    'linked': linked,
    'binary_tokens': binaryTokens,
    if (sourcePath != null) 'source_path': sourcePath,
    if (failureCode != null) 'failure_code': failureCode,
  };
}

class ReleaseValidationReport {
  ReleaseValidationReport({
    required this.buildSuccess,
    required this.analyzerPassed,
    required this.ipaHash,
    required this.lockfileHash,
    required this.components,
    this.bundlePath = '',
    this.infoPlistPresent = false,
    this.frameworks = const [],
  });

  factory ReleaseValidationReport.fromJson(Map<String, dynamic> json) {
    return ReleaseValidationReport(
      buildSuccess: json['build_success'] as bool? ?? false,
      analyzerPassed: json['analyzer_passed'] as bool? ?? false,
      ipaHash: json['ipa_sha256'] as String? ?? '',
      lockfileHash: json['lockfile_sha256'] as String? ?? '',
      components:
          (json['components'] as List<dynamic>?)
              ?.map((e) => ComponentHash.fromJson(e as Map<String, dynamic>))
              .toList(growable: false) ??
          const [],
      bundlePath: json['bundle_path'] as String? ?? '',
      infoPlistPresent: json['info_plist_present'] as bool? ?? false,
      frameworks:
          (json['frameworks'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }

  final bool buildSuccess;
  final bool analyzerPassed;
  final String ipaHash;
  final String lockfileHash;
  final List<ComponentHash> components;
  final String bundlePath;
  final bool infoPlistPresent;
  final List<String> frameworks;

  Map<String, dynamic> toJson() => {
    'build_success': buildSuccess,
    'analyzer_passed': analyzerPassed,
    'ipa_sha256': ipaHash,
    'lockfile_sha256': lockfileHash,
    'components': components.map((e) => e.toJson()).toList(),
    'bundle_path': bundlePath,
    'info_plist_present': infoPlistPresent,
    'frameworks': frameworks,
  };
}

class ComponentHash {
  ComponentHash({required this.path, required this.sha256, required this.size});

  factory ComponentHash.fromJson(Map<String, dynamic> json) {
    return ComponentHash(
      path: json['path'] as String,
      sha256: json['sha256'] as String,
      size: json['size'] as int,
    );
  }

  final String path;
  final String sha256;
  final int size;

  Map<String, dynamic> toJson() => {
    'path': path,
    'sha256': sha256,
    'size': size,
  };
}
