import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/dateibeschaffung.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/state/library_state.dart';

/// Der Vorrat an Miniaturen und Gesichtsausschnitten eines verbundenen
/// Rechners kostet im Leerlauf nichts (#434). Bis hierher las jede
/// Zustandsmeldung des Abgleichs (etwa alle 25 Sekunden) die Tabellen und
/// sah jede Datei auf der Platte nach.
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths paths;
  late Dateibeschaffung beschaffung;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_vorrat_leerlauf_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'library')),
    );
    beschaffung = Dateibeschaffung(
      paths,
      Serververbindung(
        Uri.parse('http://server/'),
        'probe',
        client: MockClient((_) async => http.Response('', 404)),
      ),
    );
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<void> aufnahme(String id) async {
    final miniatur = 'thumbnails/$id.jpg';
    paths.absolute(miniatur).writeAsBytesSync([1]);
    await db.insertAsset(
      AssetsCompanion.insert(
        id: id,
        originalFileName: '$id.jpg',
        relativePath: 'originals/$id.jpg',
        checksum: id,
        type: 'IMAGE',
        fileCreatedAt: DateTime(2026),
        importedAt: DateTime(2026),
        thumbnailRelativePath: Value(miniatur),
      ),
    );
  }

  test('was schon da ist, sieht der Vorrat nicht jedes Mal nach', () async {
    for (var i = 0; i < 5; i++) {
      await aufnahme('a$i');
    }
    final vorrat = Vorrat(db, beschaffung);
    final zaehler = _Zaehler();

    await IOOverrides.runWithIOOverrides(vorrat.fuelle, zaehler);
    expect(zaehler.nachgesehen, 5);
    await IOOverrides.runWithIOOverrides(vorrat.fuelle, zaehler);
    expect(
      zaehler.nachgesehen,
      5,
      reason: 'bisher je Lauf ein Dateisystemaufruf je Datei',
    );

    // Eine neue Aufnahme wird nachgesehen.
    await aufnahme('neu');
    await IOOverrides.runWithIOOverrides(vorrat.fuelle, zaehler);
    expect(zaehler.nachgesehen, 6);
  });

  test('gefüllt wird beim Erreichen des Servers und nach Änderungen, '
      'nicht bei jeder Zustandsmeldung', () async {
    final lib = LibraryState()
      ..db = db
      ..paths = paths;
    final zustand = StreamController<Abgleichszustand>.broadcast();
    addTearDown(zustand.close);
    final vorrat = _ZaehlenderVorrat(db, beschaffung);
    lib.richteVorratEinFuerTests(vorrat, zustand.stream);
    Future<void> melde({required bool erreichbar}) async {
      zustand.add(Abgleichszustand(erreichbar: erreichbar, ausstehend: 0));
      await Future<void>.delayed(Duration.zero);
    }

    await melde(erreichbar: true);
    await melde(erreichbar: true);
    await melde(erreichbar: true);
    expect(vorrat.laeufe, 1, reason: 'bisher ein Lauf je Meldung');

    await aufnahme('neu');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(vorrat.laeufe, 2, reason: 'eine neue Aufnahme kommt in den Vorrat');

    await melde(erreichbar: false);
    await aufnahme('offline');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(vorrat.laeufe, 2, reason: 'ohne Server nichts zu holen');
    await melde(erreichbar: true);
    expect(vorrat.laeufe, 3);
  });
}

class _ZaehlenderVorrat extends Vorrat {
  _ZaehlenderVorrat(super.db, super.beschaffung);

  var laeufe = 0;

  @override
  Future<int> fuelle() async {
    laeufe++;
    return 0;
  }
}

/// Zählt, wie oft nachgesehen wird, ob eine Datei da ist.
final class _Zaehler extends IOOverrides {
  var nachgesehen = 0;

  @override
  File createFile(String path) => _Datei(super.createFile(path), this);
}

class _Datei implements File {
  _Datei(this._echt, this._zaehler);

  final File _echt;
  final _Zaehler _zaehler;

  @override
  String get path => _echt.path;

  @override
  Future<bool> exists() {
    _zaehler.nachgesehen++;
    return _echt.exists();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
