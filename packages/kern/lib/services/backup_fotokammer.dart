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
  const GesicherterKammereintrag(this.ordner, this.angaben);

  final Directory ordner;
  final Map<String, Object?> angaben;

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

  /// Die vollständigen Einträge einer Sicherung unter [wurzel]; was sich
  /// nicht lesen lässt, zählt nicht.
  static Future<List<GesicherterKammereintrag>> eintraege(
    String wurzel,
    SecretKey schluessel,
    Directory zwischenlager,
  ) async {
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
      try {
        await VaultCrypto.decryptFile(angaben, klar, schluessel);
        final j = jsonDecode(await klar.readAsString());
        if (j is Map) {
          aus.add(GesicherterKammereintrag(e, j.cast<String, Object?>()));
        }
      } on Object catch (x) {
        protokoll('pv_restore_kammer: ${p.basename(e.path)}: $x');
      } finally {
        if (await klar.exists()) await klar.delete();
      }
    }
    return aus;
  }
}
