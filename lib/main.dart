import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'db/database.dart';
import 'l10n/app_localizations.dart';
import 'screens/bibliothek_belegt_screen.dart';
import 'screens/home_shell.dart';
import 'screens/initialisierungsfehler_screen.dart';
import 'services/bilddekodierung.dart';
import 'services/beenden_waechter.dart';
import 'state/library_state.dart';
import 'theme/app_theme.dart';
import 'theme/zierbaum_farben.dart' show zierschriftenLizenzenAnmelden;
import 'services/eigenkarte.dart';
import 'services/schwebevorschau.dart';
import 'widgets/mini_location_map.dart'
    show
        kartenSpeicherEinrichten,
        setzeCartoSchluessel,
        setzeEigeneKarte,
        setzeKarteHochaufloesend;
import 'widgets/beenden_dialog.dart';
import 'widgets/meldungsfenster.dart';
import 'widgets/schwebevorschau.dart';
import 'widgets/stromhalter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Muss vor der ersten Videowiedergabe laufen (siehe widgets/video_playback.dart).
  MediaKit.ensureInitialized();
  // Ohne Argument werden alle Locales vorbereitet – nötig, weil die
  // Sprache zur Laufzeit umschaltbar ist und die Datumsnamen sonst für
  // die jeweils andere fehlten.
  await initializeDateFormatting();
  // Muss vor der ersten Karte laufen: Der Kachelspeicher ist ein
  // Einzelstueck, dessen Angaben nur beim ersten Anlegen wirken.
  kartenSpeicherEinrichten();
  // Der Bildspeicher, bevor die erste Kachel gezeichnet wird
  // (siehe bildspeicherEinrichten).
  bildspeicherEinrichten();
  // Die Lizenzen der mitgelieferten Schriften anmelden, damit sie in der
  // Lizenzuebersicht auftauchen (siehe zierschriftenLizenzenAnmelden).
  zierschriftenLizenzenAnmelden();
  runApp(const PhotoVaultApp());
}

class PhotoVaultApp extends StatefulWidget {
  const PhotoVaultApp({super.key});

  @override
  State<PhotoVaultApp> createState() => _PhotoVaultAppState();
}

class _PhotoVaultAppState extends State<PhotoVaultApp> {
  /// Der Einstellungsstrom, festgehalten über die Neuaufbauten hinweg, die
  /// der [Consumer] unten bei jeder Meldung auslöst.
  final _einstellungen = Stromhalter<AppSettingsData?>();

  /// Nötig, um von ausserhalb des Widget-Baums einen Dialog zu zeigen: Die
  /// Frage nach dem Beenden kommt über einen Plattform-Kanal herein, nicht
  /// aus einem Knopfdruck – dort gibt es keinen BuildContext.
  final _navigator = GlobalKey<NavigatorState>();
  final _waechter = BeendenWaechter();

  @override
  void initState() {
    super.initState();
    // Nur macOS: Nur dort gibt es die native Gegenstelle. Unter Linux und
    // Windows bleibt es beim bisherigen Verhalten.
    if (!kIsWeb && Platform.isMacOS) _waechter.horche(_darfBeenden);
  }

  @override
  void dispose() {
    _waechter.schweige();
    super.dispose();
  }

