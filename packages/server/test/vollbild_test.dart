import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/bildnachlauf.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:photo_vault_server/src/fassungen_aufraeumen.dart';
import 'package:photo_vault_server/src/vollbild.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Der Betrachter bekommt jedes Foto in voller Auflösung (#256).
///
/// Bis 3.49.9 zeigten Browser und Handy von HEIC, RAW und DNG nur die
/// Vorschau mit 2048 Punkten an der langen Seite.
void main() {
  late Directory ordner;
  late Serverdatenbank sdb;
  late Kontodienst konten;
  late Bibliotheken bibliotheken;
  late _Wandler wandler;
  late Handler api;
  late String token;
  late Kontobereich bereich;
  late Bibliothek b;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_vollbild_');
    sdb = Serverdatenbank.imSpeicher();
    konten = Kontodienst(
      sdb,
      Tresorschluessel(List.filled(32, 5)),
      passwort: const Passwort(speicher: 64, durchgaenge: 1),
      totpPflicht: false,
    );
    wandler = _Wandler();
    bibliotheken = Bibliotheken(
      wurzel: Directory('${ordner.path}/bibliotheken'),
      eingang: Directory('${ordner.path}/eingang'),
      bildwerkzeuge: wandler,
      ruhe: const Duration(hours: 1),
    );
    api = baueApi(konten: konten, bibliotheken: bibliotheken);
    final erika = await konten.legeAn('erika', 'ein langes passwort');
    token = konten.meldeAn(erika.id, 'Telefon', 'x').token;
    bereich = await bibliotheken.fuer(erika.id);
    b = bereich.bibliothek;
  });

  tearDown(() async {
    await bibliotheken.schliesseAlle();
    sdb.schliesse();
    await ordner.delete(recursive: true);
  });

  Future<Response> abruf(String id, String art) async => api(
    Request(
      'GET',
      Uri.parse('http://server/api/v1/aufnahmen/$id/$art'),
      headers: {'authorization': 'Bearer $token'},
    ),
  );

  Future<Response> voll(String id) => abruf(id, 'voll');

  Future<Uint8List> inhalt(Response r) async =>
      Uint8List.fromList(await r.read().expand((x) => x).toList());

  /// Legt eine Aufnahme mit Datei (und Vorschau) an, ohne den Import.
  Future<String> aufnahme(
    String id,
    String endung, {
    String typ = 'IMAGE',
    bool gesperrt = false,
    String? dateiformat,
  }) async {
    final relativ = 'originals/$id.$endung';
    final datei = b.pfade.absolute(relativ);
    await datei.parent.create(recursive: true);
    await datei.writeAsBytes(List.filled(100, id.codeUnitAt(0)));
    final vorschau = 'previews/$id.jpg';
    await b.pfade.absolute(vorschau).parent.create(recursive: true);
    await b.pfade.absolute(vorschau).writeAsBytes([1, 2, 3]);
    await b.db
        .into(b.db.assets)
        .insert(
          AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.$endung',
            relativePath: relativ,
            checksum: 'c_$id',
            type: typ,
            fileCreatedAt: DateTime(2026, 10, 1),
            importedAt: DateTime(2026, 10, 1),
            previewRelativePath: Value(vorschau),
            isLocked: Value(gesperrt),
            dateiformat: Value(dateiformat),
          ),
        );
    return id;
  }

  test('ein JPEG geht unverändert hinaus, ohne Wandlung', () async {
    await aufnahme('j', 'jpg');

    final r = await voll('j');

    expect(r.statusCode, 200);
    expect(r.headers['content-type'], 'image/jpeg');
    expect(await inhalt(r), List.filled(100, 'j'.codeUnitAt(0)));
    expect(wandler.auftraege, isEmpty);
  });

  test('ein HEIC kommt in voller Grösse gewandelt, einmal', () async {
    await aufnahme('h', 'heic');

    final r = await voll('h');

    expect(r.statusCode, 200);
    expect(r.headers['content-type'], 'image/jpeg');
    final bild = img.decodeJpg(await inhalt(r))!;
    expect(bild.width, 40);
    expect(wandler.auftraege, [null], reason: 'ohne Grössengrenze');

    // Wer zurückblättert, bekommt dieselbe Fassung.
    expect((await voll('h')).statusCode, 200);
    expect(wandler.auftraege, hasLength(1));

    // Ändert sich die Quelle, wird neu gewandelt.
    await b.pfade
        .absolute('originals/h.heic')
        .setLastModified(DateTime.now().add(const Duration(minutes: 1)));
    expect((await voll('h')).statusCode, 200);
    expect(wandler.auftraege, hasLength(2));
  });

  test('ein grosses JPEG: die Ansicht aus dem Ansichtsbild, voll und '
      'Auswertung aus dem Original (#333)', () async {
    // Ein Kamerafoto aus der Zeit davor: über 4 MB, länger als 3000 Punkte,
    // ohne Vorschau. Bis 3.66 ging es auch als Ansicht ganz hinaus.
    final roh = img.encodeJpg(img.Image(width: 3200, height: 100));
    final original = Uint8List(5 * 1024 * 1024)..setRange(0, roh.length, roh);
    final datei = b.pfade.absolute('originals/g.jpg')
      ..createSync(recursive: true)
      ..writeAsBytesSync(original);
    await b.db
        .into(b.db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'g',
            originalFileName: 'DSC_0001.JPG',
            relativePath: 'originals/g.jpg',
            checksum: 'c_g',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 10, 1),
            importedAt: DateTime(2026, 10, 1),
            widthPx: const Value(3200),
            heightPx: const Value(100),
            fileSizeBytes: Value(original.length),
          ),
        );
    expect(await inhalt(await abruf('g', 'ansicht')), original);

    // Der Nachlauf nach dem Start legt das Ansichtsbild daneben.
    await bereich.auswertung.jetzt();
    final a = (await b.db.assetById('g'))!;
    expect(a.previewRelativePath, 'previews/g-ansicht.jpg');
    expect(await b.db.aufgabeFertigAm(nachlaufAnsichtsbilder), isNotNull);
    expect(wandler.auftraege, contains(3000));

    final ansicht = img.decodeJpg(await inhalt(await abruf('g', 'ansicht')))!;
    expect(ansicht.width, 40, reason: 'das Ansichtsbild des Wandlers');
    final v = await voll('g');
    expect(v.statusCode, 200);
    expect(await inhalt(v), original, reason: 'das Original, ungewandelt');
    expect(
      bereich.bibliothek.auswertungen.decodableFile(a).path,
      datei.path,
      reason: 'ausgewertet wird das Original',
    );

    // Was neu hereinkommt, bekommt es beim Import.
    final neu = File('${ordner.path}/DSC_0002.jpg')
      ..writeAsBytesSync(
        Uint8List.fromList(original)..[original.length - 1] = 1,
      );
    final r = await b.importe.importFile(neu.path);
    final n = (await b.db.assetById(r.assetId!))!;
    expect(n.previewRelativePath, 'previews/${n.id}-ansicht.jpg');
    // Die Miniatur kommt aus dem Ansichtsbild, die Masse aus dem Kopf des
    // Originals (#379).
    final miniatur = img.decodeJpg(
      await b.pfade.absolute(n.thumbnailRelativePath!).readAsBytes(),
    )!;
    expect(
      (miniatur.width, miniatur.height),
      (400, 300),
      reason: 'aus den 40 × 30 des Wandlers, nicht aus 3200 × 100',
    );
    expect((n.widthPx, n.heightPx), (3200, 100));
  });

  test('die entwickelte Fassung geht vor dem Original', () async {
    await aufnahme('e', 'dng');
    final entwickelt = b.pfade.absolute('developed/e.jpg');
    await entwickelt.parent.create(recursive: true);
    await entwickelt.writeAsBytes([9, 9, 9]);
    await (b.db.update(b.db.assets)..where((t) => t.id.equals('e'))).write(
      const AssetsCompanion(developedRelativePath: Value('developed/e.jpg')),
    );

    expect(await inhalt(await voll('e')), [9, 9, 9]);
    expect(wandler.auftraege, isEmpty);
  });

  test('Videos, gesperrte und unlesbare Fotos', () async {
    await aufnahme('v', 'mov', typ: 'VIDEO');
    await aufnahme('g', 'heic', gesperrt: true);
    await aufnahme('k', 'cr3');
    wandler.kaputt.add('k.cr3');

    expect((await voll('v')).statusCode, 404);
    expect((await voll('g')).statusCode, 404);
    expect((await voll('k')).statusCode, 422);
    expect((await voll('gibtesnicht')).statusCode, 404);
  });

  test('ein HEIC unter einem Videonamen geht als .heic ans Werkzeug', () async {
    // IMG_1711.MOV der Nutzerbibliothek: ein Standbild mit HEIC-Inhalt.
    // Nach der Endung ging es an dcraw_emu und scheiterte (#265).
    await aufnahme('m', 'MOV', dateiformat: 'heic');

    expect((await voll('m')).statusCode, 200);
    expect((await abruf('m', 'jpeg')).statusCode, 200);

    expect(wandler.namen, ['quelle.heic', 'quelle.heic']);
    expect(
      b.pfade.absolute('originals/m.MOV').readAsBytesSync(),
      List.filled(100, 'm'.codeUnitAt(0)),
      reason: 'das Original bleibt, wie es war',
    );
    expect(
      Directory.systemTemp.listSync().where(
        (e) => p.basename(e.path).startsWith('pv_wandeln_'),
      ),
      isEmpty,
      reason: 'kein Verweis bleibt liegen',
    );
  });

  test('was sich nicht wandeln liess, wird erst nach einer Änderung neu '
      'versucht', () async {
    await aufnahme('k', 'cr3');
    wandler.kaputt.add('k.cr3');

    expect((await voll('k')).statusCode, 422);
    expect((await voll('k')).statusCode, 422);
    expect(wandler.versuche, 1, reason: 'nicht jedes Mal neu rechnen');

    await b.pfade
        .absolute('originals/k.cr3')
        .setLastModified(DateTime.now().add(const Duration(minutes: 1)));
    wandler.kaputt.clear();
    expect((await voll('k')).statusCode, 200);
    expect(wandler.versuche, 2);
  });

  test('eine hängende Wandlung hält die nächsten nicht auf (#263)', () async {
    final speicher = Directory('${ordner.path}/speicher');
    final vollbilder = Vollbilder(frist: const Duration(milliseconds: 200));
    final haengt = File('${ordner.path}/haengt.heic')..writeAsBytesSync([1]);
    final gut = File('${ordner.path}/gut.heic')..writeAsBytesSync([1]);
    final nie = Completer<Uint8List?>();
    final erstes = vollbilder.bereit(speicher, 'h', haengt, () => nie.future);
    final zweites = vollbilder.bereit(
      speicher,
      'g',
      gut,
      () async => Uint8List(10),
    );
    expect(await zweites.timeout(const Duration(seconds: 5)), isNotNull);
    expect(await erstes, isNull);
    // Und es wird nicht bei jedem Aufruf wieder fünf Minuten gewartet.
    var gefragt = false;
    expect(
      await vollbilder.bereit(speicher, 'h', haengt, () async {
        gefragt = true;
        return Uint8List(10);
      }),
      isNull,
    );
    expect(gefragt, isFalse);
  });

  test(
    'beim Öffnen gehen Fassungen, die zu nichts mehr gehören (#261)',
    () async {
      final vollbild = Directory(p.join(b.ordner.path, 'vollbild'));
      final abspielbar = Directory(p.join(b.ordner.path, 'abspielbar'));
      File lege(Directory d, String name) => File(p.join(d.path, name))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync([1]);

      await aufnahme('k', 'heic');
      expect((await voll('k')).statusCode, 200);
      final heute = vollbild.listSync().single as File;
      final vorher = lege(vollbild, 'k-000000000000.jpg');
      await aufnahme('t', 'heic');
      await b.db.fuehreAus(const InDenPapierkorb(['t']));
      final papierkorb = Vollbilder.ziel(
        vollbild,
        't',
        b.pfade.absolute('originals/t.heic').path,
      )..writeAsBytesSync([1]);
      await aufnahme('z', 'heic', gesperrt: true);
      final gesperrt = lege(vollbild, 'z-bbbbbbbbbbbb.jpg');
      final geloescht = lege(vollbild, 'weg-aaaaaaaaaaaa.jpg');
      await aufnahme('v', 'mov', typ: 'VIDEO');
      final video = lege(abspielbar, 'v.mp4');
      final gekuerzt = lege(abspielbar, 'v-gekuerzt.mp4');
      final halb = lege(abspielbar, 'v.mp4.teil');
      final videoWeg = lege(abspielbar, 'weg.mp4');

      expect(await raeumeFassungenAuf(b, beimOeffnen: true), 6);

      expect(heute.existsSync(), isTrue, reason: 'was der Betrachter zeigt');
      expect(papierkorb.existsSync(), isTrue, reason: 'lässt sich zurückholen');
      expect(video.existsSync(), isTrue);
      expect(vorher.existsSync(), isFalse, reason: 'eine ältere Fassung');
      expect(gesperrt.existsSync(), isFalse, reason: 'gesperrt');
      expect(geloescht.existsSync(), isFalse, reason: 'gibt es nicht mehr');
      expect(gekuerzt.existsSync(), isFalse, reason: 'nicht mehr gekürzt');
      expect(halb.existsSync(), isFalse, reason: 'abgebrochene Wandlung');
      expect(videoWeg.existsSync(), isFalse);
    },
  );

  test('der Zwischenspeicher bleibt unter seiner Grenze', () async {
    final speicher = Directory('${ordner.path}/speicher');
    final vollbilder = Vollbilder(grenze: 250);
    final quellen = <File>[];
    for (final n in ['a', 'b', 'c']) {
      final q = File('${ordner.path}/$n.heic')..writeAsBytesSync([1]);
      quellen.add(q);
      final f = await vollbilder.bereit(
        speicher,
        n,
        q,
        () async => Uint8List(100),
      );
      // Die Reihenfolge des Alters soll eindeutig sein.
      await f!.setLastModified(DateTime(2026, 1, 1 + quellen.length));
      await q.setLastModified(DateTime(2026));
    }

    final uebrig = speicher.listSync().whereType<File>().toList();
    expect(uebrig, hasLength(2), reason: 'die älteste ging');
    expect(
      await Vollbilder.ziel(speicher, 'a', quellen[0].path).exists(),
      isFalse,
    );
  });

  test('Beilagen zählen nicht mit und gehen mit ihrer Datei (#379)', () async {
    // Wie die Kartenkacheln: Die Zeit einer Kachel ist ihre Frist, ihr
    // Stand beim Anbieter wird jetzt geschrieben und wäre so die älteste
    // Datei.
    final speicher = Directory('${ordner.path}/kacheln')..createSync();
    File lege(String name, int tag) => File(p.join(speicher.path, name))
      ..writeAsBytesSync(Uint8List(100))
      ..setLastModifiedSync(DateTime(2026, 1, tag));
    final spaet = lege('a.png', 5), spaetStand = lege('a.png.stand', 1);
    final frueh = lege('b.png', 3), fruehStand = lege('b.png.stand', 1);
    final zuletzt = lege('c.png', 7);

    await begrenzeZwischenspeicher(
      speicher,
      300,
      behalten: zuletzt,
      beilage: '.stand',
    );
    expect(speicher.listSync(), hasLength(5), reason: 'drei Kacheln passen');

    await begrenzeZwischenspeicher(
      speicher,
      250,
      behalten: zuletzt,
      beilage: '.stand',
    );
    expect(frueh.existsSync(), isFalse, reason: 'die früheste Frist');
    expect(fruehStand.existsSync(), isFalse, reason: 'geht mit ihr');
    expect(spaet.existsSync(), isTrue);
    expect(spaetStand.existsSync(), isTrue, reason: 'nicht nach eigener Zeit');
    expect(zuletzt.existsSync(), isTrue);
  });
}

/// Wandelt jede Datei in ein JPEG mit 40 × 30 Punkten und merkt sich die
/// verlangte Grösse.
class _Wandler extends KeineBildwerkzeuge {
  final auftraege = <int?>[];
  final kaputt = <String>{};
  final namen = <String>[];
  var versuche = 0;

  @override
  Future<Uint8List?> convertToJpegBytes(
    File file, {
    int? maxDimension = 2048,
    double quality = 0.9,
    bool objektivkorrektur = true,
  }) async {
    versuche++;
    if (kaputt.contains(file.uri.pathSegments.last)) return null;
    namen.add(file.uri.pathSegments.last);
    auftraege.add(maxDimension);
    return Uint8List.fromList(img.encodeJpg(img.Image(width: 40, height: 30)));
  }
}
