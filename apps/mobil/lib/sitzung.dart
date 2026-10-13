import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/dateibeschaffung.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'sicherung/dienst.dart';

enum Sitzungszustand { laedt, abgemeldet, bereit }

/// Die Verbindung des Telefons mit seinem Server und die Kopie der
/// Bibliothek darauf.
///
/// Das Telefon hält wie der verbundene Desktop eine Kopie der Bibliothek
/// (siehe `Abgleich` im Kern): Zeitleiste, Alben, Personen, Karte und die
/// Suche im Text laufen hier, ohne Netz und ohne Wartezeit. Bilder kommen
/// vom Server, wenn sie gebraucht werden, und bleiben dann hier liegen.
/// Änderungen (Favorit, Papierkorb, Album) gehen als Befehle zum Server,
/// auch nach einer Zeit ohne Verbindung.
class Sitzung extends ChangeNotifier {
  Sitzung({Future<Directory> Function()? ordner})
    : _ordner = ordner ?? vorgabeOrdner;

  final Future<Directory> Function() _ordner;

  /// Wo die Kopie liegt – auch die Hintergrundaufgabe der Sicherung
  /// findet sie dort.
  static Future<Directory> vorgabeOrdner() async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'bibliothek'),
  );

  Sitzungszustand _zustand = Sitzungszustand.laedt;
  Sitzungszustand get zustand => _zustand;

  Verbindungsdatei? verbindung;
  late AppDatabase db;
  late StoragePaths paths;
  Abgleich? abgleich;
  Abgleichszustand? abgleichszustand;

  /// Die Sicherung der Kamerarolle (siehe `sicherung/`).
  Sicherungsdienst? sicherung;
  StreamSubscription<Abgleichszustand>? _abo;

  /// Öffnet die Kopie, wenn es eine gibt; sonst geht es zur Anmeldung.
  Future<void> starte() async {
    final ordner = await _ordner();
    final v = await Verbindungsdatei.lies(ordner);
    if (v == null ||
        !await File(p.join(ordner.path, 'library.sqlite')).exists()) {
      _setze(Sitzungszustand.abgemeldet);
      return;
    }
    await _oeffne(ordner, v);
  }

  /// Nach der Anmeldung: holt die Bibliothek vom Server und öffnet sie.
  Future<void> verbinde({
    required Uri server,
    required String konto,
    required String geraet,
    required String token,
  }) async {
    final ordner = await _ordner();
    if (await ordner.exists()) await ordner.delete(recursive: true);
    await ordner.create(recursive: true);
    final s = Serververbindung(server, token);
    try {
      await Abgleich.holeAbzug(s, File(p.join(ordner.path, 'library.sqlite')));
    } finally {
      s.schliesse();
    }
    final v = Verbindungsdatei(
      server: server,
      konto: konto,
      geraet: geraet,
      token: token,
    );
    await v.schreibe(ordner);
    await _oeffne(ordner, v);
  }

  Future<void> _oeffne(Directory ordner, Verbindungsdatei v) async {
    db = await AppDatabase.open(ordner);
    paths = await StoragePaths.oeffne(
      Directory(p.join(ordner.path, 'library')),
    );
    final s = Serververbindung(v.server, v.token);
    final a = Abgleich(db, s);
    await a.richteEin();
    Dateibeschaffung(paths, s).binde();
    _abo = a.zustand.listen((z) {
      final vorher = abgleichszustand;
      abgleichszustand = z;
      if (vorher == null ||
          vorher.erreichbar != z.erreichbar ||
          vorher.ausstehend != z.ausstehend ||
          vorher.abgemeldet != z.abgemeldet) {
        notifyListeners();
      }
    });
    a.starte();
    verbindung = v;
    abgleich = a;
    final d = sicherung = Sicherungsdienst(
      ordner: ordner,
      server: v.server,
      token: v.token,
    );
    _setze(Sitzungszustand.bereit);
    unawaited(d.starte());
  }

  /// Den Text einer Bildsuche vom Server einbetten lassen (siehe dort
  /// `Suchapi`). `null`, wenn der Server dafür kein Modell hat.
  Future<Float32List?> textvektor(String text) async {
    try {
      final a = await abgleich!.verbindung.schicke('api/v1/suche/text', {
        'text': text,
      });
      return Float32List.fromList([
        for (final w in (a['vektor']! as List)) (w as num).toDouble(),
      ]);
    } on Serverfehler catch (f) {
      if (f.status == 404) return null;
      rethrow;
    }
  }

  /// Gleicht sofort ab – für „nach unten ziehen“.
  Future<void> gleicheAb() async {
    final a = abgleich;
    if (a == null) return;
    await a.sende();
    await a.empfange();
  }

  /// Meldet das Telefon beim Server ab und löscht die Kopie samt aller
  /// geladenen Bilder. Auf dem Server bleibt alles, wie es ist.
  Future<void> abmelden() async {
    final a = abgleich;
    if (a != null) {
      try {
        await a.verbindung.schicke('api/v1/abmelden', const {});
      } catch (_) {
        // Ohne Verbindung abgemeldet: Das Token gilt dort weiter, bis es
        // auf einem anderen Gerät oder auf dem Server abgemeldet wird.
      }
      await sicherung?.streicheAufgaben();
      await beende();
    }
    verbindung = null;
    abgleichszustand = null;
    final ordner = await _ordner();
    if (await ordner.exists()) await ordner.delete(recursive: true);
    _setze(Sitzungszustand.abgemeldet);
  }

  void _setze(Sitzungszustand z) {
    _zustand = z;
    notifyListeners();
  }

  /// Hält den Abgleich an und schliesst die Kopie; die Verbindung bleibt
  /// bestehen, `starte` öffnet sie wieder.
  Future<void> beende() async {
    final a = abgleich;
    if (a == null) return;
    abgleich = null;
    sicherung?.dispose();
    sicherung = null;
    await _abo?.cancel();
    await a.beende();
    a.verbindung.schliesse();
    await db.close();
  }

  @override
  void dispose() {
    unawaited(beende());
    super.dispose();
  }
}
