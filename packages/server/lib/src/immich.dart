/// Alben, Favoriten, Personennamen, Beschreibungen und Archivstatus aus
/// Immich übernehmen (#305).
///
/// **Immich wird nur gelesen.** Der Schlüssel liegt nur im Speicher, solange
/// die Prüfung läuft; gespeichert wird er nirgends.
///
/// **Erst prüfen, dann übernehmen.** Die Prüfung zeigt, was sich ändern
/// würde. Übernommen wird über dieselben Befehle wie von Hand, die Geräte
/// bekommen es also über den gewöhnlichen Abgleich. Was in Photo Vault schon
/// steht, bleibt: Eine vorhandene Beschreibung wird nie ersetzt, ein Favorit
/// nie entfernt, ein zugeordnetes Gesicht nie umgehängt, ein Name nie
/// geändert. Abweichungen stehen im Bericht. Ein zweiter Lauf ändert nichts
/// mehr.
///
/// **Welche Aufnahme welche ist.** Immich nennt die SHA-1 des Originals, die
/// Bibliothek kennt die SHA-256; die SHA-1 wird deshalb einmal aus den
/// Originalen gerechnet und merkt sich je SHA-256 in `immich-sha1.json`.
/// Beim Abgleich am 27.10. waren 335 Aufnahmen dasselbe Bild mit anderen
/// Metadaten. Für sie gilt: gleicher Name, gleiche Art, höchstens zwei
/// Sekunden Abstand, und genau ein Kandidat.
///
/// Der Bericht ist damit auch der Dateiabgleich vor dem Abschalten: Er nennt,
/// was in Immich liegt und in der Bibliothek fehlt.
///
/// **Gesichter.** Die Personen eines Fotos stehen in der Suche, ihre Rahmen
/// nur unter `/faces`; gefragt wird nur für Fotos mit benannten Personen. Ein
/// Rahmen gehört zu dem Gesicht der Bibliothek, das ihn am stärksten
/// überlappt.
///
/// **Archiv.** Was in Immich archiviert ist, kommt ins Archiv der Bibliothek
/// (#304): aus der Zeitleiste, in Alben und Suche weiter da.
///
/// **Nur eigene Aufnahmen** (#362). Die Suche von Immich liefert auch die
/// Fotos von Partnern, die in der eigenen Zeitleiste stehen. Sie gehören
/// nicht zum Abgleich; dafür braucht der Schlüssel `user.read`.
///
/// **Kameratexte.** Immich füllt die Beschreibung auch aus der Datei, und
/// viele Kameras schreiben dort „OLYMPUS DIGITAL CAMERA“ oder „SONY DSC“
/// hinein. Was so in der Datei steht oder so aussieht, wird nicht
/// übernommen – die Bibliothek liest diese Texte beim Import auch nicht.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show TypedResult;
import 'package:exif/exif.dart' show readExifFromFile;
import 'package:http/http.dart' as http;
import 'package:kern/db/database.dart';
import 'package:kern/protokoll.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'aussensicherung.dart' show imEigenenNetz;
import 'bibliothek.dart';
import 'bibliotheken.dart';

/// Eine Meldung, die so in der Oberfläche stehen kann.
class Immichfehler implements Exception {
  const Immichfehler(this.text);
  final String text;

  @override
  String toString() => text;
}

class ImmichPerson {
  const ImmichPerson(this.id, this.name, this.geburt, this.versteckt);

  factory ImmichPerson.aus(Map<String, Object?> j) => ImmichPerson(
    '${j['id']}',
    '${j['name'] ?? ''}'.trim(),
    j['birthDate'] is String ? DateTime.tryParse('${j['birthDate']}') : null,
    j['isHidden'] == true,
  );

  final String id;
  final String name;
  final DateTime? geburt;
  final bool versteckt;

  /// Nur benannte, nicht versteckte Personen werden übernommen.
  bool get zaehlt => name.isNotEmpty && !versteckt;
}

class ImmichAufnahme {
  const ImmichAufnahme({
    required this.id,
    required this.sha1,
    required this.name,
    required this.art,
    required this.zeit,
    required this.favorit,
    required this.archiviert,
    required this.beschreibung,
    required this.personen,
    this.besitzer,
    this.groesse,
  });

  /// `null` für alles, was nicht übernommen wird: Papierkorb, Gesperrtes
  /// und die Videohälften von Live Photos.
  static ImmichAufnahme? aus(Map<String, Object?> j) {
    final sichtbarkeit =
        j['visibility'] as String? ??
        (j['isArchived'] == true ? 'archive' : 'timeline');
    if (j['isTrashed'] == true ||
        (sichtbarkeit != 'timeline' && sichtbarkeit != 'archive')) {
      return null;
    }
    final zeit = DateTime.tryParse('${j['fileCreatedAt']}');
    final sha1 = j['checksum'];
    if (zeit == null || sha1 is! String) return null;
    final exif = j['exifInfo'];
    final text = exif is Map ? exif['description'] : null;
    return ImmichAufnahme(
      id: '${j['id']}',
      sha1: sha1,
      name: '${j['originalFileName'] ?? ''}',
      art: '${j['type'] ?? ''}',
      zeit: zeit,
      favorit: j['isFavorite'] == true,
      archiviert: sichtbarkeit == 'archive',
      beschreibung: text is String ? text.trim() : '',
      personen: [
        for (final x in (j['people'] as List?) ?? const [])
          ImmichPerson.aus((x as Map).cast<String, Object?>()),
      ],
      besitzer: j['ownerId'] as String?,
      groesse: exif is Map ? (exif['fileSizeInByte'] as num?)?.toInt() : null,
    );
  }

  final String id;
  final String sha1;
  final String name;

  /// `IMAGE` oder `VIDEO`, wie in der Bibliothek.
  final String art;
  final DateTime zeit;
  final bool favorit;
  final bool archiviert;
  final String beschreibung;
  final List<ImmichPerson> personen;

  /// Das Konto, dem die Aufnahme in Immich gehört.
  final String? besitzer;

  /// Die Grösse des Originals in Bytes, wenn Immich sie kennt.
  final int? groesse;
}

class ImmichAlbum {
  const ImmichAlbum(this.id, this.name, this.angelegt, this.aufnahmen);
  final String id;
  final String name;
  final DateTime angelegt;

  /// Die Kennungen in Immich.
  final List<String> aufnahmen;
}

/// Ein Gesicht: ein Rahmen, relativ zum Bild, und seine Person.
class ImmichGesicht {
  const ImmichGesicht(this.personId, this.x, this.y, this.b, this.h);
  final String personId;
  final double x, y, b, h;
}

