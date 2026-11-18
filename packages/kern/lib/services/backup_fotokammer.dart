import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import '../protokoll.dart';
import 'vault_crypto.dart';

/// Was ein Lauf von [FotokammerSicherung.sichere] getan hat.
class KammerSicherungsbilanz {
  const KammerSicherungsbilanz({
    required this.eintraege,
    required this.neu,
    required this.geprueft,
    required this.gescheitert,
    required this.entfernt,
  });

  /// Einträge, die jetzt in der Kammer liegen.
  final int eintraege;
  final int neu;
  final int geprueft;
  final int gescheitert;

  /// Kopien, deren Eintrag länger als [FotokammerSicherung.aufbewahren]
  /// fort ist und die dieser Lauf gelöscht hat.
  final int entfernt;
}

/// Ein Eintrag der Kammer, aus der Sicherung gelesen.
class GesicherterKammereintrag {
  const GesicherterKammereintrag(this.ordner, this.angaben, {this.gesichertAm});

  final Directory ordner;
  final Map<String, Object?> angaben;

  /// Wann der Eintrag gesichert wurde – aus dem Vermerk
  /// [FotokammerSicherung.gesichertName], bei älteren Einträgen ohne ihn
  /// die Änderungszeit der Angaben (#388).
  final DateTime? gesichertAm;

  File get datei => File(p.join(ordner.path, FotokammerSicherung.dateiName));
}

/// Die Fotokammer in der Sicherung des Servers (#341).
///
/// **Warum überhaupt.** Wer nach dem Import in die Kammer die Speicherkarte
/// formatiert, hat die Fotos bis zur Freigabe nur noch einmal, auf dem
/// Server. Die Sicherung der Bibliothek kennt sie nicht: Sie geht von den
/// Zeilen der Datenbank aus.
///
/// **Eigener Ordner statt `data/`.** Dort liegen die Dateien der Bibliothek,
/// und nichts darf sie je löschen. Die Kammer ändert sich aber täglich: Wer
/// 45 von 55 Fotos verwirft, will sie nicht auf ewig am NAS. Getrennt
/// genügt zum Aufräumen eine Regel, die keine Datei der Bibliothek treffen
/// kann.
///
/// **Nicht sofort löschen.** Fehlt ein Eintrag in der Kammer, bleibt seine
/// Kopie [aufbewahren] lang liegen. Eine versehentlich geleerte Kammer
/// nähme sonst noch in derselben Nacht ihre Sicherung mit.
///
/// Je Eintrag `fotokammer/<Kennung>/` mit [dateiName] und [angabenName],
/// beide verschlüsselt; auch der Dateiname steht nur in den Angaben.
/// Miniatur und Vorschau fehlen mit Absicht, sie entstehen beim Import neu.
abstract final class FotokammerSicherung {
  static const ordnerName = 'fotokammer';
  static const dateiName = 'datei.enc';
  static const angabenName = 'angaben.enc';

  /// Wann der Eintrag gesichert wurde, als Zeitstempel im Klartext (#388):
  /// Eine ältere Sicherungsstufe holt nur, was zu ihr gehört
  /// ([gehoertZuStufe]). Ohne Punkt, damit er auch ausser Haus mitkommt.
  static const gesichertName = 'gesichert';

  /// Mit Punkt: Die Sicherung ausser Haus überspringt solche Dateien.
  static const _wegSeitName = '.weg-seit';
  static const aufbewahren = Duration(days: 7);

