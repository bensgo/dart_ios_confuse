class DartCapabilityTemplate {
  const DartCapabilityTemplate({
    required this.name,
    required this.methodNames,
    required this.generatedMethod,
  });

  final String name;
  final List<String> methodNames;
  final String generatedMethod;
}

class DartCapabilityCatalog {
  const DartCapabilityCatalog();

  static const templates = <String, DartCapabilityTemplate>{
    'cache_key': DartCapabilityTemplate(
      name: 'cache_key',
      methodNames: ['buildCacheKey', 'buildCapabilityCacheKey'],
      generatedMethod: '''
  String buildCapabilityCacheKey(String value) {
    return '\${runtimeType}:\${value.trim().toLowerCase()}';
  }
''',
    ),
    'cache_validation': DartCapabilityTemplate(
      name: 'cache_validation',
      methodNames: ['isCacheValid', '_isCacheValid', 'isCapabilityCacheValid'],
      generatedMethod: '''
  bool isCapabilityCacheValid(Object? value) {
    return value != null;
  }
''',
    ),
    'response_normalizer': DartCapabilityTemplate(
      name: 'response_normalizer',
      methodNames: [
        'normalizeResponse',
        'normalize',
        'normalizeCapabilityResponse',
      ],
      generatedMethod: '''
  T normalizeCapabilityResponse<T>(T value) {
    return value;
  }
''',
    ),
    'request_context': DartCapabilityTemplate(
      name: 'request_context',
      methodNames: ['buildRequestContext', 'buildCapabilityRequestContext'],
      generatedMethod: '''
  Map<String, Object?> buildCapabilityRequestContext() {
    return <String, Object?>{'source': runtimeType.toString()};
  }
''',
    ),
    'input_validation': DartCapabilityTemplate(
      name: 'input_validation',
      methodNames: ['validateInput', 'validate', 'validateCapabilityInput'],
      generatedMethod: '''
  bool validateCapabilityInput(String value) {
    return value.trim().isNotEmpty;
  }
''',
    ),
    'analytics_context': DartCapabilityTemplate(
      name: 'analytics_context',
      methodNames: ['buildAnalyticsContext', 'buildCapabilityAnalyticsContext'],
      generatedMethod: '''
  Map<String, Object?> buildCapabilityAnalyticsContext() {
    return <String, Object?>{'screen': runtimeType.toString()};
  }
''',
    ),
    'state_validation': DartCapabilityTemplate(
      name: 'state_validation',
      methodNames: ['validateState', 'validateCapabilityState'],
      generatedMethod: '''
  bool validateCapabilityState(Object? value) {
    return value != null;
  }
''',
    ),
    'debug_summary': DartCapabilityTemplate(
      name: 'debug_summary',
      methodNames: ['debugSummary', 'buildCapabilityDebugSummary'],
      generatedMethod: '''
  String buildCapabilityDebugSummary() {
    return runtimeType.toString();
  }
''',
    ),
    'request_metadata': DartCapabilityTemplate(
      name: 'request_metadata',
      methodNames: ['buildRequestMetadata', 'buildCapabilityRequestMetadata'],
      generatedMethod: '''
  Map<String, String> buildCapabilityRequestMetadata() {
    return <String, String>{'source': runtimeType.toString()};
  }
''',
    ),
    'retry_context': DartCapabilityTemplate(
      name: 'retry_context',
      methodNames: [
        'withRetry',
        'buildRetryContext',
        'buildCapabilityRetryContext',
      ],
      generatedMethod: '''
  Map<String, Object?> buildCapabilityRetryContext(int attempt, Object error) {
    return <String, Object?>{'attempt': attempt, 'error': error.runtimeType.toString()};
  }
''',
    ),
    'operation_context': DartCapabilityTemplate(
      name: 'operation_context',
      methodNames: ['buildCapabilityOperationContext'],
      generatedMethod: '''
  Map<String, Object?> buildCapabilityOperationContext(String operation) {
    return <String, Object?>{
      'manager': runtimeType.toString(),
      'operation': operation.trim(),
    };
  }
''',
    ),
    'lifecycle_snapshot': DartCapabilityTemplate(
      name: 'lifecycle_snapshot',
      methodNames: ['buildCapabilityLifecycleSnapshot'],
      generatedMethod: '''
  Map<String, Object?> buildCapabilityLifecycleSnapshot() {
    return <String, Object?>{
      'owner': runtimeType.toString(),
      'active': true,
    };
  }
''',
    ),
    'decision_context': DartCapabilityTemplate(
      name: 'decision_context',
      methodNames: ['buildCapabilityDecisionContext'],
      generatedMethod: '''
  Map<String, Object?> buildCapabilityDecisionContext(Object? input) {
    return <String, Object?>{
      'logic': runtimeType.toString(),
      'input_type': input?.runtimeType.toString() ?? 'null',
    };
  }
''',
    ),
    'rule_validation': DartCapabilityTemplate(
      name: 'rule_validation',
      methodNames: ['validateCapabilityRule'],
      generatedMethod: '''
  bool validateCapabilityRule(Object? value) {
    return value != null;
  }
''',
    ),
    'presentation_metadata': DartCapabilityTemplate(
      name: 'presentation_metadata',
      methodNames: ['buildCapabilityPresentationMetadata'],
      generatedMethod: '''
  Map<String, Object?> buildCapabilityPresentationMetadata() {
    return <String, Object?>{
      'widget': runtimeType.toString(),
      'mode': 'release',
    };
  }
''',
    ),
    'accessibility_context': DartCapabilityTemplate(
      name: 'accessibility_context',
      methodNames: ['buildCapabilityAccessibilityContext'],
      generatedMethod: '''
  Map<String, Object?> buildCapabilityAccessibilityContext(String label) {
    return <String, Object?>{
      'label': label.trim(),
      'source': runtimeType.toString(),
    };
  }
''',
    ),
  };

  DartCapabilityTemplate? lookup(String capability) => templates[capability];
}
