import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  import 'package:flutter/widgets.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:flutter_web_plugins/url_strategy.dart';

  import 'app.dart';

  void main() {
    WidgetsFlutterBinding.ensureInitialized();
    usePathUrlStrategy();
    runApp(const ProviderScope(child: StickerStudioApp()));
  }
        // and then invoke "hot reload" (save your changes or press the "hot