  /// Bringt die [kammer] nach [sicherung] und räumt dort auf.
  static Future<KammerSicherungsbilanz> sichere({
    required Directory kammer,
    required Directory sicherung,
    required SecretKey schluessel,
    required DateTime jetzt,
  }) async {
    final ziel = Directory(p.join(sicherung.path, ordnerName));
    final quellen = <String, File>{};
    final erneuert = <String>{};
    final fehlgeschlagen = <String>{};
    if (await kammer.exists()) {
      await for (final e in kammer.list(followLinks: false)) {
        if (e is! Directory) continue;
        final angaben = File(p.join(e.path, 'angaben.json'));
        if (!await angaben.exists()) continue;
        final id = p.basename(e.path);
        quellen[id] = angaben;
        final platz = Directory(p.join(ziel.path, id));
        final zielAngaben = File(p.join(platz.path, angabenName));
        final zielDatei = File(p.join(platz.path, dateiName));
        try {
          final quelle = await _quelle(angaben);
          if (await zielAngaben.exists() &&
              await VaultCrypto.passtZurGroesse(
                zielDatei,
                await quelle.datei.length(),
              ) &&
              await _angabenLesbar(zielAngaben, schluessel)) {
            await _schreibeVermerk(platz, (await zielAngaben.stat()).modified);
            continue;
          }
          await _sichereEintrag(platz, angaben, quelle, schluessel, jetzt);
          erneuert.add(id);
        } on Object catch (x) {
          // Ein gleichzeitig freigegebener Eintrag ist keine offene Quelle.
          if (await angaben.exists()) {
            fehlgeschlagen.add(id);
            protokoll('Fotokammer: $id nicht gesichert: $x');
          } else {
            quellen.remove(id);
          }
        }
      }
    }
    final entfernt = await _raeumeAuf(ziel, quellen.keys.toSet(), jetzt);
    final probe = await _pruefeKopien(
      ziel,
      quellen,
      erneuert,
      fehlgeschlagen,
      schluessel,
      jetzt,
    );
    return KammerSicherungsbilanz(
      eintraege: quellen.length,
      neu: erneuert.length,
      geprueft: probe,
      gescheitert: fehlgeschlagen.length,
      entfernt: entfernt,
    );
  }

  static Future<({File datei, String pruefsumme})> _quelle(File angaben) async {
    final daten = _leseAngaben(await angaben.readAsString());
    final pruefsumme = daten['sha256'];
    if (pruefsumme is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(pruefsumme)) {
      throw const FormatException('pv_backup_kammer_quellpruefsumme');
    }
    return (
      datei: File(
        p.join(angaben.parent.path, p.basename(daten['name'] as String)),
      ),
      pruefsumme: pruefsumme,
    );
  }

  static Map<String, Object?> _leseAngaben(String text) {
    final daten = jsonDecode(text);
    if (daten is! Map<String, Object?> ||
        daten['name'] is! String ||
        (daten['name'] as String).isEmpty) {
      throw const FormatException('pv_restore_kammer_angaben');
    }
    return daten;
  }

  static Future<Map<String, Object?>> _liesVerschluesselteAngaben(
    File datei,
    SecretKey schluessel,
  ) async => _leseAngaben(
    utf8.decode(await VaultCrypto.decryptFileToBytes(datei, schluessel)),
  );

  static Future<bool> _angabenLesbar(File datei, SecretKey schluessel) async {
    try {
      await _liesVerschluesselteAngaben(datei, schluessel);
      return true;
    } on Object {
      return false;
    }
  }

  static Future<void> _schreibeVermerk(Directory platz, DateTime am) async {
    final vermerk = File(p.join(platz.path, gesichertName));
    if (!await vermerk.exists()) {
      await _schreibeTextAtomar(vermerk, am.toUtc().toIso8601String());
    }
  }

  static Future<void> _schreibeTextAtomar(File ziel, String text) async {
    final teil = File('${ziel.path}.neu');
    await teil.writeAsString(text, flush: true);
    await teil.rename(ziel.path);
  }

