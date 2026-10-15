import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:kern/db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/fotobuch.dart';
import 'package:kern/services/laendernamen.dart';
import '../services/meldungsdienst.dart';
import '../services/native_image_converter.dart';
import '../services/platform/speicherort.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import 'einfuegbares_menue.dart';

/// [dateiname] mit der Endung des Fotobuchs statt der bisherigen – aus
/// dem Namen einer Diashow wird so der des Buches.
String mitPdfEndung(String dateiname) {
  final punkt = dateiname.lastIndexOf('.');
  final stamm = punkt > 0 ? dateiname.substring(0, punkt) : dateiname;
  return '$stamm.$fotobuchFormatKuerzel';
}

/// Ein Dateiname aus einem Titel: ohne die Zeichen, die ein Dateisystem
/// ablehnt.
String dateinameAus(String titel) {
  final sauber = titel.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').trim();
  return sauber.isEmpty ? fotobuchFormatKuerzel : sauber;
}

/// Wie das Fotobuch aussehen soll – die Antwort des Dialogs.
typedef Fotobuchwahl = ({
  String titel,
  Fotobuchformat format,
  int jeSeite,
  Set<Fotobuchangabe> angaben,
});

/// Die zuletzt gewählte Gestaltung, für die Dauer der Sitzung. Wer ein
/// zweites Buch macht, will meist dasselbe noch einmal.
Fotobuchwahl? _zuletzt;

/// Macht aus [aufnahmen] ein Fotobuch als PDF – mit Rückfrage nach der
/// Gestaltung und dem Ziel und einem Fenster, das den Fortschritt zeigt
/// und abbrechen lässt.
///
/// Nur Fotos, und keine gesperrten – aus demselben Grund wie bei der
/// Diashow: Ein Buch, das man druckt und weitergibt, ist kein Ort für den
/// Tresor. Die Reihenfolge ist die der Auswahl.
Future<void> fotobuchExportieren(
  BuildContext context,
  LibraryState library,
  List<AssetData> aufnahmen, {
  String titel = '',
  String? untertitel,
  required String dateiname,
}) async {
  final t = AppTexte.of(context);
  final sprache = Localizations.localeOf(context);
  final alleFotos = [
    for (final a in aufnahmen)
      if (a.type != 'VIDEO' && !a.isLocked) a,
  ];
  if (alleFotos.isEmpty) {
    melde.hinweis(t.fotobuchKeineFotos);
    return;
  }
  final fotos = alleFotos.take(fotobuchHoechstensBilder).toList();
  final wahl = await showDialog<Fotobuchwahl>(
    context: context,
    builder: (_) =>
        _FotobuchDialog(titel: titel, anzahl: fotos.length, vorher: _zuletzt),
  );
  if (wahl == null || !context.mounted) return;
  _zuletzt = wahl;
  final pfad = await waehleSpeicherort(
    dialogTitel: t.fotobuchSpeichern,
    dateiname: dateiname,
    mitEndung: (pfad) => mitDateiendung(pfad, fotobuchFormatKuerzel),
  );
  if (pfad == null || !context.mounted) return;

  final stand = ValueNotifier<double>(0);
  var abbrechen = false;
  final fenster = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (kontext) => AlertDialog(
      title: Text(t.fotobuchWirdErstellt),
      content: ValueListenableBuilder<double>(
        valueListenable: stand,
        builder: (_, anteil, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: anteil),
            const SizedBox(height: 8),
            Text(t.fotobuchUmfang(fotos.length)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => abbrechen = true,
          child: Text(t.allgAbbrechen),
        ),
      ],
    ),
  );

  Object? fehler;
  ({int seiten, int bilder})? fertig;
  try {
    fertig = await erstelleFotobuch(
      library,
      fotos,
      wahl,
      ziel: File(pfad),
      untertitel: untertitel,
      datum: (a) => a.datumGeschaetzt
          ? t.fotobuchUmJahr(a.fileCreatedAt.year)
          : DateFormat.yMMMMd(sprache.toString()).format(a.fileCreatedAt),
      sprache: sprache.languageCode,
      fortschritt: (a) => stand.value = a,
      abbruch: () => abbrechen,
    );
  } catch (e) {
    fehler = e;
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  await fenster;
  stand.dispose();

  final uebersprungen =
      aufnahmen.length -
      (fertig?.bilder ?? 0) -
      (alleFotos.length - fotos.length);
  if (fehler != null) {
    melde.fehler(t.fotobuchFehler('$fehler'));
  } else if (abbrechen) {
    melde.hinweis(t.fotobuchAbgebrochen);
  } else if (fertig == null || fertig.bilder == 0) {
    melde.warnung(t.fotobuchKeineFotos);
  } else {
    melde.erfolg(
      [
        t.fotobuchFertig(File(pfad).uri.pathSegments.last, fertig.seiten),
        if (alleFotos.length > fotos.length)
          t.fotobuchGekuerzt(fotobuchHoechstensBilder),
        if (uebersprungen > 0) t.fotobuchUebersprungen(uebersprungen),
      ].join(' '),
    );
  }
}

