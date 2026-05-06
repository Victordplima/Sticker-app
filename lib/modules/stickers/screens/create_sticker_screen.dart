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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0F4FCB), Color(0xFF67A4FF)],
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A1A5EBA),
                      blurRadius: 28,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.auto_fix_high_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Criar sticker',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineMedium?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      pack == null
                          ? 'Selecione uma imagem, edite a arte e finalize o sticker.'
                          : 'Adicione um novo sticker ao pack ${pack.name}.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFFE7F1FF),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _SelectionCard(
                selectedImageBytes: _selectedImageBytes,
                selectedImageName: _selectedImageName,
                isBusy: _isPicking || _isSaving,
                onPickImage: _pickAndEditImage,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emojiController,
                decoration: const InputDecoration(
                  labelText: 'Emojis associados',
                  hintText: 'Ex.: 😂 🔥 ou 😂,🔥',
                  helperText:
                      'Use pelo menos um emoji para identificar o sticker.',
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
    final theme = Theme.of(context);
    final previewBytes = selectedImageBytes;

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
          Text('Imagem de origem', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                child: previewBytes == null
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
          if (selectedImageName != null) ...[
            Text(selectedImageName!, style: theme.textTheme.bodySmall),
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
    final theme = Theme.of(context);
    final hasImage = imageName != null;

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
          const _StepRow(text: 'Selecione uma imagem da galeria'),
          const _StepRow(text: 'Edite a arte com camadas, texto e imagens'),
          const _StepRow(text: 'Ajuste tamanho e posicionamento final'),
          const _StepRow(text: 'Informe os emojis'),
          if (hasImage) ...[
            const SizedBox(height: 12),
            Text(
              'Imagem selecionada: $imageName',
              style: theme.textTheme.bodyMedium,
            ),
          ] else ...[
            Text(
              'Escolha uma imagem para abrir o editor do sticker.',
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
