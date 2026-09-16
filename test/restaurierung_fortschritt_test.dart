import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/utils/dauertext.dart';
import 'package:photo_vault/services/restore_queue_service.dart';

/// Der Fortschritt der KI-Restaurierung sprach Werkzeugsprache: „Kachel
/// 12 von 20". Prozent und Restzeit beantworten die Frage, die man
/// wirklich stellt – aber nur, wenn sie sich rechnen lassen.
RestoreJobData _auftrag({
  int fertig = 0,
  int gesamt = 0,
  DateTime? gestartet,
  String status = 'running',
}) =>
    RestoreJobData(
      id: 'j1',
      assetId: 'a1',
      status: status,
      tilesDone: fertig,
      tilesTotal: gesamt,
      createdAt: DateTime(2026, 8, 26, 10),
      startedAt: gestartet,
    );

void main() {
  group('fortschrittProzent', () {
    test('rechnet den Anteil auf ganze Prozent', () {
      expect(fortschrittProzent(_auftrag(fertig: 5, gesamt: 20)), 25);
      expect(fortschrittProzent(_auftrag(fertig: 1, gesamt: 3)), 33);
    });

    test('ohne bekannte Gesamtzahl gibt es keinen Anteil', () {
      // Die Kachelzahl steht erst fest, wenn das Bild dekodiert ist.
      expect(fortschrittProzent(_auftrag(fertig: 0, gesamt: 0)), isNull);
    });

    test('mehr als hundert Prozent gibt es nicht', () {
      expect(fortschrittProzent(_auftrag(fertig: 25, gesamt: 20)), 100);
    });
  });

  group('restzeitSchaetzung', () {
    final start = DateTime(2026, 8, 26, 10, 0, 0);

    test('rechnet aus den erledigten Kacheln auf die offenen hoch', () {
      // Gemessen am einen echten Auftrag der Testbibliothek: 20 Kacheln
      // in 99 Sekunden. Nach 5 Kacheln in 25 Sekunden bleiben 15 mal 5
      // Sekunden.
      final rest = restzeitSchaetzung(
        _auftrag(fertig: 5, gesamt: 20, gestartet: start),
        jetzt: start.add(const Duration(seconds: 25)),
      );
      expect(rest, const Duration(seconds: 75));
    });

    test('ohne Startzeit keine Schaetzung', () {
      // Die Auftraege aus der Zeit vor Fassung 53 haben keine.
      expect(
          restzeitSchaetzung(_auftrag(fertig: 5, gesamt: 20),
              jetzt: start.add(const Duration(seconds: 25))),
          isNull);
    });

    test('ohne eine einzige fertige Kachel keine Schaetzung', () {
      // Es gibt nichts, woraus sich rechnen liesse. Eine geratene
      // Restzeit waere schlimmer als keine.
      expect(
          restzeitSchaetzung(
            _auftrag(fertig: 0, gesamt: 20, gestartet: start),
            jetzt: start.add(const Duration(seconds: 25)),
          ),
          isNull);
    });

    test('am Ende ist die Restzeit null und nicht negativ', () {
      expect(
          restzeitSchaetzung(
            _auftrag(fertig: 20, gesamt: 20, gestartet: start),
            jetzt: start.add(const Duration(seconds: 99)),
          ),
          Duration.zero);
    });

    test('eine Startzeit in der Zukunft ergibt keine Schaetzung', () {
      // Kommt bei einer verstellten Uhr vor; ohne diese Grenze käme eine
      // negative Restzeit heraus.
      expect(
          restzeitSchaetzung(
            _auftrag(fertig: 5, gesamt: 20, gestartet: start),
            jetzt: start.subtract(const Duration(seconds: 5)),
          ),
          isNull);
    });
  });

  group('dauerText', () {
    late AppTexte t;
    testWidgets('holt die Texte', (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Builder(builder: (context) {
          t = AppTexte.of(context);
          return const SizedBox();
        }),
      ));

      expect(dauerText(t, const Duration(seconds: 5)), '5 Sekunden');
      expect(dauerText(t, const Duration(seconds: 1)), 'eine Sekunde');
      // Unter einer Sekunde steht trotzdem eine – „0 Sekunden" waere
      // keine Restzeit, sondern ein Widerspruch zum laufenden Balken.
      expect(dauerText(t, Duration.zero), 'eine Sekunde');
      expect(dauerText(t, const Duration(seconds: 90)), '2 Minuten');
      expect(dauerText(t, const Duration(minutes: 1)), 'eine Minute');
    });
  });

  group('die Warteschlange auf dem Schirm', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('markRestoreJobStatus setzt und loescht die Startzeit', () async {
      await db.createRestoreJob(RestoreJobsCompanion.insert(
        id: 'j1',
        assetId: 'a1',
        status: 'queued',
        createdAt: DateTime(2026, 8, 26, 10),
      ));
      Future<RestoreJobData> holen() async =>
          (await (db.select(db.restoreJobs)
                ..where((j) => j.id.equals('j1')))
              .getSingle());

      expect((await holen()).startedAt, isNull);

      await db.markRestoreJobStatus('j1', 'running');
      expect((await holen()).startedAt, isNotNull);

      // Zurueck in die Warteschlange: Die alte Startzeit muss weg, sonst
      // stuende beim zweiten Anlauf eine Restzeit von Stunden da.
      await db.markRestoreJobStatus('j1', 'queued');
      expect((await holen()).startedAt, isNull);

      // Ein Endstatus laesst sie stehen – sie ist dann eine Tatsache
      // ueber die Vergangenheit.
      await db.markRestoreJobStatus('j1', 'running');
      await db.markRestoreJobStatus('j1', 'done');
      expect((await holen()).startedAt, isNotNull);
    });
  });
}
