import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:kern/services/backup_fotokammer.dart';
import 'package:kern/protokoll.dart';
import 'package:path/path.dart' as p;

import 'aussenziel.dart';
import 'konten/tresorschluessel.dart';
import 'sicherung.dart' show Serversicherung;

/// Wie es um die Sicherung ausser Haus steht – für die Apps.
enum Aussenstufe {
  /// Kein Ziel eingerichtet.
  aus,

  /// Eingerichtet, aber noch kein Lauf fertig geworden.
  ausstehend,

  /// Der letzte Lauf ist gescheitert.
  fehler,

  /// Seit über acht Tagen kein gelungener Lauf.
  veraltet,
  ok,
}

/// Was der Verwalter eingibt, geprüft. Das Geheimnis steht nur hier und in
/// [Aussensicherung] im Klartext, nie in einer Antwort.
class AussenzielAngabe {
  AussenzielAngabe({
    required this.art,
    required this.adresse,
    required this.zugang,
    required this.geheimnis,
    this.bucket = '',
    this.region = 'us-east-1',
    this.praefix = '',
    this.drosselMb,
  });

  /// `s3` oder `webdav`.
  final String art;
  final Uri adresse;
  final String zugang;
  final String geheimnis;
  final String bucket;
  final String region;
  final String praefix;

  /// Höchstens so viele MB je Sekunde, `null`: ohne Grenze.
  final int? drosselMb;

  /// Liest und prüft die Eingabe. Wirft [ArgumentError] mit einem Text für
  /// den Verwalter.
  factory AussenzielAngabe.aus(
    Map<String, Object?> j, {
    AussenzielAngabe? bisher,
  }) {
    String text(String name) => '${j[name] ?? ''}'.trim();
    final art = text('art');
    if (art != 's3' && art != 'webdav') {
      throw ArgumentError('Die Art muss s3 oder webdav sein.');
    }
    final adresse = Uri.tryParse(text('adresse'));
    if (adresse == null ||
        !adresse.hasAuthority ||
        !const {'http', 'https'}.contains(adresse.scheme)) {
      throw ArgumentError('Die Adresse muss mit https:// beginnen.');
    }
    if (adresse.scheme == 'http' && !_imEigenenNetz(adresse.host)) {
      // Zugangsdaten gingen sonst im Klartext durchs Netz.
      throw ArgumentError(
        'Unverschlüsseltes http geht nur im eigenen Netz. Bitte https nutzen.',
      );
    }
    final zugang = text('zugang');
    if (zugang.isEmpty) {
      throw ArgumentError(
        art == 's3' ? 'Die Schlüssel-ID fehlt.' : 'Der Benutzer fehlt.',
      );
    }
    final bucket = text('bucket');
    if (art == 's3' && bucket.isEmpty) {
      throw ArgumentError('Der Bucket fehlt.');
    }
    // Leer heisst bei einer Änderung: so lassen. Es kommt nie zurück ins
    // Formular. Aber nur fürs selbe Ziel: Sonst liesse es sich mit einer
    // neuen Adresse zu einem fremden Rechner schicken.
    final eingabe = j['geheimnis'];
    final selbesZiel =
        bisher != null &&
        bisher.art == art &&
        bisher.adresse == adresse &&
        bisher.zugang == zugang;
    final geheimnis = eingabe is String && eingabe.isNotEmpty
        ? eingabe
        : selbesZiel
        ? bisher.geheimnis
        : '';
    if (geheimnis.isEmpty) {
      throw ArgumentError(
        art == 's3' ? 'Der Geheimschlüssel fehlt.' : 'Das Passwort fehlt.',
      );
    }
    final praefix = text('praefix').replaceAll(RegExp(r'^/+|/+$'), '');
    if (praefix.split('/').contains('..')) {
      throw ArgumentError('Der Ordner darf kein „..“ enthalten.');
    }
    final region = text('region');
    final drossel = j['drosselMb'];
    final mb = drossel is num ? drossel.toInt() : int.tryParse('$drossel');
    return AussenzielAngabe(
      art: art,
      adresse: adresse,
      zugang: zugang,
      geheimnis: geheimnis,
      bucket: bucket,
      region: region.isEmpty ? 'us-east-1' : region,
      praefix: praefix,
      drosselMb: mb != null && mb > 0 ? mb : null,
    );
  }

