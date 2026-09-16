import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/library_location.dart';
import 'package:photo_vault/services/platform/folder_access.dart';

/// Ein Wechsel zwischen Bibliotheken darf ausschliesslich einen Zeiger
/// umbiegen. Verwechselt er sich mit dem Verschieben, werden Gigabyte an
/// Fotos bewegt – dieser Unterschied ist der Kern der Funktion und wird
/// hier per Prüfsumme über die beteiligten Ordner festgehalten.
void main() {
  late Directory tempRoot;
  late Directory anker;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_liborte_');
    anker = Directory(p.join(tempRoot.path, 'anker'))
      ..createSync(recursive: true);
    LibraryLocation.nutzeFuerTests(anker: anker, zugriff: const _TestZugriff());
  });

  tearDown(() {
    LibraryLocation.zuruecksetzenFuerTests();
    tempRoot.deleteSync(recursive: true);
  });

  /// Prüfsumme über alle Dateien eines Ordners – Namen UND Inhalte, damit
  /// auch ein Verschieben innerhalb des Ordners auffiele.
  String fingerabdruck(Directory dir) {
    if (!dir.existsSync()) return 'FEHLT';
    final teile = <String>[];
    for (final e in dir.listSync(recursive: true)
      ..sort((a, b) => a.path.compareTo(b.path))) {
      if (e is File) {
        teile.add(
            '${p.relative(e.path, from: dir.path)}:${sha256.convert(e.readAsBytesSync())}');
      }
    }
    return teile.join('|');
  }

  /// Legt einen Ordner an, der wie eine Bibliothek aussieht.
  Directory bibliothek(String name, String inhalt) {
    final dir = Directory(p.join(tempRoot.path, name))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'library.sqlite')).writeAsStringSync('DB $inhalt');
    final originals = Directory(p.join(dir.path, 'library', 'originals'))
      ..createSync(recursive: true);
    File(p.join(originals.path, 'foto.jpg')).writeAsStringSync('Foto $inhalt');
    return dir;
  }

  test('ohne Konfiguration ist der Standardordner aktiv', () async {
    final root = await LibraryLocation.currentRoot();
    expect(p.equals(root.path, anker.path), isTrue);

    final liste = await LibraryLocation.bekannte();
    expect(liste, hasLength(1));
    expect(liste.single.istAktiv, isTrue);
    expect(liste.single.erreichbar, isTrue);
  });

  test('WECHSELN bewegt keine einzige Datei', () async {
    final a = bibliothek('bibliothek_a', 'A');
    final b = bibliothek('bibliothek_b', 'B');
    final vorherA = fingerabdruck(a);
    final vorherB = fingerabdruck(b);

    await LibraryLocation.fuegeHinzu(PickedFolder(a.path, ''), name: 'A');
    await LibraryLocation.fuegeHinzu(PickedFolder(b.path, ''), name: 'B');
    await LibraryLocation.wechsleZu(
        Bibliothekseintrag(path: a.path, token: '', name: 'A'));
    expect(
        p.equals((await LibraryLocation.currentRoot()).path, a.path), isTrue);

    await LibraryLocation.wechsleZu(
        Bibliothekseintrag(path: b.path, token: '', name: 'B'));
    expect(
        p.equals((await LibraryLocation.currentRoot()).path, b.path), isTrue);

    expect(fingerabdruck(a), vorherA,
        reason: 'die abgewählte Bibliothek muss unangetastet bleiben');
    expect(fingerabdruck(b), vorherB,
        reason: 'die gewählte Bibliothek darf nichts dazubekommen');
  });

  test('VERSCHIEBEN bewegt weiterhin – die Gegenprobe', () async {
    File(p.join(anker.path, 'library.sqlite')).writeAsStringSync('DB Standard');
    final original =
        File(p.join(anker.path, 'library', 'originals', 'gross.jpg'))
          ..createSync(recursive: true)
          ..writeAsBytesSync(List<int>.filled(2 * 1024 * 1024, 17));
    final ziel = Directory(p.join(tempRoot.path, 'neuer_ort'))..createSync();
    final fortschritte = <BibliotheksVerschiebefortschritt>[];

    await LibraryLocation.applyRoot(
      PickedFolder(ziel.path, ''),
      onProgress: fortschritte.add,
    );

    expect(File(p.join(ziel.path, 'library.sqlite')).existsSync(), isTrue,
        reason: 'applyRoot muss die Daten wirklich verschieben');
    expect(File(p.join(anker.path, 'library.sqlite')).existsSync(), isFalse,
        reason: 'und am alten Ort nichts zurücklassen');
    expect(p.equals((await LibraryLocation.currentRoot()).path, ziel.path),
        isTrue);
    expect(original.existsSync(), isFalse);
    expect(fortschritte.length, greaterThan(2),
        reason:
            'auch während einer großen Datei muss sich die Anzeige bewegen');
    expect(fortschritte.first.kopierteBytes, 0);
    expect(fortschritte.last.kopierteBytes, fortschritte.last.gesamtBytes);
    expect(fortschritte.last.kopierteDateien, fortschritte.last.gesamtDateien);
    for (var i = 1; i < fortschritte.length; i++) {
      expect(fortschritte[i].kopierteBytes,
          greaterThanOrEqualTo(fortschritte[i - 1].kopierteBytes));
    }
  });

  test('das alte Einzelformat wird weiterhin verstanden', () async {
    final alt = bibliothek('alte_bibliothek', 'Alt');
    File(p.join(anker.path, 'location.json'))
        .writeAsStringSync(jsonEncode({'path': alt.path, 'token': 'xyz'}));

    expect(
        p.equals((await LibraryLocation.currentRoot()).path, alt.path), isTrue,
        reason: 'eine vorhandene Konfiguration darf nicht ins Leere laufen');

    final liste = await LibraryLocation.bekannte();
    expect(liste.map((e) => e.eintrag.path), contains(alt.path));
    expect(liste.firstWhere((e) => p.equals(e.eintrag.path, alt.path)).istAktiv,
        isTrue);
  });

  test('aus der Liste entfernen löscht keine Daten', () async {
    final a = bibliothek('zum_entfernen', 'A');
    final vorher = fingerabdruck(a);
    await LibraryLocation.fuegeHinzu(PickedFolder(a.path, ''), name: 'A');

    expect(await LibraryLocation.entferneAusListe(a.path), isTrue);

    expect((await LibraryLocation.bekannte()).map((e) => e.eintrag.path),
        isNot(contains(a.path)));
    expect(fingerabdruck(a), vorher, reason: 'die Fotos bleiben, wo sie sind');
    expect(a.existsSync(), isTrue);
  });

  test('der Standardordner lässt sich nicht entfernen und sagt das auch',
      () async {
    // Er wird von bekannte() erzeugt und steht nicht in der gespeicherten
    // Liste – ein Entfernen wäre folgenlos. Die erste Fassung bot dafür
    // trotzdem einen Knopf an, der stillschweigend nichts tat.
    final liste = await LibraryLocation.bekannte();
    final standard = liste.single;
    expect(standard.istStandard, isTrue);
    expect(standard.entfernbar, isFalse);

    expect(
        await LibraryLocation.entferneAusListe(standard.eintrag.path), isFalse,
        reason: 'die Oberfläche muss erfahren, dass nichts geschah');
    expect((await LibraryLocation.bekannte()), hasLength(1));
  });

  test('ein hinzugefügter Eintrag ist entfernbar und meldet Erfolg', () async {
    final a = bibliothek('entfernbar', 'A');
    await LibraryLocation.fuegeHinzu(PickedFolder(a.path, ''), name: 'A');

    final eintrag = (await LibraryLocation.bekannte())
        .firstWhere((e) => p.equals(e.eintrag.path, a.path));
    expect(eintrag.istStandard, isFalse);
    expect(eintrag.entfernbar, isTrue);

    expect(await LibraryLocation.entferneAusListe(a.path), isTrue);
    expect(await LibraryLocation.entferneAusListe(a.path), isFalse,
        reason: 'ein zweites Mal gibt es nichts mehr zu entfernen');
  });

  test('die aktive Bibliothek lässt sich nicht aus der Liste entfernen',
      () async {
    final a = bibliothek('aktiv', 'A');
    await LibraryLocation.fuegeHinzu(PickedFolder(a.path, ''), name: 'A');
    await LibraryLocation.wechsleZu(
        Bibliothekseintrag(path: a.path, token: '', name: 'A'));

    await LibraryLocation.entferneAusListe(a.path);

    expect((await LibraryLocation.bekannte()).map((e) => e.eintrag.path),
        contains(a.path),
        reason:
            'sonst zeigte der aktive Zeiger auf einen Eintrag, den es nicht mehr gibt');
  });

  test('ein unerreichbarer Ort wird gemeldet, nicht geworfen', () async {
    final weg = Directory(p.join(tempRoot.path, 'externe_platte'))
      ..createSync();
    await LibraryLocation.fuegeHinzu(PickedFolder(weg.path, ''),
        name: 'Extern');
    weg.deleteSync();

    final liste = await LibraryLocation.bekannte();
    final eintrag = liste.firstWhere((e) => p.equals(e.eintrag.path, weg.path));
    expect(eintrag.erreichbar, isFalse);
  });

  test('ein unerreichbarer aktiver Ort fällt auf den Standard zurück',
      () async {
    final weg = Directory(p.join(tempRoot.path, 'verschwunden'))..createSync();
    await LibraryLocation.fuegeHinzu(PickedFolder(weg.path, ''), name: 'Weg');
    await LibraryLocation.wechsleZu(
        Bibliothekseintrag(path: weg.path, token: '', name: 'Weg'));
    weg.deleteSync();

    final root = await LibraryLocation.currentRoot();
    expect(p.equals(root.path, anker.path), isTrue,
        reason: 'die App muss starten können, auch wenn die Platte fehlt');
  });
}

/// Ersetzt den Sandbox-Zugriff: Ein Ordner gilt als erreichbar, wenn es ihn
/// gibt. Genau das prüft unter macOS sonst das Security-Scoped-Bookmark.
class _TestZugriff implements FolderAccess {
  const _TestZugriff();

  @override
  Future<PickedFolder?> pickFolder({String? message}) async => null;

  @override
  Future<String?> resolveRoot({String? path, String? token}) async {
    if (path == null) return null;
    return Directory(path).existsSync() ? path : null;
  }

  @override
  bool get usesAccessToken => false;
}
