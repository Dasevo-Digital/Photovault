import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/platform/speicherlaufwerk.dart';
import 'package:photo_vault/services/speicherinventar.dart';
import 'package:photo_vault/widgets/speicherinventar_grafik.dart';

void main() {
  final stand = SpeicherinventarStand([
    const Speicherorteintrag(
      id: 'offen',
      name: 'Aktuell',
      pfad: '/Speicher/Aktuell',
      art: Speicherortart.bibliothek,
      erreichbar: true,
      aktiv: true,
      bibliothek: 'offen',
      katalogVorhanden: true,
      laufwerk: Speicherlaufwerk('lokal', 'Interner Speicher', '/'),
    ),
    const Speicherorteintrag(
      id: 'archiv',
      name: 'Fotoarchiv',
      pfad: '/Speicher/Fotoarchiv',
      art: Speicherortart.bibliothek,
      erreichbar: false,
      bibliothek: 'archiv',
      laufwerk: Speicherlaufwerk('extern', 'Archivplatte', '/Speicher'),
      laufwerkHistorisch: true,
    ),
    const Speicherorteintrag(
      id: 'dateien',
      name: 'Aktuell',
      pfad: '/Speicher/Aktuell/library/originals',
      aufgeloesterPfad: '/Medien/Originale',
      art: Speicherortart.dateien,
      erreichbar: true,
      bibliothek: 'offen',
      laufwerk: Speicherlaufwerk('medien', 'Fotoplatte', '/Medien'),
    ),
    Speicherorteintrag(
      id: 'sicherung',
      name: 'Fotoarchiv',
      pfad: '/Sicherungen/Archiv',
      art: Speicherortart.sicherung,
      erreichbar: true,
      bibliothek: 'archiv',
      pruefung: Speicherpruefung(DateTime(2026, 1, 2, 12), 42, false),
    ),
  ]);
  const key = Key('inventar-bild');
  Future<void> zeigen(WidgetTester tester, {double skalierung = 1}) async {
    final schrift = Platform.environment['PV_VISUAL_FONT'];
    if (schrift != null) {
      await tester.runAsync(() async {
        await (FontLoader('Vorschau')
              ..addFont(File(schrift).readAsBytes().then(ByteData.sublistView)))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
    }
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            fontFamily: schrift == null ? null : 'Vorschau',
          ),
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(skalierung)),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SpeicherinventarGrafik(stand: stand),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'konkrete Ordner, ausgelagerte Dateien und datierte Sicherung bleiben unterscheidbar',
    (tester) async {
      tester.view.physicalSize = const Size(1120, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await zeigen(tester);
      expect(find.text('/Speicher/Fotoarchiv'), findsOneWidget);
      expect(find.text('Geöffnete Bibliothek'), findsOneWidget);
      expect(find.text('Nicht erreichbar oder Zugriff fehlt'), findsOneWidget);
      expect(
        find.text('Zuletzt diesem Datenträger zugeordnet'),
        findsOneWidget,
      );
      expect(find.text('Bibliotheksdateien von Aktuell'), findsOneWidget);
      expect(find.text('/Medien/Originale'), findsOneWidget);
      expect(find.textContaining('42 bestätigte Originale'), findsOneWidget);
      expect(find.text('Datenträger nicht ermittelbar'), findsOneWidget);
      expect(find.textContaining('0 Fotos'), findsNothing);
      expect(tester.takeException(), isNull);
      final ausgabe = Platform.environment['PV_VISUAL_OUT'];
      if (ausgabe != null) {
        await tester.runAsync(() async {
          final bild = await tester
              .renderObject<RenderRepaintBoundary>(find.byKey(key))
              .toImage();
          try {
            final bytes = await bild.toByteData(format: ui.ImageByteFormat.png);
            await File(ausgabe).writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            bild.dispose();
          }
        });
      }
      await tester.tap(find.text('Ortsangaben anzeigen').first);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('nicht geöffnet'), findsOneWidget);
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'schmale Ansicht und große Schrift bleiben ohne Überlauf bedienbar',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await zeigen(tester, skalierung: 2.5);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('/Sicherungen/Archiv'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
