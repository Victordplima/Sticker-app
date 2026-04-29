import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/sticker_pack.dart';
import 'packs_repository.dart';

final packsRepositoryProvider = Provider<PacksRepository>((ref) {
  return PacksRepository();
});

final packsControllerProvider = AsyncNotifierProvider<PacksController, List<StickerPack>>(
  PacksController.new,
);

final packByIdProvider = Provider.family<StickerPack?, String>((ref, packId) {
  final packs = ref.watch(packsControllerProvider).valueOrNull ?? const <StickerPack>[];

  for (final pack in packs) {
    if (pack.id == packId) {
      return pack;
    }
  }

  return null;
});

class PacksController extends AsyncNotifier<List<StickerPack>> {
  @override
  Future<List<StickerPack>> build() {
    return ref.read(packsRepositoryProvider).fetchPacks();
  }

  Future<StickerPack> createPack({required String name, required String author}) async {
    final repository = ref.read(packsRepositoryProvider);
    final createdPack = await repository.createPack(name: name, author: author);
    state = AsyncData(await repository.fetchPacks());
    return createdPack;
  }

  Future<void> removePack(String packId) async {
    final repository = ref.read(packsRepositoryProvider);
    await repository.deletePack(packId);
    state = AsyncData(await repository.fetchPacks());
  }
}