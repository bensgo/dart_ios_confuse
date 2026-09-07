import 'dart:convert';

class ProductProfile {
  ProductProfile({required this.schemaVersion, required this.product});

  factory ProductProfile.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schema_version'] as int? ?? 1;
    if (schemaVersion != 1) {
      throw FormatException('Unsupported schema_version: $schemaVersion');
    }
    return ProductProfile(
      schemaVersion: schemaVersion,
      product: ProductInfo.fromJson(json['product'] as Map<String, dynamic>),
    );
  }

  final int schemaVersion;
  final ProductInfo product;

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'product': product.toJson(),
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}

class ProductInfo {
  ProductInfo({required this.id, required this.type});

  factory ProductInfo.fromJson(Map<String, dynamic> json) {
    return ProductInfo(id: json['id'] as String, type: json['type'] as String);
  }

  final String id;
  final String type;

  Map<String, dynamic> toJson() => {'id': id, 'type': type};
}
