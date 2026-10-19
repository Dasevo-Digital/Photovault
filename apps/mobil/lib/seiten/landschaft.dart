import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gelaende/flugvideo.dart';
import 'package:gelaende/gelaende_screen.dart';
import 'package:intl/intl.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/wanderobjekte.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../bilder.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';

/// Die Landschaft unter einer Spur und der Flug darüber – derselbe
/// Bildschirm wie am Rechner (`packages/gelaende`), mit dem, was nur das
/// Handy weiss: seine Bibliothek, sein Server und wie es ein Video
/// weitergibt.
Future<void> oeffneLandschaft(
  BuildContext context, {
  required Sitzung sitzung,
  required String titel,
  required List<SpurpunkteData> punkte,
  required List<AssetData> aufnahmen,
}) async {
  final db = sitzung.db;
  // Die Wahl gilt je Gerät wie am Rechner: Grund, Ebenen, Tageszeit.
  final auflage = await db.gelaendeKarteWert();
  final stimmung = await db.gelaendeStimmungWert();
  if (!context.mounted) return;
  final uhrzeit = DateFormat.Hm(
    Localizations.localeOf(context).toLanguageTag(),
  );
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => GelaendeScreen(
        titel: titel,
        auflage: auflage,
        stimmung: stimmung,
        beimStimmungswechsel: db.setzeGelaendeStimmung,
        beimKartenwechsel: db.setzeGelaendeKarte,
        wanderobjekte:
            ({
              required double sued,
              required double west,
              required double nord,
              required double ost,
            }) => _wanderobjekte(
              sitzung,
              sued: sued,
              west: west,
              nord: nord,
              ost: ost,
            ),
        fotos: [
          for (final a in aufnahmen)
            if (a.latitude != null &&
                a.longitude != null &&
                a.thumbnailRelativePath != null)
              (
                breite: a.latitude!,
                laenge: a.longitude!,
                bild: BibliotheksBild(sitzung.paths, a.thumbnailRelativePath!),
                unterschrift: uhrzeit.format(a.fileCreatedAt.toLocal()),
              ),
        ],
        spur: [
          for (final p in punkte)
            (breite: p.breite, laenge: p.laenge, hoehe: p.hoehe, zeit: p.zeit),
        ],
        videoschreiber: Platform.isIOS ? const HandyVideoschreiber() : null,
        videoWeiter: AppTexte.of(context).gelaendeVideoErstellen,
        videoZiel: (_, dateiname) async =>
            File('${(await getTemporaryDirectory()).path}/$dateiname'),
        // Fertig heisst am Handy: weitergeben – in die Fotos sichern, in
        // eine Nachricht, wohin auch immer. Danach liegt die Datei nur noch
        // im Zwischenspeicher, den iOS selbst aufräumt.
        beiVideoFertig: (ziel) async {
          await SharePlus.instance.share(
            ShareParams(files: [XFile(ziel.path, mimeType: 'video/mp4')]),
          );
        },
      ),
    ),
  );
}

/// Gipfel, Hütten und Quellen fragt das Handy beim Server: Der fragt
/// Overpass höchstens einmal je Ausschnitt und merkt es sich für Browser
/// und Handy (`GET /api/v1/wanderobjekte`). Ohne Server keine Schilder –
/// sie sind eine Zugabe, die Landschaft steht auch ohne.
Future<List<Wanderobjekt>> _wanderobjekte(
  Sitzung sitzung, {
  required double sued,
  required double west,
  required double nord,
  required double ost,
}) async {
  final verbindung = sitzung.abgleich?.verbindung;
  if (verbindung == null) return const [];
  try {
    final d = await verbindung.hole(
      'api/v1/wanderobjekte',
      parameter: {
        'sued': sued.toStringAsFixed(5),
        'west': west.toStringAsFixed(5),
        'nord': nord.toStringAsFixed(5),
        'ost': ost.toStringAsFixed(5),
      },
    );
    final arten = {for (final a in Wanderart.values) a.name: a};
    return [
      for (final (i, p) in (d['punkte'] as List? ?? const []).indexed)
        if (p is Map && arten[p['art']] != null)
          Wanderobjekt(
            osmId: (p['osmId'] as num?)?.toInt() ?? i,
            art: arten[p['art']]!,
            breite: (p['breite'] as num).toDouble(),
            laenge: (p['laenge'] as num).toDouble(),
            name: p['name'] as String?,
            hoehe: (p['hoehe'] as num?)?.toDouble(),
          ),
    ];
  } catch (_) {
    return const [];
  }
}

/// Das Flugvideo am iPhone: AVFoundation über den Kanal
/// `de.dasevo.photovault/flugvideo` (ios/Runner/Flugvideo.swift) – dieselbe
/// Schreibweise wie am Mac.
class HandyVideoschreiber implements Videoschreiber {
  const HandyVideoschreiber();

  static const _kanal = MethodChannel('de.dasevo.photovault/flugvideo');

  @override
  Future<bool> moeglich() async => Platform.isIOS;

  @override
  Future<Videoergebnis> schreibe({
    required File ziel,
    required int breite,
    required int hoehe,
    required Duration dauer,
    required void Function(ui.Canvas leinwand, ui.Size flaeche, double t)
    maleBild,
    Future<void> Function(double t)? vorBild,
    void Function(double anteil)? fortschritt,
    bool Function()? abbruch,
  }) async {
    // Gerade Kanten: H.264 tastet die Farbe halb so fein ab wie die
    // Helligkeit, eine ungerade Kante lässt sich nicht halbieren.
    final b = breite - breite % 2;
    final h = hoehe - hoehe % 2;
    final bilder = (dauer.inMilliseconds * videoBilderJeSekunde / 1000).round();
    if (b < 2 || h < 2 || bilder < 1) {
      return (ausgang: Videoausgang.fehler, meldung: 'size=${b}x$h');
    }
    try {
      await _kanal.invokeMethod<void>('videoStart', {
        'path': ziel.path,
        'breite': b,
        'hoehe': h,
        'bilderJeSekunde': videoBilderJeSekunde,
      });
    } on MissingPluginException {
      return (ausgang: Videoausgang.keinWerkzeug, meldung: null);
    } on PlatformException catch (e) {
      return (ausgang: Videoausgang.fehler, meldung: e.message ?? '$e');
    }
    return schreibeBilderfolge(
      ausgabe: const _Kanalziel(_kanal),
      breite: b,
      hoehe: h,
      bilder: bilder,
      maleBild: maleBild,
      vorBild: vorBild,
      fortschritt: fortschritt,
      abbruch: abbruch,
    );
  }
}

class _Kanalziel implements Videoziel {
  const _Kanalziel(this._kanal);

  final MethodChannel _kanal;

  @override
  Future<void> bild(Uint8List rgba) =>
      _kanal.invokeMethod<void>('videoBild', {'rgba': rgba});

  @override
  Future<String?> beende() async {
    try {
      await _kanal.invokeMethod<void>('videoFertig');
      return null;
    } on PlatformException catch (e) {
      return e.message ?? '$e';
    }
  }

  @override
  Future<void> verwirf() async {
    try {
      await _kanal.invokeMethod<void>('videoVerwerfen');
    } catch (_) {
      // Nichts zu tun: Der Lauf ist ohnehin zu Ende.
    }
  }
}
