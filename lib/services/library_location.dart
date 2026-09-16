import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'platform/folder_access.dart';

export 'platform/folder_access.dart' show PickedFolder;

@immutable
class BibliotheksVerschiebefortschritt {
  const BibliotheksVerschiebefortschritt({
    required this.kopierteBytes,
    required this.gesamtBytes,
    required this.kopierteDateien,
    required this.gesamtDateien,
  });

  final int kopierteBytes;
  final int gesamtBytes;
  final int kopierteDateien;
  final int gesamtDateien;

  double? get anteil =>
      gesamtBytes == 0 ? null : (kopierteBytes / gesamtBytes).clamp(0, 1);
}

/// Eine der App bekannte Bibliothek. [path] und [token] sind dasselbe
/// Paar, das [LibraryLocation.pickFolder] liefert; [name] dient nur der
/// Anzeige und ist standardmäßig der Ordnername.
class Bibliothekseintrag {
  const Bibliothekseintrag(
      {required this.path, this.token, required this.name});

  final String path;
  final String? token;
  final String name;

  Map<String, dynamic> toJson() => {'path': path, 'token': token, 'name': name};

  static Bibliothekseintrag fromJson(Map<String, dynamic> json) =>
      Bibliothekseintrag(
        path: json['path'] as String,
        // Ältere Konfigurationen (vor der Plattform-Trennung) speichern das
        // Token noch unter dem macOS-Namen "bookmark".
        token: (json['token'] ?? json['bookmark']) as String?,
        name: (json['name'] as String?) ?? p.basename(json['path'] as String),
      );
}

/// Ein Listeneintrag samt der Auskunft, ob er gerade benutzbar ist – ein
/// Ordner auf einer nicht eingebundenen Platte existiert weiterhin, lässt
/// sich aber nicht öffnen.
class BibliothekMitZustand {
  const BibliothekMitZustand({
    required this.eintrag,
    required this.erreichbar,
    required this.istAktiv,
    required this.istStandard,
  });

  final Bibliothekseintrag eintrag;
  final bool erreichbar;
  final bool istAktiv;

  /// Der Standardordner im Programmbereich. Er wird von
  /// [LibraryLocation.bekannte] erzeugt und steht NICHT in der
  /// gespeicherten Liste – er lässt sich deshalb auch nicht daraus
  /// entfernen, und es gibt ihn immer.
  final bool istStandard;

  /// Ob sich dieser Eintrag aus der Liste streichen lässt. Der
  /// Standardordner nicht (es gibt ihn immer), die aktive Bibliothek auch
  /// nicht (der Zeiger zeigte sonst ins Leere).
  bool get entfernbar => !istStandard && !istAktiv;
}

/// Verwaltet, WO die eigentlichen Bibliotheksdaten (`library.sqlite` +
/// `library/`-Ordner mit Originalen/Thumbnails/Gesichts-Crops) liegen, und
/// welche der bekannten Bibliotheken gerade geöffnet ist.
///
/// Zwei Dinge, die sich leicht verwechseln lassen und es nicht dürfen:
/// [wechsleZu] biegt nur den Zeiger um und bewegt keine einzige Datei,
/// [applyRoot] verschiebt die aktuelle Bibliothek tatsächlich an einen
/// anderen Ort.
///
/// Der Zeiger (`location.json`) liegt bewusst IMMER am unveränderlichen
/// Standardpfad, nie in einer der Bibliotheken selbst – sonst wüsste die
/// App beim nächsten Start nicht, wo sie suchen soll. Der `models/`-Ordner
/// bleibt unabhängig davon immer am Standardpfad (Modelldateien sind
/// jederzeit neu herunterladbar, keine "echten" Nutzerdaten) und wird von
/// einem Wechsel folglich nicht berührt.
class LibraryLocation {
  LibraryLocation._();

  /// Plattformabhängiger Teil (Sandbox-Bookmarks unter macOS, blanker Pfad
  /// unter Linux/Windows) – siehe services/platform/folder_access.dart.
  static FolderAccess _access = FolderAccess.forCurrentPlatform();

  /// Nur für Tests: verlegt den Standardordner und ersetzt den
  /// Plattformzugriff. Beides führt sonst über echte Platform-Channels
  /// (`path_provider` bzw. die Sandbox-Bookmarks), die es im Testlauf nicht
  /// gibt – dieselbe Begründung wie bei [StoragePaths.forTesting].
  /// [zuruecksetzenFuerTests] stellt den Auslieferungszustand wieder her.
  @visibleForTesting
  static void nutzeFuerTests(
      {required Directory anker, FolderAccess? zugriff}) {
    _ankerFuerTests = anker;
    if (zugriff != null) _access = zugriff;
  }

