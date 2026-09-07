import 'dart:convert';

class DartCapabilityManifest {
  DartCapabilityManifest({
    required this.schemaVersion,
    required this.rules,
    required this.integrations,
  });

  factory DartCapabilityManifest.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schema_version'] as int? ?? 1;
    if (schemaVersion != 1) {
      throw FormatException('Unsupported schema_version: $schemaVersion');
    }
    return DartCapabilityManifest(
      schemaVersion: schemaVersion,
      rules: (json['rules'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(
          key,
          CapabilityRule.fromJson(value as Map<String, dynamic>),
        ),
      ),
      integrations:
          (json['integrations'] as List<dynamic>?)
              ?.map((e) => IntegrationSpec.fromJson(e as Map<String, dynamic>))
              .toList(growable: false) ??
          const [],
    );
  }

  final int schemaVersion;
  final Map<String, CapabilityRule> rules;
  final List<IntegrationSpec> integrations;

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'rules': rules.map((k, v) => MapEntry(k, v.toJson())),
    'integrations': integrations.map((e) => e.toJson()).toList(),
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}

class CapabilityRule {
  CapabilityRule({required this.min, required this.max, required this.allowed});

  factory CapabilityRule.fromJson(Map<String, dynamic> json) {
    return CapabilityRule(
      min: json['min'] as int? ?? 0,
      max: json['max'] as int? ?? 0,
      allowed:
          (json['allowed'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList(growable: false) ??
          const [],
    );
  }

  final int min;
  final int max;
  final List<String> allowed;

  Map<String, dynamic> toJson() => {'min': min, 'max': max, 'allowed': allowed};
}

class IntegrationSpec {
  IntegrationSpec({
    required this.className,
    required this.library,
    required this.capability,
    required this.callSite,
    required this.effect,
    this.expected = 'accepted',
  });

  factory IntegrationSpec.fromJson(Map<String, dynamic> json) {
    return IntegrationSpec(
      className: json['class'] as String,
      library: json['library'] as String,
      capability: json['capability'] as String,
      callSite: CallSiteSpec.fromJson(
        json['call_site'] as Map<String, dynamic>,
      ),
      effect: json['effect'] as String,
      expected: json['expected'] as String? ?? 'accepted',
    );
  }

  final String className;
  final String library;
  final String capability;
  final CallSiteSpec callSite;
  final String effect;
  final String expected;

  Map<String, dynamic> toJson() => {
    'class': className,
    'library': library,
    'capability': capability,
    'call_site': callSite.toJson(),
    'effect': effect,
    'expected': expected,
  };
}

class CallSiteSpec {
  CallSiteSpec({required this.method, required this.anchor});

  factory CallSiteSpec.fromJson(Map<String, dynamic> json) {
    return CallSiteSpec(
      method: json['method'] as String,
      anchor: json['anchor'] as String,
    );
  }

  final String method;
  final String anchor;

  Map<String, dynamic> toJson() => {'method': method, 'anchor': anchor};
}

class NativeCapabilityManifest {
  NativeCapabilityManifest({
    required this.schemaVersion,
    required this.native,
    required this.bridges,
  });

  factory NativeCapabilityManifest.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schema_version'] as int? ?? 1;
    if (schemaVersion != 1) {
      throw FormatException('Unsupported schema_version: $schemaVersion');
    }
    return NativeCapabilityManifest(
      schemaVersion: schemaVersion,
      native: (json['native'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(
          key,
          NativeCapabilitySpec.fromJson(value as Map<String, dynamic>),
        ),
      ),
      bridges:
          (json['bridges'] as List<dynamic>?)
              ?.map((e) => BridgeSpec.fromJson(e as Map<String, dynamic>))
              .toList(growable: false) ??
          const [],
    );
  }

  final int schemaVersion;
  final Map<String, NativeCapabilitySpec> native;
  final List<BridgeSpec> bridges;

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'native': native.map((k, v) => MapEntry(k, v.toJson())),
    'bridges': bridges.map((e) => e.toJson()).toList(),
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}

class NativeCapabilitySpec {
  NativeCapabilitySpec({required this.enabled, required this.provider});

  factory NativeCapabilitySpec.fromJson(Map<String, dynamic> json) {
    return NativeCapabilitySpec(
      enabled: json['enabled'] as bool? ?? false,
      provider: json['provider'] as String? ?? 'system',
    );
  }

  final bool enabled;
  final String provider;

  Map<String, dynamic> toJson() => {'enabled': enabled, 'provider': provider};
}

class BridgeSpec {
  BridgeSpec({required this.api, required this.consumer, required this.effect});

  factory BridgeSpec.fromJson(Map<String, dynamic> json) {
    return BridgeSpec(
      api: json['api'] as String,
      consumer: json['consumer'] as String,
      effect: json['effect'] as String,
    );
  }

  final String api;
  final String consumer;
  final String effect;

  Map<String, dynamic> toJson() => {
    'api': api,
    'consumer': consumer,
    'effect': effect,
  };
}

class DependencyManifest {
  DependencyManifest({
    required this.schemaVersion,
    required this.dependencies,
    this.selection,
  });

  factory DependencyManifest.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schema_version'] as int? ?? 1;
    if (schemaVersion != 1 && schemaVersion != 2) {
      throw FormatException('Unsupported schema_version: $schemaVersion');
    }
    return DependencyManifest(
      schemaVersion: schemaVersion,
      selection: json['selection'] is Map<String, dynamic>
          ? DependencySelection.fromJson(
              json['selection'] as Map<String, dynamic>,
            )
          : null,
      dependencies:
          (json['dependencies'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(
              key,
              DependencySpec.fromJson(value as Map<String, dynamic>),
            ),
          ) ??
          {},
    );
  }

  final int schemaVersion;
  final Map<String, DependencySpec> dependencies;
  final DependencySelection? selection;

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    if (selection != null) 'selection': selection!.toJson(),
    'dependencies': dependencies.map((k, v) => MapEntry(k, v.toJson())),
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}

class DependencySelection {
  DependencySelection({
    required this.enabled,
    required this.mode,
    required this.count,
    required this.execution,
    required this.candidates,
  });

  factory DependencySelection.fromJson(Map<String, dynamic> json) {
    return DependencySelection(
      enabled: json['enabled'] as bool? ?? false,
      mode: json['mode'] as String? ?? 'deterministic_random',
      count: json['count'] as int? ?? 3,
      execution: json['execution'] as String? ?? 'startup_background_once',
      candidates:
          (json['candidates'] as List<dynamic>?)?.cast<String>().toList(
            growable: false,
          ) ??
          const [],
    );
  }

  final bool enabled;
  final String mode;
  final int count;
  final String execution;
  final List<String> candidates;

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'mode': mode,
    'count': count,
    'execution': execution,
    'candidates': candidates,
  };
}

class DependencySpec {
  DependencySpec({
    required this.version,
    required this.manager,
    required this.capability,
    required this.reason,
    this.productionCall,
  });

  factory DependencySpec.fromJson(Map<String, dynamic> json) {
    return DependencySpec(
      version: json['version'] as String,
      manager: json['package_manager'] as String,
      capability: json['capability'] as String,
      reason: json['reason'] as String,
      productionCall: json['production_call'] as String?,
    );
  }

  final String version;
  final String manager;
  final String capability;
  final String reason;
  final String? productionCall;

  Map<String, dynamic> toJson() => {
    'version': version,
    'package_manager': manager,
    'capability': capability,
    'reason': reason,
    if (productionCall != null) 'production_call': productionCall,
  };
}
