import 'package:model_pkg/src/models.dart';

/// 正例：真实生产调用 - Cache Key
class UserRepository {
  final Map<String, User> _cache = {};

  String buildCacheKey(String id) {
    return 'UserRepository:${id.trim().toLowerCase()}';
  }

  Future<User?> loadUser(String id) async {
    final key = buildCacheKey(id);
    final cached = _cache[key];

    if (cached != null && _isCacheValid(cached)) {
      return cached;
    }

    final user = await _fetchFromApi(id);
    if (user != null) {
      _cache[key] = user;
    }
    return user;
  }

  bool _isCacheValid(User user) {
    return DateTime.now().difference(user.updatedAt).inMinutes < 30;
  }

  Future<User?> _fetchFromApi(String id) async {
    // 模拟 API 调用
    await Future.delayed(Duration(milliseconds: 10));
    return User(id: id, name: 'User $id', updatedAt: DateTime.now());
  }

  // 正例：Cache Validation 真实调用
  bool isCacheValid(User user) {
    if (user.id.isEmpty) return false;
    return DateTime.now().difference(user.updatedAt).inMinutes < 30;
  }
}

/// 正例：真实生产调用 - Response Normalizer
class ProductRepository {
  Future<List<User>> fetchProducts() async {
    await Future.delayed(Duration(milliseconds: 10));
    return [
      User(id: ' 1 ', name: ' Product A ', updatedAt: DateTime.now()),
      User(id: ' 2 ', name: ' Product B ', updatedAt: DateTime.now()),
    ];
  }

  List<User> normalizeResponse(List<User> raw) {
    return raw.map((u) => u.normalize()).toList();
  }

  Future<List<User>> loadProducts() async {
    final raw = await fetchProducts();
    return normalizeResponse(raw); // 真实使用
  }
}

/// 反例：死代码 - 未被调用的能力
class DeadCodeRepository {
  String unusedCacheKey(String id) => 'dead:$id';
  bool unusedValidation(User u) => true;
  User unusedNormalizer(User u) => u;
}

/// 反例：仅 import，无实际使用
class ImportOnlyRepository {
  // 只 import 了 model_pkg 但没用
  void doNothing() {}
}

/// 反例：错误的 anchor（方法名不存在）
class WrongAnchorRepository {
  Future<User?> loadUser(String id) async {
    return null;
  }

  // 缺少 _isCacheValid 等 anchor 方法
}

/// 反例：动态反射调用
class DynamicReflectionRepository {
  dynamic callMethod(String methodName, List<dynamic> args) {
    // 动态调用，静态分析无法追踪
    return null;
  }
}
