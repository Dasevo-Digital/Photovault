import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:kern/auswertung/fortschritt.dart';
import 'package:kern/services/backup_auswahl.dart';
import 'package:kern/services/import_plan.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'library_location.dart';

enum ImportErgebnis { offen, importiert, kammer, duplikat, ausgelassen, fehler }

class Quittungsdatei {
  const Quittungsdatei(this.name, this.pruefsumme, this.ergebnis);
  final String name;
  final String? pruefsumme;
  final ImportErgebnis ergebnis;

  bool get pruefbar =>
      pruefsumme != null &&
      (ergebnis == ImportErgebnis.importiert ||
          ergebnis == ImportErgebnis.duplikat ||
          ergebnis == ImportErgebnis.kammer);

  Map<String, Object?> alsJson() => {
    'name': name,
    'sha256': pruefsumme,
    'ergebnis': ergebnis.name,
  };

  factory Quittungsdatei.ausJson(Object? wert) {
    final json = wert as Map;
    return Quittungsdatei(
      json['name'] as String,
      json['sha256'] as String?,
      ImportErgebnis.values.byName(json['ergebnis'] as String),
    );
  }
}

class QuittungKopf {
  const QuittungKopf(this.id, this.am, this.anzahl);
  final String id;
  final DateTime am;
  final int anzahl;
}

enum Kopienbefund { bestaetigt, fehlt, unlesbar }

class Quittungspruefung {
  const Quittungspruefung(this.am, this.ziel, this.befunde);
  final DateTime am;
  final String ziel;
  final Map<String, Kopienbefund> befunde;
}

class Importquittung {
  const Importquittung(this.kopf, this.dateien, this.fertig, this.pruefung);
  final QuittungKopf kopf;
  final List<Quittungsdatei> dateien;
  final bool fertig;
  final Quittungspruefung? pruefung;
  Importquittung mitVerdecktenDateinamen(Set<String> gesperrt) =>
      Importquittung(
        kopf,
        [
          for (final datei in dateien)
            if (gesperrt.contains(datei.pruefsumme))
              Quittungsdatei('', null, datei.ergebnis)
            else
              datei,
        ],
        fertig,
        pruefung,
      );

  Set<String> get pruefsummen => {
    for (final a in dateien)
      if (a.pruefbar) a.pruefsumme!,
  };
}

class QuittungSchreibfehler implements Exception {
  const QuittungSchreibfehler();
}

/// Lokale Importhistorie je Bibliothek. Nur Dateinamen und Prüfsummen
/// werden gespeichert, keine Quellpfade, Serverantworten oder Passphrasen.
class Importquittungen {
  Importquittungen(Directory bibliothek)
    : _ordner = Directory(p.join(bibliothek.path, 'importquittungen'));
  final Directory _ordner;
  static final _kennung = RegExp(r'^[a-f0-9-]{36}$');

  /// Der lokale Datenordner bleibt auch dann auf diesem Rechner, wenn die
  /// Medienbibliothek auf einem anderen Laufwerk liegt.
  static Future<Importquittungen> fuer(Directory bibliothek) async {
    final daten = await LibraryLocation.datenordner();
    final pfad = await bibliothek.resolveSymbolicLinks();
    final kennung = sha256.convert(utf8.encode(p.normalize(pfad))).toString();
    return Importquittungen(
      Directory(p.join(daten.path, 'bibliotheksverlauf', kennung)),
    );
  }

  File _datei(String id, String endung) {
    if (!_kennung.hasMatch(id)) throw const FormatException('pv_quittung_id');
    return File(p.join(_ordner.path, '$id.$endung'));
  }

  /// Das Journal erhält einen Stand vor dem ersten Import und nach jedem
  /// abgeschlossenen Eintrag. Ein unterbrochener Lauf bleibt als offen sichtbar.
  Stream<ImportProgress> protokolliere(
    ImportPlan plan,
    Stream<ImportProgress> fortschritt, {
    void Function(String id)? begonnen,
  }) async* {
    final id = const Uuid().v4();
    final am = DateTime.now().toUtc();
    final zeilen = [...plan.eintraege, ...plan.ausgelassen];
    final positionen = {
      for (var i = 0; i < plan.eintraege.length; i++) plan.eintraege[i].pfad: i,
    };
    final vorher = [
      for (var i = 0; i < zeilen.length; i++)
        Quittungsdatei(
          p.basename(zeilen[i].pfad),
          zeilen[i].angaben?.pruefsumme,
          i < plan.eintraege.length
              ? ImportErgebnis.offen
              : switch (zeilen[i].art) {
                  ImportPlanArt.vorhanden ||
                  ImportPlanArt.doppelt => ImportErgebnis.duplikat,
                  ImportPlanArt.fehler => ImportErgebnis.fehler,
                  _ => ImportErgebnis.ausgelassen,
                },
        ),
    ];
    final RandomAccessFile schreiber;
    try {
      await _ordner.create(recursive: true);
      schreiber = await _datei(id, 'jsonl').open(mode: FileMode.write);
    } on FileSystemException {
      throw const QuittungSchreibfehler();
    }
    Future<void> zeile(Object json) async {
      try {
        await schreiber.writeString('${jsonEncode(json)}\n');
        await schreiber.flush();
      } on FileSystemException {
        throw const QuittungSchreibfehler();
      }
    }

    try {
      await zeile({
        'v': 1,
        'am': am.toIso8601String(),
        'anzahl': vorher.length,
      });
      await zeile([for (final datei in vorher) datei.alsJson()]);
      begonnen?.call(id);
      await for (final stand in fortschritt) {
        if (positionen[stand.pfad] case final int n) {
          final ergebnis = switch (stand) {
            ImportProgress(gescheitert: true) => ImportErgebnis.fehler,
            ImportProgress(duplikat: true) => ImportErgebnis.duplikat,
            ImportProgress(kammer: true) => ImportErgebnis.kammer,
            ImportProgress(assetId: final String _) =>
              ImportErgebnis.importiert,
            _ => ImportErgebnis.offen,
          };
          await zeile({'n': n, 'ergebnis': ergebnis.name});
        }
        yield stand;
      }
      await zeile({'fertig': true});
    } finally {
      await schreiber.close();
    }
  }

