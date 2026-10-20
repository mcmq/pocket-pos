import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/app_localizations.dart';
import 'core/providers/app_providers.dart';
import 'core/router/app_router.dart';
import 'core/sync/sync_providers.dart';
import 'core/theme/app_theme.dart';

class PocketPosApp extends ConsumerWidget {
  const PocketPosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Starts the sync engine (no-op until signed in and online).
    ref.watch(syncEngineProvider);
    final scale = ref.watch(textScaleProvider);

    return MaterialApp.router(
      title: 'PocketPOS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        // The user's Text Size setting multiplies the OS text scale.
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear((media.textScaler.scale(14) / 14 * scale).clamp(0.8, 2.0)),
          ),
          child: child!,
        );
      },
    );
  }
}
