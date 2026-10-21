import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:kern/db/database.dart';

import '../lokal/ungesichert.dart';
import 'freigabe.dart';
import 'hintergrund.dart';
import 'lauf.dart';
import 'photo_manager_rolle.dart';
import 'stand.dart';
import 'telefonloeschung.dart';

/// Ob die App die Fotos lesen darf.
enum Zugriff { unbekannt, erlaubt, teilweise, verweigert }

/// Die Sicherung der Kamerarolle, solange die App offen ist – und das
/// Einplanen für danach (siehe `hintergrund.dart`).
///
/// Läuft beim Start, beim Zurückkehren in die App und wenn neue Fotos
/// dazukommen. Geht die App unter Android mit offener Arbeit in den
/// Hintergrund, übernimmt ein Vordergrunddienst ([imHintergrund]).
class Sicherungsdienst extends ChangeNotifier {
  Sicherungsdienst({
    required Directory ordner,
    required Uri server,
    required String token,
  }) : _stand = Sicherungsstand.oeffne(ordner),
       _verbindung = Serververbindung(server, token);

  final Sicherungsstand _stand;
  final Serververbindung _verbindung;

  Sicherungseinstellungen get einstellungen => _stand.einstellungen;

  Zugriff zugriff = Zugriff.unbekannt;

  bool get laeuft => _laeuft;
  var _laeuft = false;
  var _abbruch = false;

  /// Wie weit der laufende Lauf ist.
  Fortschritt? fortschritt;

  /// Was auf dem Telefon liegt und noch nicht auf dem Server – für die
  /// Zeitleiste (Issue #127); `null`, solange noch nicht nachgesehen.
  List<LokaleAufnahme>? ungesichert;

  /// Sieht nach, was noch nicht gesichert ist – nach jedem Lauf und wenn
  /// Fotos dazukommen. Ohne Sicherung oder Zugriff: nichts.
  Future<void> zaehleUngesicherte() async {
    if (!einstellungen.an ||
        (zugriff != Zugriff.erlaubt && zugriff != Zugriff.teilweise)) {
      ungesichert = const [];
    } else {
      try {
        final alle = await PhotoManagerRolle().eintraege(videos: true);
        ungesichert = nochNichtGesichert(alle, _stand.bekannt().erledigt);
      } on MissingPluginException {
        return; // in Tests ohne Telefon
      }
    }
    if (!_beendet) notifyListeners();
  }

  /// Warum gerade nicht gesichert wird, obwohl etwas offen ist.
  Wartegrund? wartet;

  /// Der letzte Fehler, der den ganzen Lauf beendete.
  Object? fehler;

  Laufbericht? get letzterLauf => _stand.letzterLauf;
  Map<String, String> get fehlgeschlagen => _stand.fehler;
  int get abgelehnt => _stand.anzahlAbgelehnt;
  Map<String, String> get abgelehntGruende => _stand.abgelehnteGruende;

  Timer? _nachAenderung;
  DateTime _gemeldet = DateTime(0);
  var _beendet = false;

  static const _option = PermissionRequestOption(
    androidPermission: AndroidPermission(
      type: RequestType.common,
      mediaLocation: true,
    ),
  );

  /// Nach dem Öffnen der Kopie: Zugriff prüfen (ohne zu fragen), Aufgabe
  /// einplanen, sichern.
  Future<void> starte() async {
    if (!einstellungen.an) return;
    try {
      zugriff = _zugriffAus(
        await PhotoManager.getPermissionState(requestOption: _option),
      );
      await planeSicherung(einstellungen);
      _beobachte();
    } on MissingPluginException {
      return; // in Tests ohne Telefon
    }
    notifyListeners();
    unawaited(sichere());
  }

  static Zugriff _zugriffAus(PermissionState s) => switch (s) {
    PermissionState.authorized => Zugriff.erlaubt,
    PermissionState.limited => Zugriff.teilweise,
    PermissionState.notDetermined => Zugriff.unbekannt,
    _ => Zugriff.verweigert,
  };

  /// Schaltet die Sicherung ein; fragt dafür nach dem Zugriff. Gibt
  /// zurück, ob sie läuft.
  Future<bool> schalteEin() async {
    zugriff = _zugriffAus(
      await PhotoManager.requestPermissionExtend(requestOption: _option),
    );
    if (zugriff == Zugriff.verweigert || zugriff == Zugriff.unbekannt) {
      notifyListeners();
      return false;
    }
    await setze(einstellungen.mit(an: true));
    _beobachte();
    unawaited(sichere());
    return true;
  }

