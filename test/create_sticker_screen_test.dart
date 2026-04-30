import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sticker/modules/packs/models/sticker_pack.dart';
import 'package:sticker/modules/packs/services/packs_controller.dart';
import 'package:sticker/modules/packs/services/packs_repository.dart';
import 'package:sticker/modules/stickers/models/sticker.dart';
import 'package:sticker/modules/stickers/screens/create_sticker_screen.dart';

void main() {
  testWidgets('renderiza estado inicial da criacao de sticker', (
    WidgetTester tester,
  ) async {
    final repository = PacksRepository.inMemory(
      initialPacks: const [
        StickerPack(
          id: 'pack-coffee-cats',
          name: 'Coffee Cats',
          author: 'Sticker Studio',
          stickers: [
            Sticker(
              id: 'coffee-1',
              filePath: 'samples/coffee-1.webp',
              emojis: ['☕'],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [packsRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: CreateStickerScreen(packId: 'pack-coffee-cats'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Criar sticker'), findsOneWidget);
    expect(find.text('Novo sticker para Coffee Cats'), findsOneWidget);
    expect(find.text('Selecionar da galeria'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Gerar e adicionar ao pack'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Gerar e adicionar ao pack'), findsOneWidget);
  });
}
