// Platform service for native capability bridges
// This is a minimal stub for the fixture

class PlatformService {
  final NativeDiagnosticsApi _diagnosticsApi;
  final NativeNetworkApi _networkApi;
  final NativeSecureStorageApi _secureStorageApi;
  final NativeCryptoApi _cryptoApi;
  final NativeDeviceApi _deviceApi;
  final NativePerformanceApi _performanceApi;

  PlatformService(
    this._diagnosticsApi,
    this._networkApi,
    this._secureStorageApi,
    this._cryptoApi,
    this._deviceApi,
    this._performanceApi,
  );

  Future<bool> isNetworkAvailable() async {
    final status = await _networkApi.getNetworkStatus();
    return status['isConnected'] as bool;
  }

  Future<String> getDeviceId() async {
    final info = await _deviceApi.getDeviceInfo();
    return info['deviceModel'] as String;
  }

  Future<String> sha256(List<int> data) async {
    return await _cryptoApi.sha256(data);
  }

  Future<void> saveToken(String token) async {
    await _secureStorageApi.setString('auth_token', token);
  }

  Future<String?> getToken() async {
    return await _secureStorageApi.getString('auth_token');
  }

  Future<Map<String, String>> getDiagnostics() async {
    return await _diagnosticsApi.getDiagnostics();
  }

  Future<void> markPerformance(String name) async {
    await _performanceApi.mark(name);
  }
}

// Pigeon-generated API interfaces (stubs for fixture)
abstract class NativeDiagnosticsApi {
  Future<Map<String, String>> getDiagnostics();
}

abstract class NativeNetworkApi {
  Future<Map<String, dynamic>> getNetworkStatus();
}

abstract class NativeSecureStorageApi {
  Future<String> getString(String key);
  Future<void> setString(String key, String value);
  Future<void> delete(String key);
}

abstract class NativeCryptoApi {
  Future<String> sha256(List<int> data);
  Future<String> hmacSha256(List<int> data, List<int> key);
}

abstract class NativeDeviceApi {
  Future<Map<String, String>> getDeviceInfo();
}

abstract class NativePerformanceApi {
  Future<void> mark(String name);
  Future<Map<String, dynamic>> getMetrics();
}
