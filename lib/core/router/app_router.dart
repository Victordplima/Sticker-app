import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../modules/packs/screens/create_pack_screen.dart';
import '../../modules/packs/screens/pack_details_screen.dart';
import '../../modules/packs/screens/packs_list_screen.dart';
import '../../modules/stickers/screens/create_sticker_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const PacksListScreen(),
        routes: [
          GoRoute(
            path: 'packs/create',
            builder: (context, state) => const CreatePackScreen(),
          ),
          GoRoute(
            path: 'packs/:packId',
            builder: (context, state) {
              final packId = state.pathParameters['packId']!;
              return PackDetailsScreen(packId: packId);
            },
            routes: [
              GoRoute(
                path: 'stickers/create',
                builder: (context, state) {
                  final packId = state.pathParameters['packId']!;
                  return CreateStickerScreen(packId: packId);
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
