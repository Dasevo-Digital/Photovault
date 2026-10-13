import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'verbindung.dart';

/// Hochladen in Stücken nach tus 1.0.0 – der Weg, den der Server für
/// Dateien nimmt (Reverse Proxys begrenzen die Grösse einer Anfrage).
///
/// Bricht die Verbindung ab, fragt der Client nach, wie viel angekommen
/// ist (`HEAD`), und macht dort weiter.
class TusHochladen {
  TusHochladen(this.verbindung, {this.stueck = 32 * 1024 * 1024});

  final Serververbindung verbindung;

  /// Wie gross ein Stück höchstens ist – kleiner als das, was ein Proxy
  /// durchlässt (siehe README des Servers: nginx mit 64 MB).
  final int stueck;

  static const _tus = {'tus-resumable': '1.0.0'};

  /// Lädt [datei] nach [pfad] (z. B. `api/v1/hochladen`) und gibt die
  /// Kopfzeilen der letzten Antwort zurück (`pv-ausgang`, `pv-aufnahme`).
  ///
  /// [fortsetzen] ist der Ort eines früher angefangenen Uploads derselben
  /// Datei: Dort geht es an der Stelle weiter, die der Server hat – auch
  /// nach einem Neustart der App. Kennt der Server ihn nicht mehr (oder
  /// passt die Länge nicht), beginnt ein neuer. [angelegt] meldet den Ort
  /// eines neuen Uploads, damit ihn der Aufrufer merken kann.
  ///
  /// [abbrechen] wird vor jedem Stück gefragt; sagt es ja, endet [lade] mit
  /// [Abgebrochen]. Der Upload bleibt dann auf dem Server liegen.
  Future<Map<String, String>> lade(
    File datei,
    String pfad,
    Map<String, String> metadaten, {
    void Function(int erledigt, int gesamt)? fortschritt,
    String? fortsetzen,
    void Function(String ort)? angelegt,
    bool Function()? abbrechen,
  }) async {
    final laenge = await datei.length();
    String? ort;
    var versatz = 0;
    if (fortsetzen != null) {
      final s = await verbindung.anfrage('HEAD', fortsetzen, kopf: _tus);
      if (s.statusCode == 200 &&
          s.headers['upload-length'] == '$laenge' &&
          int.tryParse(s.headers['upload-offset'] ?? '') != null) {
        ort = fortsetzen;
        versatz = int.parse(s.headers['upload-offset']!);
        if (versatz >= laenge) return _ergebnis(ort);
      } else if (s.statusCode != 404 &&
          s.statusCode != 410 &&
          s.statusCode != 200) {
        throw Serverfehler(s.statusCode, s.body);
      }
    }
    if (ort == null) {
      final neu = await verbindung.anfrage(
        'POST',
        pfad,
        kopf: {
          ..._tus,
          'upload-length': '$laenge',
          'upload-metadata': [
            for (final e in metadaten.entries)
              '${e.key} ${base64.encode(utf8.encode(e.value))}',
          ].join(','),
        },
      );
      if (neu.statusCode != 201) {
        throw Serverfehler(neu.statusCode, neu.body);
      }
      ort = neu.headers['location']!;
      angelegt?.call(ort);
    }
    var fehlversuche = 0;
    final roh = await datei.open();
    try {
      while (true) {
        if (abbrechen?.call() ?? false) throw const Abgebrochen();
        final n = min(stueck, laenge - versatz);
        await roh.setPosition(versatz);
        final bytes = await roh.read(n);
        try {
          final r = await verbindung.anfrage(
            'PATCH',
            ort,
            kopf: {
              ..._tus,
              'upload-offset': '$versatz',
              'content-type': 'application/offset+octet-stream',
            },
            inhalt: bytes,
          );
          if (r.statusCode == 409) {
            versatz = int.parse(r.headers['upload-offset']!);
            continue;
          }
          if (r.statusCode != 204) throw Serverfehler(r.statusCode, r.body);
          versatz = int.parse(r.headers['upload-offset']!);
          fehlversuche = 0;
          fortschritt?.call(versatz, laenge);
          if (versatz >= laenge) return r.headers;
        } on KeineVerbindung {
          if (++fehlversuche > 5) rethrow;
          await Future<void>.delayed(Duration(seconds: 1 << fehlversuche));
          final s = await verbindung.anfrage('HEAD', ort, kopf: _tus);
          if (s.statusCode != 200) throw Serverfehler(s.statusCode, s.body);
          versatz = int.parse(s.headers['upload-offset']!);
          // Das letzte Stück kam an, nur die Antwort nicht: Das Ergebnis
          // des Imports steht im Stand.
          if (versatz >= laenge) return await _ergebnis(ort);
        }
      }
    } finally {
      await roh.close();
    }
  }

  /// Das Ergebnis eines vollständig angekommenen Uploads aus seinem Stand
  /// (`GET`), in der Form der Kopfzeilen der letzten Antwort. Wartet kurz,
  /// falls der Server noch importiert.
  Future<Map<String, String>> _ergebnis(String ort) async {
    for (var i = 0; i < 60; i++) {
      final s = await verbindung.anfrage('GET', ort);
      if (s.statusCode != 200) throw Serverfehler(s.statusCode, s.body);
      final j = jsonDecode(s.body);
      final e = j is Map ? j['ergebnis'] : null;
      if (e is Map && e['ausgang'] is String) {
        return {
          'pv-ausgang': e['ausgang']! as String,
          if (e['aufnahme'] is String) 'pv-aufnahme': e['aufnahme']! as String,
        };
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw KeineVerbindung(TimeoutException('tus', const Duration(minutes: 1)));
  }
}

/// [TusHochladen.lade] hat auf Wunsch aufgehört; der Upload lässt sich mit
/// seinem Ort fortsetzen.
class Abgebrochen implements Exception {
  const Abgebrochen();

  @override
  String toString() => 'Abgebrochen';
}
