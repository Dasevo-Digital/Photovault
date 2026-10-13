import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:photo_manager/photo_manager.dart';

import 'hintergrund.dart';
import 'lauf.dart';
import 'photo_manager_rolle.dart';
import 'stand.dart';

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

  /// Warum gerade nicht gesichert wird, obwohl etwas offen ist.
  Wartegrund? wartet;

  /// Der letzte Fehler, der den ganzen Lauf beendete.
  Object? fehler;

  Laufbericht? get letzterLauf => _stand.letzterLauf;
  Map<String, String> get fehlgeschlagen => _stand.fehler;
  int get abgelehnt => _stand.anzahlAbgelehnt;

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

  /// Was scheiterte, noch einmal versuchen.
  void versucheFehlerErneut() {
    _stand.vergissFehler();
    notifyListeners();
    unawaited(sichere());
  }

  /// Ein Lauf, wenn die Sicherung an ist, der Zugriff erlaubt ist, das Netz
  /// passt und nicht schon einer läuft.
  Future<void> sichere() async {
    final e = einstellungen;
    if (_laeuft || _beendet || !e.an) return;
    if (zugriff != Zugriff.erlaubt && zugriff != Zugriff.teilweise) return;
    if (!await netzPasst(e)) {
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

  void _beobachte() {
    PhotoManager.addChangeCallback(_geaendert);
    unawaited(PhotoManager.startChangeNotify());
  }

  void _beobachteNicht() {
    PhotoManager.removeChangeCallback(_geaendert);
    unawaited(PhotoManager.stopChangeNotify());
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
