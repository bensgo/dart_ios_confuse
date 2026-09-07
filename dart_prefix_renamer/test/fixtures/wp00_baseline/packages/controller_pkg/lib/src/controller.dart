import 'package:service_pkg/src/service.dart';
import 'package:model_pkg/src/models.dart';

/// 正例：真实生产调用 - Analytics Context
class ConversationController {
  final ApiService _apiService;

  ConversationController(this._apiService);

  Map<String, Object?> buildAnalyticsContext() {
    return {
      'screen': runtimeType.toString(),
      'state': 'active',
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  Future<void> onPageOpen() async {
    final context = buildAnalyticsContext(); // 真实使用
    await _apiService.request('analytics/page_open');
  }

  // 正例：State Validation 真实调用
  bool validateState(String state) {
    return ['loading', 'active', 'error', 'idle'].contains(state);
  }

  void setState(String newState) {
    if (!validateState(newState)) {
      throw StateError('Invalid state: $newState');
    }
    // 真实状态变更逻辑
  }

  // 正例：Lifecycle Diagnostics 真实调用
  Map<String, Object?> captureDiagnostics() {
    return {
      'controller': runtimeType.toString(),
      'memory': 'normal',
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  void onDispose() {
    final diag = captureDiagnostics(); // 真实使用
    _apiService.request('diagnostics/dispose');
  }
}

/// 反例：死代码
class DeadCodeController {
  Map<String, Object?> unusedAnalytics() => {};
  bool unusedValidation(String s) => true;
  Map<String, Object?> unusedDiagnostics() => {};
}

/// 反例：仅 import
class ImportOnlyController {
  void doNothing() {}
}
