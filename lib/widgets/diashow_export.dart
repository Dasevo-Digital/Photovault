import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/asset_display_path.dart';
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
  final fotos = [
    for (final a in aufnahmen)
      if (a.type != 'VIDEO' && !a.isLocked) a,
  ].take(diashowHoechstensBilder).toList();
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
  final pfad = await FilePicker.platform.saveFile(
    dialogTitle: t.diashowSpeichern,
    fileName: dateiname,
    type: FileType.custom,
    allowedExtensions: const ['mp4'],
  );
  if (pfad == null || !context.mounted) return;
  final ziel = File(pfad.toLowerCase().endsWith('.mp4') ? pfad : '$pfad.mp4');

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
      for (final a in fotos) library.paths.absolute(displayRelativePath(a)),
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
  switch (ergebnis.ausgang) {
    case Videoausgang.fertig:
      melde.erfolg(t.flugVideoFertig(ziel.uri.pathSegments.last));
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
  final wahl = await FilePicker.platform.pickFiles(
    dialogTitle: t.diashowMusikWaehlen,
    type: FileType.custom,
    allowedExtensions: tonEndungen,
  );
  final pfad = wahl?.files.single.path;
  return pfad == null ? null : (datei: File(pfad));
}
