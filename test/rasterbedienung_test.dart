import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/widgets/rasterbedienung.dart';

/// Prüft die Bedienung, die alle vier Fotoraster teilen: Umschalt-Klick für
/// Bereiche, Strg/Command-Klick für einzelne, Pfeiltasten für den Zeiger und
/// Ziffern für Bewertung und Farbmarke.
///
/// Nicht gegen einen der echten Bildschirme, sondern gegen ein möglichst
/// kleines Gastwidget: Sonst prüfte jeder Fall nebenbei auch noch Datenstrom,
/// Rollbalken und Auswahlleiste mit, und ein Fehlschlag sagte nicht mehr, wo
/// er herkommt.

AssetData _foto(String id) => AssetData(
      id: id,
      relativePath: 'originals/$id.jpg',
      originalFileName: '$id.jpg',
      type: 'IMAGE',
      fileSizeBytes: 1000,
      checksum: id,
      fileCreatedAt: DateTime(2026, 8, 1),
      importedAt: DateTime(2026, 8, 1),
      isFavorite: false,
      isTrashed: false,
      isLocked: false,
      faceScanExcluded: false,
      gpsGeprueft: false,
      datumGeschaetzt: false,
      datumGeprueft: false,
      ortGeerbt: false,
      videobilderGeprueft: false,
      backedUp: false,
      autoBackedUp: false,
      facesScanned: false,
      ocrScanned: false,
      aiCaptionScanned: false,
      aiCaptionEdited: false,
      aiTagsScanned: false,
      isStackCover: false,
      rating: 0,
    );

class _Gast extends StatefulWidget {
  final AppDatabase db;
  final List<AssetData> assets;
  final bool mitTextfeld;
  const _Gast({required this.db, required this.assets, this.mitTextfeld = false});

  @override
  State<_Gast> createState() => _GastState();
}

class _GastState extends State<_Gast> with Rasterbedienung<_Gast, AssetData> {
  @override
  String rasterKennung(AssetData zeile) => zeile.id;

  @override
  ({bool favorit, String? farbe}) rasterMerkmale(AssetData zeile) =>
      (favorit: zeile.isFavorite, farbe: zeile.colorLabel);

  final Set<String> gewaehlt = {};
  final List<String> geoeffnet = [];
  late List<AssetData> _stand = widget.assets;

  @override
  Set<String> get auswahl => gewaehlt;

  @override
  AppDatabase get rasterDb => widget.db;

  @override
  List<AssetData> get rasterAssets => _stand;

  /// Wie die Suche: kein Datenstrom, also nach jeder Änderung selbst
  /// nachladen. Erst dadurch kann eine Taste eine Marke auch wieder wegnehmen.
  @override
  Future<void> rasterAktualisieren() async {
    final frisch = await widget.db.assetsByIds([for (final a in _stand) a.id]);
    if (mounted) setState(() => _stand = frisch);
  }

  /// Fest drei Spalten – die Rechnung dahinter prüft `rasterauswahl_test`.
  @override
  int get rasterSpalten => 3;

  @override
  void rasterOeffne(AssetData asset) => geoeffnet.add(asset.id);

  @override
  Widget build(BuildContext context) {
    return mitTastatur(
      kind: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.mitTextfeld) const TextField(key: Key('suchfeld')),
          for (final a in _stand)
            GestureDetector(
              key: Key('kachel-${a.id}'),
              onTap: () => rasterKlick(a),
              child: Container(
                width: 40,
                height: 20,
                color: gewaehlt.contains(a.id) ? Colors.green : Colors.grey,
              ),
            ),
        ],
      ),
    );
  }
}

