import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/helpers/emoji_helper.dart';
import '../../packs/services/packs_controller.dart';
import '../components/sticker_preview_tile.dart';
import '../models/sticker.dart';
import 'sticker_editor_screen.dart';
import '../services/sticker_creation_service.dart';

class CreateStickerScreen extends ConsumerStatefulWidget {
  const CreateStickerScreen({required this.packId, super.key});

  final String packId;

  @override
  ConsumerState<CreateStickerScreen> createState() =>
      _CreateStickerScreenState();
}

class _CreateStickerScreenState extends ConsumerState<CreateStickerScreen> {
  final ImagePicker _picker = ImagePicker();

  Uint8List? _selectedImageBytes;
  Uint8List? _selectedGifPreviewBytes;
  String? _selectedMediaPath;
  String? _selectedMediaName;
  _SelectedStickerSourceType? _selectedSourceType;
  Sticker? _previewSticker;
  bool _isPicking = false;
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final pack = ref.watch(packByIdProvider(widget.packId));

    return Scaffold(
      appBar: AppBar(title: const Text('Criar sticker')),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.surface,
              const Color(0xFFEAF2FF),
            ],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (pack != null && pack.name.trim().isNotEmpty) ...[
                Text(
                  'Pack: ${pack.name}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
              ],
              _SelectionCard(
                selectedPreviewBytes:
                    _selectedSourceType ==
                        _SelectedStickerSourceType.staticImage
                    ? _selectedImageBytes
                    : _selectedGifPreviewBytes,
                selectedMediaName: _selectedMediaName,
                selectedSourceType: _selectedSourceType,
                isBusy: _isPicking || _isSaving,
                onPickImage: _pickAndEditImage,
                onPickGif: _pickAnimatedGif,
                onPickVideo: _pickAnimatedVideo,
              ),
              const SizedBox(height: 16),
              _PipelineInfo(
                mediaName: _selectedMediaName,
                sourceType: _selectedSourceType,
              ),
              const SizedBox(height: 24),
              if (_previewSticker != null) ...[
                Text(
                  'Preview do sticker gerado',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 180,
                  child: StickerPreviewTile(sticker: _previewSticker!),
                ),
                const SizedBox(height: 24),
              ],
              SizedBox(
                width: double.infinity,
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _canSave ? _saveSticker : null,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high_rounded),
                    label: Text(
                      _isSaving
                          ? 'Gerando sticker...'
                          : 'Gerar e adicionar ao pack',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canSave => !_isSaving && !_isPicking && _hasSelectedSource;

  bool get _hasSelectedSource {
    if (_selectedSourceType == _SelectedStickerSourceType.staticImage) {
      return _selectedImageBytes != null;
    }

    if (_selectedSourceType == _SelectedStickerSourceType.animatedGif ||
        _selectedSourceType == _SelectedStickerSourceType.animatedVideo) {
      return _selectedMediaPath != null;
    }

    return false;
  }

  bool get _hasAnimatedSelection =>
      _selectedSourceType == _SelectedStickerSourceType.animatedGif ||
      _selectedSourceType == _SelectedStickerSourceType.animatedVideo;

  List<String> get _parsedEmojis {
    return const [EmojiHelper.defaultStickerEmoji];
  }

  Future<void> _pickAndEditImage() async {
    if (_isPicking) {
      return;
    }

    setState(() {
      _isPicking = true;
    });

    try {
      final source = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );

      if (source == null) {
        return;
      }

      if (!mounted) {
        return;
      }

      final sourceBytes = await source.readAsBytes();
      if (!mounted) {
        return;
      }

      final editedBytes = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          builder: (context) => StickerEditorScreen(
            initialBytes: sourceBytes,
            imageName: source.name,
          ),
        ),
      );

      if (editedBytes == null || !mounted) {
        return;
      }

      setState(() {
        _selectedImageBytes = editedBytes;
        _selectedGifPreviewBytes = null;
        _selectedMediaPath = null;
        _selectedMediaName = source.name;
        _selectedSourceType = _SelectedStickerSourceType.staticImage;
        _previewSticker = null;
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao selecionar a imagem: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  Future<void> _pickAnimatedGif() async {
    await _pickAnimatedMedia(
      sourceType: _SelectedStickerSourceType.animatedGif,
      pickSource: () => _picker.pickImage(source: ImageSource.gallery),
      previewGif: true,
    );
  }

  Future<void> _pickAnimatedVideo() async {
    await _pickAnimatedMedia(
      sourceType: _SelectedStickerSourceType.animatedVideo,
      pickSource: () => _picker.pickVideo(source: ImageSource.gallery),
      previewGif: false,
    );
  }

  Future<void> _pickAnimatedMedia({
    required _SelectedStickerSourceType sourceType,
    required Future<XFile?> Function() pickSource,
    required bool previewGif,
  }) async {
    if (_isPicking) {
      return;
    }

    setState(() {
      _isPicking = true;
    });

    try {
      final source = await pickSource();
      if (source == null || !mounted) {
        return;
      }

      final creationService = ref.read(stickerCreationServiceProvider);
      if (!creationService.supportsAnimatedSource(source.path) &&
          !creationService.supportsAnimatedSource(source.name)) {
        final typeLabel = sourceType == _SelectedStickerSourceType.animatedGif
            ? 'GIF'
            : 'video';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Selecione um $typeLabel valido.')),
        );
        return;
      }

      Uint8List? previewBytes;
      if (previewGif) {
        previewBytes = await source.readAsBytes();
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedImageBytes = null;
        _selectedGifPreviewBytes = previewBytes;
        _selectedMediaPath = source.path;
        _selectedMediaName = source.name;
        _selectedSourceType = sourceType;
        _previewSticker = null;
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao selecionar a midia: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  Future<void> _saveSticker() async {
    if (!_hasSelectedSource) {
      return;
    }

    final emojis = _parsedEmojis;
    final pack = ref.read(packByIdProvider(widget.packId));
    final containsAnimated =
        pack?.stickers.any((sticker) => sticker.isAnimated) ?? false;
    final containsStatic =
        pack?.stickers.any((sticker) => !sticker.isAnimated) ?? false;
    if (_hasAnimatedSelection && containsStatic) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'O WhatsApp nao aceita misturar stickers animados e estaticos no mesmo pack.',
          ),
        ),
      );
      return;
    }
    if (!_hasAnimatedSelection && containsAnimated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este pack ja possui stickers animados. Crie outro pack para stickers estaticos.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final creationService = ref.read(stickerCreationServiceProvider);
      final sticker = _hasAnimatedSelection
          ? await creationService.createAnimatedSticker(
              packId: widget.packId,
              sourcePath: _selectedMediaPath!,
              sourceName: _selectedMediaName,
              emojis: emojis,
            )
          : await creationService.createSticker(
              packId: widget.packId,
              sourceBytes: _selectedImageBytes!,
              emojis: emojis,
            );

      await ref
          .read(packsControllerProvider.notifier)
          .addSticker(packId: widget.packId, sticker: sticker);

      if (!mounted) {
        return;
      }

      setState(() {
        _previewSticker = sticker;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sticker criado e adicionado ao pack.')),
      );
      Navigator.of(context).pop();
    } on StickerCreationException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao gerar o sticker: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}

class _SelectionCard extends StatelessWidget {
  const _SelectionCard({
    required this.selectedPreviewBytes,
    required this.selectedMediaName,
    required this.selectedSourceType,
    required this.isBusy,
    required this.onPickImage,
    required this.onPickGif,
    required this.onPickVideo,
  });

  final Uint8List? selectedPreviewBytes;
  final String? selectedMediaName;
  final _SelectedStickerSourceType? selectedSourceType;
  final bool isBusy;
  final Future<void> Function() onPickImage;
  final Future<void> Function() onPickGif;
  final Future<void> Function() onPickVideo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewBytes = selectedPreviewBytes;
    final isVideo =
        selectedSourceType == _SelectedStickerSourceType.animatedVideo;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F1A4E93),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Midia de origem', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                child: isVideo
                    ? Center(
                        child: Icon(
                          Icons.movie_creation_outlined,
                          size: 54,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : previewBytes == null
                    ? Center(
                        child: Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 54,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : Image.memory(previewBytes, fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (selectedMediaName != null) ...[
            Text(selectedMediaName!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: isBusy ? null : onPickImage,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Imagem'),
              ),
              OutlinedButton.icon(
                onPressed: isBusy ? null : onPickGif,
                icon: const Icon(Icons.gif_box_outlined),
                label: const Text('GIF'),
              ),
              OutlinedButton.icon(
                onPressed: isBusy ? null : onPickVideo,
                icon: const Icon(Icons.video_library_outlined),
                label: const Text('Video'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PipelineInfo extends StatelessWidget {
  const _PipelineInfo({required this.mediaName, required this.sourceType});

  final String? mediaName;
  final _SelectedStickerSourceType? sourceType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasMedia = mediaName != null;
    final selectedLabel = switch (sourceType) {
      _SelectedStickerSourceType.staticImage => 'Imagem selecionada',
      _SelectedStickerSourceType.animatedGif => 'GIF selecionado',
      _SelectedStickerSourceType.animatedVideo => 'Video selecionado',
      null => 'Midia selecionada',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Status', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          const _StepRow(text: 'Selecione imagem, GIF ou video da galeria'),
          const _StepRow(text: 'Imagem estatica abre o editor de arte'),
          const _StepRow(text: 'GIF e video viram WEBP animado 512x512'),
          if (hasMedia) ...[
            const SizedBox(height: 12),
            Text(
              '$selectedLabel: $mediaName',
              style: theme.textTheme.bodyMedium,
            ),
          ] else ...[
            Text(
              'Escolha uma midia para criar o sticker.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.check_circle_outline_rounded, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

enum _SelectedStickerSourceType { staticImage, animatedGif, animatedVideo }
