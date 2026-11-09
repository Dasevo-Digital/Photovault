import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:kern/db/database.dart';
import 'package:kern/protokoll.dart';
import 'package:kern/services/platform/desktop_image_tools.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import 'anmeldung_api.dart';
import 'bibliothek.dart';
import 'bibliotheken.dart';

/// Rendert ein Foto mit seiner darktable-Bearbeitung (#351).
///
/// **Warum am Server.** Die Bearbeitung steht in der XMP-Datei als binäre
/// Parameter je Modul und Modulversion; nachrechnen kann das nur darktable.
/// Das Original liegt am Server, also rechnet dort `darktable-cli`, und das
/// Ergebnis erscheint auf allen Geräten wie eine Entwicklung aus Photo Vault.
///
/// **Freiwillig.** Ohne das Programm geht alles andere wie bisher, die Apps
/// erfahren es über `funktionen.darktable`.
///
/// **Einer nach dem anderen**, und jeder in einem eigenen Wegwerfordner:
/// darktable sperrt seine Bibliothek, und ein Lauf belegt mehrere Kerne.
class DarktableEntwickler {
  DarktableEntwickler({
    Future<String?> Function()? finde,
    this.frist = const Duration(minutes: 5),
  }) : _finde = finde ?? (() => DesktopImageTools.aufruf('darktable-cli'));

  final Future<String?> Function() _finde;

  /// Wie lange ein Lauf dauern darf. Hängt er, hielte er sonst die Reihe auf.
  final Duration frist;

  String? _programm;
  var _gesucht = false;
  Future<void> _reihe = Future.value();

  /// Ob das Programm da ist; erst nach [suche] verlässlich.
  bool get da => _programm != null;

  Future<bool> suche() async {
    if (!_gesucht) {
      _gesucht = true;
      _programm = await _finde();
      if (_programm != null) protokoll('darktable-cli gefunden: $_programm');
    }
    return da;
  }

  /// Das fertige JPEG mit höchstens [kante] Punkten an der langen Seite;
  /// `null`, wenn es nicht geklappt hat.
  Future<Uint8List?> entwickle(File original, File xmp, {int kante = 4096}) {
    final fertig = _reihe.then((_) => _lauf(original, xmp, kante));
    _reihe = fertig.then((_) {}, onError: (_) {});
    return fertig;
  }

