import 'package:model_pkg/src/models.dart';

/// 正例：真实生产调用 - Request Metadata
class ApiService {
  Map<String, String> buildRequestMetadata() {
    return {
      'client_time': DateTime.now().millisecondsSinceEpoch.toString(),
      'source': runtimeType.toString(),
    };
  }

  Future<Map<String, dynamic>> request(String endpoint) async {
    final metadata = buildRequestMetadata(); // 真实使用
    await Future.delayed(Duration(milliseconds: 5));
    return {'endpoint': endpoint, 'metadata': metadata};
  }

  // 正例：Input Validation 真实调用
  bool validateInput(String input) {
    return input.trim().isNotEmpty && input.length <= 100;
  }

  Future<Map<String, dynamic>> sanitizedRequest(String input) async {
    if (!validateInput(input)) {
      throw ArgumentError('Invalid input');
    }
    return request(input);
  }

  // 正例：Health Check 真实调用
  Future<bool> healthCheck() async {
    await Future.delayed(Duration(milliseconds: 2));
    return true;
  }

  // 正例：Retry Context 真实调用
  Future<T> withRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
  }) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        return await operation();
      } catch (e) {
        if (i == maxRetries - 1) rethrow;
        await Future.delayed(Duration(milliseconds: 100 * (i + 1)));
      }
    }
    throw StateError('unreachable');
  }
}

/// 反例：死代码
class DeadCodeService {
  Map<String, String> unusedMetadata() => {};
  bool unusedValidation(String s) => true;
  Future<void> unusedHealthCheck() async {}
}

/// 反例：仅 import
class ImportOnlyService {
  void doNothing() {}
}
