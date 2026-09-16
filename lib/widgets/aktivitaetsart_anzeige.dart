/// Wie eine Aktivitätsart aussieht und heisst.
///
/// An einer Stelle, damit Liste, Vorschlag, Kapitel und Detailansicht
/// nicht auseinanderlaufen: Ein Symbol, das in der Liste ein Fahrrad und
/// im Kapitel ein Auto ist, macht aus einer Ordnung ein Rätsel.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/aktivitaeten.dart';
import '../theme/app_spacing.dart';
import 'namens_dialog.dart';

IconData symbolFuerArt(Aktivitaetsart art) => switch (art) {
      Aktivitaetsart.spaziergang => Icons.directions_walk,
      Aktivitaetsart.wanderung => Icons.hiking,
      Aktivitaetsart.radtour => Icons.directions_bike,
      Aktivitaetsart.ausflug => Icons.directions_car_outlined,
      Aktivitaetsart.besichtigung => Icons.museum_outlined,
      Aktivitaetsart.bootsfahrt => Icons.directions_boat_outlined,
      Aktivitaetsart.sonstiges => Icons.explore_outlined,
    };

String nameFuerArt(AppTexte t, Aktivitaetsart art) => switch (art) {
      Aktivitaetsart.spaziergang => t.aktArtSpaziergang,
      Aktivitaetsart.wanderung => t.aktArtWanderung,
      Aktivitaetsart.radtour => t.aktArtRadtour,
      Aktivitaetsart.ausflug => t.aktArtAusflug,
      Aktivitaetsart.besichtigung => t.aktArtBesichtigung,
      Aktivitaetsart.bootsfahrt => t.aktArtBootsfahrt,
      Aktivitaetsart.sonstiges => t.aktArtSonstiges,
    };

/// Das Symbol zu einer Kennung aus der Datenbank – auch zu einer selbst
/// eingetragenen.
///
/// Eigene Arten bekommen alle dasselbe Zeichen. Ein geratenes Symbol
/// wäre schlimmer als ein neutrales: Wer „Konzert" einträgt und ein
/// Fahrrad danebenstehen sieht, glaubt der Ordnung nicht mehr.
IconData symbolFuerKennung(String kennung) => istBekannteArt(kennung)
    ? symbolFuerArt(Aktivitaetsart.aus(kennung))
    : Icons.label_outline;

/// Der Name zu einer Kennung – bei einer eigenen Art ihr eigener Text.
///
/// Ohne diese Unterscheidung stünde bei jeder selbst eingetragenen Art
/// „Sonstiges": [Aktivitaetsart.aus] macht aus allem Unbekannten den
/// Auffangfall, und der Name wäre nur noch in der Datenbank zu finden.
String nameFuerKennung(AppTexte t, String kennung) => istBekannteArt(kennung)
    ? nameFuerArt(t, Aktivitaetsart.aus(kennung))
    : kennung;

/// Die Namen der mitgelieferten Arten – für den Abgleich in
/// [eigeneArtKennung].
Map<Aktivitaetsart, String> bekannteArtnamen(AppTexte t) =>
    {for (final a in Aktivitaetsart.values) a: nameFuerArt(t, a)};

/// Eine Dauer, wie man sie sagt: „3 h 20 min", unter einer Stunde nur
/// die Minuten.
String dauertext(AppTexte t, Duration d) {
  final minuten = d.inMinutes;
  if (minuten < 60) return t.aktivitaetenDauerKurz(minuten);
  return t.aktivitaetenDauer(minuten ~/ 60, minuten % 60);
}

/// Eine Strecke mit einer Nachkommastelle – „12,4 km".
///
/// Eine Stelle und nicht drei: Die Zahl entsteht aus Luftlinien zwischen
/// Fotos. Sie auf Meter genau zu drucken wäre eine Genauigkeit, die
/// nirgends herkommt.
///
/// Über [NumberFormat] und nicht über `toStringAsFixed`: Das Komma
/// gehört zur Sprache, und „12.4 km" liest sich auf Deutsch falsch.
String streckentext(AppTexte t, Locale locale, double km) =>
    t.aktivitaetenStrecke(NumberFormat.decimalPatternDigits(
      locale: locale.toString(),
      decimalDigits: 1,
    ).format(km));

/// Fragt nach der Art einer Aktivität und gibt ihre Kennung zurück.
///
/// Gezeigt werden die mitgelieferten Arten, danach die selbst
/// eingetragenen (siehe [AppDatabase.eigeneAktivitaetsarten]) und zuletzt
/// der Weg zu einer neuen.
///
/// **Warum eine eigene Art überhaupt geht.** Die Spalte ist Text, nicht
/// Zahl – eine eigene Art kostet deshalb keinen Schemaschritt. Sie hat
/// dafür kein Symbol und keine Übersetzung; beides wäre geraten.
///
/// `null` heisst „abgebrochen".
Future<String?> frageAktivitaetsart(
  BuildContext context, {
  required AppDatabase db,
  String? aktuell,
}) async {
  final t = AppTexte.of(context);
  final eigene = await db.eigeneAktivitaetsarten();
  if (!context.mounted) return null;

  Widget zeile(String kennung) => Row(
        children: [
          Icon(symbolFuerKennung(kennung)),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(nameFuerKennung(t, kennung))),
          if (kennung == aktuell) const Icon(Icons.check, size: 18),
        ],
      );

  final wahl = await showDialog<String>(
    context: context,
    builder: (dialog) => SimpleDialog(
      title: Text(t.aktivitaetenArtAendern),
      children: [
        for (final a in Aktivitaetsart.values)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialog, a.kennung),
            child: zeile(a.kennung),
          ),
        for (final k in eigene)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialog, k),
            child: zeile(k),
          ),
        const Divider(),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(dialog, _neueArt),
          child: Row(
            children: [
              const Icon(Icons.add),
              const SizedBox(width: AppSpacing.md),
              Text(t.aktivitaetenArtNeu),
            ],
          ),
        ),
      ],
    ),
  );
  if (wahl != _neueArt) return wahl;
  if (!context.mounted) return null;

  final eingabe = await frageNamen(
    context,
    titel: t.aktivitaetenArtNeu,
    feldbeschriftung: t.aktivitaetenArtNeuFrage,
    vorgabe: '',
  );
  if (eingabe == null || !context.mounted) return null;
  return eigeneArtKennung(eingabe, bekannteArtnamen(t));
}

/// Kennzeichen für „neue Art" im Auswahlfenster. Ein Wert, der als Art
/// nicht vorkommen kann – [eigeneArtKennung] gibt nie einen leeren oder
/// mit einem Steuerzeichen beginnenden Text zurück.
const _neueArt = '\u0000neu';