  Future<void> schalteAus() async {
    _abbruch = true;
    _beobachteNicht();
    ungesichert = const [];
    await setze(einstellungen.mit(an: false));
  }

  Future<void> setze(Sicherungseinstellungen e) async {
    _stand.einstellungen = e;
    await planeSicherung(e);
    notifyListeners();
  }

  /// Die Auswahl der Fotos ändern (iOS: „Ausgewählte Fotos“).
  Future<void> auswahlAendern() async {
    await PhotoManager.presentLimited();
    unawaited(sichere());
  }

  Future<void> oeffneEinstellungen() => PhotoManager.openSetting();

  /// Speicher auf dem Telefon freigeben – mit der Kopie [db] als Beleg,
  /// dass die Aufnahmen auf dem Server noch da sind.
  Speicherfreigabe freigabe(AppDatabase db) => Speicherfreigabe(
    stand: _stand,
    rolle: PhotoManagerRolle(alben: einstellungen.alben),
    db: db,
  );

  /// Aufnahmen auch aus der Fotomediathek löschen (#205) – über alle
  /// Alben, nicht nur die gesicherten.
  Telefonloeschung loeschung(AppDatabase db) =>
      Telefonloeschung(stand: _stand, rolle: PhotoManagerRolle(), db: db);

  /// Was scheiterte, noch einmal versuchen.
  void versucheFehlerErneut() {
    _stand.vergissFehler();
    notifyListeners();
    unawaited(sichere());
  }

  /// „Jetzt sichern“ von Hand (#204): anders als [sichere] still nie.
  ///
  /// Der Knopf stand in der Zeitleiste neben „N Aufnahmen nur auf dem
  /// Telefon“, und ein Tipp darauf tat oft sichtbar nichts. [sichere]
  /// kehrt aus gutem Grund wortlos zurück, wenn es von selbst läuft –
  /// ohne Zugriff, ohne WLAN bei „Nur im WLAN“ (die Vorgabe), während
  /// eines Laufs im Hintergrund –, und überspringt, was dreimal scheiterte
  /// (zwölf Stunden Pause) oder was der Server abgelehnt hat. Gezählt
  /// wurden beide in der Zeitleiste trotzdem. Wer von Hand tippt, will
  /// es jetzt: Darum hier noch einmal alles versuchen, nach dem Zugriff
  /// fragen und sagen, wie es ausging.
  ///
  /// [mobil] sichert dieses eine Mal auch ohne WLAN.
  Future<Sicherungsantwort> sichereJetzt({bool mobil = false}) async {
    if (!einstellungen.an) return Sicherungsantwort.aus;
    if (_laeuft) return Sicherungsantwort.laeuft;
    if (zugriff != Zugriff.erlaubt && zugriff != Zugriff.teilweise) {
      zugriff = _zugriffAus(
        await PhotoManager.requestPermissionExtend(requestOption: _option),
      );
      notifyListeners();
      if (zugriff != Zugriff.erlaubt && zugriff != Zugriff.teilweise) {
        return Sicherungsantwort.keinZugriff;
      }
      _beobachte();
    }
    _stand.vergissFehler();
    final vorher = _stand.letzterLauf?.ende;
    await sichere(mobil: mobil);
    return switch (wartet) {
      Wartegrund.wlan => Sicherungsantwort.wartetWlan,
      Wartegrund.netz => Sicherungsantwort.wartetNetz,
      Wartegrund.hintergrund => Sicherungsantwort.imHintergrund,
      null when fehler != null => Sicherungsantwort.fehler,
      // Kein neuer Bericht: Es lief schon einer, der den Tipp mitnimmt.
      null when _stand.letzterLauf?.ende == vorher => Sicherungsantwort.laeuft,
      null => Sicherungsantwort.fertig,
    };
  }

