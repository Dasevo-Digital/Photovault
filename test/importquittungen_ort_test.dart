import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/auswertung/fortschritt.dart';
import 'package:kern/services/import_plan.dart';
import 'package:kern/services/import_service.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/importquittungen.dart';
import 'package:photo_vault/services/library_location.dart';

/// Der Importverlauf hängt an der Bibliothek, nicht an ihrem Pfad (#433).
/// Bis hierher war sein Ordner nach dem Pfad benannt; nach dem Verlegen
/// oder unter einem anderen Laufwerksbuchstaben war er nicht mehr zu
/// finden.
void main() {
  late Directory temp;
  late Directory daten;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_quittung_ort_');
    daten = Directory(p.join(temp.path, 'daten'));
    LibraryLocation.nutzeFuerTests(anker: daten);
  });
  tearDown(() async {
    LibraryLocation.zuruecksetzenFuerTests();
    await temp.delete(recursive: true);
  });

  Directory bibliothek(String ort) =>
      Directory(p.join(temp.path, ort, 'library'))..createSync(recursive: true);

  Future<void> quittung(Importquittungen ablage) async {
    final pfad = p.join(temp.path, 'dcim', 'a.jpg');
    final plan = ImportPlan(
      eintraege: [
        ImportPlanEintrag(
          pfad: pfad,
          art: ImportPlanArt.neu,
          angaben: ImportDateiangaben(
            pfad: pfad,
            pruefsumme: sha256.convert([1]).toString(),
            bytes: 1,
            datum: DateTime(2024),
            datumGeschaetzt: false,
            istBild: true,
          ),
        ),
      ],
      regelstand: 'probe',
      am: DateTime(2026),
      spaetereRegeln: 0,
    );
    await ablage
        .protokolliere(
          plan,
          Stream.fromIterable([ImportProgress(1, 1, pfad: pfad, assetId: 'x')]),
        )
        .drain<void>();
  }

  test('nach dem Verlegen ist der Verlauf noch da', () async {
    final alt = bibliothek('alt');
    await quittung(await Importquittungen.fuer(alt));

    // Verlegt: dieselbe Bibliothek (mit ihrer Standortkennung) an einem
    // anderen Ort.
    final neu = Directory(p.join(temp.path, 'neu'))..createSync();
    await alt.parent.rename(p.join(neu.path, 'bibliothek'));
    final verlegt = Directory(p.join(neu.path, 'bibliothek', 'library'));

    expect(
      await (await Importquittungen.fuer(verlegt)).liste(),
      hasLength(1),
      reason: 'bisher lag der Verlauf verwaist unter dem alten Pfad',
    );
  });

  test('ein nach dem Pfad benannter Ordner wird übernommen', () async {
    final bib = bibliothek('alt');
    final pfad = await bib.resolveSymbolicLinks();
    final frueher = Importquittungen(
      Directory(
        p.join(
          daten.path,
          'bibliotheksverlauf',
          sha256.convert(utf8.encode(p.normalize(pfad))).toString(),
        ),
      ),
    );
    await quittung(frueher);

    final ablage = await Importquittungen.fuer(bib);
    expect(await ablage.liste(), hasLength(1));
    await quittung(ablage);
    expect(await (await Importquittungen.fuer(bib)).liste(), hasLength(2));
    expect(
      Directory(p.join(daten.path, 'bibliotheksverlauf')).listSync(),
      hasLength(1),
      reason: 'der alte Ordner ist aufgegangen',
    );
  });
}