  static bool _imEigenenNetz(String host) {
    if (host == 'localhost' || host.endsWith('.local')) return true;
    final a = InternetAddress.tryParse(host);
    if (a == null) return false;
    if (a.isLoopback || a.isLinkLocal) return true;
    final b = a.rawAddress;
    if (a.type != InternetAddressType.IPv4) return false;
    return b[0] == 10 ||
        (b[0] == 172 && b[1] >= 16 && b[1] < 32) ||
        (b[0] == 192 && b[1] == 168);
  }

  Aussenziel baue() => art == 's3'
      ? S3Ziel(
          endpunkt: adresse,
          bucket: bucket,
          region: region,
          zugang: zugang,
          geheimnis: geheimnis,
          praefix: praefix,
        )
      : WebdavZiel(
          adresse: adresse,
          benutzer: zugang,
          passwort: geheimnis,
          praefix: praefix,
        );

  /// Für die Apps: alles ausser dem Geheimnis.
  Map<String, Object?> alsJson() => {
    'art': art,
    'adresse': '$adresse',
    'zugang': zugang,
    if (art == 's3') ...{'bucket': bucket, 'region': region},
    'praefix': praefix,
    'drosselMb': ?drosselMb,
  };
}

/// Hält den Strom auf [_bytesProSekunde], über alle Übertragungen zusammen.
class _Drossel {
  _Drossel(this._bytesProSekunde);
  final int _bytesProSekunde;
  var _frei = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> warte(int bytes) async {
    final jetzt = DateTime.now();
    final beginn = _frei.isAfter(jetzt) ? _frei : jetzt;
    _frei = beginn.add(
      Duration(microseconds: bytes * 1000000 ~/ _bytesProSekunde),
    );
    final pause = beginn.difference(jetzt);
    if (pause > Duration.zero) await Future<void>.delayed(pause);
  }
}

/// Bringt die fertige Sicherung des Servers ausser Haus, nach S3 oder
/// WebDAV.
///
/// **Der Anbieter sieht keinen Klartext:** Übertragen wird, was
/// [Serversicherung] geschrieben hat: Fotos, Datenbank und Beilage
/// verschlüsselt, Dateinamen als HMAC. Ein Schlüssel verlässt den Server
/// nur verpackt in `vault.key`, geöffnet mit der Passphrase. Sichtbar
/// bleiben Grösse und Anzahl der Dateien und die Namen der Konten-Ordner.
///
/// **Wiederherstellen** braucht nur den Speicher und die Passphrase: Den
/// Ordner eines Kontos herunterladen (rclone, Cyberduck) und in der App als
/// Sicherung öffnen. Das Format ist das der Sicherung selbst.
///
/// **Nur, was fehlt:** Das Ziel sagt selbst, was es hat. Ein Abbruch kostet
/// also nichts, und der erste Lauf darf Tage dauern; er macht in der
/// nächsten Nacht dort weiter.
///
/// **Gelöscht wird nie ein Foto:** `data/` wächst nur, wie am Sicherungsziel.
/// Weg kommen allein Generationen der Datenbank, die es dort auch nicht mehr
/// gibt, sonst wüchse das Ziel jeden Tag um eine ganze Datenbank.
class Aussensicherung {
  Aussensicherung({
    required this.daten,
    required this.wurzel,
    required this.tresor,
    Aussenziel Function(AussenzielAngabe angabe)? baueZiel,
    DateTime Function()? uhr,
    this.wartezeit = const Duration(seconds: 2),
    this.gleichzeitig = 4,
    Random? zufall,
  }) : _baueZiel = baueZiel ?? ((a) => a.baue()),
       _uhr = uhr ?? DateTime.now,
       _zufall = zufall ?? Random();

