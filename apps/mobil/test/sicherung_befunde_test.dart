// Sicherung: behobene Befunde aus dem Prüfkatalog der Handy-App (MOB,
// Issue #418): je Befund ein Test, der ohne die Korrektur scheitert.
import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/abgleich.dart' show Abgleichszustand;
import 'package:kern/db/database.dart';
import 'package:photo_manager/photo_manager.dart' show PermissionState;
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/sicherung.dart';
import 'package:photo_vault_mobil/sicherung/dienst.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:photo_vault_mobil/sicherung/kamerarolle.dart';
import 'package:photo_vault_mobil/sicherung/lauf.dart';
import 'package:photo_vault_mobil/sicherung/stand.dart';

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('de'),
  localizationsDelegates: AppTexte.localizationsDelegates,
  supportedLocales: AppTexte.supportedLocales,
  home: home,
);

/// Eine Kamerarolle mit festen Einträgen, ohne Dateien.
class _Rolle implements Kamerarolle {
  _Rolle(this.ids, {this.videos = const []});

  final List<String> ids;

  /// Kennungen von Videos; ohne `videos: true` liefert die Rolle sie nicht,
  /// wie `PhotoManagerRolle`.
  final List<String> videos;

  @override
  Future<List<Rolleneintrag>> eintraege({required bool videos}) async => [
    for (final id in [...ids, if (videos) ...this.videos])
      Rolleneintrag(
        id: id,
        geaendert: DateTime(2026, 6, 1),
        aufgenommen: DateTime(2026, 6, 1, 12),
        video: this.videos.contains(id),
        dateien: (_) async => null,
      ),
  ];

  @override
  Future<void> aufraeumen() async {}

  @override
  Future<int> loesche(List<String> ids) async => 0;

  @override
  Future<List<String>> vorhanden(List<String> ids) async => ids;
}

/// Eine Rolle, deren Einträge ihre Dateien so bereitstellen, wie der Test
/// es will – auch nie.
class _Bereitrolle implements Kamerarolle {
  _Bereitrolle(this.eintraege_);

  final List<Rolleneintrag> eintraege_;

  @override
  Future<List<Rolleneintrag>> eintraege({required bool videos}) async =>
      eintraege_;

  @override
  Future<void> aufraeumen() async {}

  @override
  Future<int> loesche(List<String> ids) async => 0;

  @override
  Future<List<String>> vorhanden(List<String> ids) async => ids;
}

Rolleneintrag _bereit(
  String id,
  Future<List<Rollendatei>?> Function(Bereitstellung b) dateien, {
  Future<bool> Function()? lokal,
}) => Rolleneintrag(
  id: id,
  geaendert: DateTime(2026, 6, 1),
  aufgenommen: DateTime(2026, 6, 1, 12),
  video: false,
  dateien: dateien,
  lokal: lokal,
);

Sicherungsdienst _dienst(
  Sicherungseinstellungen e, {
  Kamerarolle Function(List<String> alben)? rolle,
}) {
  final ordner = Directory.systemTemp.createTempSync('pv_sicherung_befund_');
  addTearDown(() => ordner.deleteSync(recursive: true));
  Sicherungsstand.oeffne(ordner)
    ..einstellungen = e
    ..schliesse();
  final d = Sicherungsdienst(
    ordner: ordner,
    server: Uri.parse('http://localhost:1/'),
    token: 'pv1_test',
    rolle: rolle,
  );
  addTearDown(d.dispose);
  return d;
}