  /// Ein Lauf, wenn die Sicherung an ist, der Zugriff erlaubt ist, das Netz
  /// passt und nicht schon einer läuft. [mobil] lässt „Nur im WLAN“ dieses
  /// eine Mal aus (siehe [sichereJetzt]).
  Future<void> sichere({bool mobil = false}) async {
    final e = einstellungen;
    if (_laeuft || _beendet || !e.an) return;
    if (zugriff != Zugriff.erlaubt && zugriff != Zugriff.teilweise) return;
    if (!await netzPasst(mobil ? e.mit(nurWlan: false) : e)) {
      wartet = e.nurWlan ? Wartegrund.wlan : Wartegrund.netz;
      notifyListeners();
      return;
    }
    _laeuft = true;
    _abbruch = false;
    wartet = null;
    fehler = null;
    notifyListeners();
    try {
      await Sicherungslauf(
        rolle: PhotoManagerRolle(alben: e.alben),
        verbindung: _verbindung,
        stand: _stand,
        wer: 'app',
      ).laufe(abbrechen: () => _abbruch || _beendet, meldung: _melde);
    } on Gesperrt {
      wartet = Wartegrund.hintergrund;
    } on Serverfehler catch (f) {
      fehler = f;
    } finally {
      _laeuft = false;
      fortschritt = null;
      if (_beendet) {
        _schliesse();
      } else {
        notifyListeners();
        unawaited(zaehleUngesicherte());
      }
    }
  }

  void _melde(Fortschritt f) {
    fortschritt = f;
    // Höchstens fünfmal je Sekunde neu zeichnen – die Stücke eines
    // Videos kommen schneller.
    final jetzt = DateTime.now();
    if (f.datei == null || jetzt.difference(_gemeldet).inMilliseconds > 200) {
      _gemeldet = jetzt;
      if (!_beendet) notifyListeners();
    }
  }

  /// Die App geht in den Hintergrund: unter Android an den
  /// Vordergrunddienst übergeben, wenn noch etwas offen ist.
  Future<void> imHintergrund() async {
    if (!Platform.isAndroid || !_laeuft) return;
    _abbruch = true;
    await uebergib(einstellungen);
  }

  // Die Rückgabe des Plugins abfangen, nicht nur den Aufruf: Ein Fehler
  // im unbeobachteten Future (in Tests ohne Telefon: kein Plugin) fiel
  // sonst später irgendwo anders herunter.
  void _beobachte() {
    PhotoManager.addChangeCallback(_geaendert);
    unawaited(PhotoManager.startChangeNotify().then((_) {}, onError: (_) {}));
  }

  void _beobachteNicht() {
    PhotoManager.removeChangeCallback(_geaendert);
    unawaited(PhotoManager.stopChangeNotify().then((_) {}, onError: (_) {}));
  }

  /// Ein neues Foto: kurz warten (eine Serie kommt in Schüben), dann
  /// sichern.
  void _geaendert(MethodCall _) {
    _nachAenderung?.cancel();
    _nachAenderung = Timer(const Duration(seconds: 3), sichere);
  }

  /// Abmelden: nichts mehr im Hintergrund. War die Sicherung nie an, ist
  /// auch nichts eingeplant.
  Future<void> streicheAufgaben() async {
    if (!einstellungen.an) return;
    await planeSicherung(const Sicherungseinstellungen());
  }

  @override
  void dispose() {
    _beendet = true;
    _abbruch = true;
    _nachAenderung?.cancel();
    if (einstellungen.an) {
      try {
        _beobachteNicht();
      } on MissingPluginException {
        // in Tests ohne Telefon
      }
    }
    // Ein laufender Lauf schreibt noch in den Stand; er schliesst ihn,
    // wenn er aufhört.
    if (!_laeuft) _schliesse();
    super.dispose();
  }

  void _schliesse() {
    _verbindung.schliesse();
    _stand.schliesse();
  }
}

enum Wartegrund { wlan, netz, hintergrund }

/// Wie „Jetzt sichern“ ausging (siehe [Sicherungsdienst.sichereJetzt]).
enum Sicherungsantwort {
  /// Gelaufen – wie weit, steht in [Sicherungsdienst.letzterLauf].
  fertig,

  /// Die Sicherung ist ausgeschaltet.
  aus,

  /// Die App darf die Fotos nicht lesen.
  keinZugriff,

  /// „Nur im WLAN“, und es gibt keines.
  wartetWlan,

  /// Gar kein Netz.
  wartetNetz,

  /// Ein Lauf im Hintergrund hält gerade die Sperre.
  imHintergrund,

  /// Es lief schon einer.
  laeuft,

  /// Der Server hat abgebrochen (siehe [Sicherungsdienst.fehler]).
  fehler,
}
