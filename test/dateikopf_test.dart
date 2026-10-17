import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/bildnachlauf.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/dateikopf.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/platform/desktop_image_tools.dart';
import 'package:kern/services/storage_paths.dart';

/// Ein Eintrag eines TIFF-Verzeichnisses. [werte] sind Zahlen; bei
/// SRATIONAL (Typ 10) Zähler und Nenner hintereinander.
class _E {
  const _E(this.tag, this.typ, this.werte);
  final int tag;
  final int typ;
  final List<int> werte;
}

const _short = 3, _long = 4, _srational = 10, _byte = 1;

/// Baut eine kleine TIFF-Datei (little endian): IFD0, auf Wunsch ein
/// Unter-IFD, und ein JPEG am Ende. In den Werten steht `-1` für „Offset
/// des JPEG“, `-2` für „Offset des Unter-IFD“ und `-3` für „Länge des JPEG“.
Uint8List _tiff(List<_E> ifd0, List<_E> sub, Uint8List jpeg) {
  int groesse(_E e) =>
      switch (e.typ) {
        _byte => 1,
        _short => 2,
        _srational => 8,
        _ => 4,
      } *
      (e.typ == _srational ? e.werte.length ~/ 2 : e.werte.length);
  int ifdGroesse(List<_E> l) => 2 + 12 * l.length + 4;
  final ifd0Off = 8;
  final subOff = ifd0Off + ifdGroesse(ifd0);
  final extraOff = subOff + (sub.isEmpty ? 0 : ifdGroesse(sub));
  var extraLaenge = 0;
  for (final e in [...ifd0, ...sub]) {
    if (groesse(e) > 4) extraLaenge += groesse(e);
  }
  final jpegOff = extraOff + extraLaenge;
  final out = ByteData(jpegOff + jpeg.length);
  out.setUint8(0, 0x49);
  out.setUint8(1, 0x49);
  out.setUint16(2, 42, Endian.little);
  out.setUint32(4, ifd0Off, Endian.little);
  var extra = extraOff;
  int wert(int v) => switch (v) {
    -1 => jpegOff,
    -2 => subOff,
    -3 => jpeg.length,
    _ => v,
  };
  void schreibe(List<_E> l, int off) {
    out.setUint16(off, l.length, Endian.little);
    for (var i = 0; i < l.length; i++) {
      final e = l[i];
      final o = off + 2 + 12 * i;
      out.setUint16(o, e.tag, Endian.little);
      out.setUint16(o + 2, e.typ, Endian.little);
      out.setUint32(
        o + 4,
        e.typ == _srational ? e.werte.length ~/ 2 : e.werte.length,
        Endian.little,
      );
      final ziel = groesse(e) > 4 ? extra : o + 8;
      if (groesse(e) > 4) {
        out.setUint32(o + 8, extra, Endian.little);
        extra += groesse(e);
      }
      var p = ziel;
      for (final v in e.werte) {
        switch (e.typ) {
          case _byte:
            out.setUint8(p, wert(v));
            p += 1;
          case _short:
            out.setUint16(p, wert(v), Endian.little);
            p += 2;
          case _srational:
            out.setInt32(p, v, Endian.little);
            p += 4;
          default:
            out.setUint32(p, wert(v), Endian.little);
            p += 4;
        }
      }
    }
    out.setUint32(off + 2 + 12 * l.length, 0, Endian.little);
  }

  schreibe(ifd0, ifd0Off);
  if (sub.isNotEmpty) schreibe(sub, subOff);
  final bytes = out.buffer.asUint8List();
  bytes.setRange(jpegOff, jpegOff + jpeg.length, jpeg);
  return bytes;
}

/// Ein DNG wie ein iPhone-ProRAW: IFD0 trägt ein JPEG in voller Grösse,
/// das Unter-IFD die linearen Bilddaten.
Uint8List _proraw({
  required Uint8List jpeg,
  required int breite,
  required int hoehe,
  int lage = 1,
  bool linear = true,
}) => _tiff(
  [
    const _E(254, _long, [1]),
    _E(256, _long, [breite]),
    _E(257, _long, [hoehe]),
    const _E(259, _short, [7]),
    const _E(262, _short, [6]),
    const _E(273, _long, [-1]),
    _E(274, _short, [lage]),
    const _E(279, _long, [-3]),
    const _E(330, _long, [-2]),
    const _E(50706, _byte, [1, 6, 0, 0]),
    // +1,904 Blenden wie in der echten Datei.
    const _E(50730, _srational, [1904, 1000]),
  ],
  [
    const _E(254, _long, [0]),
    _E(256, _long, [breite * 2]),
    _E(257, _long, [hoehe * 2]),
    const _E(259, _short, [7]),
    _E(262, _short, [linear ? 34892 : 32803]),
    _E(50720, _long, [breite * 2, hoehe * 2]),
  ],
  jpeg,
);