  Future<List<QuittungKopf>> liste() async {
    if (!await _ordner.exists()) return [];
    final belege = <QuittungKopf>[];
    await for (final file in _ordner.list(followLinks: false)) {
      if (file is! File || p.extension(file.path) != '.jsonl') continue;
      try {
        final j =
            jsonDecode(
                  await file
                      .openRead()
                      .transform(utf8.decoder)
                      .transform(const LineSplitter())
                      .first,
                )
                as Map;
        belege.add(_kopf(p.basenameWithoutExtension(file.path), j));
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      } on StateError {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    return belege..sort((a, b) => b.am.compareTo(a.am));
  }

  static QuittungKopf _kopf(String id, Map j) {
    if (j['v'] != 1) throw const FormatException('pv_quittung_format');
    return QuittungKopf(
      id,
      DateTime.parse(j['am'] as String).toLocal(),
      j['anzahl'] as int,
    );
  }

  Future<Importquittung> lies(String id) async {
    final zeilen = await _datei(id, 'jsonl').readAsLines();
    final j = jsonDecode(zeilen.first) as Map;
    final kopf = _kopf(id, j);
    final dateien = (jsonDecode(zeilen[1]) as List)
        .map(Quittungsdatei.ausJson)
        .toList();
    if (dateien.length != kopf.anzahl) {
      throw const FormatException('pv_quittung_format');
    }
    var fertig = false;
    for (var i = 2; i < zeilen.length; i++) {
      final Map ereignis;
      try {
        ereignis = jsonDecode(zeilen[i]) as Map;
      } on FormatException {
        // Stromausfall während des letzten Schreibens: belegte Ergebnisse
        // bleiben gültig, der nicht geschriebene Rest bleibt offen.
        if (i + 1 != zeilen.length) rethrow;
        break;
      }
      if (ereignis['fertig'] == true) {
        fertig = !dateien.any((a) => a.ergebnis == ImportErgebnis.offen);
        break;
      }
      final n = ereignis['n'] as int;
      final a = dateien[n];
      dateien[n] = Quittungsdatei(
        a.name,
        a.pruefsumme,
        ImportErgebnis.values.byName(ereignis['ergebnis'] as String),
      );
    }
    final pruefdatei = _datei(id, 'pruefung');
    Quittungspruefung? pruefung;
    if (await pruefdatei.exists()) {
      final ergebnis = jsonDecode(await pruefdatei.readAsString()) as Map;
      pruefung = Quittungspruefung(
        DateTime.parse(ergebnis['am'] as String).toLocal(),
        ergebnis['ziel'] as String,
        (ergebnis['befunde'] as Map<String, dynamic>).map(
          (id, wert) =>
              MapEntry(id, Kopienbefund.values.byName(wert as String)),
        ),
      );
    }
    return Importquittung(kopf, List.unmodifiable(dateien), fertig, pruefung);
  }

  Future<void> pruefeKopien(
    Importquittung beleg,
    BackupAuswahl sicherung,
    String ziel, {
    void Function(int erledigt, int gesamt)? fortschritt,
  }) async {
    final hashes = beleg.pruefsummen;
    final befunde = <String, Kopienbefund>{};
    for (final hash in hashes) {
      try {
        befunde[hash] = await sicherung.pruefeOriginal(hash)
            ? Kopienbefund.bestaetigt
            : Kopienbefund.fehlt;
      } on Object {
        befunde[hash] = Kopienbefund.unlesbar;
      }
      fortschritt?.call(befunde.length, hashes.length);
    }
    await _speicherePruefung(
      beleg.kopf.id,
      Quittungspruefung(DateTime.now(), ziel, befunde),
    );
  }

  Future<void> _speicherePruefung(String id, Quittungspruefung pruefung) async {
    final ziel = _datei(id, 'pruefung');
    final teil = File('${ziel.path}.${const Uuid().v4()}.neu');
    try {
      await teil.writeAsString(
        jsonEncode({
          'am': pruefung.am.toUtc().toIso8601String(),
          'ziel': pruefung.ziel,
          'befunde': pruefung.befunde.map(
            (id, wert) => MapEntry(id, wert.name),
          ),
        }),
        flush: true,
      );
      await teil.rename(ziel.path);
    } finally {
      if (await teil.exists()) await teil.delete();
    }
  }
}