  final Directory daten;

  /// Das Sicherungsziel des Servers (`PV_SICHERUNG`), die Quelle von allem.
  final Directory? wurzel;
  final Tresorschluessel tresor;

  /// Pause vor dem zweiten Versuch; jeder weitere wartet viermal so lange.
  final Duration wartezeit;
  final int gleichzeitig;
  final Aussenziel Function(AussenzielAngabe angabe) _baueZiel;
  final DateTime Function() _uhr;
  final Random _zufall;

  static const _veraltetNach = Duration(days: 8);
  static const _stichproben = 3;
  static const _stichprobeBis = 32 * 1024 * 1024;

  /// So viele Fehler in Folge heissen: Das Ziel ist weg.
  static const _fehlerInFolge = 10;

  File get _einstellungDatei =>
      File(p.join(daten.path, 'aussensicherung.json'));
  File get _standDatei =>
      File(p.join(daten.path, 'aussensicherung-stand.json'));

  bool get eingerichtet => _einstellungDatei.existsSync();
  bool get laeuft => _lauf != null;
  Future<void>? _lauf;
  var _abbrechen = false;
  ({int gesamt, int erledigt, int bytes, int bytesGesamt})? _fortschritt;

  Future<Map<String, Object?>> _lies(File f) async =>
      (jsonDecode(await f.readAsString()) as Map).cast<String, Object?>();