Uint8List _jpeg(int breite, int hoehe, {int? exifLage, int helligkeit = 200}) {
  final bild = img.Image(width: breite, height: hoehe);
  img.fill(bild, color: img.ColorRgb8(helligkeit, helligkeit, helligkeit));
  // Ein Merkmal oben links, um die Drehung zu erkennen.
  img.fillRect(
    bild,
    x1: 0,
    y1: 0,
    x2: 7,
    y2: 7,
    color: img.ColorRgb8(255, 0, 0),
  );
  if (exifLage != null) bild.exif.imageIfd.orientation = exifLage;
  return Uint8List.fromList(img.encodeJpg(bild));
}

Uint8List _kiste(String typ, List<int> inhalt) {
  final b = BytesBuilder()
    ..add(_be32(8 + inhalt.length))
    ..add(typ.codeUnits)
    ..add(inhalt);
  return b.toBytes();
}

List<int> _be32(int v) => [v >> 24 & 255, v >> 16 & 255, v >> 8 & 255, v & 255];
List<int> _be16(int v) => [v >> 8 & 255, v & 255];

Uint8List _heif({required int breite, required int hoehe, int? drehung}) {
  final ispe = _kiste('ispe', [0, 0, 0, 0, ..._be32(breite), ..._be32(hoehe)]);
  final irot = drehung == null ? null : _kiste('irot', [drehung]);
  final ipco = _kiste('ipco', [...ispe, ...?irot]);
  final assoc = [1, if (irot != null) 2];
  final ipma = _kiste('ipma', [
    0, 0, 0, 0, // Fassung 0, keine Merkmale
    ..._be32(1),
    ..._be16(1),
    assoc.length,
    ...assoc,
  ]);
  final iprp = _kiste('iprp', [...ipco, ...ipma]);
  final pitm = _kiste('pitm', [0, 0, 0, 0, ..._be16(1)]);
  final meta = _kiste('meta', [0, 0, 0, 0, ...pitm, ...iprp]);
  final ftyp = _kiste('ftyp', [
    ...'heic'.codeUnits,
    0,
    0,
    0,
    0,
    ...'mif1'.codeUnits,
  ]);
  return Uint8List.fromList([
    ...ftyp,
    ...meta,
    ..._kiste('mdat', [0, 0]),
  ]);
}

Uint8List _cr3({required int breite, required int hoehe, int lage = 1}) {
  // CMT1: ein TIFF mit nur der Lage.
  final cmt1 = _kiste(
    'CMT1',
    _tiff(
      [
        _E(274, _short, [lage]),
      ],
      const [],
      Uint8List(0),
    ),
  );
  final uuid = _kiste('uuid', [...List.filled(16, 0x85), ...cmt1]);
  final craw = _kiste('CRAW', [
    ...List.filled(6, 0), ..._be16(1), // reserviert, Datenverweis
    ...List.filled(16, 0),
    ..._be16(breite),
    ..._be16(hoehe),
    ...List.filled(8, 0),
  ]);
  final stsd = _kiste('stsd', [0, 0, 0, 0, ..._be32(1), ...craw]);
  final trak = _kiste(
    'trak',
    _kiste('mdia', _kiste('minf', _kiste('stbl', stsd))),
  );
  final moov = _kiste('moov', [...uuid, ...trak]);
  final ftyp = _kiste('ftyp', [...'crx '.codeUnits, 0, 0, 0, 1]);
  return Uint8List.fromList([...ftyp, ...moov]);
}

