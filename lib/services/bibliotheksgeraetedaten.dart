import 'dart:io';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Eine neutrale Kennung verbindet den Katalog mit den Einstellungen auf
/// diesem Gerät. Sie zieht mit dem Ordner um; Pfade und Zugriffsrechte
/// bleiben im privaten Programmbereich. Sicherung und Serverumzug nehmen
/// die versteckte Kennung nicht mit.
class Bibliotheksgeraetedaten {
  static final _offen = <String, Future<String>>{};
  static Future<String> kennung(StoragePaths paths) => kennungVon(paths.root);

  /// [kennung] für den Ordner `library/` einer Bibliothek.
  static Future<String> kennungVon(Directory bibliothek) async {
    final root = await bibliothek.resolveSymbolicLinks();
    if (_offen.length >= 128 && !_offen.containsKey(root)) {
      _offen.remove(_offen.keys.first);
    }
    final lauf = _offen.putIfAbsent(root, () => _lese(Directory(root)));
    try {
      return await lauf;
    } catch (_) {
      if (identical(_offen[root], lauf)) _offen.remove(root);
      rethrow;
    }
  }

  static Future<String?> bestehendeKennung(Directory root) async {
    final datei = File(p.join(root.path, '.standortkennung'));
    final art = await FileSystemEntity.type(datei.path, followLinks: false);
    if (art == FileSystemEntityType.file) {
      if (await datei.length() > 80) {
        throw const FormatException('pv_geraetedaten_kennung');
      }
      final s = await datei.readAsString();
      if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(s)) {
        throw const FormatException('pv_geraetedaten_kennung');
      }
      return s;
    }
    if (art != FileSystemEntityType.notFound) {
      throw const FormatException('pv_geraetedaten_pfad');
    }
    return null;
  }

  static Future<String> _lese(Directory root) async {
    final vorhanden = await bestehendeKennung(root);
    if (vorhanden != null) return vorhanden;
    final datei = File(p.join(root.path, '.standortkennung'));
    final id = const Uuid().v4(),
        teil = File('${datei.path}.${const Uuid().v4()}.part');
    try {
      await teil.writeAsString(id, flush: true);
      await teil.rename(datei.path);
      return id;
    } finally {
      if (await teil.exists()) await teil.delete();
    }
  }
}