/// Die Lesezugriffe auf Immich.
class Immichverbindung {
  Immichverbindung(
    this.basis,
    this._schluessel, {
    http.Client? netz,
    this.frist = const Duration(seconds: 60),
    this.warten = const Duration(seconds: 2),
  }) : _netz = netz ?? http.Client();

  /// Die Adresse von `…/api/`.
  final Uri basis;
  final String _schluessel;
  final http.Client _netz;
  final Duration frist;
  final Duration warten;

  /// Prüft, was ein Mensch eingetragen hat, und ergänzt `/api/`.
  static Uri basisAus(String text) {
    final a = Uri.tryParse(text.trim());
    if (a == null || !a.hasAuthority || !{'http', 'https'}.contains(a.scheme)) {
      throw ArgumentError('Die Adresse muss mit https:// beginnen.');
    }
    if (a.scheme == 'http' && !imEigenenNetz(a.host)) {
      // Der Schlüssel ginge sonst im Klartext durchs Netz.
      throw ArgumentError(
        'Unverschlüsseltes http geht nur im eigenen Netz. Bitte https nutzen.',
      );
    }
    var pfad = a.path.replaceAll(RegExp(r'/+$'), '');
    if (pfad.endsWith('/api')) pfad = pfad.substring(0, pfad.length - 4);
    return Uri(
      scheme: a.scheme,
      host: a.host,
      port: a.hasPort ? a.port : null,
      path: '$pfad/api/',
    );
  }

  void schliesse() => _netz.close();

  Future<Object?> _frage(
    String methode,
    String pfad, {
    Map<String, String>? abfrage,
    Object? inhalt,
  }) async {
    final ziel = basis.replace(
      path: '${basis.path}$pfad',
      queryParameters: abfrage,
    );
    for (var versuch = 1; ; versuch++) {
      Object grund;
      try {
        // Nicht umleiten lassen: Der Schlüssel ginge sonst an die neue
        // Adresse mit.
        final anfrage = http.Request(methode, ziel)
          ..followRedirects = false
          ..headers['x-api-key'] = _schluessel
          ..headers['accept'] = 'application/json';
        if (inhalt != null) {
          anfrage
            ..headers['content-type'] = 'application/json'
            ..body = jsonEncode(inhalt);
        }
        final a = await http.Response.fromStream(
          await _netz.send(anfrage).timeout(frist),
        ).timeout(frist);
        if (a.statusCode < 500) return _werte(a);
        grund = 'Fehler ${a.statusCode}';
      } on IOException catch (f) {
        grund = f;
      } on TimeoutException {
        grund = 'keine Antwort';
      } on http.ClientException catch (f) {
        grund = f.message;
      }
      if (versuch >= 3) throw Immichfehler('Immich antwortet nicht: $grund');
      await Future<void>.delayed(warten);
    }
  }

  Object? _werte(http.Response a) {
    switch (a.statusCode) {
      case 401:
        throw const Immichfehler('Immich lehnt den API-Schlüssel ab.');
      case 403:
        throw const Immichfehler(
          'Dem API-Schlüssel fehlt eine Berechtigung. Er braucht asset.read, '
          'album.read, face.read und user.read.',
        );
      case >= 300 && < 400:
        throw const Immichfehler(
          'Die Adresse leitet weiter. Bitte die endgültige Adresse eintragen.',
        );
      case >= 400:
        throw _Abgelehnt(a.statusCode);
    }
    try {
      return jsonDecode(utf8.decode(a.bodyBytes));
    } on FormatException {
      throw const Immichfehler('Unter dieser Adresse antwortet kein Immich.');
    }
  }

  /// Die Fassung, etwa `3.3.5`; zugleich die Probe, ob dort Immich antwortet.
  Future<String> fassung() async {
    try {
      final j = await _frage('GET', 'server/version');
      if (j is Map && j['major'] != null) {
        return '${j['major']}.${j['minor']}.${j['patch']}';
      }
    } on _Abgelehnt {
      // fällt unten durch
    }
    throw const Immichfehler('Unter dieser Adresse antwortet kein Immich.');
  }

  /// Das Konto, dem der Schlüssel gehört.
  Future<String> ich() async {
    final j = await _frage('GET', 'users/me');
    if (j is Map && j['id'] is String) return j['id'] as String;
    throw const Immichfehler('Immich antwortet in unbekannter Form.');
  }

  /// Geht alle Treffer einer Suche durch, Seite für Seite, und gibt jeden
  /// gleich an [jeTreffer] weiter – die Rohantworten von hunderttausend
  /// Aufnahmen auf einmal im Speicher wären mehrere hundert Megabyte.
  Future<int> _durchlaufe(
    Map<String, Object?> suche,
    void Function(Map<String, Object?>) jeTreffer, {
    void Function(int)? fortschritt,
  }) async {
    var anzahl = 0;
    var weiter = const <String, Object?>{};
    final gesehen = <String>{};
    while (true) {
      final j = await _frage(
        'POST',
        'search/metadata',
        inhalt: {...suche, 'size': 1000, ...weiter},
      );
      final seite = j is Map ? j['assets'] : null;
      if (seite is! Map) {
        throw const Immichfehler('Immich antwortet in unbekannter Form.');
      }
      for (final x in (seite['items'] as List?) ?? const []) {
        jeTreffer((x as Map).cast<String, Object?>());
        anzahl++;
      }
      fortschritt?.call(anzahl);
      // Die flachen Felder dieser Suche gehören zu den Seitennummern; den
      // Zeiger gibt es erst seit 3.2.
      final nummer = seite['nextPage'];
      final zeiger = seite['nextCursor'];
      if (nummer != null && '$nummer'.isNotEmpty) {
        weiter = {'page': int.parse('$nummer')};
      } else if (zeiger is String && zeiger.isNotEmpty) {
        weiter = {'cursor': zeiger};
      } else {
        return anzahl;
      }
      if (!gesehen.add('$weiter')) {
        throw const Immichfehler('Immich liefert dieselbe Seite immer wieder.');
      }
    }
  }