void main() {
  testWidgets('MOB-021 abgemeldet: die Sicherungsseite sagt es auch bei '
      'ausgeschalteter Sicherung', (tester) async {
    final d = _dienst(const Sicherungseinstellungen());
    await tester.pumpWidget(_app(Sicherungsseite(dienst: d)));
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(Sicherungsseite)));
    expect(find.text(t.abgemeldetHinweis), findsNothing);

    d.meldeAbgemeldet(true);
    await tester.pumpAndSettle();
    expect(find.text(t.abgemeldetHinweis), findsOneWidget);
  });

  testWidgets('MOB-171 Zugriff in den Einstellungen erteilt: zurück in der '
      'App verschwindet „Kein Zugriff“ ohne Neustart', (tester) async {
    const kanal = MethodChannel('com.fluttercandies/photo_manager');
    final bote = tester.binding.defaultBinaryMessenger;
    var erlaubt = false;
    bote.setMockMethodCallHandler(kanal, (aufruf) async {
      if (aufruf.method == 'getPermissionState') {
        return (erlaubt ? PermissionState.authorized : PermissionState.denied)
            .index;
      }
      return null;
    });
    addTearDown(() => bote.setMockMethodCallHandler(kanal, null));

    // Eingeschaltet scheiterte am verweigerten Zugriff: Schalter aus.
    final d = _dienst(const Sicherungseinstellungen())
      ..zugriff = Zugriff.verweigert;
    await tester.pumpWidget(_app(Sicherungsseite(dienst: d)));
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(Sicherungsseite)));
    expect(find.text(t.sicherungKeinZugriff), findsOneWidget);

    erlaubt = true;
    await tester.runAsync(d.zurueckInDerApp);
    await tester.pumpAndSettle();
    expect(d.zugriff, Zugriff.erlaubt);
    expect(find.text(t.sicherungKeinZugriff), findsNothing);
  });

  test('MOB-180 nur gewählte Alben: „nur auf dem Telefon“ zählt nur, was '
      'ein Lauf sichern würde', () async {
    final alle = _Rolle(['a1', 'a2', 'a3', 'b1', 'b2']);
    final urlaub = _Rolle(['a1', 'a2', 'a3']);
    final d = _dienst(
      const Sicherungseinstellungen(an: true, alben: ['urlaub']),
      rolle: (alben) => alben.isEmpty ? alle : urlaub,
    )..zugriff = Zugriff.erlaubt;
    await d.zaehleUngesicherte();
    expect([for (final l in d.ungesichert!) l.id], ['a1', 'a2', 'a3']);
  });

  testWidgets('#425 „Speicher freigeben“ nur, solange der Abgleich läuft', (
    tester,
  ) async {
    final d = _dienst(const Sicherungseinstellungen(an: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(_app(Sicherungsseite(dienst: d, db: db)));
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(Sicherungsseite)));
    ListTile punkt() => tester.widget<ListTile>(
      find.ancestor(
        of: find.text(t.sicherungFreigeben),
        matching: find.byType(ListTile),
      ),
    );

    Future<void> melde(Abgleichszustand? z) async {
      d.meldeAbgleich(z);
      await tester.pumpAndSettle();
    }

    // Noch keine Antwort vom Server.
    expect(punkt().enabled, isFalse);
    expect(find.text(t.sicherungFreigebenGesperrt), findsOneWidget);

    await melde(const Abgleichszustand(erreichbar: true, ausstehend: 0));
    expect(punkt().enabled, isTrue);
    expect(find.text(t.sicherungFreigebenHinweis), findsOneWidget);

    // Offline, abgemeldet, anderes Schema: Die Kopie kann veraltet sein.
    for (final z in const [
      Abgleichszustand(erreichbar: false, ausstehend: 0),
      Abgleichszustand(erreichbar: true, ausstehend: 0, abgemeldet: true),
      Abgleichszustand(
        erreichbar: true,
        ausstehend: 0,
        serverSchema: 99,
        hierSchema: 98,
      ),
      Abgleichszustand(erreichbar: false, ausstehend: 0, ungeklaert: true),
    ]) {
      await melde(const Abgleichszustand(erreichbar: true, ausstehend: 0));
      await melde(z);
      expect(punkt().enabled, isFalse);
      expect(find.text(t.sicherungFreigebenGesperrt), findsOneWidget);
    }
  });

  test('#437 „Videos sichern“ aus: Videos zählen nicht als „nur auf dem '
      'Telefon“, und eingeschaltet gleich wieder', () async {
    final rolle = _Rolle(['f1', 'f2'], videos: ['v1']);
    final d = _dienst(
      const Sicherungseinstellungen(an: true, videos: false),
      rolle: (_) => rolle,
    )..zugriff = Zugriff.erlaubt;
    await d.zaehleUngesicherte();
    expect([for (final l in d.ungesichert!) l.id], ['f1', 'f2']);

    await d.setze(d.einstellungen.mit(videos: true));
    // Die neue Zählung läuft ohne Warten auf sie an.
    await pumpEventQueue();
    expect([for (final l in d.ungesichert!) l.id], ['f1', 'f2', 'v1']);
  });

  group('#437 Bereitstellen mit Abbruch und Frist', () {
    late Directory ordner;
    late Sicherungsstand stand;
    late File datei;
    late Serververbindung verbindung;

    setUp(() {
      // Ohne Server: Jede Anfrage scheitert wie ohne Netz.
      verbindung = Serververbindung(
        Uri.parse('http://localhost:1/'),
        'pv1_test',
        client: MockClient((_) async => throw http.ClientException('weg')),
      );
      ordner = Directory.systemTemp.createTempSync('pv_bereit_');
      stand = Sicherungsstand.oeffne(ordner)
        ..einstellungen = const Sicherungseinstellungen(an: true);
      datei = File('${ordner.path}/IMG_1.JPG')..writeAsBytesSync([1, 2, 3]);
    });

    tearDown(() {
      verbindung.schliesse();
      stand.schliesse();
      ordner.deleteSync(recursive: true);
    });

    Sicherungslauf lauf(Kamerarolle rolle, {bool nurLokal = false}) =>
        Sicherungslauf(
          rolle: rolle,
          verbindung: verbindung,
          stand: stand,
          wer: 'app',
          nurLokal: nurLokal,
          bereitstellFrist: const Duration(milliseconds: 300),
          pruefTakt: const Duration(milliseconds: 20),
        );

    Future<List<Rollendatei>> eine(Bereitstellung _) async => [
      Rollendatei(teil: 'bild', name: 'IMG_1.JPG', datei: datei),
    ];

    test(
      '„Aus“ greift vor jedem Eintrag, nicht erst nach der Gruppe',
      () async {
        var halt = false;
        final geholt = <String>[];
        final rolle = _Bereitrolle([
          for (final id in ['e1', 'e2', 'e3'])
            _bereit(id, (b) async {
              geholt.add(id);
              halt = true;
              return eine(b);
            }),
        ]);
        final bericht = await lauf(rolle).laufe(abbrechen: () => halt);
        expect(geholt, ['e1']);
        expect(bericht.vollstaendig, isFalse);
      },
    );

    test('ein Download, der nie zurückkommt: „Aus“ beendet den Lauf, bricht '
        'den Abruf ab und gibt die Sperre frei', () async {
      var halt = false;
      var abgebrochen = 0;
      final rolle = _Bereitrolle([
        _bereit('haengt', (b) {
          b.beiAbbruch(() async => abgebrochen++);
          // Fortschritt hält die Frist auf; nur das Aus beendet es.
          Timer.periodic(const Duration(milliseconds: 50), (t) {
            if (b.abgebrochen) return t.cancel();
            b.geht();
          });
          return Completer<List<Rollendatei>?>().future;
        }),
      ]);
      Timer(const Duration(milliseconds: 400), () => halt = true);
      await lauf(
        rolle,
      ).laufe(abbrechen: () => halt).timeout(const Duration(seconds: 5));
      expect(abgebrochen, 1);
      expect(stand.fehler, isEmpty, reason: 'Abbruch ist kein Fehlschlag');
      expect(stand.sperre('hintergrund-1'), isTrue, reason: 'frei');
    });

    test('geht es zu lange nicht voran, scheitert der Eintrag, und der '
        'nächste kommt dran', () async {
      var abgebrochen = 0;
      final geholt = <String>[];
      final rolle = _Bereitrolle([
        _bereit('haengt', (b) {
          geholt.add('haengt');
          b.beiAbbruch(() async => abgebrochen++);
          return Completer<List<Rollendatei>?>().future;
        }),
        _bereit('naechster', (b) async {
          geholt.add('naechster');
          return eine(b);
        }),
      ]);
      // Der Testserver fehlt: Der Lauf endet beim Fragen nach den
      // Prüfsummen (KeineVerbindung), nach dem Bereitstellen.
      await lauf(rolle).laufe().timeout(const Duration(seconds: 5));
      expect(geholt, ['haengt', 'naechster']);
      expect(abgebrochen, 1);
      expect(stand.fehler.keys, ['haengt']);
    });

    test('nur lokal (kurze Auffrischung): Originale in iCloud bleiben offen, '
        'ohne Fehlschlag', () async {
      final geholt = <String>[];
      final rolle = _Bereitrolle([
        _bereit('icloud', (b) async {
          geholt.add('icloud');
          return eine(b);
        }, lokal: () async => false),
        _bereit('hier', (b) async {
          geholt.add('hier');
          return eine(b);
        }, lokal: () async => true),
      ]);
      await lauf(rolle, nurLokal: true).laufe();
      expect(geholt, ['hier']);
      expect(stand.fehler, isEmpty);
    });
  });
}
