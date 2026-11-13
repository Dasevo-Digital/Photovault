import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'l10n/app_localizations.dart';

/// Die App-Sperre (#376): Face ID, Touch ID oder der Gerätecode, bevor die
/// App etwas zeigt.
///
/// **Warum.** Die App bleibt über ihre Sitzung angemeldet. Wer das
/// entsperrte Telefon in der Hand hatte, sah die ganze Bibliothek, auch
/// Offline-Alben und die Fotos von Partnern. Ein Telefon gibt man eher aus
/// der Hand als einen Rechner, und man verliert es eher.
///
/// Sie gilt nur für dieses Gerät und nur für die Oberfläche: Die Sicherung
/// im Hintergrund und das Teilen aus anderen Apps zeigen nichts und laufen
/// weiter. Im App-Umschalter deckt das System die App ab (siehe
/// `AppDelegate.swift` und `MainActivity.kt`), solange sie an ist.
class AppSperre extends ChangeNotifier {
  AppSperre({
    this.an = false,
    this.frist = Duration.zero,
    this.datei,
    Future<bool> Function(String grund)? pruefe,
    Future<bool> Function()? verfuegbar,
    DateTime Function()? jetzt,
    Future<int?> Function()? laufzeit,
    Future<void> Function(bool an)? abdecken,
    Future<void> Function()? beiSperre,
    bool? abdeckenWennInaktiv,
  }) : _pruefe = pruefe ?? _systemPruefung,
       _verfuegbar = verfuegbar ?? LocalAuthentication().isDeviceSupported,
       _jetzt = jetzt ?? DateTime.now,
       _laufzeit = laufzeit ?? _systemLaufzeit,
       _abdecken = abdecken ?? _systemAbdeckung,
       _beiSperre = beiSperre ?? _systemSperre,
       // Android schützt den Umschalter mit FLAG_SECURE; eine Fläche bei
       // jedem Fokusverlust (geteilter Bildschirm, Berechtigungsdialog,
       // Benachrichtigungen) verdeckte dort nur grundlos die App (#382).
       _abdeckenWennInaktiv = abdeckenWennInaktiv ?? !Platform.isAndroid,
       gesperrt = an;

