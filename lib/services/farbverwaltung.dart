import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:farbverwaltung/farbverwaltung.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:kern/berechne.dart';
import 'package:kern/services/jpeg_icc.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:kern/services/wasserzeichen.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'library_location.dart';
import 'bibliotheksgeraetedaten.dart';

enum Profilrolle { bildschirm, druck, ausgabe }

class Farbeinstellungen {
  const Farbeinstellungen({
    this.bildschirm = 'system',
    this.druck,
    this.ausgabe = 'original',
    this.intent = 1,
  });
  final String bildschirm, ausgabe;
  final String? druck;
  final int intent;
  Farbeinstellungen mit(Profilrolle rolle, String? wert) => Farbeinstellungen(
    bildschirm: rolle == Profilrolle.bildschirm ? wert ?? 'system' : bildschirm,
    druck: rolle == Profilrolle.druck ? wert : druck,
    ausgabe: rolle == Profilrolle.ausgabe ? wert ?? 'original' : ausgabe,
    intent: intent,
  );
}

/// Gerätegebundene Profile bleiben außerhalb des synchronisierten Katalogs.
/// Drucksimulation und Warnfarbe sind ausschließlich Anzeigeoperationen.
class Farbverwaltung {
  Farbverwaltung(this.ordner);
  final Directory ordner;
  Farbeinstellungen? _werte;
  final _profile =
      <
        String,
        ({Uint8List bytes, int groesse, DateTime zeit, IccFarbraum art})
      >{};
  static bool _lizenzRegistriert = false;
  static void registriereLizenz() {
    if (!_lizenzRegistriert) {
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks(['Little CMS'], Farbengine.lizenz);
      });
      _lizenzRegistriert = true;
    }
  }

  static Future<Farbverwaltung> fuer(StoragePaths paths) async {
    final lokal = await LibraryLocation.datenordner();
    final id = await Bibliotheksgeraetedaten.kennung(paths);
    registriereLizenz();
    return Farbverwaltung(Directory(p.join(lokal.path, 'farbprofile', id)));
  }

  File get _datei => File(p.join(ordner.path, 'einstellungen.json'));
  static bool _kennung(String s) =>
      ['system', 'original', 'srgb', 'p3'].contains(s) ||
      RegExp(r'^[a-f0-9]{64}$').hasMatch(s);
  Future<Farbeinstellungen> laden() async {
    if (_werte != null) return _werte!;
    if (!await _datei.exists()) return _werte = const Farbeinstellungen();
    if (await _datei.length() > 4096) throw const FarbprofilFehler();
    final j = jsonDecode(await _datei.readAsString()) as Map;
    final b = j['bildschirm'] as String,
        d = j['druck'] as String?,
        a = j['ausgabe'] as String,
        i = j['intent'] as int;
    if (j['fassung'] != 1 ||
        !_kennung(b) ||
        !_kennung(a) ||
        (d != null && !_kennung(d)) ||
        i < 0 ||
        i > 3) {
      throw const FarbprofilFehler();
    }
    return _werte = Farbeinstellungen(
      bildschirm: b,
      druck: d,
      ausgabe: a,
      intent: i,
    );
  }

  Future<void> speichern(Farbeinstellungen werte) async {
    // Profile werden geprüft, bevor der bisherige Stand ersetzt wird.
    await profil(werte.bildschirm, rgb: true);
    await profil(werte.ausgabe, rgb: true);
    if (werte.druck != null) await profil(werte.druck!);
    if (werte.intent < 0 || werte.intent > 3) throw const FarbprofilFehler();
    await ordner.create(recursive: true);
    final teil = File('${_datei.path}.${const Uuid().v4()}.part');
    try {
      await teil.writeAsString(
        jsonEncode({
          'fassung': 1,
          'bildschirm': werte.bildschirm,
          'druck': werte.druck,
          'ausgabe': werte.ausgabe,
          'intent': werte.intent,
        }),
        flush: true,
      );
      await teil.rename(_datei.path);
      _werte = werte;
      _profile.clear();
    } finally {
      if (await teil.exists()) await teil.delete();
    }
    final benutzt = {werte.bildschirm, werte.druck, werte.ausgabe};
    await for (final f in ordner.list(followLinks: false)) {
      if (f is File &&
          RegExp(r'^[a-f0-9]{64}\.icc$').hasMatch(p.basename(f.path)) &&
          !benutzt.contains(p.basenameWithoutExtension(f.path))) {
        try {
          await f.delete();
        } on FileSystemException {
          /* Unbenutzte Profilkopie darf später bereinigt werden. */
        }
      }
    }
  }

  Future<Uint8List?> profil(String kennung, {bool rgb = false}) async {
    if (!_kennung(kennung)) throw const FarbprofilFehler();
    if (kennung == 'system' || kennung == 'original') return null;
    if (kennung == 'srgb') return Farbengine.standard(Standardfarbraum.srgb);
    if (kennung == 'p3') return Farbengine.standard(Standardfarbraum.displayP3);
    final datei = File(p.join(ordner.path, '$kennung.icc'));
    final stat = await datei.stat();
    if (await FileSystemEntity.type(datei.path, followLinks: false) !=
            FileSystemEntityType.file ||
        stat.size > Farbengine.hoechstensProfilbytes) {
      throw const FarbprofilFehler();
    }
    final vorher = _profile[kennung];
    if (vorher != null &&
        vorher.groesse == stat.size &&
        vorher.zeit.isAtSameMomentAs(stat.modified)) {
      if (rgb && vorher.art != IccFarbraum.rgb) throw const FarbprofilFehler();
      return vorher.bytes;
    }
    final bytes = await datei.readAsBytes();
    final art = Farbengine.pruefe(bytes);
    if (sha256.convert(bytes).toString() != kennung ||
        (rgb && art != IccFarbraum.rgb)) {
      throw const FarbprofilFehler();
    }
    if (_profile.length >= 3) _profile.remove(_profile.keys.first);
    final fest = bytes.asUnmodifiableView();
    _profile[kennung] = (
      bytes: fest,
      groesse: stat.size,
      zeit: stat.modified,
      art: art,
    );
    return fest;
  }

  Future<Farbeinstellungen> uebernehmen(File quelle, Profilrolle rolle) async {
    if (await quelle.length() > Farbengine.hoechstensProfilbytes) {
      throw const FarbprofilFehler();
    }
    final bytes = await quelle.readAsBytes();
    final art = await berechne(Farbengine.pruefe, bytes);
    if (rolle != Profilrolle.druck && art != IccFarbraum.rgb) {
      throw const FarbprofilFehler();
    }
    final kennung = sha256.convert(bytes).toString();
    await ordner.create(recursive: true);
    final datei = File(p.join(ordner.path, '$kennung.icc'));
    await datei.writeAsBytes(bytes, flush: true);
    final neu = (await laden()).mit(rolle, kennung);
    await speichern(neu);
    return neu;
  }

  Future<Uint8List> anzeige(
    Uint8List jpeg, {
    bool druckvorschau = false,
    bool gamutwarnung = false,
    bool papierfarbe = false,
  }) async {
    final werte = await laden();
    if (werte.bildschirm == 'system' && !druckvorschau && !gamutwarnung) {
      return jpeg;
    }
    if ((druckvorschau || gamutwarnung) && werte.druck == null) {
      throw const FarbprofilFehler();
    }
    return berechne(_wandleJpeg, (
      jpeg: jpeg,
      ziel: await profil(werte.bildschirm, rgb: true),
      druck: werte.druck == null ? null : await profil(werte.druck!),
      proof: druckvorschau,
      gamut: gamutwarnung,
      papier: papierfarbe,
      intent: werte.intent,
      zeichen: null,
    ));
  }

  /// Wohin [exportiere] umrechnet: das Zielprofil (`null` darin heisst
  /// sRGB) und der Intent – `null`, wenn das Bild bleibt, wie es ist
  /// (Ausgabe „original“).
  Future<({Uint8List? ziel, int intent})?> exportziel({
    bool datenschutz = false,
  }) async {
    final werte = datenschutz
        ? const Farbeinstellungen(ausgabe: 'srgb')
        : await laden();
    if (werte.ausgabe == 'original') return null;
    return (ziel: await profil(werte.ausgabe, rgb: true), intent: werte.intent);
  }

  /// Das Bild im Ausgabeprofil; mit [zeichen] auch mit dem Wasserzeichen
  /// (#497).
  ///
  /// **In einem Durchgang.** Die Farbumrechnung dekodiert das JPEG und
  /// kodiert es neu; das Wasserzeichen danach eigens einzurechnen hiesse,
  /// dasselbe Bild gleich noch einmal in reinem Dart zu dekodieren und zu
  /// kodieren – eine Runde JPEG-Verlust und die Rechenzeit dafür je Foto
  /// mehr. Deshalb kommt das Zeichen in [_wandleJpeg] nach der Umrechnung
  /// dazu, und kodiert wird einmal, in der Qualität der Vorgabe. Bleibt das
  /// Bild, wie es ist („original“), wird nur das Zeichen eingerechnet.
  ///
  /// Die Pixel des Zeichens müssen schon im Zielfarbraum sein
  /// ([exportziel]; `wasserzeichenpixelFuer` rechnet ein Logo um).
  Future<Uint8List> exportiere(
    Uint8List jpeg, {
    bool datenschutz = false,
    Exportzeichen? zeichen,
  }) async {
    final ziel = await exportziel(datenschutz: datenschutz);
    if (ziel == null) {
      if (zeichen == null) return jpeg;
      return berechne(jpegMitWasserzeichen, (
        jpeg: jpeg,
        zeichen: zeichen.pixel,
        wasserzeichen: zeichen.wasserzeichen,
        qualitaet: zeichen.qualitaet,
      ));
    }
    return berechne(_wandleJpeg, (
      jpeg: jpeg,
      ziel: ziel.ziel,
      druck: null,
      proof: false,
      gamut: false,
      papier: false,
      intent: ziel.intent,
      zeichen: zeichen,
    ));
  }
}