  static Future<void> _sichereEintrag(
    Directory platz,
    File angaben,
    ({File datei, String pruefsumme}) quelle,
    SecretKey key,
    DateTime jetzt,
  ) async {
    final bildZiel = File(p.join(platz.path, dateiName));
    final angabenZiel = File(p.join(platz.path, angabenName));
    final am = await angabenZiel.exists()
        ? (await angabenZiel.stat()).modified
        : jetzt;
    final bild = File('${bildZiel.path}.neu');
    final meta = File('${angabenZiel.path}.neu');
    await platz.create(recursive: true);
    try {
      await VaultCrypto.encryptFile(
        quelle.datei,
        bild,
        key,
        erwartetePruefsumme: quelle.pruefsumme,
      );
      await VaultCrypto.encryptFile(angaben, meta, key);
      final geschrieben = await _liesVerschluesselteAngaben(meta, key);
      if (geschrieben['sha256'] != quelle.pruefsumme) {
        throw const FormatException('pv_backup_kammer_quelle_geaendert');
      }
      await bild.rename(bildZiel.path);
      await meta.rename(angabenZiel.path);
      // Erst das fertige Paar erhält den Abschlussvermerk. Ein vorhandener
      // Vermerk behält bei der Reparatur die ursprüngliche Sicherungszeit.
      await _schreibeVermerk(platz, am);
    } finally {
      if (await bild.exists()) await bild.delete();
      if (await meta.exists()) await meta.delete();
    }
  }

  static const _probeAnzahl = 8;
  static const _probeBytes = 256 * 1024 * 1024;

  /// Prüft wechselnde Kopien, auch nachdem die Quelle die Kammer verlassen
  /// hat. Erkannte Schäden zählen weiter, bis sie repariert oder gemäß
  /// Aufbewahrungsfrist entfernt wurden.
  static Future<int> _pruefeKopien(
    Directory ziel,
    Map<String, File> quellen,
    Set<String> erneuert,
    Set<String> fehlgeschlagen,
    SecretKey key,
    DateTime jetzt,
  ) async {
    if (!await ziel.exists()) return 0;
    final stand = File(p.join(ziel.path, '.pruefstand'));
    final alt = await stand.exists()
        ? jsonDecode(await stand.readAsString()) as Map
        : const {};
    var zuletzt = alt['zuletzt'] as String?;
    final offen = (alt['offen'] as List? ?? const []).cast<String>().toSet();
    offen.removeAll(erneuert);

    final kopien = <String, Directory>{};
    await for (final e in ziel.list(followLinks: false)) {
      if (e is Directory &&
          (await File(p.join(e.path, angabenName)).exists() ||
              await File(p.join(e.path, gesichertName)).exists())) {
        kopien[p.basename(e.path)] = e;
      }
    }
    offen.retainAll(kopien.keys);
    final ids = kopien.keys.toList()..sort();
    var start = zuletzt == null
        ? 0
        : ids.indexWhere((id) => id.compareTo(zuletzt!) > 0);
    if (start < 0) start = 0;
    var geprueft = 0, bytes = 0;
    for (var i = 0; i < ids.length && geprueft < _probeAnzahl; i++) {
      final id = ids[(start + i) % ids.length];
      final platz = kopien[id]!;
      final datei = File(p.join(platz.path, dateiName));
      // Die erste Datei immer prüfen, damit auch sehr große Videos drankommen.
      final groesse = (await datei.stat()).size;
      if (geprueft > 0 && bytes + groesse > _probeBytes) break;
      bytes += groesse;
      zuletzt = id;
      geprueft++;
      try {
        final daten = await _liesVerschluesselteAngaben(
          File(p.join(platz.path, angabenName)),
          key,
        );
        await VaultCrypto.pruefeDatei(
          datei,
          key,
          erwartetePruefsumme: daten['sha256'] as String?,
        );
        offen.remove(id);
      } on Object catch (x) {
        protokoll(
          'Fotokammer: $id bei der Wiederherstellungsprobe beschädigt: $x',
        );
        final angaben = quellen[id];
        if (angaben != null && !fehlgeschlagen.contains(id)) {
          try {
            await _sichereEintrag(
              platz,
              angaben,
              await _quelle(angaben),
              key,
              jetzt,
            );
            erneuert.add(id);
            offen.remove(id);
            continue;
          } on Object catch (x) {
            protokoll('Fotokammer: $id konnte nicht neu gesichert werden: $x');
          }
        }
        offen.add(id);
      }
    }
    await _schreibeTextAtomar(
      stand,
      jsonEncode({'zuletzt': zuletzt, 'offen': offen.toList()..sort()}),
    );
    fehlgeschlagen.addAll(offen);
    return geprueft;
  }

