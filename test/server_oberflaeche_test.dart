import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/einstellungen/einstellungsstand.dart';
import 'package:photo_vault/screens/einstellungen/server.dart';
import 'package:photo_vault/screens/server_verbinden_screen.dart';
import 'package:photo_vault/services/library_location.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/qr_bild.dart';

/// Die Oberfläche zum Verbinden mit einem Server (Issue #86, Stufe 2):
/// Sie steht, auch schmal, und sagt, was sie tut.
void main() {
  late Directory ordner;
  late LibraryState bib;

  setUp(() async {
    ordner = Directory.systemTemp.createTempSync('pv_server_ui_');
    LibraryLocation.nutzeFuerTests(anker: ordner);
    PackageInfo.setMockInitialValues(
      appName: 'Photo Vault',
      packageName: 'test',
      version: '0',
      buildNumber: '0',
      buildSignature: '',
    );
    bib = LibraryState()
      ..db = AppDatabase(NativeDatabase.memory())
      ..paths = await StoragePaths.forTesting(
        Directory('${ordner.path}/library'),
      );
  });
  tearDown(() async {
    await bib.db.close();
    LibraryLocation.zuruecksetzenFuerTests();
    ordner.deleteSync(recursive: true);
  });

  Future<AppTexte> zeige(
    WidgetTester tester,
    Widget Function(Einstellungsstand) seite,
  ) async {
    await tester.binding.setSurfaceSize(const Size(380, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late Einstellungsstand stand;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Builder(
          builder: (context) {
            stand = Einstellungsstand(
              bib,
              kontext: () => context,
              aktiv: () => true,
            );
            return Scaffold(body: SingleChildScrollView(child: seite(stand)));
          },
        ),
      ),
    );
    await tester.pump();
    addTearDown(stand.dispose);
    return AppTexte.of(tester.element(find.byType(Scaffold).first));
  }

  testWidgets('ohne Verbindung: Erklärung und der Weg dorthin', (tester) async {
    final t = await zeige(tester, ServerGruppe.new);
    expect(find.text(t.serverErklaerung), findsOneWidget);
    expect(find.text(t.serverVerbinden), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('der erste Schritt steht auch schmal', (tester) async {
    final t = await zeige(
      tester,
      (stand) =>
          SizedBox(height: 800, child: ServerVerbindenScreen(stand: stand)),
    );
    expect(find.text(t.serverAdresse), findsOneWidget);
    expect(find.text(t.serverPasswort), findsOneWidget);
    expect(find.text(t.serverAnmelden), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('der QR-Code wird gezeichnet', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: QrBild('otpauth://totp/Photo%20Vault:erika?secret=ABC'),
          ),
        ),
      ),
    );
    expect(find.byType(QrBild), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
