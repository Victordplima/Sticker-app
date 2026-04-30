import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final localStoragePathServiceProvider = Provider<LocalStoragePathService>((
  ref,
) {
  return const LocalStoragePathService();
});

class LocalStoragePathService {
  const LocalStoragePathService();

  static const _packsFolder = 'packs';
  static const _stickersFolder = 'stickers';
  static const _metadataFileName = 'pack.json';
  static const _whatsAppContentsFileName = 'contents.json';
  static const _trayFileName = 'tray.png';

  Future<Directory> getAppWorkspaceDirectory() async {
    final baseDirectory = await getApplicationSupportDirectory();
    final workspaceDirectory = Directory(
      '${baseDirectory.path}${Platform.pathSeparator}sticker_studio',
    );

    if (!await workspaceDirectory.exists()) {
      await workspaceDirectory.create(recursive: true);
    }

    return workspaceDirectory;
  }

  Future<Directory> getPacksDirectory() async {
    final workspaceDirectory = await getAppWorkspaceDirectory();
    final packsDirectory = Directory(
      '${workspaceDirectory.path}${Platform.pathSeparator}$_packsFolder',
    );

    if (!await packsDirectory.exists()) {
      await packsDirectory.create(recursive: true);
    }

    return packsDirectory;
  }

  Future<Directory> getStickersDirectory() async {
    final workspaceDirectory = await getAppWorkspaceDirectory();
    final stickersDirectory = Directory(
      '${workspaceDirectory.path}${Platform.pathSeparator}$_stickersFolder',
    );

    if (!await stickersDirectory.exists()) {
      await stickersDirectory.create(recursive: true);
    }

    return stickersDirectory;
  }

  Future<Directory> getPackDirectory(String packId) async {
    final packsDirectory = await getPacksDirectory();
    final packDirectory = Directory(
      '${packsDirectory.path}${Platform.pathSeparator}$packId',
    );

    if (!await packDirectory.exists()) {
      await packDirectory.create(recursive: true);
    }

    return packDirectory;
  }

  Future<Directory> getPackStickersDirectory(String packId) async {
    final packDirectory = await getPackDirectory(packId);
    final stickersDirectory = Directory(
      '${packDirectory.path}${Platform.pathSeparator}$_stickersFolder',
    );

    if (!await stickersDirectory.exists()) {
      await stickersDirectory.create(recursive: true);
    }

    return stickersDirectory;
  }

  Future<File> getPackMetadataFile(String packId) async {
    final packDirectory = await getPackDirectory(packId);
    return File(
      '${packDirectory.path}${Platform.pathSeparator}$_metadataFileName',
    );
  }

  Future<File> getPackContentsFile(String packId) async {
    final packDirectory = await getPackDirectory(packId);
    return File(
      '${packDirectory.path}${Platform.pathSeparator}$_whatsAppContentsFileName',
    );
  }

  Future<File> getPackTrayImageFile(String packId) async {
    final packDirectory = await getPackDirectory(packId);
    return File('${packDirectory.path}${Platform.pathSeparator}$_trayFileName');
  }

  Future<void> deletePackDirectory(String packId) async {
    final packDirectory = Directory(
      '${(await getPacksDirectory()).path}${Platform.pathSeparator}$packId',
    );

    if (await packDirectory.exists()) {
      await packDirectory.delete(recursive: true);
    }
  }
}