void main() {
  late Directory ordner;
  setUp(() => ordner = Directory.systemTemp.createTempSync('pv_kopf_'));
  tearDown(() => ordner.deleteSync(recursive: true));

  File ablegen(String name, Uint8List bytes) =>
      File('${ordner.path}/$name')..writeAsBytesSync(bytes);

  test('ProRAW: eingebettetes JPEG, Lage, Grundbelichtung, echte Grösse', () {
    final jpeg = _jpeg(64, 48);
    final datei = ablegen(
      'a.dng',
      _proraw(jpeg: jpeg, breite: 64, hoehe: 48, lage: 6),
    );
    final k = leseRohkopf(datei)!;
    expect(k.dng, isTrue);
    expect(k.linear, isTrue);
    expect(k.ausrichtung, 6);
    expect(k.grundbelichtung, closeTo(1.904, 1e-9));
    final j = k.groesstes!;
    expect((j.breite, j.hoehe), (64, 48));
    expect(
      datei.readAsBytesSync().sublist(j.offset, j.offset + j.laenge),
      jpeg,
    );
    // Die Grösse kommt aus dem Rohbild (DefaultCropSize) und ist gedreht.
    expect((k.breite, k.hoehe), (96, 128));
    expect(leseOriginalmasse(datei), (breite: 96, hoehe: 128));
  });

  test(
    'ProRAW wird aus dem eingebetteten JPEG gewandelt, gedreht nach dem DNG',
    () async {
      final datei = ablegen(
        'b.dng',
        _proraw(jpeg: _jpeg(64, 48), breite: 64, hoehe: 48, lage: 6),
      );
      final r = (await DesktopImageTools.convertToJpeg(
        datei,
        maxDimension: 2048,
      ))!;
      final bild = img.decodeJpg(r)!;
      expect((bild.width, bild.height), (48, 64), reason: 'Lage 6 = hochkant');
      // Das rote Feld lag oben links und steht nach 90° rechts herum oben rechts.
      expect(bild.getPixel(44, 3).r, greaterThan(200));
      expect(bild.getPixel(3, 3).r, lessThan(240));
      expect(
        bild.getPixel(24, 32).r,
        inInclusiveRange(185, 215),
        reason: 'hell wie das JPEG',
      );
    },
  );

  test('trägt das JPEG eine eigene Lage, wird nicht doppelt gedreht', () async {
    // So liegt es im iPhone: das JPEG nennt seine Lage selbst.
    final datei = ablegen(
      'c.dng',
      _proraw(jpeg: _jpeg(64, 48, exifLage: 6), breite: 64, hoehe: 48, lage: 6),
    );
    expect(jpegExifLage(_jpeg(64, 48, exifLage: 6)), 6);
    expect(jpegExifLage(_jpeg(64, 48)), isNull);
    final r = (await DesktopImageTools.convertToJpeg(
      datei,
      maxDimension: 2048,
    ))!;
    final bild = img.decodeJpg(r)!;
    expect((bild.width, bild.height), (48, 64));
  });

  test('HEIF: Grösse des Hauptbilds, gedreht nach irot', () {
    expect(
      leseOriginalmasse(ablegen('q.heic', _heif(breite: 4032, hoehe: 3024))),
      (breite: 4032, hoehe: 3024),
    );
    expect(
      leseOriginalmasse(
        ablegen('h.heic', _heif(breite: 4032, hoehe: 3024, drehung: 1)),
      ),
      (breite: 3024, hoehe: 4032),
    );
  });

  test('CR3: Grösse der ersten Spur, gedreht nach der Lage im CMT1', () {
    expect(
      leseOriginalmasse(ablegen('q.cr3', _cr3(breite: 6000, hoehe: 4000))),
      (breite: 6000, hoehe: 4000),
    );
    expect(
      leseOriginalmasse(
        ablegen('h.cr3', _cr3(breite: 6000, hoehe: 4000, lage: 8)),
      ),
      (breite: 4000, hoehe: 6000),
    );
  });

  test('PSD: Höhe und Breite aus dem Kopf', () {
    final kopf = Uint8List(26);
    kopf.setRange(0, 4, '8BPS'.codeUnits);
    kopf.setRange(14, 18, _be32(1200));
    kopf.setRange(18, 22, _be32(1600));
    expect(leseOriginalmasse(ablegen('a.psd', kopf)), (
      breite: 1600,
      hoehe: 1200,
    ));
  });

  test('echteMasse nimmt den Kopf nur, wenn er zur Vorschau passt', () {
    final heic = ablegen('a.heic', _heif(breite: 4032, hoehe: 3024));
    expect(echteMasse(heic, 2048, 1536), (4032, 3024));
    // Anderes Seitenverhältnis: lieber die bekannte Zahl behalten.
    expect(echteMasse(heic, 2048, 2048), (2048, 2048));
    // Kleiner als die Vorschau: der Kopf hat sich geirrt.
    final klein = ablegen('k.heic', _heif(breite: 1024, hoehe: 768));
    expect(echteMasse(klein, 2048, 1536), (2048, 1536));
    expect(echteMasse(ablegen('x.txt', Uint8List(20)), 10, 10), (10, 10));
  });

  test(
    'naechsterZusatz zählt hoch und lässt sich von der UUID nicht täuschen',
    () {
      const id = 'a1b2c3d4-0000-0000-0000-123456789012';
      expect(naechsterZusatz(id, null), '-2');
      expect(naechsterZusatz(id, 'thumbnails/$id.jpg'), '-2');
      expect(naechsterZusatz(id, 'thumbnails/$id-2.jpg'), '-3');
      expect(naechsterZusatz(id, 'thumbnails/$id-9.jpg'), '-10');
    },
  );

  test(
    'Nachläufe: echte Grösse nachtragen, ProRAW-Vorschau neu unter neuem Namen',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final paths = await StoragePaths.forTesting(ordner);
      // Der Weg über die Werkzeuge, wie auf dem Server – unter macOS gäbe es
      // im Test sonst gar keinen Wandler.
      final importe = ImportService(
        db,
        paths,
        bildwerkzeuge: const WerkzeugBildwerkzeuge(),
      );
      Future<void> lege(String id, String format, Uint8List bytes) async {
        final rel = 'originals/$id.$format';
        paths.absolute(rel)
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(bytes);
        final miniatur = paths.thumbnailRelativePath(id);
        final vorschau = paths.previewRelativePath(id);
        for (final r in [miniatur, vorschau]) {
          paths.absolute(r)
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(_jpeg(20, 15, helligkeit: 30));
        }
        await db.insertAsset(
          AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.$format',
            relativePath: rel,
            checksum: 'pruef-$id',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 10, 14),
            importedAt: DateTime(2026, 10, 15),
            dateiformat: Value(format),
            thumbnailRelativePath: Value(miniatur),
            previewRelativePath: Value(vorschau),
            widthPx: const Value(2048),
            heightPx: const Value(1536),
          ),
        );
      }

      await lege('heic1', 'heic', _heif(breite: 4032, hoehe: 3024));
      await lege(
        'dng1',
        'dng',
        _proraw(jpeg: _jpeg(400, 300), breite: 400, hoehe: 300),
      );
      await lege(
        'dng2',
        'dng',
        _proraw(jpeg: _jpeg(400, 300), breite: 400, hoehe: 300, linear: false),
      );

      expect(await erneuereRohvorschauen(db, paths, importe), 1);
      final dng = (await db.assetById('dng1'))!;
      expect(
        dng.thumbnailRelativePath,
        paths.thumbnailRelativePath('dng1', '-2'),
      );
      expect(dng.previewRelativePath, paths.previewRelativePath('dng1', '-2'));
      expect(
        paths.absolute(paths.thumbnailRelativePath('dng1')).existsSync(),
        isFalse,
      );
      final neu = img.decodeJpg(
        paths.absolute(dng.previewRelativePath!).readAsBytesSync(),
      )!;
      expect(
        neu.getPixel(200, 150).r,
        greaterThan(150),
        reason: 'nicht mehr dunkel',
      );
      expect((dng.widthPx, dng.heightPx), (800, 600));
      // Das gewöhnliche DNG bleibt, wie es ist.
      expect(
        (await db.assetById('dng2'))!.thumbnailRelativePath,
        paths.thumbnailRelativePath('dng2'),
      );

      expect(await berichtigeOriginalmasse(db, paths), 1);
      final heic = (await db.assetById('heic1'))!;
      expect((heic.widthPx, heic.heightPx), (4032, 3024));
      // Ein Kopf, der kleiner ist als die Vorschau, gilt als verlesen.
      final dng2 = (await db.assetById('dng2'))!;
      expect((dng2.widthPx, dng2.heightPx), (2048, 1536));
      expect(
        await berichtigeOriginalmasse(db, paths),
        0,
        reason: 'nichts mehr zu tun',
      );
    },
  );
}
