import '../../stickers/models/sticker.dart';

class StickerPack {
  const StickerPack({
    required this.id,
    required this.name,
    required this.author,
    required this.stickers,
    this.trayImagePath,
  });

  final String id;
  final String name;
  final String author;
  final List<Sticker> stickers;
  final String? trayImagePath;

  int get stickerCount => stickers.length;

  List<String> get previewEmojis {
    final result = <String>[];

    for (final sticker in stickers) {
      if (result.length >= 4) {
        break;
      }

      if (sticker.emojis.isEmpty) {
        continue;
      }

      result.add(sticker.emojis.first);
    }

    return result;
  }

  StickerPack copyWith({
    String? id,
    String? name,
    String? author,
    List<Sticker>? stickers,
    String? trayImagePath,
  }) {
    return StickerPack(
      id: id ?? this.id,
      name: name ?? this.name,
      author: author ?? this.author,
      stickers: stickers ?? this.stickers,
      trayImagePath: trayImagePath ?? this.trayImagePath,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'author': author,
      'stickers': stickers.map((sticker) => sticker.toMap()).toList(),
      'trayImagePath': trayImagePath,
    };
  }

  factory StickerPack.fromMap(Map<String, dynamic> map) {
    return StickerPack(
      id: map['id'] as String,
      name: map['name'] as String,
      author: map['author'] as String,
      trayImagePath: map['trayImagePath'] as String?,
      stickers: (map['stickers'] as List<dynamic>)
          .map((item) => Sticker.fromMap(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
