import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';

/// Speichern und Entscheiden erfolgen in derselben Bibliotheksdatenbank.
class Beschriftungsdienst {
  const Beschriftungsdienst(this.db);
  final AppDatabase db;

  Future<void> _imAlbum(String album, String asset) async {
    final t = db.assets;
    final row =
        await (db.select(t)..where(
              (t) => db.sichtbareAufnahmeImAlbum(album) & t.id.equals(asset),
            ))
            .getSingleOrNull();
    if (row == null) throw const FormatException('pv_beschriftung_aufnahme');
  }

  Future<String> stand(String id) async {
    final a = await db.assetById(id);
    if (a == null || a.isLocked || a.isTrashed) {
      throw const FormatException('pv_beschriftung_aufnahme');
    }
    final gesichter = await db.facesForAsset(id);
    gesichter.sort((a, b) => a.id.compareTo(b.id));
    final personen = await db.peopleForAsset(id);
    personen.sort((a, b) => a.id.compareTo(b.id));
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              a.fileCreatedAt.toIso8601String(),
              a.datumGeschaetzt,
              a.locationCity,
              a.latitude,
              a.longitude,
              for (final f in gesichter)
                [f.id, f.personId, f.isIgnored, f.boxX, f.boxY, f.boxW, f.boxH],
              for (final p in personen) [p.id, p.name],
            ]),
          ),
        )
        .toString();
  }

  Future<String> vorschlagen({
    required String id,
    required String album,
    required String von,
    required String name,
    required String art,
    required String wert,
    String? gesicht,
  }) => db.transaction(() async {
    final text = wert.trim();
    if (!{'person', 'ort', 'jahr'}.contains(art) ||
        text.isEmpty ||
        text.length > 200 ||
        (art == 'jahr' &&
            (int.tryParse(text) == null ||
                int.parse(text) < 1 ||
                int.parse(text) > 9999))) {
      throw const FormatException('pv_beschriftung_wert');
    }
    await stand(id);
    await _imAlbum(album, id);
    if (art == 'person') {
      final f = (await db.facesForAsset(id)).where((f) => f.id == gesicht);
      if (f.length != 1 || f.single.isIgnored) {
        throw const FormatException('pv_beschriftung_gesicht');
      }
    } else if (gesicht != null) {
      throw const FormatException('pv_beschriftung_gesicht');
    }
    final anzahl = db.beschriftungsvorschlaege.id.count();
    final row =
        await (db.selectOnly(db.beschriftungsvorschlaege)
              ..addColumns([anzahl])
              ..where(
                db.beschriftungsvorschlaege.albumId.equals(album) &
                    db.beschriftungsvorschlaege.zustand.equals('offen'),
              ))
            .getSingle();
    if ((row.read(anzahl) ?? 0) >= 1000) {
      throw const FormatException('pv_beschriftung_umfang');
    }
    final kennung = const Uuid().v4();
    await db
        .into(db.beschriftungsvorschlaege)
        .insert(
          BeschriftungsvorschlaegeCompanion.insert(
            id: kennung,
            assetId: id,
            albumId: album,
            von: von,
            vonName: name,
            art: art,
            wert: text,
            gesichtId: Value(gesicht),
            angelegt: DateTime.now().toUtc(),
          ),
        );
    return kennung;
  });

  Future<void> entscheiden(
    String id, {
    required bool annehmen,
    required String erwartet,
    String? personId,
  }) => db.transaction(() async {
    final t = db.beschriftungsvorschlaege;
    final v = await (db.select(t)..where((t) => t.id.equals(id))).getSingle();
    final ziel = annehmen ? 'angenommen' : 'abgelehnt';
    await _imAlbum(v.albumId, v.assetId);
    await stand(v.assetId);
    if (v.zustand == ziel) return;
    if (v.zustand != 'offen') {
      throw const FormatException('pv_beschriftung_entschieden');
    }
    if (await stand(v.assetId) != erwartet) {
      throw const FormatException('pv_beschriftung_geaendert');
    }
    if (annehmen) {
      switch (v.art) {
        case 'ort':
          final a = (await db.assetById(v.assetId))!;
          await db.fuehreAus(
            OrtSetzen([a.id], a.latitude, a.longitude, stadt: v.wert),
          );
        case 'jahr':
          await db.fuehreAus(JahrSchaetzen(v.assetId, int.parse(v.wert)));
        case 'person':
          final gesichter = await db.facesForAsset(v.assetId);
          if (!gesichter.any((f) => f.id == v.gesichtId && !f.isIgnored)) {
            throw const FormatException('pv_beschriftung_gesicht');
          }
          final personen = await db.allePersonen();
          final namensgleich = personen.where((p) => p.name == v.wert).toList();
          var zielId = personId;
          if (zielId != null &&
              !personen.any((p) => p.id == zielId && p.name == v.wert)) {
            throw const FormatException('pv_beschriftung_person');
          }
          if (zielId == null) {
            if (namensgleich.length > 1) {
              throw const FormatException('pv_beschriftung_mehrdeutig');
            }
            zielId = namensgleich.firstOrNull?.id;
          }
          if (zielId == null) {
            zielId = const Uuid().v5(
              Namespace.url.value,
              'photovault-vorschlag/${v.id}',
            );
            await db.fuehreAus(PersonAnlegen(zielId, v.wert));
          }
          await db.fuehreAus(GesichterZuordnen([v.gesichtId!], zielId));
        default:
          throw const FormatException('pv_beschriftung_art');
      }
    }
    await (db.update(t)..where((r) => r.id.equals(id))).write(
      BeschriftungsvorschlaegeCompanion(
        zustand: Value(ziel),
        entschieden: Value(DateTime.now().toUtc()),
      ),
    );
  });
}
