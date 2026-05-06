import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

// ═══════════════════════════════════════════════════════════════════════════
// History snapshot
// ═══════════════════════════════════════════════════════════════════════════

class _EditorSnapshot {
  const _EditorSnapshot({
    required this.layers,
    required this.selectedLayerId,
    required this.backgroundOffset,
    required this.backgroundScale,
    required this.backgroundRotation,
    required this.backgroundFlipX,
    required this.backgroundFlipY,
  });

  final List<_StickerLayer> layers;
  final String? selectedLayerId;
  final Offset backgroundOffset;
  final double backgroundScale;
  final double backgroundRotation;
  final bool backgroundFlipX;
  final bool backgroundFlipY;
}

// ═══════════════════════════════════════════════════════════════════════════
// Screen
// ═══════════════════════════════════════════════════════════════════════════

class StickerEditorScreen extends StatefulWidget {
  const StickerEditorScreen({
    required this.initialBytes,
    required this.imageName,
    super.key,
  });

  final Uint8List initialBytes;
  final String imageName;

  @override
  State<StickerEditorScreen> createState() => _StickerEditorScreenState();
}

class _StickerEditorScreenState extends State<StickerEditorScreen> {
  static const double _minScale = 0.05;
  static const double _maxScale = 12;
  static const int _maxHistory = 50;
  static const List<Color> _textPalette = [
    Color(0xFFFFFFFF),
    Color(0xFF111827),
    Color(0xFF0F4FCB),
    Color(0xFFE85D04),
    Color(0xFF2A9D8F),
    Color(0xFFD7263D),
  ];

  final GlobalKey _canvasKey = GlobalKey();
  final GlobalKey _backgroundKey = GlobalKey();
  final ImagePicker _picker = ImagePicker();

  // ── History ──────────────────────────────────────────────────────────────
  final List<_EditorSnapshot> _undoStack = [];
  final List<_EditorSnapshot> _redoStack = [];

  // ── Layers ────────────────────────────────────────────────────────────────
  List<_StickerLayer> _layers = [];
  String? _selectedLayerId;
  int _nextLayerId = 0;
  bool _isExporting = false;
  bool _isPickingOverlay = false;

  // ── Background transform ──────────────────────────────────────────────────
  Offset _backgroundOffset = Offset.zero;
  double _backgroundScale = 1;
  double _backgroundRotation = 0;
  bool _backgroundFlipX = false;
  bool _backgroundFlipY = false;

  // ── Gesture tracking ──────────────────────────────────────────────────────
  double _gestureStartBackgroundRotation = 0;
  double _gestureStartBackgroundDistance = 0;
  double _backgroundHandleStartAngle = 0;
  Offset _gestureStartFocalPoint = Offset.zero;
  Offset _gestureStartOffset = Offset.zero;
  double _gestureStartScale = 1;
  double _gestureStartScaleX = 1;
  double _gestureStartScaleY = 1;
  double _gestureStartLayerRotation = 0;

  // ── Inspector tab ─────────────────────────────────────────────────────────
  int _inspectorTab = 0; // 0 = camada, 1 = fundo

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final selectedLayer = _selectedLayer;
    final canUndo = _undoStack.isNotEmpty;
    final canRedo = _redoStack.isNotEmpty;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: const Text('Editor de sticker'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: theme.colorScheme.onSurface,
        actions: [
          _UndoRedoButton(
            icon: Icons.undo_rounded,
            tooltip: 'Desfazer',
            onPressed: canUndo ? _undo : null,
          ),
          _UndoRedoButton(
            icon: Icons.redo_rounded,
            tooltip: 'Refazer',
            onPressed: canRedo ? _redo : null,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  RepaintBoundary(
                    key: _canvasKey,
                    child: _EditorCanvas(
                      baseImageBytes: widget.initialBytes,
                      backgroundOffset: _backgroundOffset,
                      backgroundScale: _backgroundScale,
                      backgroundRotation: _backgroundRotation,
                      backgroundFlipX: _backgroundFlipX,
                      backgroundFlipY: _backgroundFlipY,
                      backgroundKey: _backgroundKey,
                      layers: _layers,
                      selectedLayerId: _selectedLayerId,
                      showSelection: !_isExporting,
                      onBackgroundScaleStart: _onBackgroundScaleStart,
                      onBackgroundScaleUpdate: _onBackgroundScaleUpdate,
                      onBackgroundHandleStart: _onBackgroundHandleStart,
                      onBackgroundHandleUpdate: _onBackgroundHandleUpdate,
                      onBackgroundHandleEnd: _onBackgroundHandleEnd,
                      onTapCanvas: _deselectLayer,
                      onLayerTap: _selectLayer,
                      onLayerScaleStart: _onLayerScaleStart,
                      onLayerScaleUpdate: _onLayerScaleUpdate,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _EditorToolbar(
                    isBusy: _isExporting || _isPickingOverlay,
                    hasSelectedLayer: selectedLayer != null,
                    hasSelectedTextLayer:
                        selectedLayer?.type == _StickerLayerType.text,
                    canBringForward: selectedLayer != null &&
                        _layers.indexOf(selectedLayer) < _layers.length - 1,
                    canSendBackward: selectedLayer != null &&
                        _layers.indexOf(selectedLayer) > 0,
                    onAddText: _addTextLayer,
                    onEditText: _editSelectedTextLayer,
                    onAddImage: _addOverlayImage,
                    onDuplicateLayer: _duplicateSelectedLayer,
                    onRemoveLayer: _removeSelectedLayer,
                    onFlipHorizontal: _flipSelectedLayerHorizontal,
                    onFlipVertical: _flipSelectedLayerVertical,
                    onRotateCCW: _rotateSelectedLayerCCW,
                    onRotateCW: _rotateSelectedLayerCW,
                    onBringForward: _bringLayerForward,
                    onSendBackward: _sendLayerBackward,
                    onResetBackground: _resetBackground,
                    onRotateBackgroundCCW: _rotateBackgroundCCW,
                    onRotateBackgroundCW: _rotateBackgroundCW,
                    onFlipBackgroundHorizontal: _flipBackgroundHorizontal,
                    onFlipBackgroundVertical: _flipBackgroundVertical,
                  ),
                  const SizedBox(height: 12),
                  _EditorInspector(
                    tab: _inspectorTab,
                    onTabChanged: (t) => setState(() => _inspectorTab = t),
                    isLayerSelected: selectedLayer != null,
                    layerType: selectedLayer?.type,
                    layerScaleValue: selectedLayer?.scale ?? 1.0,
                    layerRotationValue: selectedLayer?.rotation ?? 0.0,
                    layerOpacityValue: selectedLayer?.opacity ?? 1.0,
                    onLayerScaleChanged:
                        selectedLayer != null ? _updateLayerScale : null,
                    onLayerRotationChanged:
                        selectedLayer != null ? _updateLayerRotation : null,
                    onLayerOpacityChanged:
                        selectedLayer != null ? _updateLayerOpacity : null,
                    bgScaleValue: _backgroundScale,
                    bgRotationValue: _backgroundRotation,
                    onBgScaleChanged: _updateBgScale,
                    onBgRotationChanged: _updateBgRotation,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          _ExportBar(
            isExporting: _isExporting,
            onCancel: () => Navigator.of(context).pop(),
            onExport: _exportComposition,
          ),
        ],
      ),
    );
  }

  // ── Undo / Redo ───────────────────────────────────────────────────────────

  _EditorSnapshot _snap() => _EditorSnapshot(
        layers: List.from(_layers),
        selectedLayerId: _selectedLayerId,
        backgroundOffset: _backgroundOffset,
        backgroundScale: _backgroundScale,
        backgroundRotation: _backgroundRotation,
        backgroundFlipX: _backgroundFlipX,
        backgroundFlipY: _backgroundFlipY,
      );

  void _pushHistory() {
    _redoStack.clear();
    _undoStack.add(_snap());
    if (_undoStack.length > _maxHistory) _undoStack.removeAt(0);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_snap());
    _restoreSnapshot(_undoStack.removeLast());
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_snap());
    _restoreSnapshot(_redoStack.removeLast());
  }

