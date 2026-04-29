import 'package:uuid/uuid.dart';

import '../../stickers/models/sticker.dart';
import '../models/sticker_pack.dart';

class PacksRepository {
  PacksRepository() : _packs = _seedPacks;

  final Uuid _uuid = const Uuid();
  final List<StickerPack> _packs;

  Future<List<StickerPack>> fetchPacks() async {
    return List<StickerPack>.unmodifiable(_packs);
  }

  Future<StickerPack> createPack({required String name, required String author}) async {
    final newPack = StickerPack(
      id: _uuid.v4(),
      name: name,
      author: author,
      stickers: const [],
    );

    _packs.insert(0, newPack);
    return newPack;
  }

  Future<void> deletePack(String packId) async {
    _packs.removeWhere((pack) => pack.id == packId);
  }

  Future<StickerPack?> findById(String packId) async {
    try {
      return _packs.firstWhere((pack) => pack.id == packId);
    } on StateError {
      return null;
    }
  }

  static final List<StickerPack> _seedPacks = [
    StickerPack(
      id: 'pack-coffee-cats',
      name: 'Coffee Cats',
      author: 'Sticker Studio',
      stickers: const [
        Sticker(id: 'coffee-1', filePath: 'samples/coffee-cat-1.webp', emojis: ['☕', '😺']),
        Sticker(id: 'coffee-2', filePath: 'samples/coffee-cat-2.webp', emojis: ['😴']),
        Sticker(id: 'coffee-3', filePath: 'samples/coffee-cat-3.webp', emojis: ['🔥']),
        Sticker(id: 'coffee-4', filePath: 'samples/coffee-cat-4.webp', emojis: ['✨']),
      ],
    ),
    StickerPack(
      id: 'pack-work-mood',
      name: 'Work Mood',
      author: 'Equipe Interna',
      stickers: const [
        Sticker(id: 'work-1', filePath: 'samples/work-1.webp', emojis: ['💻']),
        Sticker(id: 'work-2', filePath: 'samples/work-2.webp', emojis: ['📈']),
        Sticker(id: 'work-3', filePath: 'samples/work-3.webp', emojis: ['😵']),
      ],
    ),
  ];
}