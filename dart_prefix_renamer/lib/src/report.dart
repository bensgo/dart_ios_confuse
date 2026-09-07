final class RenameReport {
  const RenameReport({
    required this.renamedFiles,
    required this.renamedClasses,
    required this.renamedDirectories,
    required this.rewrittenUris,
    required this.updatedClassReferences,
    required this.renamedAssets,
    required this.updatedAssetReferences,
    required this.generatedJunkFiles,
    required this.generatedJunkClasses,
    required this.metadataEntitiesReset,
    required this.metadataResetAt,
    required this.encryptedImages,
    required this.encryptedAnimations,
    required this.encryptedAudio,
    required this.encryptedImagePlainBytes,
    required this.encryptedDartFiles,
    required this.encryptedDartStrings,
    required this.renamedIosMethodChannels,
    required this.generatedIosMethodChannels,
    required this.iosMethodChannelDartEdits,
    required this.iosMethodChannelNativeEdits,
    required this.iosProductPodName,
    required this.iosProductPodTheme,
    required this.iosProductPodSeed,
    required this.iosProductPodSourceFiles,
    required this.iosProductPodResourceFiles,
    required this.iosProductPodGeneratedFiles,
    required this.iosProductPodManifestHash,
    this.capabilitiesPlanned = 0,
    this.capabilitiesReachable = 0,
    this.nativeCapabilitiesEnabled = 0,
    this.nativeCapabilitiesCalled = 0,
    this.dependenciesJustified = 0,
    required this.baselineErrors,
    required this.finalErrors,
    required this.newErrors,
  });

  final int renamedFiles;
  final int renamedClasses;
  final int renamedDirectories;
  final int rewrittenUris;
  final int updatedClassReferences;
  final int renamedAssets;
  final int updatedAssetReferences;
  final int generatedJunkFiles;
  final int generatedJunkClasses;
  final int metadataEntitiesReset;
  final DateTime? metadataResetAt;
  final int encryptedImages;
  final int encryptedAnimations;
  final int encryptedAudio;
  final int encryptedImagePlainBytes;
  final int encryptedDartFiles;
  final int encryptedDartStrings;
  final int renamedIosMethodChannels;
  final int generatedIosMethodChannels;
  final int iosMethodChannelDartEdits;
  final int iosMethodChannelNativeEdits;
  final String? iosProductPodName;
  final String? iosProductPodTheme;
  final int? iosProductPodSeed;
  final int iosProductPodSourceFiles;
  final int iosProductPodResourceFiles;
  final int iosProductPodGeneratedFiles;
  final String? iosProductPodManifestHash;
  final int capabilitiesPlanned;
  final int capabilitiesReachable;
  final int nativeCapabilitiesEnabled;
  final int nativeCapabilitiesCalled;
  final int dependenciesJustified;
  final int baselineErrors;
  final int finalErrors;
  final List<String> newErrors;

  bool get verificationPassed => newErrors.isEmpty;
}

final class RestoreReport {
  const RestoreReport({
    required this.restoredFiles,
    required this.restoredClasses,
    required this.restoredDirectories,
    required this.restoredClassReferences,
    required this.restoredUris,
    required this.restoredAssets,
    required this.restoredAssetReferences,
    required this.restoredIosProductPodFiles,
    required this.baselineErrors,
    required this.finalErrors,
    required this.newErrors,
  });

  final int restoredFiles;
  final int restoredClasses;
  final int restoredDirectories;
  final int restoredClassReferences;
  final int restoredUris;
  final int restoredAssets;
  final int restoredAssetReferences;
  final int restoredIosProductPodFiles;
  final int baselineErrors;
  final int finalErrors;
  final List<String> newErrors;

  bool get verificationPassed => newErrors.isEmpty;
}
