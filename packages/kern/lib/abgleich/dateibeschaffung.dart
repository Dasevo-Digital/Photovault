import 'dart:async';

import '../db/database.dart';
import '../protokoll.dart';
import '../services/storage_paths.dart';
import 'verbindung.dart';

/// Holt Dateien einer verbundenen Bibliothek vom Server – jede einmal,
/// auch wenn mehrere zugleich nach ihr fragen (das Raster fragt dieselbe
/// Miniatur aus mehreren Bausteinen).
class Dateibeschaffung {
  Dateibeschaffung(this.paths, this.verbindung);

  final StoragePaths paths;
  final Serververbindung verbindung;
  final _laufend = <String, Future<void>>{};

  /// Holt [relativ] nach `paths.absolute(relativ)`. Wirft
  /// [KeineVerbindung], wenn der Server nicht erreichbar ist.
  Future<void> hole(String relativ) => _laufend.putIfAbsent(relativ, () async {
    try {
      final ziel = paths.absolute(relativ);
      if (await ziel.exists()) return;
      await verbindung.ladeHerunter(adresse(relativ), ziel);
    } finally {
      unawaited(Future<void>(() => _laufend.remove(relativ)));
    }
  });

  /// Wo der Server die Datei [relativ] der Bibliothek ausliefert.
  static String adresse(String relativ) =>
      'api/v1/dateien/'
      '${[for (final t in relativ.split('/')) Uri.encodeComponent(t)].join('/')}';

  /// Bringt eine hier geschriebene abgeleitete Datei zum Server (siehe
  /// [StoragePaths.ablege]).
  Future<void> lege(String relativ) =>
      verbindung.legeAb(adresse(relativ), paths.absolute(relativ));

  /// Verbindet [paths] mit dieser Beschaffung – holen und ablegen (siehe
  /// [StoragePaths.beschaffe] und [StoragePaths.ablege]).
  void binde() {
    paths.beschaffe = hole;
    paths.ablege = lege;
  }
}

/// Lädt im Hintergrund vor, was das Raster und die Personen sofort zeigen:
/// Miniaturen und Gesichtsausschnitte. Klein genug, um alle zu halten, und
/// danach geht die Bibliothek auch offline durchzublättern. Vorschauen
/// und Originale kommen erst, wenn sie jemand öffnet.
class Vorrat {
  Vorrat(this.db, this.beschaffung, {this.gleichzeitig = 4});

  final AppDatabase db;
  final Dateibeschaffung beschaffung;
  final int gleichzeitig;
  Future<int>? _lauf;
  bool _nochmal = false;

  /// Füllt den Vorrat auf; ein Aufruf während eines Laufs hängt einen
  /// weiteren an. Gibt zurück, wie viele Dateien geholt wurden.
  Future<int> fuelle() {
    if (_lauf != null) {
      _nochmal = true;
      return _lauf!;
    }
    return _lauf = _fuelle().whenComplete(() {
      _lauf = null;
      if (_nochmal) {
        _nochmal = false;
        unawaited(fuelle());
      }
    });
  }

  Future<int> _fuelle() async {
    final pfade = <String>[
      for (final z
          in await db
              .customSelect(
                'SELECT thumbnail_relative_path AS p FROM assets '
                'WHERE thumbnail_relative_path IS NOT NULL '
                'UNION SELECT crop_relative_path FROM faces '
                'WHERE crop_relative_path IS NOT NULL '
                'UNION SELECT cover_face_crop_path FROM people '
                'WHERE cover_face_crop_path IS NOT NULL',
              )
              .get())
        z.read<String>('p'),
    ];
    final fehlt = <String>[];
    for (final p in pfade) {
      try {
        if (!await beschaffung.paths.absolute(p).exists()) fehlt.add(p);
      } on ArgumentError {
        // Ein unbrauchbarer Pfad in der Datenbank – nicht unser Thema.
      }
    }
    var geholt = 0;
    var i = 0;
    Future<void> arbeiter() async {
      while (i < fehlt.length) {
        final p = fehlt[i++];
        try {
          await beschaffung.hole(p);
          geholt++;
        } on Serverfehler catch (f) {
          protokoll('Vorrat: $p – $f');
        }
      }
    }

    await Future.wait([for (var k = 0; k < gleichzeitig; k++) arbeiter()]);
    return geholt;
  }
}