  /// Beantwortet die Frage der nativen Seite. Läuft nichts, wird ohne
  /// Rückfrage beendet – eine Bestätigung, die immer erscheint, lernt man
  /// wegzuklicken.
  Future<bool> _darfBeenden() async {
    final kontext = _navigator.currentContext;
    if (kontext == null || !kontext.mounted) return true;
    final library = Provider.of<LibraryState>(kontext, listen: false);
    if (!library.etwasLaeuft) return true;
    return zeigeBeendenFrage(kontext, library);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LibraryState()..initialize(),
      child: Consumer<LibraryState>(
        builder: (context, library, _) {
          // Kein Stream, solange die DB noch nicht bereit ist (initialize()
          // noch nicht durchgelaufen) – StreamBuilder bleibt dann einfach im
          // Anfangszustand (kein Fehler), themeModeFromString(null) liefert
          // ThemeMode.system als Default.
          return StreamBuilder<AppSettingsData?>(
            // Festgehalten (siehe [Stromhalter]): Dieser Aufbau läuft bei
            // JEDER Meldung des Bibliothekszustands erneut, und ein neu
            // erzeugter Strom hiesse jedes Mal ein neues Abo samt frischer
            // Abfrage.
            stream: library.isReady
                ? _einstellungen.hole(true, () => library.db.watchAppSettings())
                : null,
            builder: (context, settingsSnapshot) {
              // Der CARTO-Schlüssel geht hier an die Kartenschicht, weil
              // dies die einzige Stelle ist, die IMMER von einer Änderung
              // erfährt: Die Einstellungen schreiben in dieselbe Zeile,
              // die dieser Strom beobachtet, und der Neuaufbau erfasst
              // jede Karte darunter. Eine reine Zuweisung ohne
              // Rückwirkung auf den Aufbau - sie stösst keinen zweiten
              // Durchgang an.
              setzeCartoSchluessel(settingsSnapshot.data?.cartoSchluessel);
              // Und die doppelte Auflösung, aus demselben Grund: Wer sie
              // in den Einstellungen umlegt, soll die Karte danach sofort
              // anders sehen und nicht erst nach einem Neustart.
              setzeKarteHochaufloesend(
                  settingsSnapshot.data?.karteHochaufloesend ?? true);
              // Und die Schwebe-Vorschau, aus demselben Grund: Wer sie in
              // den Einstellungen abschaltet, soll die Kachelwand danach
              // sofort still haben.
              setzeSchwebevorschau(
                  settingsSnapshot.data?.schwebeVorschau ?? true);
              // Dieselbe Stelle, derselbe Grund: Die eigene Kartenquelle
              // steht in derselben Zeile der Einstellungen.
              setzeEigeneKarte(Eigenkarte.aus(
                name: settingsSnapshot.data?.eigeneKarteName,
                url: settingsSnapshot.data?.eigeneKarteUrl,
                nennung: settingsSnapshot.data?.eigeneKarteNennung,
                stufe: settingsSnapshot.data?.eigeneKarteStufe,
                zugestimmt:
                    settingsSnapshot.data?.eigeneKarteZugestimmt ?? false,
              ));
              return MaterialApp(
                title: 'Photo Vault',
                navigatorKey: _navigator,
                debugShowCheckedModeBanner: false,
                // Der Meldungsstapel liegt über allem, was der Navigator
                // zeigt: Eine Meldung, die beim Bildschirmwechsel
                // verschwände, wäre keine – und ein Blatt, das sie
                // verdeckte, auch nicht.
                builder: (context, kind) => mitMeldungen(kind),
                theme: buildLightTheme(),
                darkTheme: buildDarkTheme(),
                themeMode: themeModeFromString(settingsSnapshot.data?.themeMode),
                // null = Systemsprache, siehe localeFromString.
                locale: localeFromString(settingsSnapshot.data?.sprache),
                supportedLocales: AppTexte.supportedLocales,
                localizationsDelegates: const [
                  AppTexte.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                // Reihenfolge mit Bedacht: Die belegte Bibliothek zuerst.
                // `isReady` bleibt in diesem Fall dauerhaft falsch – wer
                // nur darauf prüft, zeigt einen Ladekreis, der sich nie
                // dreht (siehe LibraryState.initialize).
                home: library.bibliothekBelegt
                    ? BibliothekBelegtScreen(library: library)
                    : library.initialisierungsfehler != null
                        ? InitialisierungsfehlerScreen(
                            fehler: library.initialisierungsfehler!,
                            erneutVersuchen: library.initialize,
                          )
                    : !library.isReady
                        ? const Scaffold(
                            body: Center(child: CircularProgressIndicator()))
                        // Der Bereich fuer die Schwebe-Vorschau liegt
                        // ueber allem, was Kacheln zeigt - und es gibt
                        // genau einen davon, weil es genau einen
                        // Abspieler geben soll.
                        : SchwebevorschauBereich(
                            db: library.db,
                            paths: library.paths,
                            child: HomeShell(library: library),
                          ),
              );
            },
          );
        },
      ),
    );
  }
}