  /// Was übernommen werden kann – nur Aufnahmen von [besitzer]; die von
  /// Partnern zählt `partner`.
  Future<({List<ImmichAufnahme> liste, int partner})> aufnahmen({
    String? besitzer,
    void Function(int)? fortschritt,
  }) async {
    const felder = {'withExif': true, 'withPeople': true};
    final aus = <String, ImmichAufnahme>{};
    final fremd = <String>{};
    void nimm(Map<String, Object?> j) {
      final a = ImmichAufnahme.aus(j);
      if (a == null) return;
      if (besitzer != null && a.besitzer != null && a.besitzer != besitzer) {
        fremd.add(a.id);
      } else {
        aus[a.id] = a;
      }
    }

    await _durchlaufe(felder, nimm, fortschritt: fortschritt);
    // Seit 3.x liefert die Suche ohne Angabe auch Archiviertes. Nur wenn
    // nichts davon kam, eigens danach fragen – für ältere Fassungen.
    if (!aus.values.any((a) => a.archiviert)) {
      try {
        await _durchlaufe({...felder, 'visibility': 'archive'}, nimm);
      } on _Abgelehnt {
        // Eine Fassung ohne dieses Feld hat es oben schon geliefert.
      }
    }
    return (liste: aus.values.toList(), partner: fremd.length);
  }

  /// Eigene und mit dem Konto geteilte Alben, samt Inhalt.
  Future<List<ImmichAlbum>> alben() async {
    final alle = <String, Map<String, Object?>>{};
    void nimm(Object? j) {
      for (final x in j is List ? j : const []) {
        final m = (x as Map).cast<String, Object?>();
        alle['${m['id']}'] = m;
      }
    }

    nimm(await _frage('GET', 'albums'));
    // Der Name des Felds für geteilte Alben hängt von der Fassung ab.
    for (final feld in const ['isShared', 'shared']) {
      try {
        nimm(await _frage('GET', 'albums', abfrage: {feld: 'true'}));
      } on _Abgelehnt {
        // Diese Fassung kennt das Feld nicht.
      }
    }
    return [
      for (final m in alle.values)
        ImmichAlbum(
          '${m['id']}',
          '${m['albumName'] ?? ''}'.trim(),
          DateTime.tryParse('${m['createdAt']}') ?? DateTime.now(),
          await _inhalt('${m['id']}'),
        ),
    ];
  }

  Future<List<String>> _inhalt(String album) async {
    final ids = <String>[];
    await _durchlaufe({
      'albumIds': [album],
    }, (a) => ids.add('${a['id']}'));
    return ids;
  }

  /// Die Gesichter von Personen auf einem Foto.
  Future<List<ImmichGesicht>> gesichter(String aufnahme) async {
    final Object? j;
    try {
      j = await _frage('GET', 'faces', abfrage: {'id': aufnahme});
    } on _Abgelehnt {
      // Inzwischen in Immich gelöscht: Dann gibt es dort keine Gesichter mehr,
      // und der Rest der Prüfung soll deshalb nicht scheitern.
      return const [];
    }
    return [
      for (final x in j is List ? j : const [])
        ?_gesicht((x as Map).cast<String, Object?>()),
    ];
  }

  static ImmichGesicht? _gesicht(Map<String, Object?> j) {
    final person = j['person'];
    final breite = (j['imageWidth'] as num?)?.toDouble() ?? 0;
    final hoehe = (j['imageHeight'] as num?)?.toDouble() ?? 0;
    final x1 = (j['boundingBoxX1'] as num?)?.toDouble();
    final x2 = (j['boundingBoxX2'] as num?)?.toDouble();
    final y1 = (j['boundingBoxY1'] as num?)?.toDouble();
    final y2 = (j['boundingBoxY2'] as num?)?.toDouble();
    if (person is! Map ||
        breite <= 0 ||
        hoehe <= 0 ||
        x1 == null ||
        x2 == null ||
        y1 == null ||
        y2 == null) {
      return null;
    }
    return ImmichGesicht(
      '${person['id']}',
      x1 / breite,
      y1 / hoehe,
      (x2 - x1) / breite,
      (y2 - y1) / hoehe,
    );
  }
}

/// Eine Antwort mit 4xx, die nichts über den Schlüssel sagt.
class _Abgelehnt implements Immichfehler {
  const _Abgelehnt(this.status);
  final int status;

  @override
  String get text => 'Immich lehnt die Anfrage ab (Fehler $status).';

  @override
  String toString() => text;
}

/// Eine Aufnahme der Bibliothek, so weit es hier darum geht.
class _Zeile {
  const _Zeile(this.z, this.db);
  final TypedResult z;
  final AppDatabase db;

  String get id => z.read(db.assets.id)!;
  String get name => z.read(db.assets.originalFileName)!;
  String get art => z.read(db.assets.type)!;
  DateTime get zeit => z.read(db.assets.fileCreatedAt)!;
  String get sha256 => z.read(db.assets.checksum)!;
  String get pfad => z.read(db.assets.relativePath)!;
  bool get favorit => z.read(db.assets.isFavorite)!;
  bool get imPapierkorb => z.read(db.assets.isTrashed)!;
  bool get gesperrt => z.read(db.assets.isLocked)!;
  String get beschreibung => (z.read(db.assets.description) ?? '').trim();
  String? get stapel => z.read(db.assets.stackId);
  bool get titel => z.read(db.assets.isStackCover)!;
  int? get groesse => z.read(db.assets.fileSizeBytes);
  bool get archiviert => z.read(db.assets.isArchived)!;
}

Future<List<_Zeile>> _zeilen(AppDatabase db) async {
  final a = db.assets;
  final q = db.selectOnly(a)
    ..addColumns([
      a.id,
      a.originalFileName,
      a.type,
      a.fileCreatedAt,
      a.checksum,
      a.relativePath,
      a.isFavorite,
      a.isTrashed,
      a.isLocked,
      a.description,
      a.stackId,
      a.isStackCover,
      a.fileSizeBytes,
      a.isArchived,
    ]);
  return [for (final z in await q.get()) _Zeile(z, db)];
}

/// Ein Gesicht der Bibliothek, ohne seine Einbettung.
class _Gesicht {
  const _Gesicht(
    this.id,
    this.aufnahme,
    this.person,
    this.x,
    this.y,
    this.b,
    this.h,
  );
  final String id, aufnahme;
  final String? person;
  final double x, y, b, h;
}

Future<Map<String, List<_Gesicht>>> _gesichterJeAufnahme(AppDatabase db) async {
  final f = db.faces;
  final q = db.selectOnly(f)
    ..addColumns([f.id, f.assetId, f.personId, f.boxX, f.boxY, f.boxW, f.boxH])
    ..where(f.isIgnored.equals(false));
  final aus = <String, List<_Gesicht>>{};
  for (final z in await q.get()) {
    final g = _Gesicht(
      z.read(f.id)!,
      z.read(f.assetId)!,
      z.read(f.personId),
      z.read(f.boxX)!,
      z.read(f.boxY)!,
      z.read(f.boxW)!,
      z.read(f.boxH)!,
    );
    (aus[g.aufnahme] ??= []).add(g);
  }
  return aus;
}

