import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/import_koordinator.dart';
import 'package:kern/services/import_plan.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/state/library_state.dart';

/// Ein Import mit Plan schlägt jede Datei einmal nach, statt je Datei die
/// ganze Planliste durchzugehen (#434). Bei 200 000 Dateien eines Umzugs
/// wuchs der Aufwand sonst quadratisch.
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths paths;
  late ImportService importe;
  const anzahl = 200;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_plan_nachschlagen_');
    db = AppDatabase(NativeDatabase.memory());
    paths = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'library')),
    );
    importe = _Dubletten(db, paths);
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<(ImportPlan, _ZaehlendeListe<ImportPlanEintrag>, List<String>)>
  plan() async {
    final eintraege = <ImportPlanEintrag>[];
    for (var i = 0; i < anzahl; i++) {
      final f = File(p.join(temp.path, 'quelle', 'f$i.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([i % 256]);
      eintraege.add(
        ImportPlanEintrag(
          pfad: f.path,
          art: ImportPlanArt.neu,
          angaben: ImportDateiangaben(
            pfad: f.path,
            pruefsumme: i.toRadixString(16).padLeft(64, '0'),
            bytes: 1,
            datum: DateTime(2024),
            datumGeschaetzt: false,
            istBild: true,
            geaendert: f.lastModifiedSync(),
          ),
        ),
      );
    }
    final liste = _ZaehlendeListe(eintraege);
    return (
      ImportPlan(
        eintraege: liste,
        regelstand: await ImportPlanDienst(db, importe).aktuellerRegelstand(),
        am: DateTime(2026),
        spaetereRegeln: 0,
      ),
      liste,
      [for (final e in eintraege) e.pfad],
    );
  }

  test('ohne Server', () async {
    final (plan_, liste, pfade) = await plan();
    final stand = await ImportKoordinator(
      db: db,
      importe: importe,
      nachbearbeiten: (_, {bool regelnAnwenden = true}) async {},
      starteAnalyse: () async {},
    ).importiere(pfade, plan: plan_).toList();

    expect(stand.last.done, anzahl);
    expect(
      liste.zugriffe,
      lessThan(5 * anzahl),
      reason: 'bisher ein Durchgang durch die ganze Liste je Datei',
    );
  });

  test('verbunden', () async {
    final (plan_, liste, pfade) = await plan();
    final verbindung = Serververbindung(
      Uri.parse('http://server/'),
      'probe',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/zustand')) {
          return http.Response(
            jsonEncode({
              'funktionen': {'importplan': 2},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('abgelehnt', 400);
      }),
    );
    final lib = LibraryState()
      ..db = db
      ..paths = paths
      ..verbindung = Verbindungsdatei(
        server: Uri.parse('http://server/'),
        konto: 'probe',
        geraet: 'Rechner',
        token: 'probe',
      )
      ..abgleich = Abgleich(db, verbindung);

    final stand = await lib.importFiles(pfade, plan: plan_).toList();

    expect(stand.last.done, anzahl);
    expect(liste.zugriffe, lessThan(5 * anzahl));
  });
}

/// Jede Datei ist schon da – der Test misst das Nachschlagen, nicht den
/// Import.
class _Dubletten extends ImportService {
  _Dubletten(super.db, super.paths);

  @override
  Future<ImportResult> importFile(
    String filePath, {
    String? erwartetePruefsumme,
    ImportDateiangaben? erwarteteAngaben,
    Future<void> Function(String assetId)? beiEintrag,
  }) async => ImportResult(filePath, ImportOutcome.duplicateSkipped);
}

/// Zählt jeden Zugriff auf ein Element der Planliste.
class _ZaehlendeListe<T> extends ListBase<T> {
  _ZaehlendeListe(this._inhalt);

  final List<T> _inhalt;
  var zugriffe = 0;

  @override
  int get length => _inhalt.length;

  @override
  set length(int n) => _inhalt.length = n;

  @override
  T operator [](int i) {
    zugriffe++;
    return _inhalt[i];
  }

  @override
  void operator []=(int i, T wert) => _inhalt[i] = wert;
}
