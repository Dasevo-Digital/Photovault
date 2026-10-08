import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/asset_display_path.dart';
import '../services/diashow.dart';
import '../services/flugvideo.dart';
import '../services/meldungsdienst.dart';
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

  final ergebnis = await schreibeDiashow(
    ziel: ziel,
    dateien: [
      for (final a in fotos) library.paths.absolute(displayRelativePath(a)),
    ],
    titel: titel,
    untertitel: untertitel,
    schrift: zierschrift,
    fortschritt: (a) => stand.value = a,
    abbruch: () => abbrechen,
  );
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