  Future<void> _schreibe(File f, Map<String, Object?> j) async {
    await f.parent.create(recursive: true);
    final teil = File('${f.path}.neu');
    // Erst einschränken, dann füllen: Zugangsdaten sollen keinen Augenblick
    // für andere lesbar sein, auch nicht verschlüsselt.
    await teil.writeAsString('');
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', teil.path]);
    }
    await teil.writeAsString(jsonEncode(j), flush: true);
    await teil.rename(f.path);
  }

  Future<AussenzielAngabe?> _angabe() async {
    if (!eingerichtet) return null;
    final j = await _lies(_einstellungDatei);
    return AussenzielAngabe.aus({
      ...j,
      'geheimnis': utf8.decode(
        await tresor.entschluessele('${j['geheimnis']}'),
      ),
    });
  }

  /// Prüft das Ziel wirklich, mit Schreiben, Lesen und Löschen, und merkt es
  /// sich erst dann.
  Future<void> einrichten(Map<String, Object?> eingabe) async {
    final w = wurzel;
    if (w == null) {
      throw StateError(
        'Erst braucht der Server eine eigene Sicherung (PV_SICHERUNG).',
      );
    }
    final a = AussenzielAngabe.aus(eingabe, bisher: await _angabe());
    await _pruefe(a);
    await _schreibe(_einstellungDatei, {
      ...a.alsJson(),
      'geheimnis': await tresor.verschluessele(utf8.encode(a.geheimnis)),
    });
    protokoll('Sicherung ausser Haus eingerichtet: ${a.adresse}');
  }

  Future<void> _pruefe(AussenzielAngabe a) async {
    final ziel = _baueZiel(a);
    final probe = await File(
      p.join(
        (await Directory.systemTemp.createTemp('pv_aussenprobe_')).path,
        'probe',
      ),
    ).create();
    final name =
        '.photovault-probe-${_zufall.nextInt(1 << 32).toRadixString(16)}';
    final inhalt = utf8.encode(name);
    try {
      await probe.writeAsBytes(inhalt);
      await ziel.lege(name, probe, groesse: inhalt.length);
      final zurueck = await ziel.hole(name);
      if (base64.encode(zurueck) != base64.encode(inhalt)) {
        throw const Zielfehler('Das Ziel lieferte etwas anderes zurück.');
      }
      await ziel.loesche(name);
      // Die Liste braucht jeder Lauf; scheitert sie, soll das hier auffallen.
      await ziel.liste();
    } finally {
      ziel.schliesse();
      await probe.parent.delete(recursive: true);
    }
  }

  /// Vergisst das Ziel. Was dort liegt, bleibt liegen.
  Future<void> entfernen() async {
    _abbrechen = true;
    await _lauf?.catchError((_) {});
    if (await _einstellungDatei.exists()) await _einstellungDatei.delete();
    if (await _standDatei.exists()) await _standDatei.delete();
    protokoll('Sicherung ausser Haus entfernt');
  }

  Future<Aussenstufe> stufe(Map<String, Object?> letzter) async {
    if (!eingerichtet) return Aussenstufe.aus;
    if (letzter['ok'] == false) return Aussenstufe.fehler;
    final seit = DateTime.tryParse('${letzter['letzterErfolg']}');
    if (seit == null) return Aussenstufe.ausstehend;
    return _uhr().difference(seit) > _veraltetNach
        ? Aussenstufe.veraltet
        : Aussenstufe.ok;
  }

  Future<Map<String, Object?>> stand() async {
    final letzter = await _standDatei.exists()
        ? await _lies(_standDatei)
        : const <String, Object?>{};
    final f = _fortschritt;
    return {
      ...letzter,
      'stufe': (await stufe(letzter)).name,
      'moeglich': wurzel != null,
      'laeuft': laeuft,
      if (eingerichtet)
        'ziel': await _lies(_einstellungDatei)
          ..remove('geheimnis'),
      if (f != null)
        'fortschritt': {
          'gesamt': f.gesamt,
          'erledigt': f.erledigt,
          'bytes': f.bytes,
          'bytesGesamt': f.bytesGesamt,
        },
    };
  }

  /// Überträgt jetzt; läuft schon ein Lauf, wartet es auf diesen.
  Future<void> jetzt() => _lauf ??= _laufe().whenComplete(() {
    _lauf = null;
    _fortschritt = null;
  });

  /// Pfade relativ zur Wurzel, mit `/`. Halbfertiges bleibt daheim.
  Future<Map<String, Zieldatei>> _bestand(Directory w) async {
    final aus = <String, Zieldatei>{};
    await for (final e in w.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = p.split(p.relative(e.path, from: w.path));
      if (rel.any((t) => t.startsWith('.'))) continue;
      final name = rel.last;
      if (name.endsWith('.pv-teil') || name.endsWith('.neu')) continue;
      final s = await e.stat();
      aus[rel.join('/')] = Zieldatei(s.size, s.modified);
    }
    return aus;
  }

  /// Erst die Fotos, dann erst die Datenbank, die auf sie zeigt: Reisst der
  /// Lauf ab, passt das, was schon drüben liegt, immer noch zusammen.
  static int _rang(String pfad) => pfad.contains('/data/')
      ? 0
      : pfad.contains('/generations/')
      ? 1
      : 2;

  /// In ganzen Sekunden: WebDAV nennt keine feinere Zeit. Sonst sähe eine
  /// Datei, die in derselben Sekunde entstand und hinüberging, neuer aus,
  /// als sie ist.
  static bool _veraltet(Zieldatei hier, Zieldatei? dort) {
    if (dort == null || dort.groesse != hier.groesse) return true;
    final h = hier.geaendert, d = dort.geaendert;
    if (h == null || d == null) return false;
    return h.millisecondsSinceEpoch ~/ 1000 > d.millisecondsSinceEpoch ~/ 1000;
  }

  Future<void> _laufe() async {
    _abbrechen = false;
    if (!eingerichtet || wurzel == null) return;
    final beginn = _uhr();
    var hoch = 0, bytes = 0, gesamt = 0, offenNachher = 0, geloescht = 0;
    Map<String, Object?>? stichprobe;
    String? fehler;
    Aussenziel? ziel;
    try {
      final w = wurzel!;
      // Ein leerer Mountpunkt sähe aus wie „nichts zu tun“. Und die
      // Generationen drüben sähen aus, als gäbe es sie nicht mehr.
      if (!File(p.join(w.path, Serversicherung.markeName)).existsSync()) {
        throw StateError(
          'Am Sicherungsziel ${w.path} fehlt die Kennmarke – ist es '
          'eingehängt?',
        );
      }
      final a = (await _angabe())!;
      ziel = _baueZiel(a);
      await ziel.aufraeumen();
      final dort = await ziel.liste();
      final hier = await _bestand(w);
      gesamt = hier.length;
      final offen = [
        for (final e in hier.entries)
          if (_veraltet(e.value, dort[e.key])) e,
      ]..sort((x, y) => _rang(x.key).compareTo(_rang(y.key)));
      final bytesGesamt = offen.fold<int>(0, (s, e) => s + e.value.groesse);
      final drossel = a.drosselMb == null
          ? null
          : _Drossel(a.drosselMb! * 1024 * 1024);

      var naechste = 0;
      var erledigt = 0, inFolge = 0;
      Object? abbruch;
      final gescheitert = <String>[];
      void melde() => _fortschritt = (
        gesamt: offen.length,
        erledigt: erledigt,
        bytes: bytes,
        bytesGesamt: bytesGesamt,
      );
      melde();
      Future<void> arbeite() async {
        while (naechste < offen.length && abbruch == null && !_abbrechen) {
          final e = offen[naechste++];
          try {
            await _lege(
              ziel!,
              e.key,
              File(p.joinAll([w.path, ...e.key.split('/')])),
              drossel,
            );
            hoch++;
            bytes += e.value.groesse;
            inFolge = 0;
          } on Zielfehler catch (f) {
            if (f.endgueltig) {
              abbruch = f;
              return;
            }
            gescheitert.add(e.key);
            if (++inFolge >= _fehlerInFolge) abbruch = f;
          } on Exception catch (f) {
            gescheitert.add(e.key);
            if (++inFolge >= _fehlerInFolge) abbruch = f;
          }
          erledigt++;
          melde();
        }
      }

      await Future.wait([for (var i = 0; i < gleichzeitig; i++) arbeite()]);
      offenNachher = offen.length - hoch;
      if (abbruch != null) throw abbruch!;
      if (_abbrechen) throw StateError('Abgebrochen.');
      if (gescheitert.isNotEmpty) {
        throw StateError('${gescheitert.length} Dateien nicht übertragen');
      }

      stichprobe = await _stichprobe(ziel, w, hier);
      if ((stichprobe['abweichend']! as int) > 0) {
        throw const Zielfehler('pv_stichprobe_abweichend');
      }
      geloescht =
          await _alteGenerationen(ziel, dort, hier) +
          await _alteKammerkopien(ziel, dort, hier);
    } catch (e) {
      fehler = '$e';
    } finally {
      ziel?.schliesse();
    }
    final vorher = await _standDatei.exists()
        ? await _lies(_standDatei)
        : const <String, Object?>{};
    final ende = _uhr();
    await _schreibe(_standDatei, {
      'beginn': beginn.toUtc().toIso8601String(),
      'ende': ende.toUtc().toIso8601String(),
      'ok': fehler == null,
      'fehler': ?fehler,
      'dateien': gesamt,
      'neu': hoch,
      'bytes': bytes,
      'offen': offenNachher,
      'geloescht': geloescht,
      'stichprobe': ?stichprobe,
      'letzterErfolg': fehler == null
          ? ende.toUtc().toIso8601String()
          : vorher['letzterErfolg'],
    });
    protokoll(
      fehler == null
          ? 'Sicherung ausser Haus fertig: $hoch Dateien, ${bytes ~/ 1048576} MB'
          : 'Sicherung ausser Haus gescheitert: $fehler',
    );
  }

  Future<void> _lege(
    Aussenziel ziel,
    String pfad,
    File datei,
    _Drossel? drossel,
  ) async {
    var pause = wartezeit;
    for (var versuch = 1; ; versuch++) {
      try {
        // Frisch gefragt: Die Datenbank kann sich seit der Liste geändert
        // haben, wenn der Lauf über Nacht geht.
        final groesse = await datei.length();
        await ziel.lege(pfad, datei, groesse: groesse, durch: drossel?.warte);
        return;
      } on Zielfehler catch (f) {
        if (f.endgueltig || versuch >= 3) rethrow;
      } on TimeoutException {
        if (versuch >= 3) rethrow;
      } on IOException {
        if (versuch >= 3) rethrow;
      }
      await Future<void>.delayed(pause);
      pause *= 4;
    }
  }

  /// Ein Upload, der „200“ sagt, beweist wenig. Stichproben kommen zurück und
  /// werden Byte für Byte mit dem Original verglichen.
  Future<Map<String, Object?>> _stichprobe(
    Aussenziel ziel,
    Directory w,
    Map<String, Zieldatei> hier,
  ) async {
    final kandidaten = [
      for (final e in hier.entries)
        if (e.key.contains('/data/') && e.value.groesse <= _stichprobeBis)
          e.key,
    ]..shuffle(_zufall);
    var abweichend = 0;
    final auswahl = kandidaten.take(_stichproben).toList();
    for (final pfad in auswahl) {
      final dort = await ziel.hole(pfad);
      final datei = File(p.joinAll([w.path, ...pfad.split('/')]));
      final daheim = await sha256.bind(datei.openRead()).first;
      if (sha256.convert(dort) != daheim) abweichend++;
    }
    return {'geprueft': auswahl.length, 'abweichend': abweichend};
  }

  static final _generation = RegExp(
    r'^(.*/generations/[^/]+)/(?:library\.sqlite\.enc|metadata\.json|'
    r'generation\.json)$',
  );

  /// Nur Generationen, die daheim fehlen, und nur, wenn es daheim welche
  /// gibt: Ohne jede Generation stimmt daheim etwas nicht, und drüben ist
  /// dann das Letzte, was noch da ist.
  /// Was die Sicherung aus der Kammer entfernt hat, soll auch drüben fort:
  /// Sonst läge jedes verworfene Foto für immer ausser Haus (#341). Nur
  /// dieser Ordner, die Fotos der Bibliothek löscht hier nichts.
  Future<int> _alteKammerkopien(
    Aussenziel ziel,
    Map<String, Zieldatei> dort,
    Map<String, Zieldatei> hier,
  ) async {
    const kammer = '/${FotokammerSicherung.ordnerName}/';
    // Nur wo daheim schon gesichert wurde: Bei einem neu eingerichteten Ziel
    // fehlt hier noch alles, und drüben läge dann die letzte Kopie.
    final mitDaten = {
      for (final k in hier.keys)
        if (k.contains('/data/')) k.substring(0, k.indexOf('/data/')),
    };
    var geloescht = 0;
    for (final k in dort.keys) {
      final stelle = k.indexOf(kammer);
      if (stelle < 0 || hier.containsKey(k)) continue;
      if (!mitDaten.contains(k.substring(0, stelle))) continue;
      await ziel.loesche(k);
      geloescht++;
    }
    return geloescht;
  }

  Future<int> _alteGenerationen(
    Aussenziel ziel,
    Map<String, Zieldatei> dort,
    Map<String, Zieldatei> hier,
  ) async {
    final daheim = {
      for (final k in hier.keys) ?_generation.firstMatch(k)?.group(1),
    };
    String? bibliothek(String generation) =>
        generation.substring(0, generation.lastIndexOf('/generations/'));
    final mitGeneration = daheim.map(bibliothek).toSet();
    var geloescht = 0;
    for (final k in dort.keys) {
      final g = _generation.firstMatch(k)?.group(1);
      if (g == null || daheim.contains(g)) continue;
      if (!mitGeneration.contains(bibliothek(g))) continue;
      await ziel.loesche(k);
      geloescht++;
    }
    return geloescht;
  }
}
