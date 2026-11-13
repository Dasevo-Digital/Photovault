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
    required this.gescheitert,
    required this.entfernt,
  });

  /// Einträge, die jetzt in der Kammer liegen.
  final int eintraege;
  final int neu;
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
    final da = <String>{};
    var neu = 0, gescheitert = 0;
    if (await kammer.exists()) {
      await for (final e in kammer.list(followLinks: false)) {
        if (e is! Directory) continue;
        final angaben = File(p.join(e.path, 'angaben.json'));
        // Ohne Angaben: ein abgebrochener Upload, kein Eintrag.
        if (!await angaben.exists()) continue;
        final id = p.basename(e.path);
        da.add(id);
        final platz = Directory(p.join(ziel.path, id));
        final zielAngaben = File(p.join(platz.path, angabenName));
        // Die Angaben kommen zuletzt: Sind sie da, ist es auch die Datei,
        // und ein Eintrag ändert sich nie.
        if (await zielAngaben.exists()) continue;
        try {
          final j = jsonDecode(await angaben.readAsString()) as Map;
          final name = p.basename('${j['name']}');
          await platz.create(recursive: true);
          await _verschluessele(
            File(p.join(e.path, name)),
            File(p.join(platz.path, dateiName)),
            schluessel,
          );
          await File(
            p.join(platz.path, gesichertName),
          ).writeAsString(jetzt.toUtc().toIso8601String());
          await _verschluessele(angaben, zielAngaben, schluessel);
          neu++;
        } on Object catch (x) {
          // Mitten im Lauf freigegeben oder verworfen ist kein Fehler.
          if (await angaben.exists()) {
            gescheitert++;
            protokoll('Fotokammer: $id nicht gesichert: $x');
          } else {
            da.remove(id);
          }
        }
      }
    }
    return KammerSicherungsbilanz(
      eintraege: da.length,
      neu: neu,
      gescheitert: gescheitert,
      entfernt: await _raeumeAuf(ziel, da, jetzt),
    );
  }

  static Future<void> _verschluessele(
    File von,
    File nach,
    SecretKey schluessel,
  ) async {
    final teil = File('${nach.path}.neu');
    await VaultCrypto.encryptFile(von, teil, schluessel);
    await teil.rename(nach.path);
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
  /// Der Server sichert die Kammer gleich nach der Bibliothek, also Minuten
  /// nach dem Schnappschuss der Stufe. Dazu gehört, was bis [nachlauf]
  /// danach gesichert wurde, aber nicht mehr, was zur nächsten Stufe kam.
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
    SecretKey schluessel,
    Directory zwischenlager, {
    void Function(String eintrag, Object fehler)? beiFehler,
  }) async {
    final ordner = Directory(p.join(wurzel, ordnerName));
    if (!await ordner.exists()) return const [];
    final aus = <GesicherterKammereintrag>[];
    await for (final e in ordner.list(followLinks: false)) {
      if (e is! Directory) continue;
      final angaben = File(p.join(e.path, angabenName));
      if (!await angaben.exists()) continue;
      final klar = File(
        p.join(zwischenlager.path, '${p.basename(e.path)}.json'),
      );
      final id = p.basename(e.path);
      try {
        if (!await File(p.join(e.path, dateiName)).exists()) {
          throw const FormatException('pv_restore_kammer_datei_fehlt');
        }
        await VaultCrypto.decryptFile(angaben, klar, schluessel);
        final j = jsonDecode(await klar.readAsString());
        if (j is! Map) throw const FormatException('pv_restore_kammer_angaben');
        final vermerk = File(p.join(e.path, gesichertName));
        final am = await vermerk.exists()
            ? DateTime.tryParse((await vermerk.readAsString()).trim())
            : null;
        aus.add(
          GesicherterKammereintrag(
            e,
            j.cast<String, Object?>(),
            gesichertAm: am ?? (await angaben.stat()).modified,
          ),
        );
      } on Object catch (x) {
        protokoll('pv_restore_kammer: $id: $x');
        beiFehler?.call(id, x);
      } finally {
        if (await klar.exists()) await klar.delete();
      }
    }
    return aus;
  }
}