  @visibleForTesting
  static void zuruecksetzenFuerTests() {
    _ankerFuerTests = null;
    _access = FolderAccess.forCurrentPlatform();
  }

  static Directory? _ankerFuerTests;

  /// Der Ordner, in dem die App ihre eigenen Daten hält: `location.json`,
  /// die Modelle, die Geodaten – und, solange keine Bibliothek gewählt
  /// ist, die Bibliothek selbst.
  ///
  /// Normalerweise `<App-Support>/PhotoVault`. Unter Windows gibt es
  /// einen zweiten Fall, seit es die App auch als MSIX-Paket gibt:
  /// Windows meldet einem Paket einen anderen App-Support-Ordner. Aus
  ///
  ///     C:\Users\X\AppData\Roaming\com.example\photo_vault
  ///
  /// wird dann
  ///
  ///     C:\Users\X\AppData\Local\Packages\<Paket>\LocalCache\Roaming\com.example\photo_vault
  ///
  /// Wer bisher das Zip benutzt hat und auf die Paketfassung wechselt,
  /// stünde sonst vor einer leeren App, während seine Bibliothek
  /// unauffindbar daneben läge.
  ///
  /// Umgezogen wird trotzdem nichts. In der Windows-Sandbox gemessen: Ein
  /// Prozess mit Paketidentität darf den alten Ort lesen **und**
  /// schreiben, beides geht ungehindert an die echte Stelle durch –
  /// umgeleitet wird allein, was über `SHGetKnownFolderPath` läuft. Das
  /// Paket benutzt also einfach weiter, was schon da ist. Das kostet
  /// keine Sekunde, kein Byte und lädt kein Modell erneut herunter.
  ///
  /// Nur wenn dort nichts liegt – also bei einer frischen Installation
  /// aus dem Store – bleibt es beim Ordner des Pakets. Sonst legte jede
  /// Neuinstallation Daten ausserhalb ihres Behälters an, wo niemand sie
  /// vermutet.
  static Future<Directory> datenordner() async {
    final vorgabe = _ankerFuerTests;
    if (vorgabe != null) {
      await vorgabe.create(recursive: true);
      return vorgabe;
    }
    final support = await getApplicationSupportDirectory();
    final alt = klassischerDatenordner(support.path);
    return waehleDatenordner(
      Directory(p.join(support.path, 'PhotoVault')),
      alt == null ? null : Directory(p.join(alt, 'PhotoVault')),
    );
  }

  /// Die Entscheidung selbst, getrennt davon, *wo* die beiden Orte
  /// liegen. Nur so lässt sie sich auch dort prüfen, wo es keine
  /// Windows-Pfade gibt – und die Suite läuft nicht unter Windows.
  ///
  /// Der alte Ort gewinnt nur, solange das Paket noch gar keinen eigenen
  /// Ordner hat. Sobald einer existiert, ist die Wahl gefallen und bleibt
  /// es: Ein Wechsel mitten im Betrieb hiesse, dass die App je nach
  /// Tageslage eine andere Bibliothek öffnet.
  @visibleForTesting
  static Future<Directory> waehleDatenordner(
      Directory imPaket, Directory? klassisch) async {
    if (klassisch != null &&
        !await imPaket.exists() &&
        await _siehtNachDatenAus(klassisch)) {
      return klassisch;
    }
    await imPaket.create(recursive: true);
    return imPaket;
  }

  /// Ob in [ordner] wirklich Daten dieser App liegen.
  ///
  /// Ein leerer Ordner reicht nicht: Er kann von einem abgebrochenen Lauf
  /// stammen, und ihn zu übernehmen hiesse, eine frische Installation an
  /// einen Ort zu binden, an dem nichts ist.
  static Future<bool> _siehtNachDatenAus(Directory ordner) async {
    if (!await ordner.exists()) return false;
    for (final name in const ['location.json', 'library.sqlite']) {
      if (await File(p.join(ordner.path, name)).exists()) return true;
    }
    return await Directory(p.join(ordner.path, 'models')).exists();
  }

