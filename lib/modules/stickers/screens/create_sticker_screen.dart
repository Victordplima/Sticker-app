import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/helpers/emoji_helper.dart';
import '../../packs/services/packs_controller.dart';
import '../components/sticker_preview_tile.dart';
import '../models/sticker.dart';
import '../services/sticker_creation_service.dart';

class CreateStickerScreen extends ConsumerStatefulWidget {
  const CreateStickerScreen({required this.packId, super.key});

  final String packId;

  @override
  ConsumerState<CreateStickerScreen> createState() =>
      _CreateStickerScreenState();
}

class _CreateStickerScreenState extends ConsumerState<CreateStickerScreen> {
  final _emojiController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  Sticker? _previewSticker;
  bool _isPicking = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _emojiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pack = ref.watch(packByIdProvider(widget.packId));

    return Scaffold(
      appBar: AppBar(title: const Text('Criar sticker')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Novo sticker para ${pack?.name ?? 'pack'}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Selecione uma imagem da galeria, recorte em proporcao 1:1 e gere automaticamente o arquivo final em WEBP 512x512.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            _SelectionCard(
              selectedImageBytes: _selectedImageBytes,
              selectedImageName: _selectedImageName,
              isBusy: _isPicking || _isSaving,
              onPickImage: _pickAndCropImage,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emojiController,
              decoration: const InputDecoration(
                labelText: 'Emojis associados',
                hintText: 'Ex.: 😂 🔥 ou 😂,🔥',
                helperText: 'O primeiro emoji vira o principal do preview.',
              ),
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 16),
            _PipelineInfo(imageName: _selectedImageName),
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
    );
  }

  bool get _canSave =>
      !_isSaving &&
      !_isPicking &&
      _selectedImageBytes != null &&
      _parsedEmojis.isNotEmpty;

  List<String> get _parsedEmojis {
    final raw = _emojiController.text
        .split(RegExp(r'[\s,;]+'))
        .where((item) => item.trim().isNotEmpty)
        .toList();
    return EmojiHelper.sanitize(raw);
  }

  Future<void> _pickAndCropImage() async {
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

      final croppedBytes = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(
          builder: (context) => StickerCropScreen(
            initialBytes: sourceBytes,
            imageName: source.name,
          ),
        ),
      );

      if (croppedBytes == null || !mounted) {
        return;
      }

      setState(() {
        _selectedImageBytes = croppedBytes;
        _selectedImageName = source.name;
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

  Future<void> _saveSticker() async {
    final sourceBytes = _selectedImageBytes;
    if (sourceBytes == null) {
      return;
    }

    final emojis = _parsedEmojis;
    if (emojis.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe ao menos um emoji para o sticker.'),
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final creationService = ref.read(stickerCreationServiceProvider);
      final sticker = await creationService.createSticker(
        packId: widget.packId,
        sourceBytes: sourceBytes,
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
    required this.selectedImageBytes,
    required this.selectedImageName,
    required this.isBusy,
    required this.onPickImage,
  });

  final Uint8List? selectedImageBytes;
  final String? selectedImageName;
  final bool isBusy;
  final Future<void> Function() onPickImage;

  @override
  Widget build(BuildContext context) {
    final previewBytes = selectedImageBytes;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Imagem de origem',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: previewBytes == null
                    ? const Center(
                        child: Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 54,
                        ),
                      )
                    : Image.memory(previewBytes, fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (selectedImageName != null) ...[
            Text(
              selectedImageName!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: isBusy ? null : onPickImage,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(
              previewBytes == null ? 'Selecionar da galeria' : 'Trocar imagem',
            ),
          ),
        ],
      ),
    );
  }
}

class _PipelineInfo extends StatelessWidget {
  const _PipelineInfo({required this.imageName});

  final String? imageName;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageName != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pipeline aplicado',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          const _StepRow(text: '1. Galeria com image_picker'),
          const _StepRow(text: '2. Crop quadrado com crop_your_image'),
          const _StepRow(text: '3. Resize em canvas 512x512 com image'),
          const _StepRow(
            text: '4. Compressao final WEBP com flutter_image_compress',
          ),
          if (hasImage) ...[
            const SizedBox(height: 12),
            Text(
              'Arquivo pronto para processamento: $imageName',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class StickerCropScreen extends StatefulWidget {
  const StickerCropScreen({
    required this.initialBytes,
    required this.imageName,
    super.key,
  });

  final Uint8List initialBytes;
  final String imageName;

  @override
  State<StickerCropScreen> createState() => _StickerCropScreenState();
}

class _StickerCropScreenState extends State<StickerCropScreen> {
  final CropController _cropController = CropController();
  bool _isCropping = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recortar sticker')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ajuste o enquadramento em 1:1',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Arraste e redimensione a area para definir exatamente o sticker final.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: ColoredBox(
                    color: const Color(0xFF241C17),
                    child: Crop(
                      controller: _cropController,
                      image: widget.initialBytes,
                      aspectRatio: 1,
                      fixCropRect: true,
                      radius: 24,
                      maskColor: Colors.black.withValues(alpha: 0.48),
                      baseColor: const Color(0xFF241C17),
                      onCropped: (result) {
                        switch (result) {
                          case CropSuccess(:final croppedImage):
                            Navigator.of(context).pop(croppedImage);
                          case CropFailure(:final cause):
                            setState(() {
                              _isCropping = false;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Falha ao recortar a imagem: $cause',
                                ),
                              ),
                            );
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isCropping
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isCropping
                            ? null
                            : () {
                                setState(() {
                                  _isCropping = true;
                                });
                                _cropController.crop();
                              },
                        child: _isCropping
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Aplicar recorte'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