/// Wandelt eine Bilddatei in ein JPEG mit höchstens [maxDimension]
/// Pixeln an der längeren Kante – in der App der native Wandler.
typedef Fotobuchwandler =
    Future<Uint8List?> Function(File datei, {int? maxDimension});

Future<Uint8List?> _nativ(File datei, {int? maxDimension}) =>
    NativeImageConverter.convertToJpegBytes(
      datei,
      maxDimension: maxDimension,
      quality: 0.9,
    );

/// Lädt die Bilder, plant die Seiten, baut das PDF und schreibt es.
/// `null`, wenn abgebrochen wurde.
///
/// [fotos] sind schon gefiltert (keine Videos, nichts Gesperrtes). Wer
/// sich nicht wandeln lässt, bleibt draussen und fehlt in `bilder`.
Future<({int seiten, int bilder})?> erstelleFotobuch(
  LibraryState library,
  List<AssetData> fotos,
  Fotobuchwahl wahl, {
  required File ziel,
  required String? untertitel,
  required String Function(AssetData a) datum,
  required String sprache,
  required void Function(double anteil) fortschritt,
  required bool Function() abbruch,
  Fotobuchwandler wandle = _nativ,
}) async {
  final mitUnterschrift = wahl.angaben.isNotEmpty;
  // Erst planen, dann laden: Wie gross ein Bild gerechnet werden muss,
  // hängt davon ab, wo es steht – und das aus den gespeicherten Massen.
  // Fehlen sie, gilt das übliche Kameraformat.
  final vorlaeufig = fotobuchPlan(
    [
      for (final a in fotos)
        (a.widthPx ?? 0) > 0 && (a.heightPx ?? 0) > 0
            ? a.widthPx! / a.heightPx!
            : 1.5,
    ],
    format: wahl.format,
    jeSeite: wahl.jeSeite,
    mitUnterschrift: mitUnterschrift,
  );
  final pixel = <int, int>{};
  for (final s in vorlaeufig) {
    for (final (k, i) in s.bilder.indexed) {
      pixel[i] = fotobuchPixel(
        fotobuchBildIn(s.zellen[k], 1, mitUnterschrift: mitUnterschrift),
      );
    }
  }

  final bilder = <Fotobuchbild>[];
  for (final (i, a) in fotos.indexed) {
    if (abbruch()) return null;
    fortschritt(0.9 * i / fotos.length);
    // Was der Betrachter zeigt: restauriert, entwickelt, sonst das
    // Original. Die Vorschau eines RAW ist für den Druck zu klein – dann
    // lieber das Original, gewandelt in genau der nötigen Grösse.
    final abgeleitet = a.restoredRelativePath ?? a.developedRelativePath;
    // In einer verbundenen Bibliothek erst vom Server geholt; gibt es die
    // abgeleitete Datei dort nicht, bleibt es beim Original.
    File datei;
    try {
      datei = await library.paths.bereit(abgeleitet ?? a.relativePath);
    } catch (_) {
      datei = library.paths.absolute(a.relativePath);
    }
    if (!await datei.exists()) {
      datei = await library.paths.bereit(a.relativePath);
    }
    final roh = await wandle(datei, maxDimension: pixel[i]);
    if (roh == null) continue;
    final jpeg = jpegOhneBeipackzettel(roh);
    final groesse = jpegGroesse(jpeg);
    if (groesse == null) continue;
    final personen = wahl.angaben.contains(Fotobuchangabe.personen)
        ? ([...await library.db.gesichtsregionenVon(a.id)]
                ..sort((x, y) => x.links.compareTo(y.links)))
              .map((g) => g.name)
              .toList()
        : const <String>[];
    bilder.add(
      Fotobuchbild(
        jpeg: jpeg,
        breite: groesse.$1,
        hoehe: groesse.$2,
        unterschrift: fotobuchUnterschrift(
          datum: wahl.angaben.contains(Fotobuchangabe.datum) ? datum(a) : null,
          ort: wahl.angaben.contains(Fotobuchangabe.ort)
              ? _ort(a, sprache)
              : null,
          personen: personen,
          beschreibung: wahl.angaben.contains(Fotobuchangabe.beschreibung)
              ? a.description
              : null,
        ),
      ),
    );
  }
  if (abbruch()) return null;
  if (bilder.isEmpty) return (seiten: 0, bilder: 0);

  // Neu geplant mit den Massen, die die Bilder wirklich haben: Ein
  // gedrehtes Hochformat ist in den gespeicherten Massen manchmal quer.
  final seiten = fotobuchPlan(
    [for (final b in bilder) b.verhaeltnis],
    format: wahl.format,
    jeSeite: wahl.jeSeite,
    mitUnterschrift: mitUnterschrift,
  );
  fortschritt(0.92);
  final pdf = await baueFotobuch(
    bilder: bilder,
    seiten: seiten,
    format: wahl.format,
    mitUnterschrift: mitUnterschrift,
    schrift: await rootBundle.load(fotobuchSchriftDatei),
    titel: wahl.titel,
    untertitel: untertitel,
  );
  if (abbruch()) return null;
  await ziel.writeAsBytes(pdf, flush: true);
  fortschritt(1);
  final titelseite = wahl.titel.trim().isEmpty ? 0 : 1;
  return (seiten: seiten.length + titelseite, bilder: bilder.length);
}