  /// Der App-Support-Ordner der ausgepackten Fassung, von einem
  /// MSIX-Paket aus gesehen – oder `null`, wenn [supportPfad] gar nicht
  /// nach einem Paket aussieht.
  ///
  /// Reine Zeichenkettenarbeit, damit sie ohne Windows prüfbar ist. Die
  /// beiden Marken stammen aus einer echten Messung, nicht aus der
  /// Dokumentation.
  @visibleForTesting
  static String? klassischerDatenordner(String supportPfad) {
    if (!Platform.isWindows && !_pfadPruefungErzwingen) return null;
    const marke = r'\AppData\Local\Packages\';
    const mitte = r'\LocalCache\Roaming\';
    final klein = supportPfad.toLowerCase();
    final i = klein.indexOf(marke.toLowerCase());
    if (i < 0) return null;
    final j = klein.indexOf(mitte.toLowerCase(), i);
    if (j < 0) return null;
    final benutzer = supportPfad.substring(0, i);
    final rest = supportPfad.substring(j + mitte.length);
    if (benutzer.isEmpty || rest.isEmpty) return null;
    return '$benutzer\\AppData\\Roaming\\$rest';
  }

  static bool _pfadPruefungErzwingen = false;

  /// Nur für den Test: Die Pfadableitung ist reine Rechnung, liesse sich
  /// aber sonst allein unter Windows prüfen – und dort läuft die Suite
  /// nicht.
  @visibleForTesting
  static set pfadPruefungErzwingen(bool an) => _pfadPruefungErzwingen = an;

  static Future<Directory> _anchorDir() => datenordner();

  static Future<File> _configFile() async {
    final anchor = await _anchorDir();
    return File(p.join(anchor.path, 'location.json'));
  }

