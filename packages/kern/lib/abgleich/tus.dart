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
  Future<Map<String, String>> lade(
    File datei,
    String pfad,
    Map<String, String> metadaten, {
    void Function(int erledigt, int gesamt)? fortschritt,
  }) async {
    final laenge = await datei.length();
    final angelegt = await verbindung.anfrage(
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
    if (angelegt.statusCode != 201) {
      throw Serverfehler(angelegt.statusCode, angelegt.body);
    }
    final ort = angelegt.headers['location']!;
    var versatz = 0;
    var kopf = angelegt.headers;
    var fehlversuche = 0;
    final roh = await datei.open();
    try {
      while (true) {
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
          kopf = r.headers;
          fehlversuche = 0;
          fortschritt?.call(versatz, laenge);
          if (versatz >= laenge) return kopf;
        } on KeineVerbindung {
          if (++fehlversuche > 5) rethrow;
          await Future<void>.delayed(Duration(seconds: 1 << fehlversuche));
          final s = await verbindung.anfrage('HEAD', ort, kopf: _tus);
          if (s.statusCode != 200) throw Serverfehler(s.statusCode, s.body);
          versatz = int.parse(s.headers['upload-offset']!);
        }
      }
    } finally {
      await roh.close();
    }
  }
}