/// Wie stark sich zwei Rahmen überlappen, von 0 bis 1.
double _ueberlappung(ImmichGesicht a, _Gesicht b) {
  final links = a.x > b.x ? a.x : b.x;
  final oben = a.y > b.y ? a.y : b.y;
  final rechts = a.x + a.b < b.x + b.b ? a.x + a.b : b.x + b.b;
  final unten = a.y + a.h < b.y + b.h ? a.y + a.h : b.y + b.h;
  if (rechts <= links || unten <= oben) return 0;
  final schnitt = (rechts - links) * (unten - oben);
  return schnitt / (a.b * a.h + b.b * b.h - schnitt);
}

/// Darunter gilt ein Rahmen nicht als dasselbe Gesicht. Zwei Erkenner setzen
/// ihre Rahmen verschieden eng; ein anderes Gesicht überlappt fast nie so
/// stark.
const _mindestUeberlappung = 0.3;

/// Was Immich hergibt, auf die Kennungen der Bibliothek abgebildet.
class _Bestand {
  _Bestand({
    required this.fassung,
    required this.aufnahmen,
    required this.alben,
    required this.zuordnung,
    required this.gesichter,
    required this.aehnlich,
    required this.ohne,
    required this.bibliotheksgroesse,
    this.partner = 0,
    this.unlesbar = 0,
    this.kameratexte = const {},
  });

  final String fassung;
  final List<ImmichAufnahme> aufnahmen;
  final List<ImmichAlbum> alben;

  /// Kennung in Immich → Kennung in der Bibliothek.
  final Map<String, String> zuordnung;

  /// Kennung in Immich → die Gesichter benannter Personen.
  final Map<String, List<ImmichGesicht>> gesichter;
  final int aehnlich;
  final List<Map<String, Object?>> ohne;
  final int bibliotheksgroesse;

  /// Aufnahmen von Partnern, die nicht zählen.
  final int partner;

  /// Originale, die sich nicht lesen liessen.
  final int unlesbar;

  /// Kennungen in Immich, deren Beschreibung ein Kameratext ist.
  final Set<String> kameratexte;
}

class _Albumplan {
  _Albumplan(this.name, this.angelegt, this.vorhanden, this.neu, [this.immich]);
  final String name;
  final DateTime angelegt;

  /// Die Kennung des Albums in Immich; `null` beim Archiv-Album.
  final String? immich;

  /// Die Kennung, wenn es das Album schon gibt.
  final String? vorhanden;
  final List<String> neu;
}

class _Personenplan {
  _Personenplan(this.name, this.vorhanden, this.gesichter, this.geburt);
  final String name;

  /// Die Kennung, wenn es die Person schon gibt.
  final String? vorhanden;
  final List<String> gesichter;

  /// Nur, wenn dort noch keins steht.
  final DateTime? geburt;

  /// Das Sterbedatum bleibt; der Befehl setzt beide.
  DateTime? tod;
}

class _Vorhaben {
  final alben = <_Albumplan>[];

  /// Was ins Archiv gehört und noch nicht dort liegt.
  final archiv = <String>{};
  final favoriten = <String>{};
  final beschreibungen = <String, String>{};
  var beschreibungenAbweichend = 0;
  var kameratexte = 0;
  final personen = <_Personenplan>[];
  final abweichendeNamen = <Map<String, Object?>>[];
  final unklar = <String>[];
}

Iterable<List<T>> _stuecke<T>(List<T> liste, [int groesse = 500]) sync* {
  for (var i = 0; i < liste.length; i += groesse) {
    yield liste.sublist(
      i,
      i + groesse < liste.length ? i + groesse : liste.length,
    );
  }
}

String _gleichgemacht(String name) => name.trim().toLowerCase();

/// Welche Immich-Alben welchen Alben der Bibliothek entsprechen – damit ein
/// zweiter Lauf nicht nach dem Namen gehen muss (gleichnamige Alben).
File _albenAblage(Bibliothek bib) =>
    File(p.join(bib.ordner.path, 'immich-alben.json'));

Map<String, String> _albenZuordnung(Bibliothek bib) {
  final f = _albenAblage(bib);
  try {
    if (f.existsSync()) {
      return (jsonDecode(f.readAsStringSync()) as Map).cast<String, String>();
    }
  } on Object catch (e) {
    protokoll('Immich: ${f.path} nicht lesbar, beginne neu: $e');
  }
  return {};
}

