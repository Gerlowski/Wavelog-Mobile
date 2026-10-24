import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'providers/rig_provider.dart';
import 'providers/settings_provider.dart';
import 'router.dart';

class WavelogMobileApp extends ConsumerWidget {
  const WavelogMobileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    // Start the radio link with the app, so it connects as soon as the
    // radio's USB cable is plugged in, not only once a QSO form opens.
    ref.listen(rigProvider, (_, __) {});

    final locale = settings.locale != null ? Locale(settings.locale!) : null;

    return MaterialApp.router(
      title: 'Wavelog Mobile',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: settings.darkTheme ? ThemeMode.dark : ThemeMode.light,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: appRouter,
    );
  }
}
