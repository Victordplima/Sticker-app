class Sticker {
  const Sticker({
    required this.id,
    required this.filePath,
    required this.emojis,
    this.isAnimated = false,
  });

  final String id;
  final String filePath;
  final List<String> emojis;
  final bool isAnimated;

  Sticker copyWith({
    String? id,
    String? filePath,
    List<String>? emojis,
    bool? isAnimated,
  }) {
    return Sticker(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      emojis: emojis ?? this.emojis,
      isAnimated: isAnimated ?? this.isAnimated,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'filePath': filePath,
      'emojis': emojis,
      'isAnimated': isAnimated,
    };
  }

  factory Sticker.fromMap(Map<String, dynamic> map) {
    return Sticker(
      id: map['id'] as String,
      filePath: map['filePath'] as String,
      emojis: List<String>.from(map['emojis'] as List<dynamic>),
      isAnimated: map['isAnimated'] as bool? ?? false,
    );
  }
}