Future<_Vorhaben> _berechne(Bibliothek bib, _Bestand b) async {
  final db = bib.db;
  final v = _Vorhaben();
  final zeilen = {for (final z in await _zeilen(db)) z.id: z};
  // Angaben gehören der Fassung, die man sieht (#363): Ist die Aufnahme ein
  // verdecktes Mitglied eines Stapels, geht alles an dessen Titelbild.
  final titelJeStapel = {
    for (final z in zeilen.values)
      if (z.titel && z.stapel != null) z.stapel!: z.id,
  };
  String? sichtbar(String? id) {
    final z = zeilen[id];
    if (z == null) return null;
    final stapel = z.stapel;
    return stapel == null || z.titel ? z.id : (titelJeStapel[stapel] ?? z.id);
  }

  for (final a in b.aufnahmen) {
    final z = zeilen[sichtbar(b.zuordnung[a.id])];
    if (z == null) continue;
    if (a.favorit && !z.favorit) v.favoriten.add(z.id);
    if (a.beschreibung.isEmpty) continue;
    if (b.kameratexte.contains(a.id)) {
      v.kameratexte++;
    } else if (z.beschreibung.isEmpty) {
      v.beschreibungen.putIfAbsent(z.id, () => a.beschreibung);
    } else if (z.beschreibung != a.beschreibung) {
      v.beschreibungenAbweichend++;
    }
  }

  final alleAlben = await db.alleAlben();
  final albumNamen = {for (final a in alleAlben) a.name: a.id};
  final albumIds = {for (final a in alleAlben) a.id};
  final frueher = _albenZuordnung(bib);
  Future<_Albumplan?> album(
    String name,
    DateTime angelegt,
    Iterable<String?> aufnahmen, {
    String? immich,
    String? vorhanden,
  }) async {
    final ids = {for (final id in aufnahmen) ?sichtbar(id)};
    vorhanden ??= albumNamen[name];
    if (vorhanden != null) {
      // Direkt aus album_assets: Die Abfrage fürs Raster liesse verdeckte
      // Stapelmitglieder weg, und jeder Lauf füllte sie erneut.
      ids.removeAll(await db.imAlbum(vorhanden, ids.toList()));
    }
    return ids.isEmpty
        ? null
        : _Albumplan(name, angelegt, vorhanden, ids.toList(), immich);
  }

  // Zwei Immich-Alben mit demselben Namen blieben sonst nicht getrennt. Was
  // schon einmal übernommen wurde, behält sein Album, auch wenn ein neues
  // gleichnamiges dazukommt; für die übrigen zählt das Alter.
  final sortiert = [...b.alben]
    ..sort((x, y) {
      final z = x.angelegt.compareTo(y.angelegt);
      return z != 0 ? z : x.id.compareTo(y.id);
    });
  final belegt = <String>{
    for (final a in sortiert)
      if (albumIds.contains(frueher[a.id]))
        alleAlben.firstWhere((x) => x.id == frueher[a.id]).name,
  };
  for (final a in sortiert) {
    if (a.name.isEmpty) continue;
    final mitglieder = [for (final x in a.aufnahmen) b.zuordnung[x]];
    final schon = frueher[a.id];
    _Albumplan? plan;
    if (schon != null && albumIds.contains(schon)) {
      plan = await album(
        alleAlben.firstWhere((x) => x.id == schon).name,
        a.angelegt,
        mitglieder,
        immich: a.id,
        vorhanden: schon,
      );
    } else {
      var name = a.name;
      for (var n = 2; belegt.contains(name); n++) {
        name = '${a.name} ($n)';
      }
      belegt.add(name);
      plan = await album(name, a.angelegt, mitglieder, immich: a.id);
    }
    if (plan != null) v.alben.add(plan);
  }
  for (final a in b.aufnahmen) {
    if (!a.archiviert) continue;
    final z = zeilen[sichtbar(b.zuordnung[a.id])];
    if (z != null && !z.archiviert) v.archiv.add(z.id);
  }

  await _berechnePersonen(db, b, v);
  return v;
}

Future<void> _berechnePersonen(AppDatabase db, _Bestand b, _Vorhaben v) async {
  final personen = {for (final p in await db.allePersonen()) p.id: p};
  final jeName = {for (final p in personen.values) _gleichgemacht(p.name): p};
  final inBibliothek = await _gesichterJeAufnahme(db);
  final namen = <String, ImmichPerson>{};
  final stimmen = <String, Map<String, int>>{};
  final frei = <String, Set<String>>{};
  for (final a in b.aufnahmen) {
    for (final p in a.personen) {
      if (p.zaehlt) namen[p.id] = p;
    }
    final vorhanden = inBibliothek[b.zuordnung[a.id]];
    final immich = b.gesichter[a.id];
    if (vorhanden == null || immich == null) continue;
    // Das am stärksten überlappende Paar zuerst, jedes Gesicht nur einmal.
    final paare = [
      for (final i in immich)
        for (final g in vorhanden)
          if (_ueberlappung(i, g) >= _mindestUeberlappung)
            (i, g, _ueberlappung(i, g)),
    ]..sort((x, y) => y.$3.compareTo(x.$3));
    final vergeben = <Object>{};
    for (final (i, g, _) in paare) {
      if (vergeben.contains(i) || vergeben.contains(g)) continue;
      vergeben
        ..add(i)
        ..add(g);
      if (g.person != null) {
        final s = stimmen[i.personId] ??= {};
        s[g.person!] = (s[g.person!] ?? 0) + 1;
      } else {
        (frei[i.personId] ??= {}).add(g.id);
      }
    }
  }

  // Zwei Immich-Personen gleichen Namens (nicht zusammengeführt) werden
  // eine neue Person, nicht zwei.
  final neuJeName = <String, _Personenplan>{};
  for (final p in namen.values) {
    final s = stimmen[p.id] ?? const <String, int>{};
    final freie = frei[p.id] ?? const <String>{};
    final namensgleich = jeName[_gleichgemacht(p.name)];
    String? ziel;
    if (s.isNotEmpty) {
      final summe = s.values.reduce((x, y) => x + y);
      final beste = s.entries.reduce((x, y) => x.value >= y.value ? x : y);
      final gleicherName =
          _gleichgemacht(personen[beste.key]?.name ?? '') ==
          _gleichgemacht(p.name);
      // Ein einzelnes Gesicht unter anderem Namen kann ein Irrtum sein. Und
      // zeigen die Gesichter auf jemand anderen, während es eine Person
      // dieses Namens gibt, widersprechen sich die Hinweise: lieber nichts.
      if (beste.value >= summe * 0.7 &&
          (beste.value >= 2 || gleicherName) &&
          (gleicherName || namensgleich == null)) {
        ziel = beste.key;
      } else {
        v.unklar.add(p.name);
        continue;
      }
    } else {
      ziel = namensgleich?.id;
    }
    if (ziel == null) {
      final schon = neuJeName[_gleichgemacht(p.name)];
      if (schon != null) {
        schon.gesichter.addAll(freie);
        continue;
      }
    }
    final vorhanden = ziel == null ? null : personen[ziel];
    if (vorhanden != null &&
        _gleichgemacht(vorhanden.name) != _gleichgemacht(p.name)) {
      v.abweichendeNamen.add({'immich': p.name, 'bibliothek': vorhanden.name});
    }
    final geburt = vorhanden?.geburtsdatum == null ? p.geburt : null;
    if (freie.isEmpty && (vorhanden == null || geburt == null)) continue;
    final plan = _Personenplan(p.name, ziel, freie.toList(), geburt)
      ..tod = vorhanden?.sterbedatum;
    v.personen.add(plan);
    if (ziel == null) neuJeName[_gleichgemacht(p.name)] = plan;
  }
}

