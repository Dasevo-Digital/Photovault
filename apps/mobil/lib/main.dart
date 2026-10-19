import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gelaende/texte.dart' show GelaendeTexte;
import 'package:zierbild/zierschrift.dart';
import 'package:kern/protokoll.dart';
import 'package:workmanager/workmanager.dart';

import 'l10n/app_localizations.dart';
import 'seiten/anmelden.dart';
import 'seiten/start.dart';
import 'sicherung/hintergrund.dart';
import 'sitzung.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Meldungen aus dem Kern über debugPrint, wie in der Desktop-App.
  protokollZiel = debugPrint;
  // Die Sicherung der Kamerarolle im Hintergrund (sicherung/hintergrund.dart).
  await Workmanager().initialize(sicherungImHintergrund);
  final sitzung = Sitzung();
  // Die Schriften des Lebensbaums stehen unter der SIL Open Font License.
  zierschriftenLizenzenAnmelden();
  runApp(PhotoVaultMobil(sitzung: sitzung));
  unawaited(sitzung.starte());
}

/// Photo Vault auf dem Telefon (Issue #86, Stufe 3).
class PhotoVaultMobil extends StatelessWidget {
  const PhotoVaultMobil({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sitzung,
    builder: (context, _) => MaterialApp(
      title: 'Photo Vault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3B6EA8),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF3B6EA8),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        ...AppTexte.localizationsDelegates,
        GelaendeTexte.delegate,
      ],
      supportedLocales: AppTexte.supportedLocales,
      locale: switch (sitzung.sprache) {
        final s? => Locale(s),
        null => null,
      },
      home: switch (sitzung.zustand) {
        Sitzungszustand.laedt => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        Sitzungszustand.abgemeldet => Anmelden(sitzung: sitzung),
        Sitzungszustand.bereit => Start(sitzung: sitzung),
      },
    ),
  );
}
