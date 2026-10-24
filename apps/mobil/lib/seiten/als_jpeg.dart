import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../sitzung.dart';

/// Die Grössen, in denen ein Foto als JPEG geteilt werden kann – wie im
/// Browser (web/app.js, `JPEG_GROESSEN`, #210). `0` ist die volle Grösse.
const jpegKanten = [0, 4096, 2048, 1024];

/// Was geteilt werden soll: das Original (`null` im Ergebnis von
/// [frageTeilart] heisst abgebrochen) oder ein JPEG mit dieser [kante].
typedef Teilart = ({bool original, int kante});

/// Fragt wie der Browser beim Herunterladen: Original oder JPEG in einer
/// der vier Grössen. Ohne Fotos ([mitFotos]) stehen die JPEG-Zeilen
/// ausgegraut da.
Future<Teilart?> frageTeilart(
  BuildContext context, {
  required bool mitFotos,
  required bool mitVideos,
}) {
  final t = AppTexte.of(context);
  String groesse(int kante) =>
      kante == 0 ? t.jpegVolleGroesse : t.jpegKante(kante);
  return showModalBottomSheet<Teilart>(
    context: context,
    showDragHandle: true,
    // So hoch wie nötig: Sonst schneidet die Vorgabe (9/16 des Bildschirms)
    // auf kleinen Telefonen die letzte Grösse ab.
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(t.teilenOriginal),
              subtitle: Text(t.teilenOriginalHinweis),
              onTap: () => Navigator.pop(context, (original: true, kante: 0)),
            ),
            for (final kante in jpegKanten)
              ListTile(
                enabled: mitFotos,
                leading: const Icon(Icons.image_outlined),
                title: Text(groesse(kante)),
                subtitle: kante == 0
                    ? Text(
                        [
                          t.teilenJpegHinweis,
                          if (mitVideos) t.teilenOhneVideos,
                        ].join(' '),
                      )
                    : null,
                onTap: () =>
                    Navigator.pop(context, (original: false, kante: kante)),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Holt die Fotos [aufnahmen] als JPEG vom Server – gewandelt wird dort,
/// mit der Bearbeitung (`GET /api/v1/aufnahmen/<id>/jpeg`) – und teilt sie.
/// Videos bleiben aussen vor, wie im Browser.
Future<void> teileAlsJpeg(
  Sitzung sitzung,
  List<({String id, String name, bool video})> aufnahmen,
  int kante,
) async {
  final verbindung = sitzung.abgleich?.verbindung;
  if (verbindung == null) throw KeineVerbindung('ohne Server');
  final ordner = await Directory.systemTemp.createTemp('pv_jpeg_');
  final dateien = <XFile>[];
  final namen = <String>[];
  for (final a in aufnahmen) {
    if (a.video) continue;
    final ziel = File(p.join(ordner.path, '${a.id}.jpg'));
    await verbindung.ladeHerunter(
      'api/v1/aufnahmen/${Uri.encodeComponent(a.id)}/jpeg'
      '${kante > 0 ? '?kante=$kante' : ''}',
      ziel,
    );
    dateien.add(XFile(ziel.path, mimeType: 'image/jpeg'));
    namen.add('${p.basenameWithoutExtension(a.name)}.jpg');
  }
  if (dateien.isEmpty) return;
  await SharePlus.instance.share(
    ShareParams(files: dateien, fileNameOverrides: namen),
  );
}
