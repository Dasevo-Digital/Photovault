import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:kern/abgleich/tus.dart';
import 'package:kern/abgleich/verbindung.dart';

import 'kamerarolle.dart';
import 'stand.dart';

/// Ein Durchgang der Sicherung: was in der Kamerarolle noch nicht sicher
/// ist, zum Server.
///
/// Je Gruppe von Einträgen: Dateien bereitstellen, Prüfsummen rechnen, den
/// Server fragen, was er davon schon hat (`POST /api/v1/pruefsummen`), und
/// nur den Rest hochladen. Nach einem Umzug vom Rechner liegt meist das
/// meiste schon dort; Lesen kostet am Telefon Sekunden, Hochladen Stunden.
///
/// Ein abgebrochener Upload geht beim nächsten Lauf an der Stelle weiter,
/// die der Server hat (der Ort steht im [Sicherungsstand]). Ohne Netz endet
/// der Lauf; das ist kein Fehler des Eintrags.
class Sicherungslauf {
  Sicherungslauf({
    required this.rolle,
    required this.verbindung,
    required this.stand,
    required this.wer,
    this.stueck = 32 * 1024 * 1024,
    this.gruppe = 20,
    this.gruppeBytes = 256 * 1024 * 1024,
  });

  final Kamerarolle rolle;
  final Serververbindung verbindung;
  final Sicherungsstand stand;

  /// Wer läuft (`app`, `hintergrund`) – für die Sperre.
  final String wer;

  /// Grösse der Stücke beim Hochladen (siehe [TusHochladen]).
  final int stueck;

  /// Wie viele Einträge auf einmal geprüft werden …
  final int gruppe;

  /// … und wie viel Platz ihre Dateien dabei höchstens belegen. Android
  /// und iOS stellen jedes Original als Kopie im Zwischenspeicher bereit;
  /// zwanzig Videos zu je zwei Gigabyte lägen sonst gleichzeitig dort.
  final int gruppeBytes;

  /// Läuft, bis alles sicher ist, [abbrechen] ja sagt oder das Netz fehlt.
  /// Wirft [Gesperrt], wenn schon ein anderer Lauf arbeitet.
  Future<Laufbericht> laufe({
    bool Function()? abbrechen,
    void Function(Fortschritt)? meldung,
  }) async {
    if (!stand.sperre(wer)) throw const Gesperrt();
    var hochgeladen = 0, vorhanden = 0, fehlgeschlagen = 0;
    var gesamt = 0, sicher = 0;
    var vollstaendig = false;
    var offen = <Rolleneintrag>[];
    void melde({String? datei, int? bytes, int? von}) => meldung?.call(
      Fortschritt(
        gesamt: gesamt,
        sicher: sicher,
        hochgeladen: hochgeladen,
        vorhanden: vorhanden,
        fehlgeschlagen: fehlgeschlagen,
        datei: datei,
        bytes: bytes,
        von: von,
      ),
    );
    try {
      final e = stand.einstellungen;
      final eintraege = await rolle.eintraege(videos: e.videos);
      final bekannt = stand.bekannt();
      for (final x in eintraege) {
        final ms = x.geaendert.millisecondsSinceEpoch;
        if (bekannt.erledigt[x.id] == ms) {
          sicher++;
        } else if (bekannt.abgelehnt[x.id] == ms ||
            bekannt.pausiert.contains(x.id)) {
          fehlgeschlagen++;
        } else {
          offen.add(x);
        }
      }
      gesamt = eintraege.length;
      melde();

      var i = 0;
      while (i < offen.length) {
        if ((abbrechen?.call() ?? false) || !stand.sperre(wer)) break;
        final bereit = <Rolleneintrag, List<(Rollendatei, String)>>{};
        final ergebnis = <String, _Erfolg>{};
        var bytes = 0;
        try {
          while (i < offen.length &&
              bereit.length + ergebnis.length < gruppe &&
              bytes < gruppeBytes) {
            final x = offen[i++];
            final d = await _bereitstellen(x, ergebnis);
            if (d == null) continue;
            bereit[x] = d;
            for (final (f, _) in d) {
              bytes += await f.datei.length();
            }
          }
          await _sichere(bereit, ergebnis, abbrechen: abbrechen, melde: melde);
          for (final r in ergebnis.values) {
            switch (r) {
              case _Erfolg.hochgeladen:
                hochgeladen++;
                sicher++;
              case _Erfolg.vorhanden:
                vorhanden++;
                sicher++;
              case _Erfolg.fehlgeschlagen:
                fehlgeschlagen++;
            }
          }
          melde();
        } finally {
          await rolle.aufraeumen();
        }
      }
      vollstaendig = sicher + fehlgeschlagen >= gesamt;
    } on Abgebrochen {
      // Die Zeit ist um; der Upload geht beim nächsten Mal weiter.
    } on KeineVerbindung {
      // Ohne Netz geht es beim nächsten Lauf weiter.
    } finally {
      stand.gibFrei(wer);
    }
    final bericht = Laufbericht(
      ende: DateTime.now(),
      gesamt: gesamt,
      offen: gesamt - sicher - fehlgeschlagen,
      hochgeladen: hochgeladen,
      vorhanden: vorhanden,
      fehlgeschlagen: fehlgeschlagen,
      vollstaendig: vollstaendig,
    );
    stand.letzterLauf = bericht;
    return bericht;
  }

