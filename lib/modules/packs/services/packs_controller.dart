import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/local_storage_path_service.dart';
import '../../stickers/models/sticker.dart';
import '../models/sticker_pack.dart';
import 'packs_repository.dart';
import 'whatsapp_export_service.dart';

final packsRepositoryProvider = Provider<PacksRepository>((ref) {
  // On Web we cannot use file system (path_provider isn't available),
  // so use an in-memory repository for packs to avoid MissingPluginException.
  if (kIsWeb) {
    return PacksRepository.inMemory();
  }

  return PacksRepository(
    storagePathService: ref.read(localStoragePathServiceProvider),
  );
});

final packsControllerProvider =
    AsyncNotifierProvider<PacksController, List<StickerPack>>(
      PacksController.new,
    );

final packByIdProvider = Provider.family<StickerPack?, String>((ref, packId) {
  final packs =
      ref.watch(packsControllerProvider).asData?.value ?? const <StickerPack>[];

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

  Future<StickerPack> createPack({
    required String name,
    required String author,
  }) async {
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

  Future<StickerPack> addSticker({
    required String packId,
    required Sticker sticker,
  }) async {
    final repository = ref.read(packsRepositoryProvider);
    final updatedPack = await repository.addSticker(
      packId: packId,
      sticker: sticker,
    );
    state = AsyncData(await repository.fetchPacks());
    return updatedPack;
  }

  Future<void> exportPackForWhatsApp(String packId) async {
    final repository = ref.read(packsRepositoryProvider);
    await repository.exportPackForWhatsApp(packId);
    state = AsyncData(await repository.fetchPacks());

    if (!kIsWeb && Platform.isAndroid) {
      final pack = await repository.findById(packId);
      if (pack != null) {
        await ref.read(whatsappExportServiceProvider).addStickerPack(pack);
      }
    }
  }
}
