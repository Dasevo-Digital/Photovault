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

  test('ohne Anstoss bleibt es bei einem Lauf', () async {
    final rolle = _Rolle()..erste.complete();
    final d = dienst(rolle);
    addTearDown(d.dispose);
    await d.sichere();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(rolle.abfragen, 2, reason: 'ein Lauf und das Zählen danach');
  });
}
