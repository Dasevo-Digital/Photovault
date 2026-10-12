import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kern und Server rechnen mit denselben Paketfassungen wie die App.
///
/// Sie lösen ihre Pakete selbst auf (der Server soll sich ohne Flutter bauen
/// lassen), und pub wählt dabei gern neuere Fassungen. Schon eine andere
/// Fassung von `package:image` verkleinert ein Bild anders – gemessen
/// verschob das die CLIP-Einbettung und änderte den Satz von Florence. Ein
/// Server, der anders rechnet als die App, liefert keine austauschbaren
/// Ergebnisse. Angleichen: `python3 tool/pakete_angleichen.py`.
void main() {
  Map<String, String> fassungen(String datei) {
    final aus = <String, String>{};
    String? name;
    var gehostet = false;
    for (final z in File(datei).readAsLinesSync()) {
      final kopf = RegExp(r'^  ([A-Za-z0-9_]+):$').firstMatch(z);
      if (kopf != null) {
        name = kopf.group(1);
        gehostet = false;
        continue;
      }
      if (z.trim() == 'source: hosted') gehostet = true;
      final v = RegExp(r'^    version: "(.+)"$').firstMatch(z);
      if (v != null && name != null && gehostet) aus[name] = v.group(1)!;
    }
    return aus;
  }

  final app = fassungen('pubspec.lock');

  /// Was [paket] zur Laufzeit braucht – ohne die Werkzeuge zum Bauen und
  /// Prüfen (build_runner, drift_dev, test), die nichts rechnen und eigene
  /// Fassungen haben dürfen.
  Set<String> laufzeit(String paket) {
    final r = Process.runSync('dart', [
      'pub',
      'deps',
      '--json',
    ], workingDirectory: paket);
    final d = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    final pakete = {
      for (final p in (d['packages'] as List).cast<Map<String, dynamic>>())
        p['name'] as String: p,
    };
    final wurzel = pakete.values.firstWhere((p) => p['kind'] == 'root');
    final offen = [...(wurzel['directDependencies'] as List).cast<String>()];
    final gesehen = <String>{};
    while (offen.isNotEmpty) {
      final n = offen.removeLast();
      if (!gesehen.add(n) || !pakete.containsKey(n)) continue;
      offen.addAll((pakete[n]!['dependencies'] as List).cast<String>());
    }
    return gesehen;
  }

  for (final paket in ['packages/kern', 'packages/server']) {
    test('$paket hat die Fassungen der App', () {
      final eigene = fassungen('$paket/pubspec.lock');
      final noetig = laufzeit(paket);
      expect(noetig, contains('image'), reason: 'pub deps lieferte nichts');
      final anders = [
        for (final e in eigene.entries)
          if (noetig.contains(e.key) &&
              app[e.key] != null &&
              app[e.key] != e.value)
            '${e.key}: ${e.value} statt ${app[e.key]}',
      ];
      expect(
        anders,
        isEmpty,
        reason: 'python3 tool/pakete_angleichen.py gleicht sie an',
      );
    });
  }
}
