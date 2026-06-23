import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:sticker/modules/stickers/screens/sticker_editor_screen.dart';

void main() {
  testWidgets('abre o dialogo de texto e aplica uma camada sem erros', (
    WidgetTester tester,
  ) async {
    final image = img.Image(width: 32, height: 32, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(255, 0, 0, 255));
    final pngBytes = img.encodePng(image);

    await tester.pumpWidget(
      MaterialApp(
        home: StickerEditorScreen(
          initialBytes: pngBytes,
          imageName: 'base.png',
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Texto'));
    await tester.pumpAndSettle();

    expect(find.text('Adicionar texto'), findsOneWidget);
    expect(find.text('Cor do texto'), findsOneWidget);
    expect(find.text('Fundo do texto'), findsOneWidget);
    expect(find.text('Tamanho do texto'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Promo');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    expect(find.text('Promo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