  /// Wie lange die App im Hintergrund sein darf, ehe sie wieder fragt.
  static const fristen = [
    Duration.zero,
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  bool an;
  Duration frist;

  /// Ob die Oberfläche gerade gesperrt ist.
  bool gesperrt;

  /// Ob die App gerade nicht vorne ist: Dann liegt eine Abdeckung über
  /// allem, damit der App-Umschalter nichts zeigt.
  bool verdeckt = false;

  /// Wo die Einstellung liegt; ohne sie bleibt sie im Speicher.
  final File? datei;
  final Future<bool> Function(String grund) _pruefe;
  final Future<bool> Function() _verfuegbar;
  final DateTime Function() _jetzt;
  final Future<int?> Function() _laufzeit;
  final Future<void> Function(bool an) _abdecken;
  final Future<void> Function() _beiSperre;
  final bool _abdeckenWennInaktiv;

  /// Wann die App den Vordergrund verliess – nach der Uhrzeit und nach der
  /// [_laufzeit] des Geräts.
  DateTime? _weg;
  Future<int?>? _wegLaufzeit;

  /// Zählt die Rückkehren; eine ältere Prüfung der Laufzeit, die erst nach
  /// dem nächsten Verlassen fertig wird, gilt nicht mehr.
  var _rueckkehr = 0;
  bool _fragtGerade = false;

  /// Der letzte Zustand aus [lebenslauf].
  AppLifecycleState? _zustand;

  /// Ob gerade nach Face ID, Touch ID oder dem Gerätecode gefragt wird.
  bool get fragtGerade => _fragtGerade;

  /// Liest die Einstellung dieses Geräts. Ohne Datei ist die Sperre aus.
  ///
  /// Lässt sich eine vorhandene Datei nicht lesen, ist sie an (#382): Die
  /// Datei gibt es nur, seit jemand die Sperre einmal geschaltet hat, und
  /// ein Fehler soll sie nicht still abschalten. Hat das Gerät gar keinen
  /// Code, schaltet [entsperre] sie ohnehin ab.
  static Future<AppSperre> lade() async {
    final datei = File(
      p.join((await getApplicationSupportDirectory()).path, 'app_sperre.json'),
    );
    final (an, frist) = await leseEinstellung(datei);
    final sperre = AppSperre(an: an, frist: frist, datei: datei);
    unawaited(sperre._abdecken(an).catchError((Object _) {}));
    return sperre;
  }

  /// An und Frist aus [datei]; siehe [lade].
  @visibleForTesting
  static Future<(bool, Duration)> leseEinstellung(File datei) async {
    try {
      if (!await datei.exists()) return (false, Duration.zero);
      final w = jsonDecode(await datei.readAsString());
      if (w is! Map) return (true, Duration.zero);
      return (
        w['an'] != false,
        Duration(seconds: (w['frist'] as num?)?.toInt() ?? 0),
      );
    } on Object catch (e) {
      debugPrint('App-Sperre nicht gelesen: $e');
      return (true, Duration.zero);
    }
  }

  /// Ob das Gerät überhaupt Face ID, Touch ID oder einen Gerätecode hat.
  /// Ein Fehler zählt hier als nein: Einschalten soll nur, wer es sicher
  /// wieder aufbekommt.
  Future<bool> verfuegbar() async => await _sicherVerfuegbar() ?? false;

  /// `null`, wenn das System nicht antwortet.
  Future<bool?> _sicherVerfuegbar() async {
    try {
      return await _verfuegbar();
    } on Object catch (e) {
      debugPrint('App-Sperre: Verfügbarkeit unbekannt: $e');
      return null;
    }
  }

  /// Fragt nach Face ID, Touch ID oder dem Gerätecode; `true`, wenn es
  /// geklappt hat. Ein Fehler des Systems zählt als nein.
  Future<bool> pruefe(String grund) async {
    if (_fragtGerade) return false;
    _fragtGerade = true;
    try {
      return await _pruefe(grund);
    } on Object catch (e) {
      debugPrint('App-Sperre: $e');
      return false;
    } finally {
      _fragtGerade = false;
    }
  }

  /// Gibt die App frei, wenn Face ID, Touch ID oder der Gerätecode es
  /// bestätigen.
  ///
  /// **Kein Aussperren.** Hat das Gerät gar keinen Code mehr (jemand hat
  /// ihn nach dem Einschalten entfernt), liesse sich nie wieder prüfen,
  /// und die Einstellung zum Abschalten läge hinter der Sperre. Dann ist
  /// das Gerät ohnehin offen: Die Sperre schaltet sich ab. Nur wenn das
  /// System das sagt – ein Fehler beim Fragen schaltet nichts ab (#382).
  Future<bool> entsperre(String grund) async {
    if (!gesperrt) return true;
    if (await _sicherVerfuegbar() == false) {
      debugPrint('App-Sperre: kein Gerätecode mehr – abgeschaltet');
      await setze(an: false);
      return true;
    }
    // Inzwischen anders entsperrt: keine zweite Abfrage über der offenen
    // App.
    if (!gesperrt) return true;
    final ok = await pruefe(grund);
    if (ok) {
      gesperrt = false;
      // Wer eben bestätigt hat, war da. Unter Android 9 und 10 ist die
      // Eingabe des Codes eine eigene Activity; ihr „weg“ soll nicht gleich
      // wieder sperren (#382). Ist die App aber jetzt schon wieder im
      // Hintergrund (nach dem Häkchen nach Hause gewischt), zählt diese
      // Abwesenheit – sonst käme später jeder ohne Frage hinein.
      if (_zustand != AppLifecycleState.hidden &&
          _zustand != AppLifecycleState.paused) {
        _vergiss();
      }
      notifyListeners();
    }
    return ok;
  }

  /// Schaltet die Sperre um oder ändert die Frist und merkt es sich.
  Future<void> setze({bool? an, Duration? frist}) async {
    this.an = an ?? this.an;
    this.frist = frist ?? this.frist;
    if (!this.an) gesperrt = false;
    notifyListeners();
    await _abdecken(this.an).catchError((Object _) {});
    final ziel = datei;
    if (ziel == null) return;
    try {
      await ziel.parent.create(recursive: true);
      // Erst daneben, dann an die Stelle: Bricht das Schreiben ab, bleibt
      // die alte Einstellung ganz statt einer halben (#382).
      final teil = File('${ziel.path}.neu');
      await teil.writeAsString(
        jsonEncode({'an': this.an, 'frist': this.frist.inSeconds}),
        flush: true,
      );
      await teil.rename(ziel.path);
    } on Object catch (e) {
      debugPrint('App-Sperre nicht gespeichert: $e');
    }
  }

  /// Die App verlässt den Vordergrund oder kommt zurück. Der Dialog von
  /// Face ID selbst macht sie nur inaktiv, nicht unsichtbar – das zählt
  /// nicht als weg.
  void lebenslauf(AppLifecycleState zustand) {
    _zustand = zustand;
    if (!an) {
      if (verdeckt) {
        verdeckt = false;
        notifyListeners();
      }
      return;
    }
    switch (zustand) {
      case AppLifecycleState.inactive:
        if (_abdeckenWennInaktiv && !_fragtGerade && !verdeckt) {
          verdeckt = true;
          notifyListeners();
        }
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _rueckkehr++;
        _weg ??= _jetzt();
        _wegLaufzeit ??= _sichereLaufzeit();
        if (!verdeckt) {
          verdeckt = true;
          notifyListeners();
        }
      case AppLifecycleState.resumed:
        _zurueck();
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Zurück im Vordergrund: Lag die Frist dazwischen, wird gesperrt.
  ///
  /// **Nicht nach der Uhrzeit allein** (#382). Wer das entsperrte Telefon
  /// hat, stellt sie in den Einstellungen zurück und käme ohne Abfrage
  /// hinein. Massgeblich ist darum auch die Laufzeit des Geräts, die sich
  /// nicht verstellen lässt und im Schlaf weiterzählt. Eine Uhrzeit vor
  /// dem Verlassen sperrt sofort; liegt sie innerhalb der Frist, bleibt die
  /// Abdeckung, bis die Laufzeit es bestätigt. Antwortet das System nicht,
  /// wird gesperrt.
  ///
  /// Das Verlassen bleibt vermerkt, bis eine Prüfung entschieden hat. Geht
  /// die App vorher wieder weg, zählt die Abwesenheit ab dem ersten
  /// Verlassen weiter (#382).
  void _zurueck() {
    final weg = _weg;
    if (weg == null) {
      _decke(auf: false);
      return;
    }
    final vergangen = _jetzt().difference(weg);
    if (vergangen.isNegative || vergangen >= frist) {
      _vergiss();
      _sperre();
      _decke(auf: false);
      return;
    }
    final wegLaufzeit = _wegLaufzeit;
    final nr = _rueckkehr;
    unawaited(() async {
      final vorher = await wegLaufzeit;
      final jetzt = await _sichereLaufzeit();
      if (nr != _rueckkehr) return;
      if (vorher == null ||
          jetzt == null ||
          jetzt < vorher ||
          Duration(milliseconds: jetzt - vorher) >= frist) {
        _sperre();
      }
      _vergiss();
      _decke(auf: false);
    }());
  }

  void _vergiss() {
    _weg = null;
    _wegLaufzeit = null;
  }

  void _sperre() {
    if (gesperrt) return;
    gesperrt = true;
    unawaited(_beiSperre().catchError((Object _) {}));
  }

  void _decke({required bool auf}) {
    verdeckt = auf;
    notifyListeners();
  }

  Future<int?> _sichereLaufzeit() async {
    try {
      return await _laufzeit();
    } on Object catch (e) {
      debugPrint('App-Sperre: keine Laufzeit: $e');
      return null;
    }
  }

  /// Unter iOS fragt der Dialog nach dem Hintergrund von selbst weiter.
  /// Unter Android nicht: Dort stellt das Plugin bei jedem Zurückkommen eine
  /// neue Abfrage, auch nach der Code-Eingabe in eigener Activity (Android
  /// 9/10) – eine zweite stünde dann über der eben entsperrten App (#382).
  static Future<bool> _systemPruefung(String grund) =>
      LocalAuthentication().authenticate(
        localizedReason: grund,
        persistAcrossBackgrounding: !Platform.isAndroid,
      );

  static const _kanal = MethodChannel('de.dasevo.photovault/gemeinsam');

  static Future<void> _systemAbdeckung(bool an) async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    await _kanal.invokeMethod<void>('abdeckung', an);
  }

  static Future<int?> _systemLaufzeit() async {
    if (!Platform.isIOS && !Platform.isAndroid) return null;
    return _kanal.invokeMethod<int>('laufzeit');
  }

  /// Schliesst unter iOS, was das System über der App zeigt (Teilen-Blatt,
  /// Browser in der App): Es läge sonst über der Sperre. Unter Android ist
  /// die Auswahl zum Teilen eine eigene Activity und vorne, solange sie
  /// offen ist; dort ist nichts zu tun.
  static Future<void> _systemSperre() async {
    if (!Platform.isIOS) return;
    await _kanal.invokeMethod<void>('sperrt');
  }
}

/// Legt die Sperre über die ganze App: davor die Abfrage, solange
/// [AppSperre.gesperrt], und eine leere Fläche, solange die App nicht vorne
/// ist. Was darunter liegt, bekommt keine Berührung, keinen Tastaturfokus
/// und keine Ansage für VoiceOver.
class AppSperrschicht extends StatefulWidget {
  const AppSperrschicht({super.key, required this.sperre, required this.child});

  final AppSperre sperre;
  final Widget child;

  @override
  State<AppSperrschicht> createState() => _AppSperrschichtState();
}

class _AppSperrschichtState extends State<AppSperrschicht>
    with WidgetsBindingObserver {
  var _gefragt = false;

  /// Ob die App seit der letzten Abfrage wirklich weg war (hidden/paused).
  /// Nur dann fragt sie beim Zurückkommen wieder von selbst.
  var _warWeg = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.sperre.addListener(_neu);
  }

  @override
  void dispose() {
    widget.sperre.removeListener(_neu);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _neu() {
    if (!widget.sperre.gesperrt) _gefragt = false;
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        // Nicht, solange die eigene Abfrage läuft: Unter Android 9/10 ist die
        // Eingabe des Codes eine eigene Activity, und nach „Zurück“ stünde
        // sie sonst gleich wieder da – immer wieder (#382).
        if (!widget.sperre.fragtGerade) _warWeg = true;
      case AppLifecycleState.resumed:
        // Wer die Abfrage abgebrochen hat und aus dem Hintergrund
        // wiederkommt, wird wieder gefragt. Nicht aber nach dem Dialog von
        // Face ID selbst: Der macht die App nur kurz inaktiv, und nach
        // „Abbrechen“ stünde er sonst sofort wieder da – immer wieder (#382).
        if (_warWeg) _gefragt = false;
        _warWeg = false;
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
    widget.sperre.lebenslauf(state);
  }

  Future<void> _entsperre() async {
    final t = AppTexte.of(context);
    await widget.sperre.entsperre(t.appSperreGrund);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sperre;
    final zeige = s.an && (s.gesperrt || s.verdeckt);
    // Einmal von selbst fragen, sobald die Sperre vorne steht – danach nur
    // noch auf Tipp, sonst stünde der Dialog nach „Abbrechen“ gleich wieder.
    if (s.an && s.gesperrt && !s.verdeckt && !_gefragt) {
      _gefragt = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _entsperre();
      });
    }
    return Stack(
      children: [
        // Nur gesperrt, nicht schon verdeckt: Sonst schlösse jedes
        // Kontrollzentrum die Tastatur, und AutoFill verlöre seine Eingabe.
        ExcludeFocus(
          excluding: s.an && s.gesperrt,
          child: ExcludeSemantics(excluding: zeige, child: widget.child),
        ),
        if (zeige)
          Positioned.fill(
            child: _Sperrbild(
              frage: s.gesperrt && !s.verdeckt,
              beiTipp: _entsperre,
            ),
          ),
      ],
    );
  }
}

class _Sperrbild extends StatelessWidget {
  const _Sperrbild({required this.frage, required this.beiTipp});

  final bool frage;
  final VoidCallback beiTipp;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    return Material(
      color: farben.surface,
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 56, color: farben.primary),
              if (frage) ...[
                const SizedBox(height: 16),
                Text(
                  t.appSperreGesperrt,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: beiTipp,
                  icon: const Icon(Icons.face_outlined),
                  label: Text(t.appSperreEntsperren),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