Map<String, Object?> _bericht(_Bestand b, _Vorhaben v) {
  int anzahl(bool Function(Map<String, Object?>) was) =>
      b.ohne.where(was).length;
  final personen = {
    for (final a in b.aufnahmen)
      for (final p in a.personen)
        if (p.zaehlt) p.id,
  };
  final alben = v.alben;
  return {
    'fassung': b.fassung,
    'immich': {
      'aufnahmen': b.aufnahmen.length,
      'partner': b.partner,
      'archiviert': b.aufnahmen.where((a) => a.archiviert).length,
      'favoriten': b.aufnahmen.where((a) => a.favorit).length,
      'beschreibungen': b.aufnahmen
          .where((a) => a.beschreibung.isNotEmpty)
          .length,
      'alben': b.alben.length,
      'personen': personen.length,
    },
    'zuordnung': {
      'bitgleich': b.zuordnung.length - b.aehnlich,
      'aehnlich': b.aehnlich,
      'fehlen': anzahl((o) => o['grund'] == 'fehlt'),
      'andereZeit': anzahl((o) => o['grund'] == 'andereZeit'),
      'papierkorb': anzahl((o) => o['grund'] == 'papierkorb'),
      'gesperrt': anzahl((o) => o['grund'] == 'gesperrt'),
      'mehrdeutig': anzahl((o) => o['grund'] == 'mehrdeutig'),
      'nurPhotoVault': b.bibliotheksgroesse - b.zuordnung.values.toSet().length,
      'unlesbar': b.unlesbar,
      'ohneAnzahl': b.ohne.length,
      'beispiele': b.ohne.take(500).toList(),
    },
    'vorhaben': {
      'albenNeu': v.alben.where((a) => a.vorhanden == null).length,
      'albenErgaenzt': v.alben.where((a) => a.vorhanden != null).length,
      'albumAufnahmen': v.alben.fold<int>(0, (n, a) => n + a.neu.length),
      'favoriten': v.favoriten.length,
      'beschreibungen': v.beschreibungen.length,
      'beschreibungenAbweichend': v.beschreibungenAbweichend,
      'kameratexte': v.kameratexte,
      'personenNeu': v.personen.where((p) => p.vorhanden == null).length,
      'personenVorhanden': v.personen.where((p) => p.vorhanden != null).length,
      'gesichter': v.personen.fold<int>(0, (n, p) => n + p.gesichter.length),
      'geburtstage': v.personen.where((p) => p.geburt != null).length,
      'archiv': v.archiv.length,
      'abweichendeNamen': v.abweichendeNamen,
      'unklar': v.unklar,
      'aenderungen':
          alben.fold<int>(0, (n, a) => n + a.neu.length) +
          v.archiv.length +
          v.favoriten.length +
          v.beschreibungen.length +
          v.personen.fold<int>(
            0,
            (n, p) => n + p.gesichter.length + (p.geburt != null ? 1 : 0),
          ),
    },
  };
}

Future<void> _parallel<T>(
  Iterable<T> dinge,
  int breite,
  Future<void> Function(T) tue,
) async {
  final zeiger = dinge.iterator;
  Future<void> arbeiter() async {
    while (zeiger.moveNext()) {
      final x = zeiger.current;
      await tue(x);
    }
  }

  await Future.wait([for (var i = 0; i < breite; i++) arbeiter()]);
}

Future<String> _sha1VonDatei(String pfad) => Isolate.run(() async {
  final summe = await sha1.bind(File(pfad).openRead()).first;
  return base64.encode(summe.bytes);
});

class _Lauf {
  /// `leer`, `laden`, `pruefsummen`, `gesichter`, `bereit`, `uebernehmen`,
  /// `fertig` oder `fehler`.
  var stufe = 'leer';
  var fertig = 0;
  var von = 0;
  String? fehler;
  _Bestand? bestand;
  Map<String, Object?>? bericht;
  Map<String, Object?>? ergebnis;

  bool get beschaeftigt => const {
    'laden',
    'pruefsummen',
    'gesichter',
    'uebernehmen',
  }.contains(stufe);

  void weiter(String s, {int von = 0}) {
    stufe = s;
    fertig = 0;
    this.von = von;
  }

  Map<String, Object?> alsJson() => {
    'stufe': stufe,
    'fertig': fertig,
    'von': von,
    'fehler': ?fehler,
    'bericht': ?bericht,
    'ergebnis': ?ergebnis,
  };
}

/// Ein Kameratext statt einer Beschreibung? Gross- und Kleinschreibung
/// zählen nicht. Die Liste deckt ab, was Kameras ab Werk hineinschreiben.
const _kameratexte = {
  'olympus digital camera',
  'sony dsc',
  'digital camera',
  'minolta digital camera',
  'konica minolta digital camera',
  'leica digital camera',
  'samsung digital camera',
  'kodak digital still camera',
  'exif_jpeg_picture',
  'default',
  'dcim',
  'image',
  'picture',
};

/// Ob [text] aus der Datei stammt oder wie ein Kameratext aussieht.
Future<bool> _istKameratext(String text, String? pfad) async {
  final t = text.trim().toLowerCase();
  if (_kameratexte.contains(t) || RegExp(r'^[\s?._-]*$').hasMatch(t)) {
    return true;
  }
  if (pfad == null) return false;
  try {
    final tags = await readExifFromFile(File(pfad));
    final inDatei = tags['Image ImageDescription']?.printable.trim();
    return inDatei != null && inDatei.toLowerCase() == t;
  } on Object {
    return false;
  }
}

/// Die Übernahme je Konto. Es läuft immer nur eine.
class Immichuebernahme {
  Immichuebernahme(this.bibliotheken, {this._netz, this.vergessenNach});

  final Bibliotheken bibliotheken;
  final http.Client Function()? _netz;
  final _laeufe = <String, _Lauf>{};

  /// Nach so langer Ruhe wird eine fertige Prüfung vergessen: Sie hält die
  /// Angaben aller Immich-Aufnahmen im Speicher. Vorgabe zwei Stunden.
  final Duration? vergessenNach;
  final _uhren = <String, Timer>{};

  void _vergissSpaeter(String konto, _Lauf l) {
    _uhren.remove(konto)?.cancel();
    _uhren[konto] = Timer(vergessenNach ?? const Duration(hours: 2), () {
      _uhren.remove(konto);
      if (identical(_laeufe[konto], l) && !l.beschaeftigt) {
        _laeufe.remove(konto);
      }
    });
  }

  Map<String, Object?> stand(String konto) =>
      (_laeufe[konto] ?? _Lauf()).alsJson();

  /// Beginnt eine Prüfung im Hintergrund. [ArgumentError] bei falschen
  /// Angaben, [StateError], wenn schon etwas läuft.
  Future<void> pruefe(
    String konto, {
    required String adresse,
    required String schluessel,
    Duration? warten,
  }) async {
    if (schluessel.trim().isEmpty) {
      throw ArgumentError('Der API-Schlüssel fehlt.');
    }
    final basis = Immichverbindung.basisAus(adresse);
    if (_laeufe[konto]?.beschaeftigt ?? false) {
      throw StateError('Es läuft schon eine Prüfung oder Übernahme.');
    }
    final lauf = _laeufe[konto] = _Lauf()..weiter('laden');
    final verbindung = Immichverbindung(
      basis,
      schluessel.trim(),
      netz: _netz?.call(),
      warten: warten ?? const Duration(seconds: 2),
    );
    unawaited(_pruefe(konto, lauf, verbindung));
  }

