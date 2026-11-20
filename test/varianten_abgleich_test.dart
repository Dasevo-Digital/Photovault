import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/abgleich/protokoll.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/entwicklungsvariante.dart';

class _Kopie extends AppDatabase {
  _Kopie(super.executor);
}

void main() {
  test(
    'Varianten, Zuschnitt und private Entfernung wandern vollständig zum zweiten Gerät',
    () async {
      final db = AppDatabase(NativeDatabase.memory()),
          kopie = _Kopie(NativeDatabase.memory());
      addTearDown(db.close);
      addTearDown(kopie.close);
      final server = Protokoll(db), geraet = Protokoll(kopie);
      await server.richteEin(mitschreiben: -1);
      await geraet.richteEin(mitschreiben: 0);
      await db.insertAsset(
        AssetsCompanion.insert(
          id: 'foto',
          originalFileName: 'test.jpg',
          relativePath: 'originals/test.jpg',
          checksum: 'a' * 64,
          type: 'IMAGE',
          fileCreatedAt: DateTime(2024),
          importedAt: DateTime(2026),
        ),
      );
      await db.saveDevelopResult(
        'foto',
        settings: DevelopSettingsCompanion.insert(
          assetId: 'foto',
          cropJson: const Value('{"l":0,"o":0,"b":0.5,"h":1,"d":1}'),
          updatedAt: DateTime(2026),
        ),
        developedRelativePath: 'developed/basis.jpg',
      );
      final s = Entwicklungsstand(
        'a' * 64,
        (await db.developSettingsForAsset('foto'))!,
        [],
        {'developed/var-test.jpg': 'b' * 64},
      );
      final v = DevelopVariantData(
        id: 'test-variante',
        assetId: 'foto',
        name: 'Druck',
        stateJson: s.encode(),
        previewRelativePath: 'developed/var-test.jpg',
        updatedAt: DateTime(2026),
      );
      await db.fuehreAus(EntwicklungsvarianteSpeichern(v));
      await db.fuehreAus(
        const EntwicklungsvarianteAktivieren('foto', 'test-variante'),
      );
      var stand = 0;
      Future<void> abgleichen() async {
        while (true) {
          final neu = await server.seit(stand, anzahl: 3);
          final zeilen = [
            for (final z in neu.zeilen)
              Zeilenstand.ausJson(
                (jsonDecode(jsonEncode(z.alsJson())) as Map)
                    .cast<String, Object?>(),
              ),
          ];
          await kopie.transaction(() => geraet.wendeAn(zeilen));
          stand = neu.bis;
          if (!neu.mehr) break;
        }
      }

      await abgleichen();
      expect((await kopie.variantenFuer('foto')).single.name, 'Druck');
      expect(
        (await kopie.developSettingsForAsset('foto'))!.cropJson,
        s.einstellungen.cropJson,
      );
      expect(
        (await kopie.assetById('foto'))!.developedRelativePath,
        v.previewRelativePath,
      );
      expect(await kopie.varianteVerwendetDatei(v.previewRelativePath), isTrue);
      await db.hidePrivateMetadata('foto');
      await abgleichen();
      expect(await kopie.variantenFuer('foto'), isEmpty);
      expect(
        (await kopie.select(kopie.developVariantFiles).get()).every(
          (f) => f.sha256.isEmpty,
        ),
        isTrue,
      );
    },
  );
}
