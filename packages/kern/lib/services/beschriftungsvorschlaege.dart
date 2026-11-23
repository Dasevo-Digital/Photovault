import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'reverse_geocoder.dart';

class Beschriftungsstand {
  Beschriftungsstand(this.aufnahme, this.gesichter, this.personen);
  final AssetData aufnahme;
  final List<FaceData> gesichter;
  final List<PersonData> personen;
  late final String stand = Beschriftungsdienst.berechneStand(
    aufnahme,
    gesichter,
    personen,
  );
}

/// Speichern und Entscheiden erfolgen in derselben Bibliotheksdatenbank.
class Beschriftungsdienst {
  const Beschriftungsdienst(this.db, {this.ortsverzeichnis});
  final AppDatabase db;

  /// Löst einen angenommenen Ortsnamen zu Koordinaten, Land und Region auf
  /// ([_ortAusVorschlag]); ohne Verzeichnis bleibt es beim Namen.
  final ReverseGeocoder? ortsverzeichnis;

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
    final daten = await staende([id]);
    if (!daten.containsKey(id)) {
      throw const FormatException('pv_beschriftung_aufnahme');
    }
    return daten[id]!.stand;
  }

  /// Eine begrenzte Vorschlagsseite benötigt je eine Abfrage für Fotos,
  /// Gesichter und zugeordnete Personen, statt Abfragen pro Vorschlag.
  Future<Map<String, Beschriftungsstand>> staende(List<String> ids) async {
    if (ids.isEmpty) return {};
    if (ids.length > 100) throw ArgumentError('pv_beschriftung_umfang');
    final assets = await db.assetsByIds(ids);
    final faces =
        await (db.select(db.faces)
              ..where((t) => t.assetId.isIn(ids))
              ..orderBy([(t) => OrderingTerm.asc(t.id)]))
            .get();
    final people = await (db.select(db.people).join([
      innerJoin(db.faces, db.faces.personId.equalsExp(db.people.id)),
    ])..where(db.faces.assetId.isIn(ids))).get();
    final nachAufnahme = <String, List<FaceData>>{};
    for (final f in faces) {
      nachAufnahme.putIfAbsent(f.assetId, () => []).add(f);
    }
    final personenNachAufnahme = <String, Map<String, PersonData>>{};
    for (final row in people) {
      final f = row.readTable(db.faces), person = row.readTable(db.people);
      personenNachAufnahme.putIfAbsent(f.assetId, () => {})[person.id] = person;
    }
    return {
      for (final a in assets)
        if (!a.isLocked && !a.isTrashed)
          a.id: Beschriftungsstand(
            a,
            nachAufnahme[a.id] ?? [],
            (personenNachAufnahme[a.id]?.values.toList() ?? [])
              ..sort((a, b) => a.id.compareTo(b.id)),
          ),
    };
  }

  static String berechneStand(
    AssetData a,
    List<FaceData> gesichter,
    List<PersonData> personen,
  ) {
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

  /// Was „Annehmen“ eines Ortes setzt (#484).
  ///
  /// Bisher nur den Namen als Stadt, zu den alten Koordinaten. Bei einem
  /// Foto ohne GPS zeigten die Angaben danach keinen Ort, und auf der Karte
  /// fehlte er; bei einem mit GPS widersprachen Name und Koordinaten, und
  /// Land und Region waren still gelöscht.
  ///
  /// Jetzt wie die Ortssuche: Kennt das Ortsverzeichnis den Namen – bei
  /// gleichnamigen der nächste zum bisherigen Ort –, gelten seine
  /// Koordinaten und Namen. Sonst kommt nur der Name dazu; Koordinaten,
  /// Land und Region bleiben, wie sie waren.
  OrtSetzen _ortAusVorschlag(AssetData a, String name) {
    final geo = ortsverzeichnis;
    final treffer = geo?.sucheOrt(
      name,
      naheBreite: a.latitude,
      naheLaenge: a.longitude,
    );
    if (geo != null && treffer != null) {
      final namen = geo.lookup(treffer.breite, treffer.laenge);
      return OrtSetzen(
        [a.id],
        treffer.breite,
        treffer.laenge,
        land: namen?.country,
        region: namen?.state,
        stadt: namen?.city ?? treffer.name,
      );
    }
    return OrtSetzen(
      [a.id],
      a.latitude,
      a.longitude,
      land: a.locationCountry,
      region: a.locationState,
      stadt: name,
    );
  }

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
          await db.fuehreAus(_ortAusVorschlag(a, v.wert));
        case 'jahr':
          await db.fuehreAus(JahrSchaetzen(v.assetId, int.parse(v.wert)));
        case 'person':
          final gesichter = await db.facesForAsset(v.assetId);
          if (!gesichter.any((f) => f.id == v.gesichtId && !f.isIgnored)) {
            throw const FormatException('pv_beschriftung_gesicht');
          }
          final namensgleich =
              await (db.select(db.people)
                    ..where(
                      (p) =>
                          p.name.equals(v.wert) &
                          (personId == null
                              ? const Constant(true)
                              : p.id.equals(personId)),
                    )
                    ..limit(personId == null ? 2 : 1))
                  .get();
          var zielId = personId;
          if (zielId != null && namensgleich.isEmpty) {
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