void main() {
  late AppDatabase db;
  late List<AssetData> assets;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    assets = [for (var i = 1; i <= 7; i++) _foto('f$i')];
    for (final a in assets) {
      await db.insertAsset(AssetsCompanion.insert(
        id: a.id,
        relativePath: a.relativePath,
        originalFileName: a.originalFileName,
        type: a.type,
        fileSizeBytes: Value(a.fileSizeBytes),
        checksum: a.checksum,
        fileCreatedAt: a.fileCreatedAt,
        importedAt: a.importedAt,
      ));
    }
  });

  tearDown(() async => db.close());

  Future<_GastState> zeige(WidgetTester tester, {bool mitTextfeld = false}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: _Gast(db: db, assets: assets, mitTextfeld: mitTextfeld),
      ),
    ));
    return tester.state<_GastState>(find.byType(_Gast));
  }

  Future<void> tippeMit(
    WidgetTester tester,
    LogicalKeyboardKey zusatz,
    String kachel,
  ) async {
    await tester.sendKeyDownEvent(zusatz);
    await tester.tap(find.byKey(Key('kachel-$kachel')));
    await tester.sendKeyUpEvent(zusatz);
    await tester.pump();
  }

  group('Maus mit Zusatztasten', () {
    testWidgets('einfacher Klick ohne Auswahl öffnet weiterhin das Foto', (tester) async {
      final gast = await zeige(tester);
      await tester.tap(find.byKey(const Key('kachel-f3')));
      await tester.pump();
      expect(gast.geoeffnet, ['f3']);
      expect(gast.gewaehlt, isEmpty);
    });

    testWidgets('Command-Klick wählt aus, ohne zu öffnen', (tester) async {
      final gast = await zeige(tester);
      await tippeMit(tester, LogicalKeyboardKey.metaLeft, 'f3');
      expect(gast.gewaehlt, {'f3'});
      expect(gast.geoeffnet, isEmpty);
    });

    testWidgets('Umschalt-Klick zieht den Bereich vom Anker auf', (tester) async {
      final gast = await zeige(tester);
      await tippeMit(tester, LogicalKeyboardKey.metaLeft, 'f2');
      await tippeMit(tester, LogicalKeyboardKey.shiftLeft, 'f5');
      expect(gast.gewaehlt, {'f2', 'f3', 'f4', 'f5'});
    });

    testWidgets('Umschalt-Klick verliert eine Auswahl ausserhalb nicht', (tester) async {
      final gast = await zeige(tester);
      await tippeMit(tester, LogicalKeyboardKey.metaLeft, 'f7');
      await tippeMit(tester, LogicalKeyboardKey.metaLeft, 'f2');
      await tippeMit(tester, LogicalKeyboardKey.shiftLeft, 'f4');
      expect(gast.gewaehlt, {'f2', 'f3', 'f4', 'f7'});
    });

    testWidgets('Umschalt-Klick ohne Anker wählt nur diese eine', (tester) async {
      final gast = await zeige(tester);
      await tippeMit(tester, LogicalKeyboardKey.shiftLeft, 'f4');
      expect(gast.gewaehlt, {'f4'});
    });

    /// **Der Fehler aus dem Erstlauf-Bericht.** "Einzelauswahl
    /// funktioniert, Umschalt-Klick nur bis zu dem gewaehlten Foto,
    /// teilweise auch einige zusammenhaengende Fotos, aber nicht der
    /// ganze Bereich." Ausgewaehlt wird mit dem Finger ueber einen
    /// langen Druck - und der setzte den Anker nicht.
    testWidgets('nach dem Auswaehlen per langem Druck greift Umschalt',
        (tester) async {
      final gast = await zeige(tester);
      gast.rasterUmschalten('f2');
      await tester.pump();
      await tippeMit(tester, LogicalKeyboardKey.shiftLeft, 'f5');
      expect(gast.gewaehlt, {'f2', 'f3', 'f4', 'f5'},
          reason: 'der lange Druck hat keinen Anker hinterlassen');
    });

    testWidgets('ein alter Anker darf den langen Druck nicht ueberstimmen',
        (tester) async {
      // Genau die zweite Haelfte der Beobachtung: Es kamen "einige
      // zusammenhaengende Fotos", naemlich der Bereich ab einem laengst
      // vergessenen Klick - und nicht der, den man aufziehen wollte.
      final gast = await zeige(tester);
      await tippeMit(tester, LogicalKeyboardKey.metaLeft, 'f7');
      gast.rasterUmschalten('f2');
      await tester.pump();
      await tippeMit(tester, LogicalKeyboardKey.shiftLeft, 'f4');
      expect(gast.gewaehlt, {'f2', 'f3', 'f4', 'f7'});
    });

    testWidgets('auch das Abwaehlen setzt den Anker um', (tester) async {
      final gast = await zeige(tester);
      gast.rasterUmschalten('f2');
      gast.rasterUmschalten('f5');
      gast.rasterUmschalten('f5');
      await tester.pump();
      await tippeMit(tester, LogicalKeyboardKey.shiftLeft, 'f7');
      // Bezugspunkt ist die zuletzt angefasste Kachel (f5), nicht die
      // zuletzt hinzugefuegte (f2).
      expect(gast.gewaehlt, {'f2', 'f5', 'f6', 'f7'});
    });

    testWidgets('eine ganze Gruppe hinterlaesst ihren letzten Eintrag',
        (tester) async {
      final gast = await zeige(tester);
      gast.rasterGruppeUmschalten(['f1', 'f2', 'f3']);
      await tester.pump();
      await tippeMit(tester, LogicalKeyboardKey.shiftLeft, 'f5');
      expect(gast.gewaehlt, {'f1', 'f2', 'f3', 'f4', 'f5'});
    });

    testWidgets('das Abwaehlen einer Gruppe laesst den Anker stehen',
        (tester) async {
      final gast = await zeige(tester);
      gast.rasterGruppeUmschalten(['f1', 'f2']);
      gast.rasterGruppeUmschalten(['f1', 'f2']);
      await tester.pump();
      expect(gast.gewaehlt, isEmpty);
      // Der Anker steht noch auf f2 - vom Auswaehlen, nicht vom
      // Abwaehlen. Wer eine Gruppe wieder loslaesst, hat damit nicht
      // gesagt, wo der naechste Bereich beginnen soll.
      await tippeMit(tester, LogicalKeyboardKey.shiftLeft, 'f4');
      expect(gast.gewaehlt, {'f2', 'f3', 'f4'});
    });

    testWidgets('Command-Klick auf ein ausgewähltes wählt es wieder ab', (tester) async {
      final gast = await zeige(tester);
      await tippeMit(tester, LogicalKeyboardKey.metaLeft, 'f3');
      await tippeMit(tester, LogicalKeyboardKey.metaLeft, 'f3');
      expect(gast.gewaehlt, isEmpty);
    });
  });

  group('Tastatur', () {
    testWidgets('der erste Pfeil setzt den Zeiger auf das erste Foto', (tester) async {
      final gast = await zeige(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(gast.aktiveKachel, 'f1');
    });

    testWidgets('Pfeil nach rechts rückt eines weiter', (tester) async {
      final gast = await zeige(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(gast.aktiveKachel, 'f2');
    });

    testWidgets('Pfeil nach unten springt bei drei Spalten um drei', (tester) async {
      final gast = await zeige(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(gast.aktiveKachel, 'f4');
    });

    testWidgets('Umschalt und Pfeil zieht die Auswahl mit', (tester) async {
      final gast = await zeige(tester);
      await tippeMit(tester, LogicalKeyboardKey.metaLeft, 'f2');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(gast.gewaehlt, {'f2', 'f3', 'f4'});
    });

    testWidgets('Ziffer bewertet die aktive Kachel, wenn nichts ausgewählt ist', (tester) async {
      await zeige(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.pumpAndSettle();
      expect((await db.assetById('f1'))!.rating, 3);
      expect((await db.assetById('f2'))!.rating, 0);
    });

    testWidgets('Ziffer bewertet die ganze Auswahl, nicht nur die aktive Kachel', (tester) async {
      await zeige(tester);
      await tippeMit(tester, LogicalKeyboardKey.metaLeft, 'f2');
      await tippeMit(tester, LogicalKeyboardKey.shiftLeft, 'f4');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.pumpAndSettle();
      expect((await db.assetById('f2'))!.rating, 5);
      expect((await db.assetById('f3'))!.rating, 5);
      expect((await db.assetById('f4'))!.rating, 5);
      expect((await db.assetById('f1'))!.rating, 0);
    });

    testWidgets('Taste 6 setzt Rot, dieselbe Taste nimmt es wieder weg', (tester) async {
      await zeige(tester);
      await tippeMit(tester, LogicalKeyboardKey.metaLeft, 'f1');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit6);
      await tester.pumpAndSettle();
      expect((await db.assetById('f1'))!.colorLabel, 'red');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit6);
      await tester.pumpAndSettle();
      expect((await db.assetById('f1'))!.colorLabel, isNull);
    });

    testWidgets('F schaltet den Favoriten um, hin und zurück', (tester) async {
      await zeige(tester);
      await tippeMit(tester, LogicalKeyboardKey.metaLeft, 'f1');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();
      expect((await db.assetById('f1'))!.isFavorite, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pumpAndSettle();
      expect((await db.assetById('f1'))!.isFavorite, isFalse);
    });

    testWidgets('Escape leert die Auswahl', (tester) async {
      final gast = await zeige(tester);
      await tippeMit(tester, LogicalKeyboardKey.metaLeft, 'f1');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(gast.gewaehlt, isEmpty);
    });

    testWidgets('Eingabetaste öffnet die aktive Kachel', (tester) async {
      final gast = await zeige(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(gast.geoeffnet, ['f1']);
    });

    testWidgets('Command und Ziffer bleibt den Fensterkürzeln überlassen', (tester) async {
      // Die Hülle wechselt mit ⌘1…⌘9 den Bereich. Fingen wir die Taste hier
      // ab, käme der Wechsel nie an – und es stünde eine Bewertung da, die
      // niemand vergeben wollte.
      await zeige(tester);
      await tippeMit(tester, LogicalKeyboardKey.metaLeft, 'f1');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect((await db.assetById('f1'))!.rating, 0);
    });

    testWidgets('im Textfeld getippte Ziffern bewerten nichts', (tester) async {
      // Der Befund, um den es geht: Der Mixin sitzt als Focus über dem ganzen
      // Bildschirm. Ohne Prüfung auf ein aktives Textfeld hiesse „2026" in
      // der Suche: vier Bewertungen vergeben.
      await zeige(tester, mitTextfeld: true);
      await tippeMit(tester, LogicalKeyboardKey.metaLeft, 'f1');
      await tester.tap(find.byKey(const Key('suchfeld')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.pumpAndSettle();
      expect((await db.assetById('f1'))!.rating, 0);
    });
  });

  group('unter der Hülle der App', () {
    /// Wie im Programm: `HomeShell` legt einen eigenen `Focus` mit
    /// `autofocus` über den ganzen Bildschirm, damit ⌘1…⌘0 und „?"
    /// ankommen. Bis zur Prüfrunde vom 04.09.2026 gewann dieser äussere
    /// Knoten den Fokus und das Raster ging leer aus – **im Programm tat
    /// keine einzige Rastertaste etwas**, obwohl jeder Fall hier oben grün
    /// war. Genau diese Verschachtelung fehlte im Prüfstand.
    Future<_GastState> zeigeUnterHuelle(
      WidgetTester tester, {
      List<String>? huellenTasten,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              huellenTasten?.add(event.logicalKey.keyLabel);
            }
            return KeyEventResult.ignored;
          },
          child: Scaffold(body: _Gast(db: db, assets: assets)),
        ),
      ));
      await tester.pump();
      return tester.state<_GastState>(find.byType(_Gast));
    }

    testWidgets('die Ziffer bewertet auch unter dem Fokus der Hülle',
        (tester) async {
      await zeigeUnterHuelle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.pumpAndSettle();
      expect((await db.assetById('f1'))!.rating, 3);
    });

    testWidgets('die Pfeiltaste setzt den Zeiger auch dort', (tester) async {
      final gast = await zeigeUnterHuelle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(gast.aktiveKachel, 'f1');
    });

    testWidgets('das Nummernfeld bewertet wie die Ziffernreihe',
        (tester) async {
      // Gemeldet als „Nummernfeld nur ein Piep": Die Zuordnung kannte nur
      // digit0…digit5, nicht numpad0…numpad5.
      await zeigeUnterHuelle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad4);
      await tester.pumpAndSettle();
      expect((await db.assetById('f1'))!.rating, 4);
    });

    testWidgets('das Nummernfeld setzt auch die Farbmarke', (tester) async {
      await zeigeUnterHuelle(tester);
      await tippeMit(tester, LogicalKeyboardKey.metaLeft, 'f1');
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad7);
      await tester.pumpAndSettle();
      expect((await db.assetById('f1'))!.colorLabel, 'yellow');
    });

    testWidgets('die Hülle sieht ⌘2 weiterhin', (tester) async {
      // Die Gegenprobe zur Reparatur: Das Raster nimmt den Fokus, aber die
      // Bereichskürzel dürfen darüber nicht verlorengehen – Tasten wandern
      // vom Raster aus nach oben weiter.
      final gesehen = <String>[];
      await zeigeUnterHuelle(tester, huellenTasten: gesehen);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(gesehen, contains('2'));
    });
  });
}