  Future<void> _pruefe(String konto, _Lauf l, Immichverbindung v) async {
    try {
      final b = (await bibliotheken.fuer(konto)).bibliothek;
      final fassung = await v.fassung();
      final ich = await v.ich();
      final (liste: aufnahmen, :partner) = await v.aufnahmen(
        besitzer: ich,
        fortschritt: (n) => l.fertig = n,
      );
      final alben = await v.alben();
      final (:zuordnung, :aehnlich, :ohne, :groesse, :unlesbar) =
          await _ordneZu(b, aufnahmen, l);
      final pfade = {for (final z in await _zeilen(b.db)) z.id: z.pfad};
      final kameratexte = <String>{};
      await _parallel(
        [
          for (final a in aufnahmen)
            if (a.beschreibung.isNotEmpty && zuordnung.containsKey(a.id)) a,
        ],
        4,
        (a) async {
          final pfad = pfade[zuordnung[a.id]];
          if (await _istKameratext(
            a.beschreibung,
            pfad == null ? null : b.pfade.absolute(pfad).path,
          )) {
            kameratexte.add(a.id);
          }
        },
      );
      final mitPersonen = [
        for (final a in aufnahmen)
          if (zuordnung.containsKey(a.id) && a.personen.any((p) => p.zaehlt)) a,
      ];
      l.weiter('gesichter', von: mitPersonen.length);
      final gesichter = <String, List<ImmichGesicht>>{};
      await _parallel(mitPersonen, 4, (a) async {
        final zaehlt = {
          for (final p in a.personen)
            if (p.zaehlt) p.id,
        };
        gesichter[a.id] = [
          for (final g in await v.gesichter(a.id))
            if (zaehlt.contains(g.personId)) g,
        ];
        l.fertig++;
      });
      final bestand = _Bestand(
        fassung: fassung,
        aufnahmen: aufnahmen,
        alben: alben,
        zuordnung: zuordnung,
        gesichter: gesichter,
        aehnlich: aehnlich,
        ohne: ohne,
        bibliotheksgroesse: groesse,
        partner: partner,
        unlesbar: unlesbar,
        kameratexte: kameratexte,
      );
      l
        ..bestand = bestand
        ..bericht = _bericht(bestand, await _berechne(b, bestand))
        ..weiter('bereit');
      _vergissSpaeter(konto, l);
    } on Immichfehler catch (f) {
      l
        ..fehler = f.text
        ..weiter('fehler');
    } on Object catch (f, spur) {
      protokoll('Immich: Prüfung gescheitert: $f\n$spur');
      l
        ..fehler = 'Die Prüfung ist gescheitert: $f'
        ..weiter('fehler');
    } finally {
      v.schliesse();
    }
  }

  Future<
    ({
      Map<String, String> zuordnung,
      int aehnlich,
      List<Map<String, Object?>> ohne,
      int groesse,
      int unlesbar,
    })
  >
  _ordneZu(Bibliothek b, List<ImmichAufnahme> aufnahmen, _Lauf l) async {
    final zeilen = await _zeilen(b.db);
    final lesbar = [
      for (final z in zeilen)
        if (!z.imPapierkorb && !z.gesperrt) z,
    ];
    final ablage = File(p.join(b.ordner.path, 'immich-sha1.json'));
    final bekannt = <String, String>{};
    try {
      if (ablage.existsSync()) {
        bekannt.addAll(
          (jsonDecode(await ablage.readAsString()) as Map)
              .cast<String, String>(),
        );
      }
    } on Object catch (e) {
      // Nur ein Zwischenspeicher: Kaputt heisst neu rechnen, nicht aufgeben.
      protokoll('Immich: ${ablage.path} nicht lesbar, rechne neu: $e');
    }
    // Was es in der Bibliothek nicht mehr gibt, braucht keinen Eintrag.
    final vorhanden = {for (final z in zeilen) z.sha256};
    bekannt.removeWhere((k, _) => !vorhanden.contains(k));
    var geaendert = false;
    Future<void> sichere() async {
      if (!geaendert) return;
      geaendert = false;
      final neu = File('${ablage.path}.neu');
      await neu.writeAsString(jsonEncode(bekannt));
      await neu.rename(ablage.path);
    }

    // Eine bitgleiche Datei hat dieselbe Grösse. Kennt Immich die Grössen
    // aller Aufnahmen, braucht nur gehasht zu werden, was dazu passt.
    final groessen = {for (final a in aufnahmen) a.groesse};
    final nachGroesse = groessen.isNotEmpty && !groessen.contains(null);
    bool kommtInFrage(_Zeile z) =>
        !nachGroesse || z.groesse == null || groessen.contains(z.groesse);

    l.weiter('pruefsummen', von: lesbar.length);
    final zuSha1 = <String, _Zeile>{};
    var unlesbar = 0;
    var zuletzt = DateTime.now();
    await _parallel(lesbar, 3, (z) async {
      var s = bekannt[z.sha256];
      if (s == null && kommtInFrage(z)) {
        final pfad = b.pfade.absolute(z.pfad).path;
        try {
          if (File(pfad).existsSync()) {
            s = bekannt[z.sha256] = await _sha1VonDatei(pfad);
            geaendert = true;
          }
        } on Object catch (e) {
          unlesbar++;
          protokoll('Immich: $pfad nicht lesbar: $e');
        }
        // Zwischendurch sichern, aber nach der Uhr: Nach der Zahl hiesse es
        // bei hunderttausend Fotos zweihundert Mal die ganze Datei.
        if (DateTime.now().difference(zuletzt) > const Duration(minutes: 1)) {
          zuletzt = DateTime.now();
          await sichere();
        }
      }
      if (s != null) zuSha1[s] = z;
      l.fertig++;
    });
    geaendert = true;
    await sichere();

    final zuordnung = <String, String>{};
    final rest = <ImmichAufnahme>[];
    for (final a in aufnahmen) {
      final z = zuSha1[a.sha1];
      if (z == null) {
        rest.add(a);
      } else {
        zuordnung[a.id] = z.id;
      }
    }

    final vergeben = zuordnung.values.toSet();
    final jeName = <String, List<_Zeile>>{};
    for (final z in zeilen) {
      (jeName[_gleichgemacht(z.name)] ??= []).add(z);
    }
    bool nah(ImmichAufnahme a, _Zeile z) =>
        a.art == z.art && a.zeit.difference(z.zeit).inSeconds.abs() <= 2;

    var aehnlich = 0;
    final ohne = <Map<String, Object?>>[];
    for (final a in rest) {
      final gleichnamig = jeName[_gleichgemacht(a.name)] ?? const <_Zeile>[];
      final passend = gleichnamig.where((z) => nah(a, z)).toList();
      final frei = passend
          .where(
            (z) => !z.imPapierkorb && !z.gesperrt && !vergeben.contains(z.id),
          )
          .toList();
      if (frei.length == 1) {
        zuordnung[a.id] = frei.single.id;
        vergeben.add(frei.single.id);
        aehnlich++;
        continue;
      }
      ohne.add({
        'name': a.name,
        'zeit': a.zeit.toUtc().toIso8601String(),
        'grund': passend.any((z) => z.imPapierkorb)
            ? 'papierkorb'
            : passend.any((z) => z.gesperrt)
            ? 'gesperrt'
            : frei.length > 1
            ? 'mehrdeutig'
            : gleichnamig.isNotEmpty
            ? 'andereZeit'
            : 'fehlt',
      });
    }
    return (
      zuordnung: zuordnung,
      aehnlich: aehnlich,
      ohne: ohne,
      groesse: lesbar.length,
      unlesbar: unlesbar,
    );
  }

