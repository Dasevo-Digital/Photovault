import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/dateibeschaffung.dart';
import 'package:kern/abgleich/sicherung.dart';
import 'package:kern/abgleich/speicher.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/abgleich/zwischenspeicher.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/listengliederung.dart';
import 'package:kern/services/listenspalten.dart';
import 'package:kern/services/rasterstufen.dart';
import 'package:kern/services/sortierung.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'gemeinsam.dart';
import 'offline_alben.dart';
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
  OfflineAlben? offlineAlben;
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
    offlineAlben = await OfflineAlben.oeffne(
      File(p.join(ordner.path, 'offline_alben.json')),
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
          vorher.ungeklaert != z.ungeklaert ||
          vorher.ausstehend != z.ausstehend ||
          vorher.abgemeldet != z.abgemeldet ||
          vorher.serverSchema != z.serverSchema) {
        notifyListeners();
      }
    });
    a.starte();
    verbindung = v;
    abgleich = a;
    // Widget und Teilen-Erweiterung sprechen selbst mit dem Server.
    unawaited(Gemeinsam.setze(v.server, v.token));
    final d = sicherung = Sicherungsdienst(
      ordner: ordner,
      server: v.server,
      token: v.token,
    );
    _setze(Sitzungszustand.bereit);
    unawaited(d.starte());
    unawaited(pruefeServerspeicher());
    unawaited(pruefeServersicherung());
    unawaited(holeServerfassung());
    _speicherUhr = Timer.periodic(const Duration(minutes: 15), (_) {
      pruefeServerspeicher();
      pruefeServersicherung();
      pflegeOfflineUndZwischenspeicher();
    });
    unawaited(pflegeOfflineUndZwischenspeicher());
  }

  /// Vorschauen und Originale, die das Telefon vom Server geholt hat.
  Zwischenspeicher get zwischenspeicher => Zwischenspeicher(paths);

  /// Die Grenze in MB; 0 heisst ohne Grenze.
  int get zwischenspeicherGrenzeMb =>
      verbindung?.zwischenspeicherMb ?? Zwischenspeicher.vorgabeMb;

  /// Hält den Zwischenspeicher unter seiner Grenze.
  Future<void> pflegeZwischenspeicher() async {
    final mb = zwischenspeicherGrenzeMb;
    if (mb <= 0 || abgleich == null) return;
    final behalten = await offlineAlben?.geschuetztePfade(db) ?? <String>{};
    await zwischenspeicher.begrenze(mb * 1024 * 1024, behalten: behalten);
  }

  Future<void>? _offlinePflege;

  /// Ob das Telefon gerade im WLAN (oder über Ethernet) hängt – für Tests
  /// ersetzbar.
  Future<bool> Function() imWlan = _imWlan;

  static Future<bool> _imWlan() async {
    final art = await Connectivity().checkConnectivity();
    return art.contains(ConnectivityResult.wifi) ||
        art.contains(ConnectivityResult.ethernet);
  }

  /// Ob die Pflege angeheftete Alben jetzt nachladen darf: nur im WLAN
  /// (#220). Die Pflege läuft alle 15 Minuten von selbst, und neue
  /// Aufnahmen eines Albums können Originale und Videos von Gigabytes sein –
  /// über Mobilfunk käme das ungefragt aufs Datenvolumen. Wer ein Album
  /// ausdrücklich anheftet, bekommt es sofort, auch unterwegs.
  Future<bool> darfOfflineNachladen() async =>
      (offlineAlben?.albumIds.isNotEmpty ?? false) && await imWlan();

  /// Hält neue Aufnahmen angehefteter Alben nach und räumt erst danach den
  /// übrigen Cache auf. Ein zweiter Zeitgeber startet keinen parallelen Lauf.
  Future<void> pflegeOfflineUndZwischenspeicher() {
    final laufend = _offlinePflege;
    if (laufend != null) return laufend;
    final lauf = () async {
      try {
        if (await darfOfflineNachladen()) {
          await offlineAlben?.aktualisiere(db, paths);
        }
      } catch (_) {
        // Ohne Server bleibt der bisherige Offline-Stand erhalten. Der
        // nächste Pflegegang versucht nur die noch fehlenden Dateien erneut.
      }
      await pflegeZwischenspeicher();
    }();
    _offlinePflege = lauf;
    return lauf.whenComplete(() {
      if (identical(_offlinePflege, lauf)) _offlinePflege = null;
    });
  }

  bool istAlbumOffline(String albumId) =>
      offlineAlben?.enthaelt(albumId) ?? false;

  /// Ändert die gerätebezogene Offline-Auswahl. Beim Anheften bleibt die
  /// Absicht auch bei einem Verbindungsabbruch gespeichert; der nächste
  /// Pflegegang setzt das unvollständige Herunterladen fort.
  Future<int> setzeAlbumOffline(String albumId, bool offline) async {
    final alben = offlineAlben;
    if (alben == null) throw StateError('pv_offline_alben_nicht_bereit');
    await alben.setze(albumId, offline);
    notifyListeners();
    if (!offline) {
      await pflegeZwischenspeicher();
      return 0;
    }
    final anzahl = await alben.holeAlbum(db, paths, albumId);
    // Die Anzeige des belegten Platzes (AlbumSeite) rechnet neu.
    notifyListeners();
    await pflegeZwischenspeicher();
    return anzahl;
  }

  /// Leert nur den entbehrlichen Cache; ausdrücklich angeheftete Alben
  /// bleiben auch bei diesem manuellen Schritt offline verfügbar.
  Future<int> leereZwischenspeicher() async => zwischenspeicher.leere(
    behalten: await offlineAlben?.geschuetztePfade(db) ?? <String>{},
  );

  /// Setzt die Grenze (0 = ohne) und räumt gleich auf.
  Future<void> setzeZwischenspeicherGrenze(int mb) async {
    final v = verbindung;
    if (v == null) return;
    verbindung = v.mitZwischenspeicher(mb);
    await verbindung!.schreibe(await _ordner());
    notifyListeners();
    await pflegeZwischenspeicher();
  }

  /// Spalten des Rasters, mit zwei Fingern oder den Knöpfen der
  /// Ansichtsleiste einstellbar (2 bis 6).
  static const spaltenVorgabe = 4;
  int get rasterspalten =>
      verbindung?.rasterspalten ?? _spaltenHier ?? spaltenVorgabe;

  // Ohne Verbindungsdatei (in Tests) gilt die Wahl bis zum Ende.
  int? _spaltenHier;
  int? _sortierungHier;
  int? _formHier;
  bool _nurMonateHier = false;
  bool _listeHier = false;
  int? _gliederungHier;
  String? _spaltenwahlHier;

  Future<void> setzeRasterspalten(int n) async {
    if (n == rasterspalten) return;
    final v = verbindung;
    if (v == null) {
      _spaltenHier = n;
      notifyListeners();
      return;
    }
    verbindung = v.mitRasterspalten(n);
    notifyListeners();
    await verbindung!.schreibe(await _ordner());
  }

  /// Die Ansicht der Zeitleiste (Issue #194), wie am Rechner und im
  /// Browser: Reihenfolge, Form und ob nur nach Monaten gegliedert wird.
  /// Gilt für dieses Gerät.
  Rastersortierung get sortierung => rastersortierung(
    verbindung?.sortierung ?? _sortierungHier ?? rastersortierungVorgabe.index,
  );
  Zeitleistenform get form => zeitleisteForm(
    verbindung?.form ?? _formHier ?? zeitleisteFormVorgabe.index,
  );
  bool get nurMonate => verbindung?.nurMonate ?? _nurMonateHier;

  /// Liste statt Raster (Issue #195), wie am Rechner und im Browser.
  bool get alsListe => verbindung?.liste ?? _listeHier;
  ListenGruppierung get gliederung {
    final i = verbindung?.gliederung ?? _gliederungHier ?? 0;
    return i >= 0 && i < ListenGruppierung.values.length
        ? ListenGruppierung.values[i]
        : ListenGruppierung.monat;
  }

  Listenspaltenwahl get listenspalten =>
      Listenspaltenwahl.ausText(verbindung?.listenspalten ?? _spaltenwahlHier);

  Future<void> setzeAnsicht({
    Rastersortierung? sortierung,
    Zeitleistenform? form,
    bool? nurMonate,
    bool? alsListe,
    ListenGruppierung? gliederung,
    Listenspaltenwahl? listenspalten,
  }) async {
    final v = verbindung;
    if (v == null) {
      _sortierungHier = sortierung?.index ?? _sortierungHier;
      _formHier = form?.index ?? _formHier;
      _nurMonateHier = nurMonate ?? _nurMonateHier;
      _listeHier = alsListe ?? _listeHier;
      _gliederungHier = gliederung?.index ?? _gliederungHier;
      _spaltenwahlHier = listenspalten?.alsText() ?? _spaltenwahlHier;
      notifyListeners();
      return;
    }
    verbindung = v.mitAnsicht(
      sortierung: sortierung?.index,
      form: form?.index,
      nurMonate: nurMonate,
      liste: alsListe,
      gliederung: gliederung?.index,
      listenspalten: listenspalten?.alsText(),
    );
    notifyListeners();
    await verbindung!.schreibe(await _ordner());
  }

  /// Die Sprache der App, wie in den Einstellungen gewählt; `null` heisst:
  /// die des Telefons.
  String? get sprache => verbindung?.sprache;

  Future<void> setzeSprache(String? s) async {
    final v = verbindung;
    if (v == null || s == sprache) return;
    verbindung = v.mitSprache(s);
    await verbindung!.schreibe(await _ordner());
    notifyListeners();
  }

  /// Welche Fassung der Server ist (`/api/v1/zustand`), für die Kontoseite.
  String? serverfassung;

  Future<void> holeServerfassung() async {
    final a = abgleich;
    if (a == null) return;
    try {
      final z = await a.verbindung.hole('api/v1/zustand');
      final f = z['fassung'] as String?;
      final c = z['commit'] as String?;
      serverfassung = f == null
          ? null
          : (c == null || c.isEmpty ? f : '$f ($c)');
      notifyListeners();
    } on KeineVerbindung {
      // Beim nächsten Mal.
    } on Serverfehler {
      // Ebenso.
    }
  }

  /// Die Sicherung des Servers – nur für Verwalter, sonst `null`.
  Serversicherungsstand? serversicherung;

  Future<void> pruefeServersicherung() async {
    final a = abgleich;
    if (a == null) return;
    try {
      final neu = await Serversicherungsstand.hole(a.verbindung);
      final vorher = serversicherung;
      serversicherung = neu;
      if (vorher?.stufe != neu?.stufe || vorher?.ende != neu?.ende) {
        notifyListeners();
      }
    } on KeineVerbindung {
      // Beim nächsten Mal.
    } on Serverfehler {
      // Ebenso.
    }
  }

  /// Wie es um den Speicher des Servers steht (siehe dort
  /// `Speicherwaechter`); `null`, solange unbekannt.
  Serverspeicher? serverspeicher;
  Timer? _speicherUhr;

  Future<void> pruefeServerspeicher() async {
    final a = abgleich;
    if (a == null) return;
    try {
      final neu = await Serverspeicher.hole(a.verbindung);
      final vorher = serverspeicher;
      serverspeicher = neu;
      if (Serverspeicher.anders(vorher, neu)) notifyListeners();
    } on KeineVerbindung {
      // Dann beim nächsten Mal.
    } on Serverfehler {
      // Ebenso.
    }
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
    await Gemeinsam.loesche();
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
    _speicherUhr?.cancel();
    serverspeicher = null;
    serversicherung = null;
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
