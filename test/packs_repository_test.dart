import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sticker/core/services/local_storage_path_service.dart';
import 'package:sticker/modules/packs/services/packs_repository.dart';
import 'package:sticker/modules/stickers/models/sticker.dart';

void main() {
  test('persiste pack, tray icon e contents.json em disco', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'sticker_repo_test_',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final storage = _FakeLocalStoragePathService(tempRoot);
    final repository = PacksRepository(storagePathService: storage);

    final createdPack = await repository.createPack(
      name: 'Pack Persistido',
      author: 'Teste',
    );

    final stickersDirectory = await storage.getPackStickersDirectory(
      createdPack.id,
    );

    for (var index = 1; index <= 3; index++) {
      final stickerFile = File(
        '${stickersDirectory.path}${Platform.pathSeparator}sticker-$index.png',
      );
      final image = img.Image(width: 512, height: 512, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));
      await stickerFile.writeAsBytes(img.encodePng(image), flush: true);

      await repository.addSticker(
        packId: createdPack.id,
        sticker: Sticker(
          id: 'sticker-$index',
          filePath: stickerFile.path,
          emojis: const ['🔥'],
        ),
      );
    }

    // Explicitly export pack to generate contents.json and tray image on disk.
    await repository.exportPackForWhatsApp(createdPack.id);

    final reloadedRepository = PacksRepository(storagePathService: storage);
    final packs = await reloadedRepository.fetchPacks();

    expect(packs, hasLength(1));
    expect(packs.single.name, 'Pack Persistido');
    expect(packs.single.stickers, hasLength(3));
    expect(packs.single.trayImagePath, isNotNull);

    final metadataFile = await storage.getPackMetadataFile(createdPack.id);
    final contentsFile = await storage.getPackContentsFile(createdPack.id);
    final trayFile = await storage.getPackTrayImageFile(createdPack.id);

    expect(metadataFile.existsSync(), isTrue);
    expect(contentsFile.existsSync(), isTrue);
    expect(trayFile.existsSync(), isTrue);
  });
}

class _FakeLocalStoragePathService extends LocalStoragePathService {
  _FakeLocalStoragePathService(this.rootDirectory);

  final Directory rootDirectory;

  @override
  Future<Directory> getAppWorkspaceDirectory() async {
    if (!await rootDirectory.exists()) {
      await rootDirectory.create(recursive: true);
    }
    return rootDirectory;
  }
}