  static Future<int> _raeumeAuf(
    Directory ziel,
    Set<String> da,
    DateTime jetzt,
  ) async {
    if (!await ziel.exists()) return 0;
    var entfernt = 0;
    await for (final e in ziel.list(followLinks: false)) {
      if (e is! Directory) continue;
      final marke = File(p.join(e.path, _wegSeitName));
      if (da.contains(p.basename(e.path))) {
        if (await marke.exists()) await marke.delete();
        continue;
      }
      final seit = await marke.exists()
          ? DateTime.tryParse(await marke.readAsString())
          : null;
      if (seit == null) {
        await marke.writeAsString(jetzt.toUtc().toIso8601String());
      } else if (jetzt.difference(seit) >= aufbewahren) {
        await e.delete(recursive: true);
        entfernt++;
      }
    }
    return entfernt;
  }

  /// Ob ein Eintrag, gesichert um [gesichertAm], zur Sicherungsstufe von
  /// [stufe] gehört, wenn die nächste Stufe um [naechste] entstand (#388).
  ///
  /// Bei früheren Fassungen konnte die Kammer erst Minuten nach dem
  /// Schnappschuss folgen. Dazu gehört, was bis [nachlauf] danach gesichert
  /// wurde, aber nicht mehr, was zur nächsten Stufe kam.
  /// Bis 3.67.2 holte jede ältere Stufe auch Kammerfotos, die erst später
  /// gesichert wurden. Die neueste Stufe ([naechste] `null`) holt alles,
  /// wie eine Wiederherstellung ohne gewählte Stufe.
  static bool gehoertZuStufe(
    DateTime? gesichertAm, {
    required DateTime stufe,
    DateTime? naechste,
  }) {
    if (gesichertAm == null || naechste == null) return true;
    var bis = stufe.add(nachlauf);
    if (naechste.isBefore(bis)) bis = naechste;
    return !gesichertAm.isAfter(bis);
  }

  /// Wie lange nach einer Sicherungsstufe die Kammer noch zu ihr zählt.
  static const nachlauf = Duration(hours: 12);

  /// Die vollständigen Einträge einer Sicherung unter [wurzel]. Was sich
  /// nicht lesen lässt oder ohne Datei dasteht, meldet [beiFehler] (#388) –
  /// bis 3.67.2 stand es nur im Protokoll, und eine Wiederherstellung mit
  /// beschädigten Angaben galt als erfolgreich.
  static Future<List<GesicherterKammereintrag>> eintraege(
    String wurzel,
    SecretKey schluessel, {
    bool Function(DateTime? am)? auswahl,
    void Function(String eintrag, Object fehler)? beiFehler,
  }) async {
    final ordner = Directory(p.join(wurzel, ordnerName));
    if (!await ordner.exists()) return const [];
    final aus = <GesicherterKammereintrag>[];
    await for (final e in ordner.list(followLinks: false)) {
      if (e is! Directory) continue;
      final angaben = File(p.join(e.path, angabenName));
      final vermerk = File(p.join(e.path, gesichertName));
      final id = p.basename(e.path);
      try {
        final hatAngaben = await angaben.exists();
        final hatVermerk = await vermerk.exists();
        if (!hatAngaben && !hatVermerk) continue;
        final vermerkt = hatVermerk
            ? DateTime.tryParse((await vermerk.readAsString()).trim())
            : null;
        final am =
            vermerkt ?? (hatAngaben ? (await angaben.stat()).modified : null);
        if (auswahl?.call(am) == false) continue;
        if (!hatAngaben) {
          throw const FormatException('pv_restore_kammer_angaben_fehlen');
        }
        if (!await File(p.join(e.path, dateiName)).exists()) {
          throw const FormatException('pv_restore_kammer_datei_fehlt');
        }
        final daten = await _liesVerschluesselteAngaben(angaben, schluessel);
        aus.add(GesicherterKammereintrag(e, daten, gesichertAm: am));
      } on Object catch (x) {
        protokoll('pv_restore_kammer: $id: $x');
        beiFehler?.call(id, x);
      }
    }
    return aus;
  }
}