  /// Übernimmt, was die letzte Prüfung gefunden hat, im Hintergrund.
  /// [teile] sagt, was davon; fehlt ein Teil, gilt er als gewählt.
  Future<void> uebernimm(String konto, Map<String, Object?> teile) async {
    final l = _laeufe[konto];
    if (l == null || l.bestand == null || l.beschaeftigt) {
      throw StateError('Es liegt keine fertige Prüfung vor.');
    }
    l
      ..ergebnis = null
      ..fehler = null
      ..weiter('uebernehmen');
    unawaited(_uebernimm(konto, l, teile));
  }

  Future<void> _uebernimm(
    String konto,
    _Lauf l,
    Map<String, Object?> teile,
  ) async {
    bool gewaehlt(String teil) => teile[teil] != false;
    try {
      final bib = (await bibliotheken.fuer(konto)).bibliothek;
      final db = bib.db;
      // Neu gerechnet: Seit der Prüfung kann sich etwas geändert haben.
      final v = await _berechne(bib, l.bestand!);
      final albenZuordnung = _albenZuordnung(bib);
      Future<int> fuelle(_Albumplan a) async {
        final id = a.vorhanden ?? const Uuid().v4();
        if (a.vorhanden == null) {
          await db.fuehreAus(AlbumAnlegen(id, a.name, a.angelegt));
        }
        if (a.immich case final immich?) albenZuordnung[immich] = id;
        for (final teil in _stuecke(a.neu)) {
          await db.fuehreAus(AlbumFuellen(id, teil));
        }
        return a.neu.length;
      }

      var alben = 0, archiv = 0, gesichter = 0, geburtstage = 0, neu = 0;
      l.von =
          (gewaehlt('alben') ? v.alben.length : 0) +
          (gewaehlt('favoriten') ? v.favoriten.length : 0) +
          (gewaehlt('beschreibungen') ? v.beschreibungen.length : 0) +
          (gewaehlt('personen') ? v.personen.length : 0) +
          (gewaehlt('archiv') ? v.archiv.length : 0);
      if (gewaehlt('alben')) {
        for (final a in v.alben) {
          alben += await fuelle(a);
          l.fertig++;
        }
      }
      if (gewaehlt('alben')) {
        final f = _albenAblage(bib);
        await File('${f.path}.neu').writeAsString(jsonEncode(albenZuordnung));
        await File('${f.path}.neu').rename(f.path);
      }
      if (gewaehlt('favoriten')) {
        for (final teil in _stuecke(v.favoriten.toList())) {
          await db.fuehreAus(FavoritSetzen(teil, true));
          l.fertig += teil.length;
        }
      }
      if (gewaehlt('beschreibungen')) {
        for (final MapEntry(key: id, value: text) in v.beschreibungen.entries) {
          await db.fuehreAus(BeschreibungSetzen([id], text));
          l.fertig++;
        }
      }
      if (gewaehlt('personen')) {
        for (final p in v.personen) {
          final id = p.vorhanden ?? const Uuid().v4();
          if (p.vorhanden == null) {
            await db.fuehreAus(PersonAnlegen(id, p.name));
            neu++;
          }
          for (final teil in _stuecke(p.gesichter)) {
            await db.fuehreAus(GesichterZuordnen(teil, id));
          }
          gesichter += p.gesichter.length;
          if (p.geburt != null) {
            await db.fuehreAus(
              LebensdatenSetzen(id, geburt: p.geburt, tod: p.tod),
            );
            geburtstage++;
          }
          l.fertig++;
        }
      }
      if (gewaehlt('archiv')) {
        for (final teil in _stuecke(v.archiv.toList())) {
          await db.fuehreAus(ArchivSetzen(teil, true));
          archiv += teil.length;
          l.fertig += teil.length;
        }
      }
      l
        ..ergebnis = {
          'albumAufnahmen': alben,
          'favoriten': gewaehlt('favoriten') ? v.favoriten.length : 0,
          'beschreibungen': gewaehlt('beschreibungen')
              ? v.beschreibungen.length
              : 0,
          'personenNeu': neu,
          'gesichter': gesichter,
          'geburtstage': geburtstage,
          'archiv': archiv,
        }
        // Der Bericht zeigt, was jetzt noch offen wäre.
        ..bericht = _bericht(l.bestand!, await _berechne(bib, l.bestand!))
        ..weiter('fertig');
      _vergissSpaeter(konto, l);
    } on Object catch (f, spur) {
      protokoll('Immich: Übernahme gescheitert: $f\n$spur');
      l
        ..fehler = 'Die Übernahme ist gescheitert: $f'
        ..weiter('fehler');
    }
  }

  /// Vergisst Prüfung und Bericht.
  void verwirf(String konto) {
    if (_laeufe[konto]?.beschaeftigt ?? false) {
      throw StateError('Es läuft gerade etwas.');
    }
    _uhren.remove(konto)?.cancel();
    _laeufe.remove(konto);
  }
}