  /// Die Dateien eines Eintrags samt Prüfsummen; `null` (und ein
  /// vermerkter Fehlschlag), wenn sie sich nicht bereitstellen lassen.
  Future<List<(Rollendatei, String)>?> _bereitstellen(
    Rolleneintrag x,
    Map<String, _Erfolg> aus,
  ) async {
    try {
      final d = await x.dateien();
      if (d == null || d.isEmpty) {
        _scheitert(x, 'Datei nicht verfügbar', aus);
        return null;
      }
      return [for (final f in d) (f, await _pruefsumme(f.datei.path))];
    } on FileSystemException catch (f) {
      _scheitert(x, f.message, aus);
      return null;
    }
  }

  /// Sichert, was [bereit] liegt, und trägt das Ergebnis in [aus] ein.
  /// [Abgebrochen], [KeineVerbindung] und eine abgelaufene Anmeldung
  /// beenden den Lauf; alles andere trifft nur den einen Eintrag.
  Future<void> _sichere(
    Map<Rolleneintrag, List<(Rollendatei, String)>> bereit,
    Map<String, _Erfolg> aus, {
    required bool Function()? abbrechen,
    required void Function({String? datei, int? bytes, int? von}) melde,
  }) async {
    if (bereit.isEmpty) return;

    // Was der Server schon hat. Ein Server ohne diese Frage nimmt
    // Dubletten beim Import ebenfalls nicht auf; dann eben hochladen.
    var schonDa = <String, String>{};
    try {
      final antwort = await verbindung.schicke('api/v1/pruefsummen', {
        'pruefsummen': {
          for (final l in bereit.values)
            for (final (_, s) in l) s,
        }.toList(),
      });
      schonDa = (antwort['vorhanden']! as Map).cast<String, String>();
    } on Serverfehler catch (f) {
      if (f.status != 404) rethrow;
    }

    // Der Rest geht hoch.
    for (final MapEntry(key: x, value: liste) in bereit.entries) {
      var hoch = false;
      var endgueltig = false;
      String? aufnahme;
      String? abgelehnt;
      for (final (f, summe) in liste) {
        final da = schonDa[summe];
        if (da != null) {
          aufnahme ??= da;
          continue;
        }
        final Map<String, String> kopf;
        try {
          kopf = await TusHochladen(verbindung, stueck: stueck).lade(
            f.datei,
            'api/v1/hochladen',
            {
              'filename': f.name,
              'geaendert': '${x.aufgenommen.millisecondsSinceEpoch}',
              'sha256': summe,
            },
            fortsetzen: stand.ort(x.id, f.teil, summe),
            angelegt: (ort) => stand.merkeOrt(x.id, f.teil, summe, ort),
            abbrechen: abbrechen,
            fortschritt: (bytes, von) =>
                melde(datei: f.name, bytes: bytes, von: von),
          );
        } on Serverfehler catch (s) {
          if (s.abgemeldet) rethrow;
          abgelehnt = 'Server: ${s.status}';
          break;
        } on FileSystemException catch (s) {
          abgelehnt = s.message;
          break;
        }
        switch (kopf['pv-ausgang']) {
          case 'imported':
            hoch = true;
          case 'duplicateSkipped':
            break;
          default:
            // Der Import scheiterte an der Datei selbst (etwa ein Format,
            // das der Server nicht liest). Noch einmal hochladen hiesse,
            // dasselbe Ergebnis mit derselben Bandbreite zu bezahlen.
            abgelehnt = 'Der Server konnte ${f.name} nicht aufnehmen';
            endgueltig = true;
        }
        if (abgelehnt != null) break;
        aufnahme ??= kopf['pv-aufnahme'];
      }
      if (abgelehnt != null) {
        if (endgueltig) {
          stand.erledige(x.id, x.geaendert, ausgang: 'abgelehnt');
          aus[x.id] = _Erfolg.fehlgeschlagen;
        } else {
          _scheitert(x, abgelehnt, aus);
        }
        continue;
      }
      stand.erledige(
        x.id,
        x.geaendert,
        ausgang: hoch ? 'hochgeladen' : 'vorhanden',
        aufnahme: aufnahme,
      );
      aus[x.id] = hoch ? _Erfolg.hochgeladen : _Erfolg.vorhanden;
    }
  }

  void _scheitert(Rolleneintrag x, String grund, Map<String, _Erfolg> aus) {
    stand.fehlschlag(x.id, grund);
    aus[x.id] = _Erfolg.fehlgeschlagen;
  }

  /// SHA-256 wie beim Import auf dem Server – in einem eigenen Isolate,
  /// damit ein Video von mehreren Gigabyte die Oberfläche nicht anhält.
  static Future<String> _pruefsumme(String pfad) => Isolate.run(
    () async => (await sha256.bind(File(pfad).openRead()).first).toString(),
  );
}

enum _Erfolg { hochgeladen, vorhanden, fehlgeschlagen }

/// Ein anderer Lauf (App oder Hintergrund) arbeitet gerade.
class Gesperrt implements Exception {
  const Gesperrt();
}

/// Wie weit ein Lauf ist.
class Fortschritt {
  const Fortschritt({
    required this.gesamt,
    required this.sicher,
    required this.hochgeladen,
    required this.vorhanden,
    required this.fehlgeschlagen,
    this.datei,
    this.bytes,
    this.von,
  });

  /// Einträge in den gewählten Alben.
  final int gesamt;

  /// Davon sicher (auch aus früheren Läufen).
  final int sicher;

  /// In diesem Lauf hochgeladen bzw. als schon vorhanden erkannt.
  final int hochgeladen;
  final int vorhanden;

  /// Wegen eines Fehlers nicht sicher: vom Server abgelehnt, nach
  /// mehreren Fehlschlägen pausiert oder in diesem Lauf gescheitert.
  final int fehlgeschlagen;

  /// Die Datei, die gerade hochgeht, und wie viel davon.
  final String? datei;
  final int? bytes;
  final int? von;
}
