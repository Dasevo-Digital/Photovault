import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:kern/services/beilagenangaben.dart';
import 'package:kern/services/import_plan.dart';
import 'package:kern/services/import_service.dart';
import 'package:path/path.dart' as p;

import 'begrenzter_ausgabestrom.dart';
import 'xmp_reader.dart';

class Umzugsquelle {
  Umzugsquelle._(this.dateien, this.beilagen, this.fehler, this._temp);
  final List<String> dateien;
  final Map<String, Beilagenangaben> beilagen;
  final Set<String> fehler;
  final Map<String, List<String>> konflikte = {};
  final Directory? _temp;

  /// Takeout wiederholt dieselbe Datei für jedes Album. Nur die erste
  /// Kopie wird importiert; ihre Albumzuordnungen bleiben vollständig.
  void verbindeDubletten(ImportPlan plan) {
    final gruppen = <String, List<String>>{};
    for (final e in plan.eintraege) {
      if (e.angaben case final a?) {
        gruppen.putIfAbsent(a.pruefsumme, () => []).add(e.pfad);
      }
    }
    for (final pfade in gruppen.values.where((p) => p.length > 1)) {
      final scalar = <String, Object?>{};
      final alben = <String>{}, tags = <String>{};
      var konflikt = pfade.any(fehler.contains);
      var favorit = false;
      for (final pfad in pfade) {
        final j = beilagen[pfad]?.alsMap() ?? {};
        alben.addAll((j['alben'] as List?)?.cast<String>() ?? []);
        tags.addAll((j['schlagwoerter'] as List?)?.cast<String>() ?? []);
        favorit |= j['favorit'] == true;
        for (final e in j.entries) {
          if ({'alben', 'schlagwoerter', 'favorit'}.contains(e.key)) continue;
          if (scalar.containsKey(e.key) && scalar[e.key] != e.value) {
            konflikt = true;
          }
          scalar[e.key] = e.value;
        }
      }
      final wert = Beilagenangaben.aus({
        ...scalar,
        'alben': alben.toList(),
        'schlagwoerter': tags.toList(),
        'favorit': favorit,
      });
      if (wert != null &&
          utf8.encode(jsonEncode(wert.alsMap())).length >
              Beilagenangaben.hoechstensBytes) {
        konflikt = true;
      }
      for (final pfad in pfade) {
        if (konflikt) {
          fehler.add(pfad);
          beilagen.remove(pfad);
        } else if (wert != null) {
          beilagen[pfad] = wert;
        }
      }
    }
  }

  Future<void> schliesse() async {
    if (_temp != null && await _temp.exists()) {
      await _temp.delete(recursive: true);
    }
  }

  static Future<Umzugsquelle> ordner(String pfad) =>
      Isolate.run(() => _lies(pfad, null));

  static Future<Umzugsquelle> archive(List<String> pfade) async {
    if (pfade.isEmpty) throw const FormatException('pv_umzug_quelle');
    final temp = await Directory.systemTemp.createTemp('pv_umzug_');
    try {
      if (!Platform.isWindows) {
        final rechte = await Process.run('chmod', ['700', temp.path]);
        if (rechte.exitCode != 0) {
          throw const FileSystemException('pv_umzug_rechte');
        }
      }
      final ziel = temp.path;
      await Isolate.run(() => _entpacke(pfade, ziel));
      return await Isolate.run(() => _lies(ziel, temp));
    } on Object {
      await temp.delete(recursive: true);
      rethrow;
    }
  }

