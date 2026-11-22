import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault_mobil/sicherung/dienst.dart';
import 'package:photo_vault_mobil/sicherung/kamerarolle.dart';
import 'package:photo_vault_mobil/sicherung/stand.dart';

/// Eine Kamerarolle, deren erste Abfrage wartet, bis der Test sie freigibt –
/// so lässt sich ein Anstoss mitten in einen Lauf legen.
class _Rolle implements Kamerarolle {
  var abfragen = 0;
  final erste = Completer<void>();

  @override
  Future<List<Rolleneintrag>> eintraege({required bool videos}) async {
    abfragen++;
    if (abfragen == 1) await erste.future;
    return const [];
  }

  @override
  Future<void> aufraeumen() async {}

  @override
  Future<int> loesche(List<String> ids) async => 0;

  @override
  Future<List<String>> vorhanden(List<String> ids) async => const [];
}

/// Eine Kamerarolle mit festen Einträgen, die mitschreibt, wessen Dateien
/// angefragt werden – bereitstellen lässt sich keine.
class _Merkrolle implements Kamerarolle {
  _Merkrolle(this.ids, this.geaendert);

  final List<String> ids;
  final DateTime geaendert;
  final angefragt = <String>[];

  @override
  Future<List<Rolleneintrag>> eintraege({required bool videos}) async => [
    for (final id in ids)
      Rolleneintrag(
        id: id,
        geaendert: geaendert,
        aufgenommen: geaendert,
        video: false,
        dateien: (_) async {
          angefragt.add(id);
          return null;
        },
      ),
  ];

  @override
  Future<void> aufraeumen() async {}

  @override
  Future<int> loesche(List<String> ids) async => 0;

  @override
  Future<List<String>> vorhanden(List<String> ids) async => const [];
}

/// Wer während eines Laufs neue Fotos speichert, wartete bis zum nächsten
/// Öffnen der App oder bis zur Nacht: Der Anstoss fiel weg, und der Lauf
/// kannte nur die Fotos von seinem Beginn.
void main() {
  late Directory ordner;

  setUp(() {
    ordner = Directory.systemTemp.createTempSync('pv_anstoss_');
    Sicherungsstand.oeffne(ordner)
      ..einstellungen = const Sicherungseinstellungen(an: true)
      ..schliesse();
  });
  tearDown(() => ordner.deleteSync(recursive: true));

  Sicherungsdienst dienst(_Rolle rolle) => Sicherungsdienst(
    ordner: ordner,
    server: Uri.parse('http://localhost:1/'),
    token: 'pv1_test',
    rolle: (_) => rolle,
    netz: (_) async => true,
  )..zugriff = Zugriff.erlaubt;

  test(
    'ein Anstoss während eines Laufs löst danach einen weiteren aus',
    () async {
      final rolle = _Rolle();
      final d = dienst(rolle);
      addTearDown(d.dispose);

      final erster = d.sichere();
      await Future<void>.delayed(Duration.zero);
      expect(d.laeuft, isTrue);
      // Neue Fotos aus Nachrichten, während der erste noch arbeitet.
      await d.sichere();
      await d.sichere();
      expect(rolle.abfragen, 1);

      rolle.erste.complete();
      await erster;
      for (var i = 0; i < 50 && (rolle.abfragen < 4 || d.laeuft); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      // Je Lauf eine Abfrage, danach eine fürs Zählen des Ungesicherten:
      // zwei Läufe, nicht drei – zwei Anstösse ergeben einen weiteren.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(rolle.abfragen, 4);
      expect(d.laeuft, isFalse);
    },
  );

  test('„Jetzt sichern“ versucht Pausiertes erneut, lädt aber nicht noch '
      'einmal hoch, was der Server abgelehnt hat', () async {
    final zeit = DateTime(2026, 5, 6, 7);
    final stand = Sicherungsstand.oeffne(ordner)
      ..erledige(
        'abgelehnt',
        zeit,
        ausgang: 'abgelehnt',
        grund: 'Der Server konnte IMG_0001.MOV nicht aufnehmen',
      );
    for (var i = 0; i < Sicherungsstand.fehlerGrenze; i++) {
      stand.fehlschlag('pausiert', 'Datei kam nicht rechtzeitig');
    }
    stand.schliesse();
    final rolle = _Merkrolle(['abgelehnt', 'pausiert'], zeit);
    final d = Sicherungsdienst(
      ordner: ordner,
      server: Uri.parse('http://localhost:1/'),
      token: 'pv1_test',
      rolle: (_) => rolle,
      netz: (_) async => true,
    )..zugriff = Zugriff.erlaubt;
    addTearDown(d.dispose);

    expect(await d.sichereJetzt(), Sicherungsantwort.fertig);
    // Das Pausierte kam dran, das Abgelehnte nicht – es noch einmal
    // hochzuladen, brächte nur dieselbe Ablehnung.
    expect(rolle.angefragt, ['pausiert']);
    expect(d.abgelehnt, 1);
    expect(d.abgelehntGruende['abgelehnt'], contains('IMG_0001.MOV'));
    // Der Bericht zählt es weiter als gescheitert („Details“).
    expect(d.letzterLauf!.fehlgeschlagen, 2);

    // „Erneut versuchen“ auf der Sicherungsseite nimmt es wieder mit.
    rolle.angefragt.clear();
    d.versucheFehlerErneut();
    for (var i = 0; i < 50 && rolle.angefragt.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(rolle.angefragt, unorderedEquals(['abgelehnt', 'pausiert']));
  });

  test('ohne Anstoss bleibt es bei einem Lauf', () async {
    final rolle = _Rolle()..erste.complete();
    final d = dienst(rolle);
    addTearDown(d.dispose);
    await d.sichere();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(rolle.abfragen, 2, reason: 'ein Lauf und das Zählen danach');
  });
}