  Future<Uint8List?> _lauf(File original, File xmp, int kante) async {
    final programm = _programm;
    if (programm == null) return null;
    final ordner = await Directory.systemTemp.createTemp('pv_darktable_');
    try {
      final aus = File(p.join(ordner.path, 'ergebnis.jpg'));
      final proc = await Process.start(
        programm,
        [
          original.path,
          xmp.path,
          aus.path,
          '--width',
          '$kante',
          '--height',
          '$kante',
          '--hq',
          'true',
          '--apply-custom-presets',
          'false',
          '--core',
          // Eine eigene, leere Bibliothek je Lauf: Die Bearbeitung kommt
          // allein aus der XMP-Datei.
          '--library',
          ':memory:',
          '--configdir',
          p.join(ordner.path, 'config'),
          '--cachedir',
          p.join(ordner.path, 'cache'),
          '--tmpdir',
          ordner.path,
          '--conf',
          'plugins/imageio/format/jpeg/quality=92',
        ],
        environment: {'HOME': ordner.path},
      );
      final fehler = StringBuffer();
      proc.stdout.drain<void>().ignore();
      proc.stderr.transform(utf8.decoder).listen(fehler.write, onError: (_) {});
      final code = await proc.exitCode.timeout(
        frist,
        onTimeout: () {
          proc.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      if (code != 0 || !await aus.exists()) {
        final grund = '$fehler'.trim();
        protokoll(
          'darktable-cli gescheitert (Code $code) bei '
          '${p.basename(original.path)}'
          '${grund.isEmpty ? '' : ': ${grund.substring(0, grund.length.clamp(0, 300))}'}',
        );
        return null;
      }
      return await aus.readAsBytes();
    } on ProcessException catch (e) {
      protokoll('darktable-cli liess sich nicht starten: $e');
      return null;
    } finally {
      await ordner.delete(recursive: true);
    }
  }
}

/// `PUT /api/v1/darktable/<id>`: die XMP-Datei mit der Bearbeitung.
/// `GET` sagt, wie weit es ist.
class Darktableapi {
  Darktableapi(this.bibliotheken, this.entwickler);

  final Bibliotheken bibliotheken;
  final DarktableEntwickler entwickler;

  /// Wie es je Aufnahme steht. Nur im Speicher: Nach einem Neustart gibt es
  /// nichts mehr, worauf eine App noch warten könnte.
  final _stand = <String, String>{};

  Future<Bibliothek> _bibliothek(Request r) async =>
      (await bibliotheken.fuer(kontoVon(r).id)).bibliothek;

  static bool _zulaessig(AssetData? a) =>
      a != null && !a.isLocked && !a.isTrashed && a.type == 'IMAGE';

  /// Nimmt die Bearbeitung an und rechnet im Hintergrund: Das dauert länger,
  /// als ein Proxy davor auf eine Antwort wartet. → 202.
  Future<Response> bearbeitung(Request r, String id) async {
    if (!await entwickler.suche()) {
      return _json({'fehler': 'pv_darktable_fehlt'}, status: 501);
    }
    final b = await _bibliothek(r);
    final a = await b.db.assetById(id);
    if (!_zulaessig(a)) return _json({'fehler': 'unbekannt'}, status: 404);
    final text = await r.readAsString();
    if (!text.contains('darktable:history')) {
      return _json({'fehler': 'pv_darktable_leer'}, status: 422);
    }
    final xmp = File(p.join(b.ordner.path, 'darktable', '${a!.id}.xmp'));
    await xmp.parent.create(recursive: true);
    final teil = File('${xmp.path}.neu');
    await teil.writeAsString(text, flush: true);
    await teil.rename(xmp.path);
    _stand[a.id] = 'laeuft';
    unawaited(_entwickle(b, a, xmp));
    return _json({'stand': 'laeuft'}, status: 202);
  }

  Future<Response> stand(Request r, String id) async {
    final b = await _bibliothek(r);
    if (await b.db.assetById(id) == null) {
      return _json({'fehler': 'unbekannt'}, status: 404);
    }
    return _json({'stand': _stand[id] ?? 'keiner'});
  }

  Future<void> _entwickle(Bibliothek b, AssetData a, File xmp) async {
    var ausgang = 'fehler';
    try {
      final jpeg = await entwickler.entwickle(
        b.pfade.absolute(a.relativePath),
        xmp,
      );
      if (jpeg == null) return;
      // Während des Rechnens kann das Foto gesperrt oder gelöscht worden
      // sein. Dann gehört das Ergebnis nirgends hin.
      final jetzt = await b.db.assetById(a.id);
      if (!_zulaessig(jetzt)) return;
      final pfad = b.pfade.neuerEntwicklungspfad(a.id);
      final datei = b.pfade.absolute(pfad);
      await datei.parent.create(recursive: true);
      await datei.writeAsBytes(jpeg, flush: true);
      await b.db.fuehreAus(
        EntwicklungSpeichern(
          a.id,
          DevelopSettingsCompanion.insert(
            assetId: a.id,
            updatedAt: DateTime.now(),
          ),
          pfad,
        ),
      );
      final vorher = jetzt!.developedRelativePath;
      if (vorher != null && p.isWithin('developed', p.normalize(vorher))) {
        final alt = b.pfade.absolute(vorher);
        if (await alt.exists()) await alt.delete();
      }
      ausgang = 'fertig';
    } on Object catch (e) {
      protokoll('darktable: ${a.id} nicht entwickelt: $e');
    } finally {
      _stand[a.id] = ausgang;
    }
  }
}

Response _json(Object? daten, {int status = 200}) => Response(
  status,
  body: jsonEncode(daten),
  headers: {'content-type': 'application/json'},
);
