import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/db/database.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/startfehler.dart';
import 'package:photo_vault_mobil/sitzung.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Geht die Kopie beim Start nicht auf, zeigt das Telefon den Grund statt
/// eines Ladekreises, der sich ewig dreht – etwa vor einer Kopie, die eine
/// neuere Fassung der App schon aufgestuft hat.
void main() {
  test(
    'eine neuere Kopie führt zum Startfehler und bleibt, wie sie ist',
    () async {
      final ordner = await Directory.systemTemp.createTemp('pv_mobil_neuer_');
      addTearDown(() => ordner.delete(recursive: true));
      final datei = File('${ordner.path}/library.sqlite');
      final db = AppDatabase(NativeDatabase(datei));
      await db.customSelect('SELECT 1').get();
      final neuer = db.schemaVersion + 1;
      await db.close();
      final roh = sqlite.sqlite3.open(datei.path);
      roh.execute('PRAGMA user_version = $neuer');
      roh.close();
      await Verbindungsdatei(
        server: Uri.parse('http://127.0.0.1:9'),
        konto: 'erika',
        geraet: 'Telefon',
        token: 'probe',
      ).schreibe(ordner);

      final sitzung = Sitzung(ordner: () async => ordner);
      await sitzung.starte();

      expect(sitzung.zustand, Sitzungszustand.fehler);
      expect(sitzung.startfehler, contains(NeuereBibliothek.kennung));
      final pruefen = sqlite.sqlite3.open(
        datei.path,
        mode: sqlite.OpenMode.readOnly,
      );
      addTearDown(pruefen.close);
      expect(pruefen.select('PRAGMA user_version').single.values.single, neuer);
    },
  );

  testWidgets('die Seite erklärt eine neuere Kopie eigens', (tester) async {
    final sitzung = Sitzung()
      ..startfehler =
          'DriftRemoteException: pv_neuere_bibliothek: schema 96 > 95';
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Startfehler(sitzung: sitzung),
      ),
    );
    final t = AppTexte.of(tester.element(find.byType(Scaffold)));

    expect(find.text(t.startfehlerNeuerTitel), findsOneWidget);
    expect(find.text(t.startfehlerNeuerText), findsOneWidget);
    expect(find.text(t.startfehlerErneut), findsOneWidget);
  });
}
