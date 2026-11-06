import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:teilen_ui/geteilte_alben.dart';

/// Ein Foto aus der Bibliothek eines Partners in der eigenen Zeitleiste
/// (#299). Es liegt nicht in der Kopie auf dem Telefon: Der Server liefert
/// die Liste, die Bilder kommen über die Freigabe – wie in
/// `PartnerBibliothekSeite`, nur zwischen den eigenen Fotos.
class Partnerfoto {
  const Partnerfoto(this.bibliothek, this.aufnahme, {this.breite, this.hoehe});

  factory Partnerfoto.aus(GeteiltesAlbum bibliothek, Map<String, Object?> j) =>
      Partnerfoto(
        bibliothek,
        GeteilteAufnahme.aus(j),
        breite: (j['breite'] as num?)?.toInt(),
        hoehe: (j['hoehe'] as num?)?.toInt(),
      );

  /// Die Bibliothek des Partners, aus [GeteiltesAlbum.partner].
  final GeteiltesAlbum bibliothek;
  final GeteilteAufnahme aufnahme;
  final int? breite;
  final int? hoehe;

  /// Womit Zeilen eines Partners in der Zeitleiste beginnen – so stossen
  /// sie nie mit eigenen oder mit denen vom Telefon zusammen.
  static const vorsatz = 'partner:';

  String get kennung => '$vorsatz${bibliothek.partner}:${aufnahme.id}';

  /// Der Name des Partners, für die Marke auf der Kachel.
  String get name => bibliothek.besitzer;

  ImageProvider miniatur(Serververbindung verbindung, Directory? ablage) =>
      bibliothek.bild(
        verbindung,
        ablage,
        aufnahme.id,
        'miniatur',
        aufnahme.stand,
      );

  /// Als Zeile fürs Raster – ohne Pfade, die gibt es auf dem Telefon nicht.
  Rasterzeile get zeile => Rasterzeile(
    id: kennung,
    type: aufnahme.video ? 'VIDEO' : 'IMAGE',
    originalFileName: aufnahme.name,
    relativePath: '',
    thumbnailRelativePath: null,
    fileCreatedAt: aufnahme.aufgenommen,
    durationSeconds: aufnahme.dauer,
    isFavorite: false,
    isStackCover: false,
    stackId: null,
    stackSize: null,
    linkedAssetId: null,
    rating: 0,
    colorLabel: null,
    widthPx: breite,
    heightPx: hoehe,
    latitude: null,
    longitude: null,
    cameraMake: null,
    isLocked: false,
  );
}

/// Höchstens so viele Fotos von Partnern hält das Telefon in der Liste.
const partnerfotosHoechstens = 100000;

/// Holt die Fotos aller Partner, die dieses Konto in seiner Zeitleiste
/// sehen will, die neuesten zuerst. Ein Server ohne Partnerfreigabe gibt
/// eine leere Liste.
///
/// [stand] ist das Merkmal der Liste. Stimmt [bekannt] damit überein, kommt
/// [fotos] als `null` zurück: Die Liste wird nicht noch einmal geladen, denn
/// sie kann bei grossen Bibliotheken viele Megabyte schwer sein, und das
/// Telefon fragt alle 15 Minuten. Das Merkmal kennt Anzahl und neuestes
/// Foto je Partner; eine neue Fassung eines älteren Fotos kommt also erst
/// mit der nächsten Änderung oder dem nächsten Start.
Future<({String stand, List<Partnerfoto>? fotos})> holePartnerfotos(
  Serververbindung v, {
  String? bekannt,
}) async {
  final Map<String, Object?> d;
  try {
    d = await v.hole('api/v1/partner');
  } on Serverfehler catch (e) {
    if (e.status == 404) return (stand: '', fotos: const <Partnerfoto>[]);
    rethrow;
  }
  final partner = [
    for (final x in (d['mitMir'] as List? ?? const []))
      if (x is Map && x['inZeitleiste'] == true) x,
  ];
  final stand = [
    for (final x in partner)
      '${x['konto']}:${x['anzahl']}:${x['titelbild']}:${x['titelstand']}',
  ].join('|');
  if (stand == bekannt) return (stand: stand, fotos: null);
  final alle = <Partnerfoto>[];
  for (final x in partner) {
    final b = GeteiltesAlbum.partner(x.cast<String, Object?>());
    String? weiter;
    do {
      final s = await v.hole(
        'api/v1/partner/von/${Uri.encodeComponent(b.partner!)}/aufnahmen',
        parameter: {'anzahl': '1000', 'nach': ?weiter},
        zeitlimit: const Duration(minutes: 2),
      );
      for (final z in (s['aufnahmen'] as List? ?? const [])) {
        if (z is Map) alle.add(Partnerfoto.aus(b, z.cast<String, Object?>()));
      }
      weiter = s['weiter'] as String?;
    } while (weiter != null && alle.length < partnerfotosHoechstens);
  }
  alle.sort((a, b) => b.aufnahme.aufgenommen.compareTo(a.aufnahme.aufgenommen));
  return (stand: stand, fotos: alle);
}

/// Reiht [partner] zwischen [zeilen], beide nach Datum absteigend.
/// Liefert die Zeilen und dazu, welche von Partnern sind.
({List<Rasterzeile> zeilen, Map<String, Partnerfoto> partner})
mischeMitPartnern(List<Rasterzeile> zeilen, List<Partnerfoto> partner) {
  if (partner.isEmpty) return (zeilen: zeilen, partner: const {});
  final aus = <Rasterzeile>[];
  var i = 0;
  var j = 0;
  while (i < zeilen.length || j < partner.length) {
    final s = i < zeilen.length ? zeilen[i] : null;
    final f = j < partner.length ? partner[j] : null;
    if (f == null ||
        (s != null && !s.fileCreatedAt.isBefore(f.aufnahme.aufgenommen))) {
      aus.add(s!);
      i++;
    } else {
      aus.add(f.zeile);
      j++;
    }
  }
  return (zeilen: aus, partner: {for (final f in partner) f.kennung: f});
}
