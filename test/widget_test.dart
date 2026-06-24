import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sticker/app.dart';
import 'package:sticker/modules/packs/models/sticker_pack.dart';
import 'package:sticker/modules/packs/services/packs_controller.dart';
import 'package:sticker/modules/packs/services/packs_repository.dart';
import 'package:sticker/modules/stickers/models/sticker.dart';

void main() {
  testWidgets('renders repository packs on startup', (
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
            Sticker(
              id: 'coffee-2',
              filePath: 'samples/coffee-2.webp',
              emojis: ['😺'],
            ),
          ],
        ),
        StickerPack(
          id: 'pack-work-mood',
          name: 'Work Mood',
          author: 'Equipe Interna',
          stickers: [
            Sticker(
              id: 'work-1',
              filePath: 'samples/work-1.webp',
              emojis: ['💻'],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [packsRepositoryProvider.overrideWithValue(repository)],
        child: const StickerStudioApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Biblioteca'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Coffee Cats'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Coffee Cats'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Work Mood'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Work Mood'), findsOneWidget);
  });
}