/// Ein Wasserzeichen, das [Farbverwaltung.exportiere] im selben Durchgang
/// wie die Farbumrechnung einrechnet (#497): die Pixel im Zielfarbraum,
/// die Einstellungen und die Qualität, in der danach kodiert wird (1–100).
typedef Exportzeichen = ({
  Zeichenpixel pixel,
  Wasserzeichen wasserzeichen,
  int qualitaet,
});

Uint8List _wandleJpeg(
  ({
    Uint8List jpeg,
    Uint8List? ziel,
    Uint8List? druck,
    bool proof,
    bool gamut,
    bool papier,
    int intent,
    Exportzeichen? zeichen,
  })
  w,
) {
  JpegIcc.masse(w.jpeg);
  final quelle = JpegIcc.lesen(w.jpeg);
  final bild = img.decodeJpg(w.jpeg);
  if (bild == null) throw const FarbprofilFehler();
  final rgb = bild.getBytes(order: img.ChannelOrder.rgb);
  final gewandelt = Farbengine.transformiere(
    rgb,
    quelle: quelle,
    ziel: w.ziel,
    druck: w.druck,
    druckvorschau: w.proof,
    gamutwarnung: w.gamut,
    papierfarbe: w.papier,
    intent: w.intent,
  );
  var aus = img.Image.fromBytes(
    width: bild.width,
    height: bild.height,
    bytes: gewandelt.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  final zeichen = w.zeichen;
  if (zeichen != null) {
    aus = rechneZeichenpixelEin(aus, zeichen.pixel, zeichen.wasserzeichen);
  }
  // Neu kodiert: keine EXIF/GPS-Daten und kein fehlerhafter ICC-Encoderpfad.
  // Mit Wasserzeichen ist das die letzte Kodierung vor der Datei, also in
  // der Qualität der Vorgabe (vorher kodierte das Einrechnen danach noch
  // einmal in ihr).
  return JpegIcc.schreiben(
    Uint8List.fromList(
      img.encodeJpg(aus, quality: zeichen?.qualitaet.clamp(1, 100) ?? 95),
    ),
    w.ziel ?? Farbengine.standard(Standardfarbraum.srgb),
  );
}
