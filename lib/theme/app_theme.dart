import 'dart:io';

import 'package:flutter/material.dart';

import 'app_spacing.dart';

/// Zentrale Theme-Definition für Light/Dark Mode (siehe
/// [AppSettings.themeMode] in database.dart für die Persistenz, main.dart
/// für die Umschaltung). Beide Helligkeiten teilen sich denselben Seed
/// (Teal), damit der Markencharakter erhalten bleibt und nicht zwei
/// unabhängig gepflegte Paletten auseinanderlaufen können.
///
/// `.AppleSystemUIFont` löst macOS intern auf San Francisco auf – kein
/// Font-Bundling nötig (reines System-Font-Referencing, keine Lizenzfrage),
/// sorgt aber für ein deutlich natives Schriftbild statt Flutters
/// Material-3-Standard (Roboto-Fallback).
///
/// **Ausserhalb von macOS kennt diesen Namen niemand.** Die Oberfläche
/// bekam dort still Flutters Standardschrift – nicht die Schrift, mit der
/// die Arbeitsumgebung selbst schreibt.
///
/// `Adwaita Sans` ist die Oberflächenschrift heutiger GNOME-Fassungen und
/// geht auf Inter zurück; sie kommt San Francisco im Schriftbild nahe und
/// ist zugleich die native Wahl. Dahinter stehen Cantarell (ältere
/// GNOME-Fassungen) und Noto Sans für alles andere.
///
/// Dass sie wirklich greift und nicht still ersetzt wird, misst
/// `integration_test/schrift_greift_test.dart` über die Textbreite:
/// Adwaita Sans 608,9 px, DejaVu Sans 653,3 px, unbekannter Name
/// 588,2 px – drei verschiedene Werte, also drei verschiedene Schriften.
/// Windows schreibt seit 11 in `Segoe UI Variable`; ältere Fassungen
/// kennen nur `Segoe UI`, das deshalb im Rückfall gleich dahinter steht.
final String _fontFamily = switch (Platform.operatingSystem) {
  'macos' => '.AppleSystemUIFont',
  'windows' => 'Segoe UI Variable',
  _ => 'Adwaita Sans',
};

/// Nach der ersten Wahl der Reihe nach das, was die jeweilige Umgebung
/// sonst noch hat. Namen fremder Plattformen stören dabei nicht – sie
/// werden schlicht übersprungen.
const _fontFamilyFallback = <String>[
  'Segoe UI',
  'Cantarell',
  'Noto Sans',
  'DejaVu Sans',
];

/// Farben für Warnung und Erfolg.
///
/// Sie fehlen im Material-Farbschema, das nur `error` kennt – und genau
/// deshalb standen vorher überall `Colors.orange` und `Colors.green` im
/// Quelltext. Die sind für den dunklen Modus gemacht: Gegen die helle
/// Oberfläche dieser App gemessen kommt `Colors.orange` auf 2,05:1 und
/// `Colors.green` auf 2,65:1, wo die Zugänglichkeitsrichtlinie 4,5:1
/// verlangt. Die Werte hier sind je Helligkeit eigens gewählt.
class AppSemantik extends ThemeExtension<AppSemantik> {
  /// Für Hinweise, die etwas verhindern oder einschränken – fehlendes
  /// Modell, gesperrte Passphrase, unvollständige Bedingung.
  final Color warnung;

  /// Für gelungene Abschlüsse.
  final Color erfolg;

  const AppSemantik({required this.warnung, required this.erfolg});

  static const _hell = AppSemantik(
    warnung: Color(0xFF8A5000), // 5,9:1 auf heller Oberfläche
    erfolg: Color(0xFF1B5E20), // 8,3:1
  );

  static const _dunkel = AppSemantik(
    warnung: Color(0xFFFFB74D),
    erfolg: Color(0xFF81C784),
  );

  @override
  AppSemantik copyWith({Color? warnung, Color? erfolg}) => AppSemantik(
        warnung: warnung ?? this.warnung,
        erfolg: erfolg ?? this.erfolg,
      );