  void _restoreSnapshot(_EditorSnapshot s) {
    setState(() {
      _layers = List.from(s.layers);
      _selectedLayerId = s.selectedLayerId;
      _backgroundOffset = s.backgroundOffset;
      _backgroundScale = s.backgroundScale;
      _backgroundRotation = s.backgroundRotation;
      _backgroundFlipX = s.backgroundFlipX;
      _backgroundFlipY = s.backgroundFlipY;
    });
  }

  // ── Layer helpers ─────────────────────────────────────────────────────────

  _StickerLayer? get _selectedLayer {
    final id = _selectedLayerId;
    if (id == null) return null;
    for (final l in _layers) {
      if (l.id == id) return l;
    }
    return null;
  }

  void _selectLayer(String id) => setState(() => _selectedLayerId = id);
  void _deselectLayer() => setState(() => _selectedLayerId = null);

  _StickerLayer? _layerById(String id) {
    for (final l in _layers) {
      if (l.id == id) return l;
    }
    return null;
  }

  void _updateLayer(String id, _StickerLayer Function(_StickerLayer) fn) {
    final index = _layers.indexWhere((l) => l.id == id);
    if (index < 0) return;
    setState(() {
      _layers[index] = fn(_layers[index]);
      _selectedLayerId = id;
    });
  }

  String _nextLayerKey() => 'layer_${++_nextLayerId}';

  // ── Background gestures ───────────────────────────────────────────────────

  void _onBackgroundScaleStart(ScaleStartDetails d) {
    _pushHistory();
    _gestureStartFocalPoint = d.focalPoint;
    _gestureStartOffset = _backgroundOffset;
    _gestureStartScale = _backgroundScale;
    _gestureStartBackgroundRotation = _backgroundRotation;
  }

