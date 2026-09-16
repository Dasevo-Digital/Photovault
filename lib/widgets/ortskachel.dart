import 'package:flutter/material.dart';

import '../db/database.dart';
import '../db/rasterzeile.dart';
import '../l10n/app_localizations.dart';
import '../services/storage_paths.dart';
import '../theme/app_spacing.dart';
import 'asset_thumbnail_tile.dart';
import '../services/laendernamen.dart';

/// Der Kopf einer Übersicht: Sinnbild, Titel, und darunter die Zahlen.
///
/// **Warum die Zahlen in den Kopf und nicht in eine eigene Karte.** Sie
/// beantworten die Frage, die man beim Öffnen stellt („wie viel ist das
/// überhaupt?"), und zwar bevor man zu scrollen anfängt. In einer Karte
/// zwischen den Einträgen wären sie eine Zeile wie jede andere.
class Uebersichtskopf extends StatelessWidget {
  final IconData symbol;
  final String titel;

  /// Die Zahlen, mit Mittelpunkten verbunden. Leere Einträge fallen
  /// weg – eine Bibliothek ohne Ortsdaten soll nicht „0 Orte" behaupten
  /// müssen.
  final List<String> zahlen;

  const Uebersichtskopf({
    super.key,
    required this.symbol,
    required this.titel,
    required this.zahlen,
  });

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final gefuellt = [for (final z in zahlen) if (z.isNotEmpty) z];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: farben.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(symbol, color: farben.onPrimaryContainer),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(titel, style: Theme.of(context).textTheme.headlineSmall),
                if (gefuellt.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      gefuellt.join(' • '),
                      style: TextStyle(
                          fontSize: 13, color: farben.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Die Ortszeile einer Kachel: „Ort, Region, Land" – und, wenn es mehr
/// als einen Ort gab, wie viele weitere.
///
/// Gibt `null` zurück, wenn keine Aufnahme einen Ort trug. Das ist
/// Absicht und kein Versehen: „Unbekannt" hinzuschreiben behauptet, es
/// sei nachgesehen worden und nichts dabei herausgekommen. In Wahrheit
/// hat schlicht keine Aufnahme eine Koordinate – oft, weil der
/// GeoNames-Datensatz gar nicht eingespielt ist.
///
/// Land und Region dürfen einzeln fehlen; die Zeile wird dann kürzer,
/// statt Kommas ins Leere zu setzen.
String? ortszeile(AppTexte t, Ortsbezug? bezug, {required String sprache}) {
  if (bezug == null || bezug.ort == null) return null;
  final teile = [
    bezug.ort!,
    if (bezug.region case final r? when r.isNotEmpty && r != bezug.ort) r,
    // Der Datensatz kennt Länder nur englisch (siehe [landAnzeige]); Orte
    // und Regionen kommen unverändert durch.
    if (landAnzeige(bezug.land, sprache) case final l when l.isNotEmpty) l,
  ].join(', ');
  return bezug.weitereOrte == 0
      ? teile
      : '$teile · ${t.ortsbezugWeitere(bezug.weitereOrte)}';
}

/// Ein Eintrag im ⋯-Menü einer [Ortskachel].
typedef Kachelbefehl = ({IconData symbol, String text, VoidCallback tun});

/// Eine Reise oder Aktivität als Kachel: Titelbild, Art, Name, Ort.
///
/// **Der Unterschied zur bisherigen Zeile.** Eine `ListTile` mit
/// 52-Punkte-Vorschau zeigt Namen und Zeitraum; wo etwas stattfand, stand
/// nirgends – dabei ist genau das die Frage, mit der man eine Reiseliste
/// öffnet. Die Kachel hat Platz für den Ort, und das Titelbild ist gross
/// genug, um eine Reise daran wiederzuerkennen.
///
/// Beide Übersichten benutzen dieselbe Kachel. Reisen und Aktivitäten
/// unterscheiden sich in dem, was auf dem Bild steht ([kennzeichen]) –
/// nicht im Aufbau.
class Ortskachel extends StatelessWidget {
  /// Das Titelbild. `null` heisst: keins vorhanden – dann steht [symbol]
  /// auf einer ruhigen Fläche.
  final AssetData? bild;
  final StoragePaths paths;

  final IconData symbol;
  final String name;

  /// Das Schildchen unten links auf dem Bild – die Art der Aktivität,
  /// die Zahl der Nächte einer Reise.
  final String kennzeichen;

  /// Der Zeitraum, oben links auf dem Bild. Kurz gehalten: Auf dem Bild
  /// ist Platz für ein Jahr, nicht für zwei volle Daten.
  final String zeitraum;

  /// Wo es stattfand. `null` heisst: keine Aufnahme trug einen Ort –
  /// dann bleibt die Zeile weg, statt einen Platzhalter zu zeigen.
  final String? ort;

  final VoidCallback onTippen;
  final List<Kachelbefehl> befehle;

  const Ortskachel({
    super.key,
    required this.bild,
    required this.paths,
    required this.symbol,
    required this.name,
    required this.kennzeichen,
    required this.zeitraum,
    required this.ort,
    required this.onTippen,
    this.befehle = const [],
  });

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTippen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Der Textteil bekommt eine feste Höhe, das Bild den Rest –
            // und **nicht umgekehrt**. Zwei Gründe, beide am Bildschirm
            // nachgesehen:
            //
            // Erstens sässe der Trennstrich zwischen Bild und Text sonst
            // in jeder Kachel woanders: Ein einzeiliger Name braucht
            // weniger Platz als ein zweizeiliger, eine Kachel ohne
            // Ortszeile noch weniger. In einer Reihe nebeneinander sieht
            // das aus, als wäre etwas verrutscht.
            //
            // Zweitens kann so nichts überlaufen. Die Kachelhöhe steht
            // fest (siehe [kachelHoehe]); gibt der Text nach, entsteht
            // der rote Balken. Gibt das Bild nach, wird es ein paar
            // Punkte flacher – und das fällt niemandem auf.
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (bild case final b?)
                    AssetThumbnailTile(
                        asset: Rasterzeile.aus(b), paths: paths, onTap: onTippen)
                  else
                    ColoredBox(
                      color: farben.surfaceContainerHighest,
                      child: Icon(symbol,
                          size: 40, color: farben.onSurfaceVariant),
                    ),
                  Positioned(
                    top: AppSpacing.sm,
                    left: AppSpacing.sm,
                    child: _Schildchen(text: zeitraum),
                  ),
                  Positioned(
                    bottom: AppSpacing.sm,
                    left: AppSpacing.sm,
                    child: _Schildchen(text: kennzeichen, symbol: symbol),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: MediaQuery.textScalerOf(context).scale(_textblockHoehe),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.md, AppSpacing.sm, AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            // Zeilenhöhe ausdrücklich: Aus ihr rechnet
                            // sich [_textblockHoehe], und die Vorgabe des
                            // Schriftschnitts könnte sich mit dem Theme
                            // ändern, ohne dass es hier auffiele.
                            style: TextStyle(
                              fontSize: _nameGroesse,
                              height: _nameZeile / _nameGroesse,
                              fontWeight: FontWeight.w500,
                              color: farben.onSurface,
                            ),
                          ),
                        ),
                        if (befehle.isNotEmpty)
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: PopupMenuButton<Kachelbefehl>(
                              padding: EdgeInsets.zero,
                              iconSize: 18,
                              tooltip: '',
                              onSelected: (b) => b.tun(),
                              itemBuilder: (_) => [
                                for (final b in befehle)
                                  PopupMenuItem(
                                    value: b,
                                    child: Row(children: [
                                      Icon(b.symbol, size: 18),
                                      const SizedBox(width: AppSpacing.md),
                                      Text(b.text),
                                    ]),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    if (ort case final o?) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.place_outlined,
                              size: 15, color: farben.onSurfaceVariant),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              o,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: _ortGroesse,
                                height: _ortZeile / _ortGroesse,
                                color: farben.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ein Schildchen auf dem Titelbild.
///
/// Eigener Grund, nicht bloss halbdurchsichtig: Ein Bild kann an dieser
/// Stelle hell oder dunkel sein, und heller Text auf hellem Himmel wäre
/// unlesbar. Der Grund kommt aus dem Farbschema und trägt seine eigene
/// Vordergrundfarbe mit – dieselbe Überlegung wie bei der Namensnennung
/// auf der Karte.
class _Schildchen extends StatelessWidget {
  final String text;
  final IconData? symbol;

  const _Schildchen({required this.text, this.symbol});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final farben = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: farben.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (symbol case final s?) ...[
              Icon(s, size: 13, color: farben.onSurface),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(
              text,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: farben.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

/// Die Breite, ab der eine weitere Spalte Kacheln passt.
///
/// 340 Punkte, an der Kachel selbst abgelesen: Darunter bricht der Name
/// zweizeilig um und die Ortszeile wird abgeschnitten. `GridView` teilt
/// die vorhandene Breite dann in so viele gleich breite Spalten, dass
/// keine schmaler wird – ein festes Raster hiesse auf einem schmalen
/// Fenster abgeschnittene Kacheln und auf einem breiten drei Spalten
/// Leere daneben.
const kachelBreite = 340.0;

/// Das Raster für [Ortskachel]n, als Sliver.
///
/// Als Sliver und nicht als `GridView` mit `shrinkWrap`: Jenes baut
/// **alle** Kacheln auf einmal, auch die weit ausserhalb des Bildes. Bei
/// dreissig Reisen fällt das nicht auf, bei dreihundert Aktivitäten
/// schon – und jede Kachel holt ihr Titelbild.
class Kachelraster extends StatelessWidget {
  final List<Widget> kacheln;
  const Kachelraster({super.key, required this.kacheln});

  @override
  Widget build(BuildContext context) => SliverGrid(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: kachelBreite,
          mainAxisSpacing: AppSpacing.lg,
          crossAxisSpacing: AppSpacing.lg,
          mainAxisExtent: kachelHoehe(context),
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => kacheln[i],
          childCount: kacheln.length,
        ),
      );
}

/// Die Höhe einer Kachel.
///
/// **Fest und nicht nach Inhalt** – Kacheln unterschiedlicher Höhe
/// nebeneinander sähen aus wie ein Fehler. Der Preis dafür: Bei einer
/// Kachel ohne Ortszeile bleibt unten etwas Luft. Das ist die bessere
/// Hälfte des Tauschs.
///
/// **Aber sie wächst mit der Schrift.** Wer die Systemschrift
/// vergrössert, bekommt einen zweizeiligen Namen dort, wo sonst einer
/// steht – bei fester Höhe liefe der Text über und Flutter zeichnete
/// den roten Balken quer über die Kachel. Das Bild gibt zwar zuerst
/// nach (siehe [Ortskachel]), aber irgendwann ist auch dort nichts mehr
/// zu holen.
///
/// Der Bildteil rechnet mit der **vollen** Kachelbreite: In einer
/// schmaleren Spalte wird das Bild dadurch etwas höher als 16:10 – eine
/// Kachel, die dort plötzlich niedriger wäre als nebenan, sähe verkehrt
/// aus.
double kachelHoehe(BuildContext context) =>
    kachelBreite / 1.6 +
    MediaQuery.textScalerOf(context).scale(_textblockHoehe);

const _nameGroesse = 16.0;
const _nameZeile = 21.0;
const _ortGroesse = 13.0;
const _ortZeile = 17.0;

/// Was der Textteil einer Kachel bei normaler Schriftgrösse braucht:
/// zweimal Innenabstand, ein **zweizeiliger** Name, der Zwischenraum und
/// eine **zweizeilige** Ortsangabe.
///
/// Immer für zwei Zeilen gerechnet, auch wenn eine reicht. Sonst
/// sprängen Trennstrich und Ortszeile von Kachel zu Kachel – der Grund,
/// warum die Zeilenhöhen oben ausdrücklich dastehen statt aus dem Theme
/// zu kommen: Diese Rechnung muss aufgehen, sonst läuft der Text über.
/// Ob sie aufgeht, prüft `ortskachel_test.dart` über vier Fensterbreiten
/// und drei Schriftgrössen.
const _textblockHoehe =
    2 * AppSpacing.md + 2 * _nameZeile + AppSpacing.sm + 2 * _ortZeile;