  /// Liest `location.json` und versteht dabei BEIDE Formate:
  ///
  /// - alt: `{path, token}` – genau eine Bibliothek, wie vor der Einführung
  ///   des Wechsels. Wird als Liste mit einem Eintrag gelesen, der zugleich
  ///   der aktive ist. Deshalb braucht es keinen Migrationsschritt: Eine
  ///   bestehende Konfiguration funktioniert unverändert weiter und wird
  ///   erst beim nächsten Schreibvorgang ins neue Format überführt.
  /// - neu: `{aktiv, bibliotheken: [...]}`
  ///
  /// Fehlt die Datei oder ist sie unlesbar, ist die Liste leer – die App
  /// arbeitet dann im Standardordner.
  static Future<({String? aktiv, List<Bibliothekseintrag> liste})>
      _leseKonfig() async {
    final configFile = await _configFile();
    if (!await configFile.exists()) {
      return (aktiv: null, liste: <Bibliothekseintrag>[]);
    }
    try {
      final json =
          jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
      final roh = json['bibliotheken'] as List<dynamic>?;
      if (roh == null) {
        // Altes Format.
        final pfad = json['path'] as String?;
        if (pfad == null) return (aktiv: null, liste: <Bibliothekseintrag>[]);
        return (aktiv: pfad, liste: [Bibliothekseintrag.fromJson(json)]);
      }
      return (
        aktiv: json['aktiv'] as String?,
        liste: roh
            .map((e) => Bibliothekseintrag.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } catch (_) {
      return (aktiv: null, liste: <Bibliothekseintrag>[]);
    }
  }

  /// Schreibt die Konfiguration – erst daneben, dann umbenennen.
  ///
  /// Ein `writeAsString` kürzt die Datei zuerst auf null und füllt sie dann.
  /// Bricht das Programm oder der Rechner in diesem Moment ab, bleibt ein
  /// Rumpf zurück, den [_leseKonfig] nicht auswerten kann – und da es dort
  /// (bewusst) keinen Fehler gibt, sondern einen Rückfall auf „keine
  /// Bibliothek", stünde die App danach wortlos im Standardordner: leere
  /// Übersicht, und das Security-Scoped-Bookmark des echten Ordners weg,
  /// das nur der Ordnerdialog wieder erzeugen kann. Selten, aber teuer –
  /// und ein Umbenennen kostet nichts.
  static Future<void> _schreibeKonfig(
      String? aktiv, List<Bibliothekseintrag> liste) async {
    final configFile = await _configFile();
    if (aktiv == null && liste.isEmpty) {
      if (await configFile.exists()) await configFile.delete();
      return;
    }
    final inhalt = jsonEncode({
      'aktiv': aktiv,
      'bibliotheken': [for (final e in liste) e.toJson()],
    });
    final teil = File('${configFile.path}.neu');
    try {
      await teil.writeAsString(inhalt, flush: true);
      await teil.rename(configFile.path);
    } finally {
      // Bleibt nur liegen, wenn schon das Schreiben scheiterte – dann ist
      // die alte Fassung noch da und der Rumpf hat nichts zu suchen.
      if (await teil.exists()) await teil.delete();
    }
  }

  /// Aktuelles Wurzelverzeichnis für `library.sqlite` und den `library/`-
  /// Ordner. Stellt dabei – falls ein externer Ordner konfiguriert ist – den
  /// Zugriff darauf wieder her: unter macOS über das gespeicherte
  /// Security-Scoped-Bookmark (die Sandbox entzieht ihn sonst bei jedem
  /// Neustart), unter Linux/Windows über den gespeicherten Pfad.
  static Future<Directory> currentRoot() async {
    final konfig = await _leseKonfig();
    final aktiv = konfig.aktiv;
    if (aktiv == null) return _anchorDir();

    final eintrag =
        konfig.liste.where((e) => p.equals(e.path, aktiv)).firstOrNull;
    if (eintrag == null) return _anchorDir();

    final resolved =
        await _access.resolveRoot(path: eintrag.path, token: eintrag.token);
    // Ordner nicht mehr erreichbar (gelöscht/umbenannt, Laufwerk nicht
    // eingebunden, Bookmark ungültig) – auf den Standardordner
    // zurückfallen, statt die App gar nicht erst starten zu lassen.
    if (resolved == null) return _anchorDir();
    return Directory(resolved);
  }

  /// Alle bekannten Bibliotheken samt Auskunft, ob sie gerade erreichbar
  /// sind und welche die aktive ist. Der Standardordner ist immer dabei,
  /// auch wenn er nie ausdrücklich hinzugefügt wurde – sonst liesse sich
  /// aus einer externen Bibliothek nicht mehr zurückwechseln.
  static Future<List<BibliothekMitZustand>> bekannte() async {
    final konfig = await _leseKonfig();
    final standard = await _anchorDir();
    final aktiv = konfig.aktiv ?? standard.path;

    final eintraege = <Bibliothekseintrag>[
      Bibliothekseintrag(path: standard.path, token: null, name: 'Standard'),
      ...konfig.liste.where((e) => !p.equals(e.path, standard.path)),
    ];

    final ergebnis = <BibliothekMitZustand>[];
    for (final e in eintraege) {
      final erreichbar = p.equals(e.path, standard.path)
          ? true
          : (await _access.resolveRoot(path: e.path, token: e.token)) != null;
      ergebnis.add(BibliothekMitZustand(
        eintrag: e,
        erreichbar: erreichbar,
        istAktiv: p.equals(e.path, aktiv),
        istStandard: p.equals(e.path, standard.path),
      ));
    }
    return ergebnis;
  }

  /// Wechselt die aktive Bibliothek – und **verschiebt dabei nichts**. Es
  /// wird ausschliesslich der Zeiger umgebogen; beide Ordner bleiben Byte
  /// für Byte, wie sie sind.
  ///
  /// Das ist der entscheidende Unterschied zu [applyRoot], das die Daten
  /// tatsächlich umkopiert. Wer die beiden verwechselt, schiebt eine
  /// mehrere Gigabyte grosse Bibliothek um, statt in einer Sekunde
  /// umzuschalten – die Beschriftung in der Oberfläche muss das
  /// unmissverständlich trennen.
  ///
  /// Die App muss danach neu starten: Datenbankverbindung, [StoragePaths]
  /// und sämtliche Zwischenspeicher hängen am alten Ort.
  static Future<void> wechsleZu(Bibliothekseintrag ziel) async {
    final konfig = await _leseKonfig();
    final standard = await _anchorDir();

    final liste = [...konfig.liste];
    if (!p.equals(ziel.path, standard.path) &&
        !liste.any((e) => p.equals(e.path, ziel.path))) {
      liste.add(ziel);
    }
    await _schreibeKonfig(ziel.path, liste);
  }

  /// Nimmt einen Ordner in die Liste auf, ohne ihn zu öffnen oder etwas zu
  /// verschieben. Enthält er bereits eine `library.sqlite`, ist es eine
  /// bestehende Bibliothek; ist er leer, entsteht beim ersten Öffnen eine
  /// neue (siehe [AppDatabase.open], das die Datei anlegt).
  static Future<Bibliothekseintrag> fuegeHinzu(PickedFolder picked,
      {String? name}) async {
    final konfig = await _leseKonfig();
    final eintrag = Bibliothekseintrag(
      path: picked.path,
      token: picked.token,
      name: name ?? p.basename(picked.path),
    );
    final liste = [
      ...konfig.liste.where((e) => !p.equals(e.path, picked.path)),
      eintrag,
    ];
    await _schreibeKonfig(konfig.aktiv, liste);
    return eintrag;
  }

  /// Streicht einen Eintrag aus der Liste. **Löscht keine Daten** – die
  /// Fotos bleiben, wo sie sind, die Bibliothek lässt sich jederzeit
  /// wieder hinzufügen.
  ///
  /// Liefert `false`, wenn nichts zu entfernen war: bei der aktiven
  /// Bibliothek (der Zeiger zeigte sonst ins Leere) und beim
  /// Standardordner, den [bekannte] erzeugt statt ihn zu speichern. Ohne
  /// diese Rückmeldung zeigte die Oberfläche einen Knopf, der
  /// stillschweigend nichts tut (Fehlerbericht).
  static Future<bool> entferneAusListe(String pfad) async {
    final konfig = await _leseKonfig();
    if (konfig.aktiv != null && p.equals(konfig.aktiv!, pfad)) return false;
    final rest = konfig.liste.where((e) => !p.equals(e.path, pfad)).toList();
    if (rest.length == konfig.liste.length) return false;
    await _schreibeKonfig(konfig.aktiv, rest);
    return true;
  }

  /// Ob aktuell ein vom Standard abweichender Speicherort konfiguriert ist.
  static Future<bool> get isCustom async => (await _configFile()).exists();

  /// Zeigt einen Ordnerauswahl-Dialog. Unter macOS entsteht dabei atomar im
  /// selben nativen Aufruf ein dauerhaftes Security-Scoped-Bookmark, unter
  /// Linux/Windows genügt der gewählte Pfad (siehe
  /// services/platform/folder_access.dart). Gibt `null` zurück, falls der
  /// Nutzer abgebrochen hat. Bewusst von [applyRoot] getrennt: die
  /// eigentliche UI (z.B. eine Ladeanzeige) soll erst nach der Ordnerauswahl
  /// erscheinen, nicht schon währenddessen.
  static Future<PickedFolder?> pickFolder({String? dialogMessage}) {
    return _access.pickFolder(message: dialogMessage);
  }

  /// Legt einen zuvor per [pickFolder] gewählten Ordner als neuen
  /// Speicherort fest und verschiebt die vorhandenen Bibliotheksdaten
  /// dorthin. Wirft eine [Exception] mit einer für die UI verständlichen
  /// Meldung, falls das Verschieben fehlschlägt – die bisherigen Daten
  /// bleiben in diesem Fall unangetastet (siehe [_moveLibraryData]).
  ///
  /// [beforeMove] wird erst aufgerufen, nachdem feststeht, dass tatsächlich
  /// verschoben wird (also nicht bei einem No-Op, falls [picked] bereits der
  /// aktuelle Ort ist) – so schließt z.B. [LibraryState] darüber die
  /// Datenbankverbindung erst kurz bevor `library.sqlite` wirklich
  /// verschoben wird, statt vorschnell und ggf. für nichts.
  static Future<String> applyRoot(
    PickedFolder picked, {
    Future<void> Function()? beforeMove,
    ValueChanged<BibliotheksVerschiebefortschritt>? onProgress,
  }) async {
    final oldRoot = await currentRoot();
    final newRoot = Directory(picked.path);
    if (p.equals(oldRoot.path, newRoot.path)) return picked.path;

    if (beforeMove != null) await beforeMove();

    await newRoot.create(recursive: true);
    await _moveLibraryData(oldRoot, newRoot, onProgress: onProgress);

    // Die aktive Bibliothek ist umgezogen: Ihr alter Eintrag zeigt ins
    // Leere und wird durch den neuen Ort ersetzt. Andere Einträge der
    // Liste bleiben unberührt – sie wurden ja nicht verschoben.
    final konfig = await _leseKonfig();
    final neuerEintrag = Bibliothekseintrag(
      path: picked.path,
      token: picked.token,
      name: konfig.liste
              .where((e) => p.equals(e.path, oldRoot.path))
              .map((e) => e.name)
              .firstOrNull ??
          p.basename(picked.path),
    );
    await _schreibeKonfig(picked.path, [
      ...konfig.liste.where((e) =>
          !p.equals(e.path, oldRoot.path) && !p.equals(e.path, picked.path)),
      neuerEintrag,
    ]);
    return picked.path;
  }

  /// Setzt den Speicherort zurück auf den Standard-App-Support-Ordner.
  static Future<void> resetToDefault({
    ValueChanged<BibliotheksVerschiebefortschritt>? onProgress,
  }) async {
    final oldRoot = await currentRoot();
    final defaultRoot = await _anchorDir();
    if (p.equals(oldRoot.path, defaultRoot.path)) return;

    await _moveLibraryData(oldRoot, defaultRoot, onProgress: onProgress);

    // Der bisherige Ort ist jetzt leer – seinen Eintrag streichen und den
    // Standard aktiv setzen. Übrige Einträge bleiben erhalten, sonst ginge
    // die Liste bei einem Zurücksetzen verloren.
    final konfig = await _leseKonfig();
    await _schreibeKonfig(
      defaultRoot.path,
      konfig.liste.where((e) => !p.equals(e.path, oldRoot.path)).toList(),
    );
  }

  /// Kopiert `library.sqlite` (+ evtl. WAL/SHM-Nebendateien) und den
  /// `library/`-Ordner von [from] nach [to] und löscht die Originale erst,
  /// wenn das vollständig geklappt hat – bei einem Fehler mitten im Kopieren
  /// (z.B. Speicherplatz voll) bleibt die bisherige Bibliothek so
  /// unverändert erhalten, statt in einem halb verschobenen Zustand zu enden.
  static Future<void> _moveLibraryData(
    Directory from,
    Directory to, {
    ValueChanged<BibliotheksVerschiebefortschritt>? onProgress,
  }) async {
    if (p.equals(from.path, to.path)) return;

    final dbFrom = File(p.join(from.path, 'library.sqlite'));
    final dbTo = File(p.join(to.path, 'library.sqlite'));
    final libFrom = Directory(p.join(from.path, 'library'));
    final libTo = Directory(p.join(to.path, 'library'));

    final dateien = <({File quelle, File ziel, int bytes})>[];

    Future<void> nimmAuf(File quelle, File ziel) async {
      if (!await quelle.exists()) return;
      dateien.add((quelle: quelle, ziel: ziel, bytes: await quelle.length()));
    }

    await nimmAuf(dbFrom, dbTo);
    for (final suffix in ['-wal', '-shm']) {
      await nimmAuf(File('${dbFrom.path}$suffix'), File('${dbTo.path}$suffix'));
    }
    if (await libFrom.exists()) {
      await for (final entity in libFrom.list(recursive: true)) {
        if (entity is! File) continue;
        final relativ = p.relative(entity.path, from: libFrom.path);
        await nimmAuf(entity, File(p.join(libTo.path, relativ)));
      }
    }

    final gesamtBytes = dateien.fold<int>(0, (summe, d) => summe + d.bytes);
    var kopierteBytes = 0;
    var kopierteDateien = 0;
    var zuletztGemeldet = 0;

    void melde({bool erzwingen = false}) {
      if (!erzwingen && kopierteBytes - zuletztGemeldet < 1024 * 1024) return;
      zuletztGemeldet = kopierteBytes;
      onProgress?.call(BibliotheksVerschiebefortschritt(
        kopierteBytes: kopierteBytes,
        gesamtBytes: gesamtBytes,
        kopierteDateien: kopierteDateien,
        gesamtDateien: dateien.length,
      ));
    }

    melde(erzwingen: true);
    for (final datei in dateien) {
      await datei.ziel.parent.create(recursive: true);
      final ausgabe = datei.ziel.openWrite();
      try {
        await for (final block in datei.quelle.openRead()) {
          ausgabe.add(block);
          kopierteBytes += block.length;
          melde();
        }
      } finally {
        await ausgabe.close();
      }
      kopierteDateien++;
      melde(erzwingen: true);
    }

    // Erst nach erfolgreichem Kopieren die Originale löschen.
    if (await dbFrom.exists()) {
      await dbFrom.delete();
      for (final suffix in ['-wal', '-shm']) {
        final side = File('${dbFrom.path}$suffix');
        if (await side.exists()) await side.delete();
      }
    }
    if (await libFrom.exists()) {
      await libFrom.delete(recursive: true);
    }
  }
}
