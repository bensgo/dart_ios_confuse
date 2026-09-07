// Pigeon API definition for Native Capabilities
// This is a minimal stub that can be used for code generation

import 'package:pigeon/pigeon.dart';

@HostApi()
abstract class NativeDeviceApi {
  @async
  Map<String, String> getDeviceInfo();
}

@HostApi()
abstract class NativeNetworkApi {
  @async
  Map<String, dynamic> getNetworkStatus();
}

@HostApi()
abstract class NativeSecureStorageApi {
  @async
  String getString(String key);
  @async
  void setString(String key, String value);
  @async
  void delete(String key);
}

@HostApi()
abstract class NativeCryptoApi {
  @async
  String sha256(List<int> data);
  @async
  String hmacSha256(List<int> data, List<int> key);
}

@HostApi()
abstract class NativeDiagnosticsApi {
  @async
  Map<String, String> getDiagnostics();
}

@HostApi()
abstract class NativePerformanceApi {
  @async
  void mark(String name);
  @async
  Map<String, dynamic> getMetrics();
}

// Data classes
class NetworkStatus {
  NetworkStatus({
    required this.isConnected,
    required this.connectionType,
    required this.isExpensive,
    required this.isConstrained,
  });

  final bool isConnected;
  final String connectionType;
  final bool isExpensive;
  final bool isConstrained;
}

class DeviceInfo {
  DeviceInfo({
    required this.systemVersion,
    required this.deviceModel,
    required this.isLowPowerMode,
    required this.memoryInfo,
    required this.locale,
  });

  final String systemVersion;
  final String deviceModel;
  final bool isLowPowerMode;
  final String memoryInfo;
  final String locale;
}

class DiagnosticsInfo {
  DiagnosticsInfo({
    required this.appVersion,
    required this.buildNumber,
    required this.availableStorage,
    required this.cacheSize,
    required this.runtimeInfo,
  });

  final String appVersion;
  final String buildNumber;
  final String availableStorage;
  final String cacheSize;
  final String runtimeInfo;
}