  static Future<Umzugsquelle> _lies(String root, Directory? temp) async {
    final alle = await ImportPlanDienst.dateienImOrdner(root);
    final medien = alle.where(unterstuetztesFormat).toList();
    final medienNamen = medien.map((s) => s.toLowerCase()).toSet();
    final json = <String, List<Map>>{};
    final alben = <String, String>{};
    final fehler = <String>{};
    final defekt = <String>{};
    for (final pfad in alle.where(
      (s) => p.extension(s).toLowerCase() == '.json',
    )) {
      final file = File(pfad);
      try {
        if (await file.length() > 1024 * 1024) throw const FormatException();
        final wert = jsonDecode(await file.readAsString());
        if (wert is! Map) continue;
        final titel = wert['title'];
        final ordner = p.dirname(pfad);
        if (p.basename(pfad).toLowerCase() == 'metadata.json' &&
            titel is String &&
            titel.trim().isNotEmpty &&
            titel.length <= 200) {
          alben[ordner] = titel.trim();
        }
        final beilageName = pfad.replaceFirst(
          RegExp(r'(\.supplemental-metadata)?\.json$', caseSensitive: false),
          '',
        );
        if (medienNamen.contains(beilageName.toLowerCase())) {
          json.putIfAbsent(beilageName.toLowerCase(), () => []).add(wert);
        } else if (titel is String &&
            p.basename(titel) == titel &&
            unterstuetztesFormat(titel)) {
          json
              .putIfAbsent(p.join(ordner, titel).toLowerCase(), () => [])
              .add(wert);
        }
      } on Object {
        defekt.add(pfad.toLowerCase());
      }
    }
    final beilagen = <String, Beilagenangaben>{};
    final konflikte = <String, List<String>>{};
    for (final pfad in medien) {
      try {
        final kandidaten = json[pfad.toLowerCase()] ?? [];
        if (kandidaten.length > 1 &&
            kandidaten.map(jsonEncode).toSet().length > 1) {
          throw const FormatException('pv_umzug_mehrdeutig');
        }
        if (defekt.contains('$pfad.json'.toLowerCase()) ||
            defekt.contains('$pfad.supplemental-metadata.json'.toLowerCase())) {
          throw const FormatException('pv_umzug_json');
        }
        for (final name in [p.setExtension(pfad, '.xmp'), '$pfad.xmp']) {
          final typ = FileSystemEntity.typeSync(name, followLinks: false);
          if (typ != FileSystemEntityType.notFound &&
              (typ != FileSystemEntityType.file ||
                  File(name).lengthSync() > 1024 * 1024 ||
                  parseXmpFile(File(name)) == null)) {
            throw const FormatException('pv_umzug_xmp');
          }
        }
        final xmp = beilageNeben(pfad);
        final takeout = kandidaten.firstOrNull;
        final datum = (takeout?['photoTakenTime'] as Map?)?['timestamp'];
        final sekunden = datum is String ? int.tryParse(datum) : null;
        if (datum != null &&
            (sekunden == null || sekunden.abs() > 253402300799)) {
          throw const FormatException('pv_umzug_datum');
        }
        final geo = takeout?['geoData'] as Map?;
        final breite = geo?['latitude'], laenge = geo?['longitude'];
        final ort =
            breite is num &&
            laenge is num &&
            breite.isFinite &&
            laenge.isFinite &&
            breite.abs() <= 90 &&
            laenge.abs() <= 180 &&
            (breite != 0 || laenge != 0);
        final beschreibung = takeout?['description'];
        if (beschreibung is String &&
            beschreibung.isNotEmpty &&
            xmp?.beschreibung != null &&
            beschreibung != xmp!.beschreibung) {
          konflikte[pfad] = [
            'Takeout: $beschreibung',
            'XMP: ${xmp.beschreibung}',
          ];
        }
        final beilage = Beilagenangaben(
          sterne: xmp?.sterne,
          abgelehnt: xmp?.abgelehnt ?? false,
          farbe: xmp?.farbe,
          beschreibung: beschreibung is String && beschreibung.isNotEmpty
              ? beschreibung
              : xmp?.beschreibung,
          schlagwoerter: xmp?.schlagwoerter ?? const [],
          breite: ort ? breite.toDouble() : xmp?.breite,
          laenge: ort ? laenge.toDouble() : xmp?.laenge,
          aufgenommenAm: sekunden == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  sekunden * 1000,
                  isUtc: true,
                ),
          alben: [?alben[p.dirname(pfad)]],
          favorit: takeout?['favorited'] == true,
        );
        if (utf8.encode(jsonEncode(beilage.alsMap())).length >
            Beilagenangaben.hoechstensBytes) {
          throw const FormatException('pv_umzug_angaben_zu_gross');
        }
        if (beilage.alsMap().isNotEmpty) beilagen[pfad] = beilage;
      } on Object {
        fehler.add(pfad);
      }
    }
    return Umzugsquelle._(medien, beilagen, fehler, temp)
      ..konflikte.addAll(konflikte);
  }
}

Future<void> _entpacke(List<String> pfade, String ziel) async {
  var total = 0, anzahl = 0;
  final globaleNamen = <String, String>{};
  for (final pfad in pfade) {
    final input = InputFileStream(pfad);
    final namen = <String>{};
    try {
      final archive = ZipDecoder().decodeStream(
        input,
        verify: true,
        callback: (entry) {
          final name = entry.name.replaceAll('\\', '/');
          final teile = name.split('/').where((s) => s.isNotEmpty);
          if (entry.isSymbolicLink ||
              name.isEmpty ||
              name.contains('//') ||
              name.startsWith('/') ||
              teile.any(
                (s) =>
                    s == '..' ||
                    s == '.' ||
                    s.contains(':') ||
                    RegExp(r'[\x00-\x1f]').hasMatch(s) ||
                    RegExp(
                      r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
                      caseSensitive: false,
                    ).hasMatch(s) ||
                    s.endsWith('.') ||
                    s.endsWith(' '),
              ) ||
              !namen.add(name.toLowerCase()) ||
              entry.size < 0 ||
              ++anzahl > 200000) {
            throw const FormatException('pv_umzug_zip_pfad');
          }
          total += entry.size;
          if (total > 512 * 1024 * 1024 * 1024 ||
              entry.size > File(pfad).lengthSync() * 100 + 64 * 1024 * 1024) {
            throw const FormatException('pv_umzug_zip_groesse');
          }
        },
      );
      for (final entry in archive) {
        final name = entry.name.replaceAll('\\', '/');
        final key = name.toLowerCase();
        if (globaleNamen.containsKey(key) && globaleNamen[key] != name) {
          throw const FormatException('pv_umzug_zip_mehrdeutig');
        }
        globaleNamen[key] = name;
        if (entry.isDirectory) continue;
        final datei = File(p.joinAll([ziel, ...name.split('/')]));
        if (!p.isWithin(ziel, datei.path)) {
          throw const FormatException('pv_umzug_zip_pfad');
        }
        datei.parent.createSync(recursive: true);
        final staging = Directory(ziel).createTempSync('.pv-teil-');
        final teil = File(p.join(staging.path, 'inhalt'));
        final output = BegrenzterDateiAusgabestrom(teil.path, entry.size);
        try {
          entry.writeContent(output);
          if (output.length != entry.size) {
            throw const FormatException('pv_umzug_zip_groesse');
          }
        } catch (_) {
          output.closeSync();
          staging.deleteSync(recursive: true);
          rethrow;
        } finally {
          output.closeSync();
        }
        if (datei.existsSync()) {
          if (datei.lengthSync() != teil.lengthSync() ||
              await sha256.bind(datei.openRead()).first !=
                  await sha256.bind(teil.openRead()).first) {
            throw const FormatException('pv_umzug_zip_mehrdeutig');
          }
          teil.deleteSync();
        } else {
          teil.renameSync(datei.path);
        }
        staging.deleteSync(recursive: true);
      }
    } finally {
      input.closeSync();
    }
  }
}
