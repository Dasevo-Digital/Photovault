import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:kern/db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/platform/speicherort.dart';
import 'package:kern/services/asset_display_path.dart';
import '../services/diashow.dart';
import '../services/flugvideo.dart';
import '../services/meldungsdienst.dart';
import '../services/tonspur.dart';
import '../state/library_state.dart';
import '../theme/zierbaum_farben.dart' show zierschrift;

/// Macht aus [aufnahmen] eine Diashow als MP4 – mit Rückfrage nach dem
/// Ziel und einem Fenster, das den Fortschritt zeigt und abbrechen lässt.
///
/// Nur Fotos: Ein Video in einer Diashow müsste mitlaufen, und das kann
/// diese Ausgabe nicht. Gesperrte Aufnahmen bleiben ebenfalls draussen –
/// ein Video, das man weitergibt, ist kein Ort für den Tresor.
Future<void> diashowExportieren(
  BuildContext context,
  LibraryState library,
  List<AssetData> aufnahmen, {
  required String titel,
  String? untertitel,
  required String dateiname,
}) async {
  final t = AppTexte.of(context);
  final alleFotos = [
    for (final a in aufnahmen)
      if (a.type != 'VIDEO' && !a.isLocked) a,
  ];
  final fotos = alleFotos.take(diashowHoechstensBilder).toList();
  // Gesagt, nicht still gekürzt – wie beim Fotobuch (BEA-109).
  final gekuerzt = alleFotos.length > fotos.length;
  if (fotos.isEmpty) {
    melde.hinweis(t.diashowKeineFotos);
    return;
  }
  if (!await videoausgabeMoeglich()) {
    melde.warnung(t.flugVideoKeinWerkzeug);
    return;
  }
  if (!context.mounted) return;
  final musik = await _frageNachMusik(context);
  if (musik == null || !context.mounted) return;
  final pfad = await waehleSpeicherort(
    dialogTitel: t.diashowSpeichern,
    dateiname: dateiname,
    mitEndung: (pfad) => mitDateiendung(pfad, 'mp4'),
  );
  if (pfad == null || !context.mounted) return;
  final ziel = File(pfad);

  final stand = ValueNotifier<double>(0);
  var abbrechen = false;
  final fenster = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (kontext) => AlertDialog(
      title: Text(t.diashowWirdErstellt),
      content: ValueListenableBuilder<double>(
        valueListenable: stand,
        builder: (_, anteil, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: anteil),
            const SizedBox(height: 8),
            Text(t.diashowUmfang(fotos.length)),
            if (gekuerzt) ...[
              const SizedBox(height: 4),
              Text(t.diashowGekuerzt(diashowHoechstensBilder)),
            ],
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

  // Mit Musik entsteht das stumme Video erst daneben; die Tonspur kommt
  // im zweiten Schritt und schreibt das Ziel (siehe tonspur.dart).
  final stumm = musik.datei == null
      ? ziel
      : File(
          '${(await Directory.systemTemp.createTemp('pv_diashow_')).path}'
          '/stumm.mp4',
        );
  var ergebnis = await schreibeDiashow(
    ziel: stumm,
    dateien: [
      for (final a in fotos)
        await library.paths.bereit(
          displayRelativePath(a, mitAnsichtsbild: false),
        ),
    ],
    titel: titel,
    untertitel: untertitel,
    schrift: zierschrift,
    fortschritt: (a) => stand.value = a * (musik.datei == null ? 1 : 0.9),
    abbruch: () => abbrechen,
  );
  if (musik.datei case final ton?) {
    if (ergebnis.ausgang == Videoausgang.fertig && !abbrechen) {
      ergebnis = await unterlegeMusik(
        video: stumm,
        musik: ton,
        ziel: ziel,
        dauer: diashowDauer(fotos.length),
      );
      stand.value = 1;
    }
    try {
      await stumm.parent.delete(recursive: true);
    } on FileSystemException {
      // Liegt im temporären Ordner; das System räumt ihn ohnehin.
    }
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  await fenster;
  stand.dispose();
  // Ohne fertiges Video bliebe sonst der leere Platzhalter der
  // Speicherortwahl am Ziel liegen – mit Musik schreibt erst der zweite
  // Schritt dorthin (BEA-116).
  if (ergebnis.ausgang != Videoausgang.fertig) leerenPlatzhalterEntfernen(pfad);
  switch (ergebnis.ausgang) {
    case Videoausgang.fertig:
      melde.erfolg(
        [
          t.flugVideoFertig(ziel.uri.pathSegments.last),
          if (gekuerzt) t.diashowGekuerzt(diashowHoechstensBilder),
        ].join(' '),
      );
    case Videoausgang.abgebrochen:
      melde.hinweis(t.flugVideoAbgebrochen);
    case Videoausgang.keinWerkzeug:
      melde.warnung(t.flugVideoKeinWerkzeug);
    case Videoausgang.fehler:
      melde.warnung(t.flugVideoFehler(ergebnis.meldung ?? '?'));
  }
}

/// Die Antwort auf „mit Musik?": [datei] ist `null` für „ohne".
typedef _Musikwahl = ({File? datei});

/// Fragt, ob Musik unter die Diashow soll, und lässt sie gegebenenfalls
/// wählen. `null` heisst abgebrochen – dann entsteht kein Video.
Future<_Musikwahl?> _frageNachMusik(BuildContext context) async {
  final t = AppTexte.of(context);
  final mitMusik = await showDialog<bool>(
    context: context,
    builder: (kontext) => AlertDialog(
      title: Text(t.diashowMusikTitel),
      content: Text(t.diashowMusikText),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(kontext).pop(),
          child: Text(t.allgAbbrechen),
        ),
        TextButton(
          onPressed: () => Navigator.of(kontext).pop(false),
          child: Text(t.diashowOhneMusik),
        ),
        FilledButton(
          onPressed: () => Navigator.of(kontext).pop(true),
          child: Text(t.diashowMusikWaehlen),
        ),
      ],
    ),
  );
  if (mitMusik == null) return null;
  if (!mitMusik) return (datei: null);
  final wahl = await FilePicker.pickFile(
    dialogTitle: t.diashowMusikWaehlen,
    type: FileType.custom,
    allowedExtensions: tonEndungen,
  );
  final pfad = wahl?.path;
  return pfad == null ? null : (datei: File(pfad));
}