  void _onBackgroundScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      _backgroundOffset =
          _gestureStartOffset + (d.focalPoint - _gestureStartFocalPoint);
      _backgroundScale =
          (_gestureStartScale * d.scale).clamp(_minScale, _maxScale);
      _backgroundRotation = _gestureStartBackgroundRotation + d.rotation;
    });
  }

  void _onBackgroundHandleStart(DragStartDetails d, String kind) {
    _pushHistory();
    final render =
        _backgroundKey.currentContext?.findRenderObject() as RenderBox?;
    if (render == null) return;
    final center = render.localToGlobal(render.size.center(Offset.zero));
    _backgroundHandleStartAngle = math.atan2(
      d.globalPosition.dy - center.dy,
      d.globalPosition.dx - center.dx,
    );
    _gestureStartBackgroundRotation = _backgroundRotation;
    _gestureStartBackgroundDistance = (d.globalPosition - center).distance;
    _gestureStartScale = _backgroundScale;
  }

  void _onBackgroundHandleUpdate(DragUpdateDetails d, String kind) {
    final render =
        _backgroundKey.currentContext?.findRenderObject() as RenderBox?;
    if (render == null) return;
    final center = render.localToGlobal(render.size.center(Offset.zero));
    if (kind == 'rotate') {
      final angle = math.atan2(
        d.globalPosition.dy - center.dy,
        d.globalPosition.dx - center.dx,
      );
      setState(() => _backgroundRotation =
          _gestureStartBackgroundRotation +
              (angle - _backgroundHandleStartAngle));
    } else if (kind == 'scale') {
      final dist = (d.globalPosition - center).distance;
      if (_gestureStartBackgroundDistance > 0) {
        setState(() => _backgroundScale =
            (_gestureStartScale * dist / _gestureStartBackgroundDistance)
                .clamp(_minScale, _maxScale));
      }
    }
  }

  void _onBackgroundHandleEnd(DragEndDetails d, String kind) {}

  // ── Layer gestures ────────────────────────────────────────────────────────

  void _onLayerScaleStart(String id, ScaleStartDetails d) {
    final layer = _layerById(id);
    if (layer == null) return;
    _pushHistory();
    _selectLayer(id);
    _gestureStartFocalPoint = d.focalPoint;
    _gestureStartOffset = layer.offset;
    _gestureStartScaleX = layer.scaleX;
    _gestureStartScaleY = layer.scaleY;
    _gestureStartScale = layer.scale;
    _gestureStartLayerRotation = layer.rotation;
  }

  void _onLayerScaleUpdate(String id, ScaleUpdateDetails d) {
    if (_layerById(id) == null) return;
    _updateLayer(
      id,
      (c) => c.copyWith(
        offset: _gestureStartOffset + (d.focalPoint - _gestureStartFocalPoint),
        scaleX: (_gestureStartScaleX * d.scale).clamp(-_maxScale, _maxScale),
        scaleY: (_gestureStartScaleY * d.scale).clamp(-_maxScale, _maxScale),
        rotation: _gestureStartLayerRotation + d.rotation,
      ),
    );
  }

  // ── Discrete layer actions ────────────────────────────────────────────────

  Future<void> _addTextLayer() async {
    final draft = await _showTextLayerDialog();
    if (draft == null || draft.text.trim().isEmpty || !mounted) return;
    _pushHistory();
    final layer = _StickerLayer.text(
      id: _nextLayerKey(),
      text: draft.text.trim(),
      color: draft.color,
      backgroundColor: draft.backgroundColor,
      fontSize: draft.fontSize,
      offset: Offset.zero,
      scale: 1,
    );
    setState(() {
      _layers.add(layer);
      _selectedLayerId = layer.id;
    });
  }

  Future<void> _editSelectedTextLayer() async {
    final sel = _selectedLayer;
    if (sel == null || sel.type != _StickerLayerType.text) return;
    final draft = await _showTextLayerDialog(
      initial: _TextLayerDraft(
        text: sel.text ?? '',
        color: sel.color,
        backgroundColor: sel.backgroundColor,
        fontSize: sel.fontSize,
      ),
    );
    if (draft == null || !mounted) return;
    _pushHistory();
    _updateLayer(
      sel.id,
      (c) => c.copyWith(
        text: draft.text.trim(),
        color: draft.color,
        backgroundColor: draft.backgroundColor,
        fontSize: draft.fontSize,
      ),
    );
  }

  Future<void> _addOverlayImage() async {
    if (_isPickingOverlay) return;
    setState(() => _isPickingOverlay = true);
    try {
      final source = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (source == null || !mounted) return;
      final bytes = await source.readAsBytes();
      if (!mounted) return;
      _pushHistory();
      final layer = _StickerLayer.image(
        id: _nextLayerKey(),
        imageBytes: bytes,
        offset: Offset.zero,
        scale: 1,
      );
      setState(() {
        _layers.add(layer);
        _selectedLayerId = layer.id;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao adicionar imagem: $e')),
      );
    } finally {
      if (mounted) setState(() => _isPickingOverlay = false);
    }
  }

  void _duplicateSelectedLayer() {
    final sel = _selectedLayer;
    if (sel == null) return;
    _pushHistory();
    final dup = sel
        .duplicateWithId(_nextLayerKey())
        .copyWith(offset: sel.offset + const Offset(18, 18));
    setState(() {
      final idx = _layers.indexOf(sel);
      _layers.insert(idx + 1, dup);
      _selectedLayerId = dup.id;
    });
  }

  void _removeSelectedLayer() {
    final id = _selectedLayerId;
    if (id == null) return;
    _pushHistory();
    setState(() {
      _layers.removeWhere((l) => l.id == id);
      _selectedLayerId = null;
    });
  }

  void _flipSelectedLayerHorizontal() {
    final sel = _selectedLayer;
    if (sel == null) return;
    _pushHistory();
    _updateLayer(sel.id, (c) => c.copyWith(scaleX: -c.scaleX));
  }

  void _flipSelectedLayerVertical() {
    final sel = _selectedLayer;
    if (sel == null) return;
    _pushHistory();
    _updateLayer(sel.id, (c) => c.copyWith(scaleY: -c.scaleY));
  }

  void _rotateSelectedLayerCW() {
    final sel = _selectedLayer;
    if (sel == null) return;
    _pushHistory();
    _updateLayer(
        sel.id, (c) => c.copyWith(rotation: c.rotation + math.pi / 2));
  }

  void _rotateSelectedLayerCCW() {
    final sel = _selectedLayer;
    if (sel == null) return;
    _pushHistory();
    _updateLayer(
        sel.id, (c) => c.copyWith(rotation: c.rotation - math.pi / 2));
  }

  void _bringLayerForward() {
    final sel = _selectedLayer;
    if (sel == null) return;
    final idx = _layers.indexOf(sel);
    if (idx >= _layers.length - 1) return;
    _pushHistory();
    setState(() {
      _layers.removeAt(idx);
      _layers.insert(idx + 1, sel);
    });
  }

  void _sendLayerBackward() {
    final sel = _selectedLayer;
    if (sel == null) return;
    final idx = _layers.indexOf(sel);
    if (idx <= 0) return;
    _pushHistory();
    setState(() {
      _layers.removeAt(idx);
      _layers.insert(idx - 1, sel);
    });
  }

  // ── Background discrete ───────────────────────────────────────────────────

  void _resetBackground() {
    _pushHistory();
    setState(() {
      _backgroundOffset = Offset.zero;
      _backgroundScale = 1;
      _backgroundRotation = 0;
      _backgroundFlipX = false;
      _backgroundFlipY = false;
      _selectedLayerId = null;
    });
  }

  void _rotateBackgroundCW() {
    _pushHistory();
    setState(() => _backgroundRotation += math.pi / 2);
  }

  void _rotateBackgroundCCW() {
    _pushHistory();
    setState(() => _backgroundRotation -= math.pi / 2);
  }

  void _flipBackgroundHorizontal() {
    _pushHistory();
    setState(() => _backgroundFlipX = !_backgroundFlipX);
  }

  void _flipBackgroundVertical() {
    _pushHistory();
    setState(() => _backgroundFlipY = !_backgroundFlipY);
  }

  // ── Inspector value updates ───────────────────────────────────────────────

  void _updateLayerScale(double v) {
    final sel = _selectedLayer;
    if (sel == null) return;
    _updateLayer(
        sel.id, (c) => c.copyWith(scale: v.clamp(_minScale, _maxScale)));
  }

  void _updateLayerRotation(double v) {
    final sel = _selectedLayer;
    if (sel == null) return;
    _updateLayer(sel.id, (c) => c.copyWith(rotation: v));
  }

  void _updateLayerOpacity(double v) {
    final sel = _selectedLayer;
    if (sel == null) return;
    _updateLayer(sel.id, (c) => c.copyWith(opacity: v.clamp(0.05, 1.0)));
  }

  void _updateBgScale(double v) =>
      setState(() => _backgroundScale = v.clamp(_minScale, _maxScale));

  void _updateBgRotation(double v) =>
      setState(() => _backgroundRotation = v);

  // ── Export ────────────────────────────────────────────────────────────────

  Future<void> _exportComposition() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _canvasKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Canvas indisponivel.');
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null || !mounted) {
        throw StateError('Falha ao gerar imagem.');
      }
      Navigator.of(context).pop(byteData.buffer.asUint8List());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao exportar: $e')),
      );
      setState(() => _isExporting = false);
    }
  }

  Future<_TextLayerDraft?> _showTextLayerDialog(
      {_TextLayerDraft? initial}) {
    return showDialog<_TextLayerDraft>(
      context: context,
      builder: (ctx) =>
          _TextLayerDialog(palette: _textPalette, initial: initial),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Undo/Redo button
// ═══════════════════════════════════════════════════════════════════════════

class _UndoRedoButton extends StatelessWidget {
  const _UndoRedoButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: enabled ? 1.0 : 0.35,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            backgroundColor: enabled
                ? theme.colorScheme.primaryContainer
                : Colors.transparent,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Editor canvas
// ═══════════════════════════════════════════════════════════════════════════

class _EditorCanvas extends StatelessWidget {
  const _EditorCanvas({
    required this.baseImageBytes,
    required this.backgroundOffset,
    required this.backgroundScale,
    required this.backgroundRotation,
    required this.backgroundFlipX,
    required this.backgroundFlipY,
    required this.backgroundKey,
    required this.layers,
    required this.selectedLayerId,
    required this.showSelection,
    required this.onBackgroundScaleStart,
    required this.onBackgroundScaleUpdate,
    required this.onBackgroundHandleStart,
    required this.onBackgroundHandleUpdate,
    required this.onBackgroundHandleEnd,
    required this.onTapCanvas,
    required this.onLayerTap,
    required this.onLayerScaleStart,
    required this.onLayerScaleUpdate,
  });

  final Uint8List baseImageBytes;
  final Offset backgroundOffset;
  final double backgroundScale;
  final double backgroundRotation;
  final bool backgroundFlipX;
  final bool backgroundFlipY;
  final GlobalKey backgroundKey;
  final List<_StickerLayer> layers;
  final String? selectedLayerId;
  final bool showSelection;
  final GestureScaleStartCallback onBackgroundScaleStart;
  final GestureScaleUpdateCallback onBackgroundScaleUpdate;
  final void Function(DragStartDetails, String) onBackgroundHandleStart;
  final void Function(DragUpdateDetails, String) onBackgroundHandleUpdate;
  final void Function(DragEndDetails, String) onBackgroundHandleEnd;
  final VoidCallback onTapCanvas;
  final ValueChanged<String> onLayerTap;
  final void Function(String, ScaleStartDetails) onLayerScaleStart;
  final void Function(String, ScaleUpdateDetails) onLayerScaleUpdate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFD7DFED)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1418457A),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: GestureDetector(
            onTap: onTapCanvas,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _EditorBackdropPainter()),
                GestureDetector(
                  onScaleStart: onBackgroundScaleStart,
                  onScaleUpdate: onBackgroundScaleUpdate,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Center(
                      child: Transform.translate(
                        offset: backgroundOffset,
                        child: Transform(
                          transform: vm.Matrix4.identity()
                            ..rotateZ(backgroundRotation),
                          alignment: Alignment.center,
                          child: Transform.scale(
                            scaleX: (backgroundFlipX ? -1.0 : 1.0) *
                                backgroundScale,
                            scaleY: (backgroundFlipY ? -1.0 : 1.0) *
                                backgroundScale,
                            alignment: Alignment.center,
                            child: Stack(
                              key: backgroundKey,
                              alignment: Alignment.center,
                              children: [
                                Image.memory(
                                  baseImageBytes,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                  gaplessPlayback: true,
                                ),
                                // Rotate handle (top center)
                                if (showSelection)
                                  Align(
                                    alignment: Alignment.topCenter,
                                    child: _CanvasHandle(
                                      icon: Icons.rotate_right,
                                      color: const Color(0xFF0F4FCB),
                                      onPanStart: (d) =>
                                          onBackgroundHandleStart(
                                              d, 'rotate'),
                                      onPanUpdate: (d) =>
                                          onBackgroundHandleUpdate(
                                              d, 'rotate'),
                                      onPanEnd: (d) =>
                                          onBackgroundHandleEnd(d, 'rotate'),
                                    ),
                                  ),
                                // Scale handle (bottom right)
                                if (showSelection)
                                  Align(
                                    alignment: Alignment.bottomRight,
                                    child: _CanvasHandle(
                                      icon: Icons.open_in_full,
                                      color: const Color(0xFF2A9D8F),
                                      onPanStart: (d) =>
                                          onBackgroundHandleStart(
                                              d, 'scale'),
                                      onPanUpdate: (d) =>
                                          onBackgroundHandleUpdate(
                                              d, 'scale'),
                                      onPanEnd: (d) =>
                                          onBackgroundHandleEnd(d, 'scale'),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                for (final layer in layers)
                  _LayerWidget(
                    layer: layer,
                    isSelected: showSelection && selectedLayerId == layer.id,
                    onTap: () => onLayerTap(layer.id),
                    onScaleStart: (d) => onLayerScaleStart(layer.id, d),
                    onScaleUpdate: (d) => onLayerScaleUpdate(layer.id, d),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Canvas drag handle ────────────────────────────────────────────────────

class _CanvasHandle extends StatelessWidget {
  const _CanvasHandle({
    required this.icon,
    required this.color,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final IconData icon;
  final Color color;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: onPanStart,
      onPanUpdate: onPanUpdate,
      onPanEnd: onPanEnd,
      child: Container(
        margin: const EdgeInsets.all(4),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
          boxShadow: const [
            BoxShadow(color: Color(0x22000000), blurRadius: 6),
          ],
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Layer widget
// ═══════════════════════════════════════════════════════════════════════════

class _LayerWidget extends StatelessWidget {
  const _LayerWidget({
    required this.layer,
    required this.isSelected,
    required this.onTap,
    required this.onScaleStart,
    required this.onScaleUpdate,
  });

  final _StickerLayer layer;
  final bool isSelected;
  final VoidCallback onTap;
  final GestureScaleStartCallback onScaleStart;
  final GestureScaleUpdateCallback onScaleUpdate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Transform.translate(
        offset: layer.offset,
        child: Transform(
          transform: vm.Matrix4.identity()..rotateZ(layer.rotation),
          alignment: Alignment.center,
          child: Transform.scale(
            scaleX: layer.scaleX,
            scaleY: layer.scaleY,
            alignment: Alignment.center,
            child: Opacity(
              opacity: layer.opacity,
              child: GestureDetector(
                onTap: onTap,
                onScaleStart: onScaleStart,
                onScaleUpdate: onScaleUpdate,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF0F4FCB)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: switch (layer.type) {
                      _StickerLayerType.text =>
                        _TextLayerPreview(layer: layer),
                      _StickerLayerType.image =>
                        _ImageLayerPreview(layer: layer),
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Layer content previews ───────────────────────────────────────────────

class _TextLayerPreview extends StatelessWidget {
  const _TextLayerPreview({required this.layer});
  final _StickerLayer layer;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: layer.backgroundColor.a != 0
            ? BoxDecoration(
                color: layer.backgroundColor,
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        child: Text(
          layer.text ?? '',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: layer.color,
            fontSize: layer.fontSize,
            fontWeight: FontWeight.w800,
            height: 0.98,
            shadows: const [
              Shadow(
                color: Color(0x66000000),
                blurRadius: 14,
                offset: Offset(0, 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageLayerPreview extends StatelessWidget {
  const _ImageLayerPreview({required this.layer});
  final _StickerLayer layer;

  @override
  Widget build(BuildContext context) {
    return Image.memory(
      layer.imageBytes!,
      width: 220,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Toolbar
// ═══════════════════════════════════════════════════════════════════════════

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.isBusy,
    required this.hasSelectedLayer,
    required this.hasSelectedTextLayer,
    required this.canBringForward,
    required this.canSendBackward,
    required this.onAddText,
    required this.onEditText,
    required this.onAddImage,
    required this.onDuplicateLayer,
    required this.onRemoveLayer,
    required this.onFlipHorizontal,
    required this.onFlipVertical,
    required this.onRotateCCW,
    required this.onRotateCW,
    required this.onBringForward,
    required this.onSendBackward,
    required this.onResetBackground,
    required this.onRotateBackgroundCCW,
    required this.onRotateBackgroundCW,
    required this.onFlipBackgroundHorizontal,
    required this.onFlipBackgroundVertical,
  });

  final bool isBusy;
  final bool hasSelectedLayer;
  final bool hasSelectedTextLayer;
  final bool canBringForward;
  final bool canSendBackward;
  final Future<void> Function() onAddText;
  final Future<void> Function() onEditText;
  final Future<void> Function() onAddImage;
  final VoidCallback onDuplicateLayer;
  final VoidCallback onRemoveLayer;
  final VoidCallback onFlipHorizontal;
  final VoidCallback onFlipVertical;
  final VoidCallback onRotateCCW;
  final VoidCallback onRotateCW;
  final VoidCallback onBringForward;
  final VoidCallback onSendBackward;
  final VoidCallback onResetBackground;
  final VoidCallback onRotateBackgroundCCW;
  final VoidCallback onRotateBackgroundCW;
  final VoidCallback onFlipBackgroundHorizontal;
  final VoidCallback onFlipBackgroundVertical;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A18457A),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Adicionar ─────────────────────────────────────────────────
          _ToolbarSection(
            label: 'Adicionar',
            children: [
              _ToolBtn(
                icon: Icons.text_fields_rounded,
                label: 'Texto',
                onPressed: isBusy ? null : onAddText,
                color: const Color(0xFF0F4FCB),
              ),
              _ToolBtn(
                icon: Icons.add_photo_alternate_outlined,
                label: 'Imagem',
                onPressed: isBusy ? null : onAddImage,
                color: const Color(0xFF2A9D8F),
              ),
            ],
          ),
          const _ToolDivider(),
          // ── Camada selecionada ────────────────────────────────────────
          _ToolbarSection(
            label: 'Camada selecionada',
            children: [
              _ToolBtn(
                icon: Icons.edit_note_rounded,
                label: 'Editar',
                onPressed:
                    isBusy || !hasSelectedTextLayer ? null : onEditText,
                color: const Color(0xFF7C3AED),
              ),
              _ToolBtn(
                icon: Icons.copy_rounded,
                label: 'Duplicar',
                onPressed:
                    isBusy || !hasSelectedLayer ? null : onDuplicateLayer,
                color: const Color(0xFF0891B2),
              ),
              _ToolBtn(
                icon: Icons.delete_outline_rounded,
                label: 'Remover',
                onPressed:
                    isBusy || !hasSelectedLayer ? null : onRemoveLayer,
                color: const Color(0xFFDC2626),
              ),
            ],
          ),
          const _ToolDivider(),
          // ── Transformar camada ────────────────────────────────────────
          _ToolbarSection(
            label: 'Transformar camada',
            children: [
              _ToolBtn(
                icon: Icons.rotate_left_rounded,
                label: '-90°',
                onPressed: isBusy || !hasSelectedLayer ? null : onRotateCCW,
                color: const Color(0xFF059669),
              ),
              _ToolBtn(
                icon: Icons.rotate_right_rounded,
                label: '+90°',
                onPressed: isBusy || !hasSelectedLayer ? null : onRotateCW,
                color: const Color(0xFF059669),
              ),
              _ToolBtn(
                icon: Icons.flip_rounded,
                label: 'Flip H',
                onPressed:
                    isBusy || !hasSelectedLayer ? null : onFlipHorizontal,
                color: const Color(0xFFF59E0B),
              ),
              _ToolBtn(
                icon: Icons.flip_rounded,
                label: 'Flip V',
                onPressed:
                    isBusy || !hasSelectedLayer ? null : onFlipVertical,
                color: const Color(0xFFF59E0B),
                rotateIcon: math.pi / 2,
              ),
              _ToolBtn(
                icon: Icons.arrow_upward_rounded,
                label: 'Subir',
                onPressed:
                    isBusy || !canBringForward ? null : onBringForward,
                color: const Color(0xFF64748B),
              ),
              _ToolBtn(
                icon: Icons.arrow_downward_rounded,
                label: 'Descer',
                onPressed:
                    isBusy || !canSendBackward ? null : onSendBackward,
                color: const Color(0xFF64748B),
              ),
            ],
          ),
          const _ToolDivider(),
          // ── Fundo ─────────────────────────────────────────────────────
          _ToolbarSection(
            label: 'Fundo',
            children: [
              _ToolBtn(
                icon: Icons.rotate_left_rounded,
                label: '-90°',
                onPressed: isBusy ? null : onRotateBackgroundCCW,
                color: const Color(0xFF7C3AED),
              ),
              _ToolBtn(
                icon: Icons.rotate_right_rounded,
                label: '+90°',
                onPressed: isBusy ? null : onRotateBackgroundCW,
                color: const Color(0xFF7C3AED),
              ),
              _ToolBtn(
                icon: Icons.flip_rounded,
                label: 'Flip H',
                onPressed: isBusy ? null : onFlipBackgroundHorizontal,
                color: const Color(0xFFE85D04),
              ),
              _ToolBtn(
                icon: Icons.flip_rounded,
                label: 'Flip V',
                onPressed: isBusy ? null : onFlipBackgroundVertical,
                color: const Color(0xFFE85D04),
                rotateIcon: math.pi / 2,
              ),
              _ToolBtn(
                icon: Icons.center_focus_weak_rounded,
                label: 'Resetar',
                onPressed: isBusy ? null : onResetBackground,
                color: const Color(0xFF94A3B8),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolbarSection extends StatelessWidget {
  const _ToolbarSection({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF94A3B8),
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolDivider extends StatelessWidget {
  const _ToolDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      indent: 16,
      endIndent: 16,
      color: Color(0xFFE2E8F4),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  const _ToolBtn({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.color,
    this.rotateIcon,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final double? rotateIcon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1.0 : 0.38,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: enabled
                ? color.withValues(alpha: 0.10)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: enabled
                  ? color.withValues(alpha: 0.35)
                  : const Color(0xFFE2E8F4),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.rotate(
                angle: rotateIcon ?? 0,
                child: Icon(
                  icon,
                  size: 20,
                  color: enabled ? color : const Color(0xFFB0B8C8),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: enabled ? color : const Color(0xFFB0B8C8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Inspector
// ═══════════════════════════════════════════════════════════════════════════

class _EditorInspector extends StatelessWidget {
  const _EditorInspector({
    required this.tab,
    required this.onTabChanged,
    required this.isLayerSelected,
    required this.layerType,
    required this.layerScaleValue,
    required this.layerRotationValue,
    required this.layerOpacityValue,
    required this.onLayerScaleChanged,
    required this.onLayerRotationChanged,
    required this.onLayerOpacityChanged,
    required this.bgScaleValue,
    required this.bgRotationValue,
    required this.onBgScaleChanged,
    required this.onBgRotationChanged,
  });

  final int tab;
  final ValueChanged<int> onTabChanged;
  final bool isLayerSelected;
  final _StickerLayerType? layerType;
  final double layerScaleValue;
  final double layerRotationValue;
  final double layerOpacityValue;
  final ValueChanged<double>? onLayerScaleChanged;
  final ValueChanged<double>? onLayerRotationChanged;
  final ValueChanged<double>? onLayerOpacityChanged;
  final double bgScaleValue;
  final double bgRotationValue;
  final ValueChanged<double> onBgScaleChanged;
  final ValueChanged<double> onBgRotationChanged;

  String _fmtDeg(double rad) => '${(rad * 180 / math.pi).round()}°';
  String _fmtPct(double v) => '${(v * 100).round()}%';
  String _fmtScale(double v) => '${v.abs().toStringAsFixed(2)}x';

  double _normRad(double r) {
    double n = r % (2 * math.pi);
    if (n > math.pi) n -= 2 * math.pi;
    if (n < -math.pi) n += 2 * math.pi;
    return n;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F4)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                _InspectorTab(
                  label: 'Camada',
                  icon: Icons.layers_rounded,
                  isActive: tab == 0,
                  onTap: () => onTabChanged(0),
                ),
                const SizedBox(width: 8),
                _InspectorTab(
                  label: 'Fundo',
                  icon: Icons.image_rounded,
                  isActive: tab == 1,
                  onTap: () => onTabChanged(1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1, color: Color(0xFFE2E8F4)),
          Padding(
            padding: const EdgeInsets.all(20),
            child:
                tab == 0 ? _buildLayerTab(context) : _buildBgTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildLayerTab(BuildContext context) {
    if (!isLayerSelected) {
      return Row(
        children: [
          const Icon(
            Icons.touch_app_rounded,
            color: Color(0xFFB0B8C8),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Selecione uma camada no canvas para ajustar escala, rotação e opacidade.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF94A3B8),
                  ),
            ),
          ),
        ],
      );
    }

    final layerLabel =
        layerType == _StickerLayerType.text ? 'Texto' : 'Imagem';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InspectorSlider(
          icon: Icons.open_in_full_rounded,
          label: 'Escala — $layerLabel',
          valueLabel: _fmtScale(layerScaleValue),
          value: layerScaleValue.abs().clamp(0.05, 12),
          min: 0.05,
          max: 12,
          divisions: 240,
          onChanged: onLayerScaleChanged,
        ),
        const SizedBox(height: 16),
        _InspectorSlider(
          icon: Icons.rotate_right_rounded,
          label: 'Rotação',
          valueLabel: _fmtDeg(layerRotationValue),
          value: _normRad(layerRotationValue),
          min: -math.pi,
          max: math.pi,
          divisions: 360,
          onChanged: onLayerRotationChanged,
        ),
        const SizedBox(height: 16),
        _InspectorSlider(
          icon: Icons.opacity_rounded,
          label: 'Opacidade',
          valueLabel: _fmtPct(layerOpacityValue),
          value: layerOpacityValue.clamp(0.05, 1.0),
          min: 0.05,
          max: 1.0,
          divisions: 19,
          onChanged: onLayerOpacityChanged,
        ),
      ],
    );
  }

  Widget _buildBgTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InspectorSlider(
          icon: Icons.open_in_full_rounded,
          label: 'Escala do fundo',
          valueLabel: _fmtScale(bgScaleValue),
          value: bgScaleValue.clamp(0.05, 12),
          min: 0.05,
          max: 12,
          divisions: 240,
          onChanged: onBgScaleChanged,
        ),
        const SizedBox(height: 16),
        _InspectorSlider(
          icon: Icons.rotate_right_rounded,
          label: 'Rotação do fundo',
          valueLabel: _fmtDeg(bgRotationValue),
          value: _normRad(bgRotationValue),
          min: -math.pi,
          max: math.pi,
          divisions: 360,
          onChanged: onBgRotationChanged,
        ),
      ],
    );
  }
}

class _InspectorTab extends StatelessWidget {
  const _InspectorTab({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? theme.colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive
                  ? theme.colorScheme.onPrimaryContainer
                  : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? theme.colorScheme.onPrimaryContainer
                    : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InspectorSlider extends StatelessWidget {
  const _InspectorSlider({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF64748B)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF334155),
                ),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                valueLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F4FCB),
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Export bar
// ═══════════════════════════════════════════════════════════════════════════

class _ExportBar extends StatelessWidget {
  const _ExportBar({
    required this.isExporting,
    required this.onCancel,
    required this.onExport,
  });

  final bool isExporting;
  final VoidCallback onCancel;
  final Future<void> Function() onExport;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F4))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: isExporting ? null : onCancel,
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: isExporting ? null : onExport,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F4FCB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: isExporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_rounded),
                  label:
                      Text(isExporting ? 'Gerando...' : 'Aplicar edição'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Backdrop painter
// ═══════════════════════════════════════════════════════════════════════════

class _EditorBackdropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const tile = 24.0;
    final lightPaint = Paint()..color = const Color(0xFFF5F8FD);
    final darkPaint = Paint()..color = const Color(0xFFE9EEF8);
    for (double y = 0; y < size.height; y += tile) {
      for (double x = 0; x < size.width; x += tile) {
        final isEven =
            ((x / tile).floor() + (y / tile).floor()).isEven;
        canvas.drawRect(
          Rect.fromLTWH(x, y, tile, tile),
          isEven ? lightPaint : darkPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ═══════════════════════════════════════════════════════════════════════════
// Data model
// ═══════════════════════════════════════════════════════════════════════════

enum _StickerLayerType { text, image }

class _StickerLayer {
  const _StickerLayer._({
    required this.id,
    required this.type,
    required this.offset,
    required this.scaleX,
    required this.scaleY,
    required this.rotation,
    required this.opacity,
    required this.color,
    required this.backgroundColor,
    required this.fontSize,
    this.text,
    this.imageBytes,
  });

  const _StickerLayer.text({
    required String id,
    required String text,
    required Color color,
    required Color backgroundColor,
    required double fontSize,
    required Offset offset,
    required double scale,
  }) : this._(
          id: id,
          type: _StickerLayerType.text,
          offset: offset,
          scaleX: scale,
          scaleY: scale,
          rotation: 0,
          opacity: 1.0,
          color: color,
          backgroundColor: backgroundColor,
          fontSize: fontSize,
          text: text,
        );

  const _StickerLayer.image({
    required String id,
    required Uint8List imageBytes,
    required Offset offset,
    required double scale,
  }) : this._(
          id: id,
          type: _StickerLayerType.image,
          offset: offset,
          scaleX: scale,
          scaleY: scale,
          rotation: 0,
          opacity: 1.0,
          color: Colors.white,
          backgroundColor: const Color(0x00000000),
          fontSize: 56,
          imageBytes: imageBytes,
        );

  final String id;
  final _StickerLayerType type;
  final Offset offset;
  final double scaleX;
  final double scaleY;
  final double rotation;
  final double opacity;
  final String? text;
  final Color color;
  final Color backgroundColor;
  final double fontSize;
  final Uint8List? imageBytes;

  double get scale => (scaleX.abs() + scaleY.abs()) / 2.0;

  _StickerLayer duplicateWithId(String newId) => _StickerLayer._(
        id: newId,
        type: type,
        offset: offset,
        scaleX: scaleX,
        scaleY: scaleY,
        rotation: rotation,
        opacity: opacity,
        color: color,
        backgroundColor: backgroundColor,
        fontSize: fontSize,
        text: text,
        imageBytes: imageBytes,
      );

  _StickerLayer copyWith({
    Offset? offset,
    double? scale,
    double? scaleX,
    double? scaleY,
    double? rotation,
    double? opacity,
    String? text,
    Color? color,
    Color? backgroundColor,
    double? fontSize,
    Uint8List? imageBytes,
  }) {
    final newScaleX = scaleX ??
        (scale != null ? scale * (this.scaleX < 0 ? -1 : 1) : this.scaleX);
    final newScaleY = scaleY ??
        (scale != null ? scale * (this.scaleY < 0 ? -1 : 1) : this.scaleY);
    return _StickerLayer._(
      id: id,
      type: type,
      offset: offset ?? this.offset,
      scaleX: newScaleX,
      scaleY: newScaleY,
      rotation: rotation ?? this.rotation,
      opacity: opacity ?? this.opacity,
      color: color ?? this.color,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      fontSize: fontSize ?? this.fontSize,
      text: text ?? this.text,
      imageBytes: imageBytes ?? this.imageBytes,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Text layer draft
// ═══════════════════════════════════════════════════════════════════════════

class _TextLayerDraft {
  const _TextLayerDraft({
    required this.text,
    required this.color,
    required this.backgroundColor,
    required this.fontSize,
  });

  final String text;
  final Color color;
  final Color backgroundColor;
  final double fontSize;
}

// ═══════════════════════════════════════════════════════════════════════════
// Text layer dialog
// ═══════════════════════════════════════════════════════════════════════════

class _TextLayerDialog extends StatefulWidget {
  const _TextLayerDialog({required this.palette, required this.initial});

  final List<Color> palette;
  final _TextLayerDraft? initial;

  @override
  State<_TextLayerDialog> createState() => _TextLayerDialogState();
}

class _TextLayerDialogState extends State<_TextLayerDialog> {
  late final TextEditingController _controller;
  late Color _selectedColor;
  late Color _selectedBackground;
  late bool _hasBackground;
  late double _fontSize;

  bool get _canApply => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial?.text ?? '');
    _selectedColor = widget.initial?.color ?? widget.palette.first;
    _selectedBackground =
        widget.initial?.backgroundColor ?? const Color(0x00000000);
    _hasBackground = _selectedBackground.a > 0;
    _fontSize = widget.initial?.fontSize ?? 56;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title:
          Text(widget.initial == null ? 'Adicionar texto' : 'Editar texto'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Texto da camada',
                hintText: 'Digite o texto que vai no sticker',
                errorText:
                    _canApply ? null : 'Informe um texto para continuar',
              ),
            ),
            const SizedBox(height: 16),
            const Text('Cor do texto'),
            const SizedBox(height: 10),
            _ColorSwatchRow(
              colors: widget.palette,
              selected: _selectedColor,
              onSelect: (c) => setState(() => _selectedColor = c),
              onCustom: () async {
                final picked = await showDialog<Color>(
                  context: context,
                  builder: (c) =>
                      _ColorPickerDialog(initial: _selectedColor),
                );
                if (picked != null) {
                  setState(() => _selectedColor = picked);
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Fundo do texto'),
                Switch(
                  value: _hasBackground,
                  onChanged: (v) => setState(() => _hasBackground = v),
                ),
              ],
            ),
            if (_hasBackground) ...[
              const SizedBox(height: 8),
              _ColorSwatchRow(
                colors: widget.palette,
                selected: _selectedBackground,
                onSelect: (c) => setState(() => _selectedBackground = c),
                onCustom: () async {
                  final picked = await showDialog<Color>(
                    context: context,
                    builder: (c) =>
                        _ColorPickerDialog(initial: _selectedBackground),
                  );
                  if (picked != null) {
                    setState(() => _selectedBackground = picked);
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            const Text('Tamanho do texto'),
            Slider(
              value: _fontSize.clamp(12, 160),
              min: 12,
              max: 160,
              divisions: 148,
              label: '${_fontSize.round()}px',
              onChanged: (v) => setState(() => _fontSize = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _canApply
              ? () => Navigator.of(context).pop(
                    _TextLayerDraft(
                      text: _controller.text,
                      color: _selectedColor,
                      backgroundColor: _hasBackground
                          ? _selectedBackground
                          : const Color(0x00000000),
                      fontSize: _fontSize,
                    ),
                  )
              : null,
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}

// ── Color swatch row ──────────────────────────────────────────────────────

class _ColorSwatchRow extends StatelessWidget {
  const _ColorSwatchRow({
    required this.colors,
    required this.selected,
    required this.onSelect,
    required this.onCustom,
  });

  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onSelect;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in colors)
          InkWell(
            onTap: () => onSelect(c),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected == c
                      ? const Color(0xFF0F4FCB)
                      : const Color(0xFFD7DFED),
                  width: selected == c ? 3 : 1.5,
                ),
              ),
            ),
          ),
        InkWell(
          onTap: onCustom,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFD7DFED)),
            ),
            child: const Icon(Icons.colorize, size: 18),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Color picker dialogs
// ═══════════════════════════════════════════════════════════════════════════

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial});

  final Color initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late Color _current;

  static final List<Color> _gridColors = [
    const Color(0xFF000000),
    const Color(0xFF4B4B4B),
    const Color(0xFF7A7A7A),
    const Color(0xFFBDBDBD),
    const Color(0xFFFFFFFF),
    const Color(0xFFEF9A9A),
    const Color(0xFFF48FB1),
    const Color(0xFFCE93D8),
    const Color(0xFFB39DDB),
    const Color(0xFF9FA8DA),
    const Color(0xFF90CAF9),
    const Color(0xFF81D4FA),
    const Color(0xFF80DEEA),
    const Color(0xFF80CBC4),
    const Color(0xFFA5D6A7),
    const Color(0xFFC5E1A5),
    const Color(0xFFFFF59D),
    const Color(0xFFFFE082),
    const Color(0xFFFFCC80),
    const Color(0xFFFFAB91),
    const Color(0xFFFF8A65),
    const Color(0xFFD7CCC8),
    const Color(0xFFBCAAA4),
    const Color(0xFF90A4AE),
    const Color(0xFFB71C1C),
    const Color(0xFFD32F2F),
    const Color(0xFFE53935),
    const Color(0xFFD81B60),
    const Color(0xFF8E24AA),
    const Color(0xFF5E35B1),
    const Color(0xFF3949AB),
    const Color(0xFF1E88E5),
    const Color(0xFF039BE5),
    const Color(0xFF00ACC1),
    const Color(0xFF00897B),
    const Color(0xFF43A047),
    const Color(0xFF7CB342),
    const Color(0xFFCDDC39),
    const Color(0xFFFFEB3B),
    const Color(0xFFFFC107),
    const Color(0xFFFFA000),
    const Color(0xFFFF5722),
    const Color(0xFF6D4C41),
    const Color(0xFF757575),
    const Color(0xFF455A64),
    const Color(0xFF263238),
  ];

  @override
  void initState() {
    super.initState();
    _current = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Escolher cor'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              height: 44,
              decoration: BoxDecoration(
                color: _current,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD7DFED)),
              ),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              itemCount: _gridColors.length,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemBuilder: (ctx, i) {
                final c = _gridColors[i];
                final sel = c == _current;
                return InkWell(
                  onTap: () => setState(() => _current = c),
                  child: Container(
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: sel
                            ? const Color(0xFF0F4FCB)
                            : const Color(0xFFD7DFED),
                        width: sel ? 3 : 1.5,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final picked = await showDialog<Color>(
                    context: context,
                    builder: (c) =>
                        _LegacySliderColorPickerDialog(initial: _current),
                  );
                  if (picked != null) setState(() => _current = picked);
                },
                icon: const Icon(Icons.tune),
                label: const Text('Mais cores'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_current),
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}

class _LegacySliderColorPickerDialog extends StatefulWidget {
  const _LegacySliderColorPickerDialog({required this.initial});

  final Color initial;

  @override
  State<_LegacySliderColorPickerDialog> createState() =>
      _LegacySliderColorPickerDialogState();
}

class _LegacySliderColorPickerDialogState
    extends State<_LegacySliderColorPickerDialog> {
  late double _r;
  late double _g;
  late double _b;
  late double _a;

  @override
  void initState() {
    super.initState();
    _r = widget.initial.r * 255.0;
    _g = widget.initial.g * 255.0;
    _b = widget.initial.b * 255.0;
    _a = widget.initial.a * 255.0;
  }

  Color get _current =>
      Color.fromARGB(_a.round(), _r.round(), _g.round(), _b.round());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Personalizar cor'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            height: 44,
            decoration: BoxDecoration(
              color: _current,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD7DFED)),
            ),
          ),
          const SizedBox(height: 12),
          _buildSlider('A', _a, (v) => setState(() => _a = v), 0, 255),
          _buildSlider('R', _r, (v) => setState(() => _r = v), 0, 255),
          _buildSlider('G', _g, (v) => setState(() => _g = v), 0, 255),
          _buildSlider('B', _b, (v) => setState(() => _b = v), 0, 255),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_current),
          child: const Text('Aplicar'),
        ),
      ],
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    ValueChanged<double> onChanged,
    double min,
    double max,
  ) {
    return Row(
      children: [
        SizedBox(width: 18, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: (max - min).round(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 36, child: Text(value.round().toString())),
      ],
    );
  }
}
