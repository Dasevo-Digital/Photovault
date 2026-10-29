import 'dart:io';

import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:path/path.dart' as p;

/// Das Telefon hält die Kopie ausschließlich im privaten App-Verzeichnis.
/// Der Schlüssel liegt getrennt von der SQLite-Datei; exportiert wird er nicht.
class Fallschluesselablage implements Tokenablage {
  const Fallschluesselablage(this.ordner);
  final Directory ordner;

  File _datei(String kennung) {
    if (!RegExp(r'^[a-f0-9]{48}$').hasMatch(kennung)) {
      throw const TokenablageFehler();
    }
    return File(p.join(ordner.path, kennung));
  }

  @override
  Future<String?> lies(String kennung) async {
    final f = _datei(kennung);
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<bool> schreibe(String kennung, String wert) async {
    try {
      await ordner.create(recursive: true);
      final f = _datei(kennung);
      final teil = File('${f.path}.neu');
      await teil.writeAsString(wert, flush: true);
      await teil.rename(f.path);
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> loesche(String kennung) async {
    final f = _datei(kennung);
    if (await f.exists()) await f.delete();
  }
}