  @override
  AppSemantik lerp(covariant AppSemantik? other, double t) => other == null
      ? this
      : AppSemantik(
          warnung: Color.lerp(warnung, other.warnung, t)!,
          erfolg: Color.lerp(erfolg, other.erfolg, t)!,
        );
}

/// Farben für die dauerhaft dunklen Arbeitsflächen – Entwickeln, Betrachter,
/// Histogramm, Kurve, Farbmischer.
///
/// Diese Bildschirme richten sich bewusst NICHT nach Hell/Dunkel: Ein Foto
/// beurteilt man vor neutralem Schwarz, sonst färbt die Oberfläche das
/// Urteil. Deshalb stehen die Werte hier fest und nicht in [AppSemantik].
///
/// Die Zahlen daneben sind gemessen (WCAG-Kontrastformel gegen [grund]),
/// nicht geschätzt. Der Anlass: `Colors.white38` stand an sechs Stellen
/// unter erklärendem Text in 11 px – bei 3,44:1, wo 4,5:1 gefordert sind.
/// Als benannte Rolle ist schwerer zu übersehen, welcher Wert wofür gedacht
/// ist.
abstract final class DunkleFlaeche {
  /// Der Grund, gegen den alles andere gemessen ist.
  static const grund = Colors.black;

  /// Beschriftungen und Werte, die man lesen muss. 21:1.
  static const text = Colors.white;

  /// Zweitrangiges, das noch gut lesbar bleibt. 10,0:1.
  static const zweitText = Colors.white70;

  /// Erklärende Hinweise unter Bedienelementen. 6,1:1 – der Material-übliche
  /// Wert für sekundären Text auf dunklem Grund.
  static const hinweis = Colors.white54;

  /// NUR für abgeschaltete Bedienelemente. 3,4:1 – zu wenig für Text, den
  /// jemand lesen soll, aber richtig für etwas, das gerade nicht gilt (die
  /// Zugänglichkeitsrichtlinie nimmt inaktive Elemente ausdrücklich aus).
  static const inaktiv = Colors.white38;

  /// Trennlinien und Rahmen. Kein Text.
  static const linie = Colors.white24;
}

/// Kurzer Weg zu [AppSemantik] – `Theme.of(context).extension<…>()!` an
/// jeder Aufrufstelle wäre nur Lärm.
extension AppSemantikZugriff on BuildContext {
  AppSemantik get semantik => Theme.of(this).extension<AppSemantik>()!;
}

/// Die eine Farbe, aus der Material alles Übrige ableitet.
///
/// **Der einzige Knopf, an dem Geschmack sitzt.** Alles andere in dieser
/// Datei lässt sich begründen; die Wahl des Farbtons nicht. Er steht
/// deshalb hier, benannt und an einer Stelle, statt zweimal im Aufbau.
const Color _saatfarbe = Colors.teal;

/// Warum die Flächen **grau** sind und nicht getönt.
///
/// Materials Vorgabe (`tonalSpot`) zieht den Farbton der Saat durch jede
/// Fläche – Karten, Leisten, Hintergründe bekommen einen Stich. Für die
/// meisten Anwendungen ist das gewollt. Eine Fotoverwaltung ist der
/// Gegenfall: Alles, was hier eine Farbe hat, steht neben einem Bild und
/// verschiebt, wie man dessen Farben sieht. Ein grüner Stich am Rand macht
/// aus einem neutralen Foto ein magentastichiges.
///
/// [DynamicSchemeVariant.neutral] nimmt die Saat aus den Flächen – aber es
/// nimmt sie **auch aus dem Akzent**. Am Vergleichsbild von
/// `aufgaben_optik_test` gesehen: Der Knopf, der eine Aufgabe startet, sah
/// danach aus wie ein abgeschalteter. Ein Akzent, der nicht als Akzent
/// liest, ist keine Verbesserung.
///
/// Deshalb aus zwei Ableitungen zusammengesetzt: die Flächen aus der
/// neutralen, die Akzentfamilie aus der gewöhnlichen. Die Hülle bleibt
/// grau, der Knopf bleibt ein Knopf.
ColorScheme _schema(Brightness helligkeit) {
  final flaechen = ColorScheme.fromSeed(
    seedColor: _saatfarbe,
    brightness: helligkeit,
    dynamicSchemeVariant: DynamicSchemeVariant.neutral,
  );
  final akzent =
      ColorScheme.fromSeed(seedColor: _saatfarbe, brightness: helligkeit);
  return flaechen.copyWith(
    primary: akzent.primary,
    onPrimary: akzent.onPrimary,
    primaryContainer: akzent.primaryContainer,
    onPrimaryContainer: akzent.onPrimaryContainer,
    secondary: akzent.secondary,
    onSecondary: akzent.onSecondary,
    secondaryContainer: akzent.secondaryContainer,
    onSecondaryContainer: akzent.onSecondaryContainer,
    tertiary: akzent.tertiary,
    onTertiary: akzent.onTertiary,
    inversePrimary: akzent.inversePrimary,
  );
}

