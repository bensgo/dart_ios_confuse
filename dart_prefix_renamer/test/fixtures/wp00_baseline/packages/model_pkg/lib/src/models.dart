class User {
  final String id;
  final String name;
  final DateTime updatedAt;

  User({required this.id, required this.name, required this.updatedAt});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      name: json['name'] as String,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'updatedAt': updatedAt.toIso8601String(),
  };

  bool validate() {
    return id.isNotEmpty && name.trim().isNotEmpty;
  }

  User normalize() {
    return User(
      id: id.trim().toLowerCase(),
      name: name.trim(),
      updatedAt: updatedAt,
    );
  }
}

class Message {
  final String id;
  final String content;
  final String conversationId;
  final DateTime timestamp;

  Message({
    required this.id,
    required this.content,
    required this.conversationId,
    required this.timestamp,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      content: json['content'] as String,
      conversationId: json['conversationId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'conversationId': conversationId,
    'timestamp': timestamp.toIso8601String(),
  };
}
