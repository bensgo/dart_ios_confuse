import 'package:controller_pkg/src/controller.dart';
import 'package:model_pkg/src/models.dart';

/// 正例：真实生产调用 - Accessibility
class UserProfileWidget {
  final ConversationController _controller;

  UserProfileWidget(this._controller);

  Map<String, String> buildAccessibilityLabels() {
    return {
      'name': 'User Name',
      'avatar': 'User Avatar',
      'settings': 'Settings Button',
    };
  }

  void render(User user) {
    final labels = buildAccessibilityLabels(); // 真实使用
    // 渲染逻辑
  }

  // 正例：Presentation Normalization 真实调用
  String normalizeText(String input) {
    return input.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  String formatDisplayName(User user) {
    return normalizeText(user.name); // 真实使用
  }

  // 正例：Layout Metadata 真实调用
  Map<String, double> calculateLayoutMetrics() {
    return {'width': 320.0, 'height': 480.0, 'padding': 16.0};
  }

  void layout() {
    final metrics = calculateLayoutMetrics(); // 真实使用
    // 布局逻辑
  }
}

/// 反例：死代码
class DeadCodeWidget {
  Map<String, String> unusedAccessibility() => {};
  String unusedNormalize(String s) => s;
  Map<String, double> unusedMetrics() => {};
}

/// 反例：仅 import
class ImportOnlyWidget {
  void doNothing() {}
}