String? _ort(AssetData a, String sprache) {
  final teile = [
    a.locationCity,
    landAnzeige(a.locationCountry, sprache),
  ].whereType<String>().where((s) => s.isNotEmpty);
  return teile.isEmpty ? null : teile.join(', ');
}

/// Der Dialog für die Gestaltung.
class _FotobuchDialog extends StatefulWidget {
  final String titel;
  final int anzahl;
  final Fotobuchwahl? vorher;

  const _FotobuchDialog({
    required this.titel,
    required this.anzahl,
    this.vorher,
  });

  @override
  State<_FotobuchDialog> createState() => _FotobuchDialogState();
}

class _FotobuchDialogState extends State<_FotobuchDialog> {
  late final TextEditingController _titel = TextEditingController(
    text: widget.titel,
  );
  late Fotobuchformat _format = widget.vorher?.format ?? Fotobuchformat.a4Hoch;
  late int _jeSeite = widget.vorher?.jeSeite ?? 1;
  late final Set<Fotobuchangabe> _angaben = {
    ...(widget.vorher?.angaben ??
        {Fotobuchangabe.datum, Fotobuchangabe.ort, Fotobuchangabe.personen}),
  };

  @override
  void dispose() {
    _titel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final stil = Theme.of(context).textTheme.labelLarge;
    return AlertDialog(
      title: Text(t.fotobuchGestalten),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.fotobuchUmfang(widget.anzahl)),
              const SizedBox(height: AppSpacing.md),
              TextField(
                contextMenuBuilder: einfuegbaresMenue,
                controller: _titel,
                decoration: InputDecoration(
                  labelText: t.fotobuchTitelseite,
                  helperText: t.fotobuchTitelseiteHinweis,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(t.fotobuchFormat, style: stil),
              const SizedBox(height: AppSpacing.xs),
              SegmentedButton<Fotobuchformat>(
                segments: [
                  ButtonSegment(
                    value: Fotobuchformat.a4Hoch,
                    label: Text(t.fotobuchA4Hoch),
                  ),
                  ButtonSegment(
                    value: Fotobuchformat.a4Quer,
                    label: Text(t.fotobuchA4Quer),
                  ),
                  ButtonSegment(
                    value: Fotobuchformat.quadrat,
                    label: Text(t.fotobuchQuadrat),
                  ),
                ],
                selected: {_format},
                showSelectedIcon: false,
                onSelectionChanged: (w) => setState(() => _format = w.first),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(t.fotobuchJeSeite, style: stil),
              const SizedBox(height: AppSpacing.xs),
              SegmentedButton<int>(
                segments: [
                  for (final n in fotobuchBilderJeSeite)
                    ButtonSegment(value: n, label: Text('$n')),
                ],
                selected: {_jeSeite},
                showSelectedIcon: false,
                onSelectionChanged: (w) => setState(() => _jeSeite = w.first),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(t.fotobuchUnterschrift, style: stil),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final (angabe, name) in [
                    (Fotobuchangabe.datum, t.fotobuchMitDatum),
                    (Fotobuchangabe.ort, t.fotobuchMitOrt),
                    (Fotobuchangabe.personen, t.fotobuchMitPersonen),
                    (Fotobuchangabe.beschreibung, t.fotobuchMitBeschreibung),
                  ])
                    FilterChip(
                      label: Text(name),
                      selected: _angaben.contains(angabe),
                      onSelected: (an) => setState(
                        () =>
                            an ? _angaben.add(angabe) : _angaben.remove(angabe),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.allgAbbrechen),
        ),
        FilledButton(
          onPressed: () => Navigator.pop<Fotobuchwahl>(context, (
            titel: _titel.text.trim(),
            format: _format,
            jeSeite: _jeSeite,
            angaben: {..._angaben},
          )),
          child: Text(t.fotobuchErstellen),
        ),
      ],
    );
  }
}