/// Die gemeinsamen Teile beider Themen.
///
/// **Dichte.** Material 3 ist für Finger auf Telefonen bemessen. Diese App
/// läuft auf dem Schreibtisch, mit Maus, oft in einem sehr breiten
/// Fenster, und zeigt vor allem Listen. `compact` holt in jeder Liste
/// mehrere Zeilen mehr ins Bild, ohne dass etwas schwerer zu treffen wäre.
///
/// **Karten.** Ohne eigene Angabe bringt jede Karte einen Aussenabstand
/// mit, der sich mit dem Abstand der Liste addiert. Einmal hier gesetzt
/// statt an jeder Karte nachgebessert.
ThemeData _grundthema(Brightness helligkeit, AppSemantik semantik) {
  final schema = _schema(helligkeit);
  return ThemeData(
    useMaterial3: true,
    colorScheme: schema,
    fontFamily: _fontFamily,
    fontFamilyFallback: _fontFamilyFallback,
    visualDensity: VisualDensity.compact,
    cardTheme: CardThemeData(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: schema.outlineVariant),
      ),
    ),
    dividerTheme: DividerThemeData(
      space: 1,
      thickness: 1,
      color: schema.outlineVariant,
    ),
    extensions: [semantik],
  );
}

ThemeData buildLightTheme() =>
    _grundthema(Brightness.light, AppSemantik._hell);

ThemeData buildDarkTheme() => _grundthema(Brightness.dark, AppSemantik._dunkel);

/// Ziffern, die untereinander stehen bleiben.
///
/// Wo Zahlen in Spalten oder in einer Zeile stehen, die sich laufend
/// ändert – Belegung, Fortschritt, Kennzahlen –, wandert der Text bei
/// proportionalen Ziffern bei jeder Änderung hin und her. Eine `1` ist in
/// den meisten Schriften schmaler als eine `8`.
///
/// Als Erweiterung auf [TextStyle], damit an der Aufrufstelle
/// `.mitTabellenziffern` steht und nicht drei Zeilen `fontFeatures`.
extension Tabellenziffern on TextStyle {
  TextStyle get mitTabellenziffern =>
      copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}

/// Wandelt den in [AppSettings.themeMode] gespeicherten String
/// ('system'|'light'|'dark') in ein [ThemeMode] um – unbekannte/fehlende
/// Werte (z.B. noch keine Zeile in der DB) fallen auf System zurück.
ThemeMode themeModeFromString(String? value) {
  switch (value) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

/// Wandelt den in [AppSettings.sprache] gespeicherten String
/// ('system'|'de'|'en') in eine [Locale] um.
///
/// `null` als Rückgabe ist kein Fehlerfall, sondern die Antwort auf
/// „Systemsprache": Flutter wählt dann selbst aus [supportedLocales] die
/// passende aus. Es braucht dafür also keinen Sonderfall im Aufrufer.
///
/// Unbekannte Angaben – etwa aus einer neueren Fassung, die schon mehr
/// Sprachen kennt – gelten ebenfalls als Systemsprache, statt den Start
/// zu verhindern.
Locale? localeFromString(String? value) {
  switch (value) {
    case 'de':
      return const Locale('de');
    case 'en':
      return const Locale('en');
    default:
      return null;
  }
}

String themeModeToString(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return 'light';
    case ThemeMode.dark:
      return 'dark';
    case ThemeMode.system:
      return 'system';
  }
}
