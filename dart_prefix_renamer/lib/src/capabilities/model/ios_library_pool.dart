class IosLibraryPool {
  const IosLibraryPool({
    required this.schemaVersion,
    required this.researchedAt,
    required this.libraries,
  });

  factory IosLibraryPool.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schema_version'] as int? ?? 1;
    if (schemaVersion != 1) {
      throw FormatException('Unsupported schema_version: $schemaVersion');
    }
    return IosLibraryPool(
      schemaVersion: schemaVersion,
      researchedAt: json['researched_at'] as String,
      libraries: (json['libraries'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(
          key,
          IosLibraryCandidate.fromJson(value as Map<String, dynamic>),
        ),
      ),
    );
  }

  final int schemaVersion;
  final String researchedAt;
  final Map<String, IosLibraryCandidate> libraries;

  IosLibraryCandidate? find(String name) {
    return findEntry(name)?.value;
  }

  MapEntry<String, IosLibraryCandidate>? findEntry(String name) {
    final normalized = name.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    for (final entry in libraries.entries) {
      final key = entry.key.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
      final pod = entry.value.podName?.toLowerCase().replaceAll(
        RegExp('[^a-z0-9]'),
        '',
      );
      if (key == normalized || pod == normalized) return entry;
    }
    return null;
  }
}

class IosLibraryCandidate {
  const IosLibraryCandidate({
    required this.repository,
    required this.capability,
    required this.selectedVersion,
    required this.packageManager,
    required this.license,
    required this.minimumIos,
    required this.status,
    required this.reason,
    required this.evidenceUrls,
    this.podName,
    this.moduleName,
    this.probeTemplate,
    this.binaryTokens = const [],
    this.conflictGroup,
    this.sourceGit,
    this.sourceTag,
  });

  factory IosLibraryCandidate.fromJson(Map<String, dynamic> json) {
    return IosLibraryCandidate(
      repository: json['repository'] as String,
      capability: json['capability'] as String,
      selectedVersion: json['selected_version'] as String,
      packageManager: json['package_manager'] as String,
      license: json['license'] as String,
      minimumIos: json['minimum_ios'] as String,
      status: json['status'] as String,
      reason: json['reason'] as String,
      evidenceUrls: (json['evidence_urls'] as List<dynamic>)
          .cast<String>()
          .toList(growable: false),
      podName: json['pod_name'] as String?,
      moduleName: json['module_name'] as String?,
      probeTemplate: json['probe_template'] as String?,
      binaryTokens:
          (json['binary_tokens'] as List<dynamic>?)?.cast<String>().toList(
            growable: false,
          ) ??
          const [],
      conflictGroup: json['conflict_group'] as String?,
      sourceGit: json['source_git'] as String?,
      sourceTag: json['source_tag'] as String?,
    );
  }

  final String repository;
  final String capability;
  final String selectedVersion;
  final String packageManager;
  final String license;
  final String minimumIos;
  final String status;
  final String reason;
  final List<String> evidenceUrls;
  final String? podName;
  final String? moduleName;
  final String? probeTemplate;
  final List<String> binaryTokens;
  final String? conflictGroup;
  final String? sourceGit;
  final String? sourceTag;
}
