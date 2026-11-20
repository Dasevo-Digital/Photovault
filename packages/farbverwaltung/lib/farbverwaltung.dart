import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'src/native.dart' as native;

enum IccFarbraum { rgb, cmyk, grau }

enum Standardfarbraum { srgb, displayP3 }

class FarbprofilFehler implements Exception {
  const FarbprofilFehler();
}

class Farbengine {
  static const hoechstensProfilbytes = 8 * 1024 * 1024;
  static String get lizenz => native.lizenz().cast<Utf8>().toDartString();

  static void pruefeKopf(Uint8List daten) {
    if (daten.length < 132 || daten.length > hoechstensProfilbytes) {
      throw const FarbprofilFehler();
    }
    final b = ByteData.sublistView(daten);
    final laenge = b.getUint32(0);
    final tags = b.getUint32(128);
    if (laenge < 132 ||
        laenge > daten.length ||
        b.getUint32(36) != 0x61637370 ||
        tags > 4096 ||
        132 + tags * 12 > laenge) {
      throw const FarbprofilFehler();
    }
    for (var i = 0; i < tags; i++) {
      final offset = b.getUint32(136 + i * 12),
          size = b.getUint32(140 + i * 12);
      if (offset < 128 || offset > laenge || size > laenge - offset) {
        throw const FarbprofilFehler();
      }
    }
  }

  static Pointer<Uint8> _kopie(Uint8List? daten) {
    if (daten == null) return nullptr;
    pruefeKopf(daten);
    final p = malloc<Uint8>(daten.length);
    p.asTypedList(daten.length).setAll(0, daten);
    return p;
  }

  static IccFarbraum pruefe(Uint8List daten) {
    final p = _kopie(daten);
    try {
      return switch (native.profil(p, daten.length)) {
        1 => IccFarbraum.rgb,
        2 => IccFarbraum.cmyk,
        3 => IccFarbraum.grau,
        _ => throw const FarbprofilFehler(),
      };
    } finally {
      malloc.free(p);
    }
  }

  static Uint8List standard(Standardfarbraum raum) {
    final n = native.standardprofil(raum.index, nullptr, 0);
    if (n < 132 || n > hoechstensProfilbytes) throw const FarbprofilFehler();
    final p = malloc<Uint8>(n);
    try {
      if (native.standardprofil(raum.index, p, n) != n) {
        throw const FarbprofilFehler();
      }
      final daten = Uint8List.fromList(p.asTypedList(n));
      // Eingebaute Profile sind dieselben Werte auf jedem Gerät und in
      // jedem Isolat, unabhängig vom Zeitpunkt ihrer Erzeugung.
      final kopf = ByteData.sublistView(daten);
      const datum = [2000, 1, 1, 0, 0, 0];
      for (var i = 0; i < datum.length; i++) {
        kopf.setUint16(24 + i * 2, datum[i]);
      }
      return daten;
    } finally {
      malloc.free(p);
    }
  }

  static Uint8List transformiere(
    Uint8List rgb, {
    Uint8List? quelle,
    Uint8List? ziel,
    Uint8List? druck,
    bool druckvorschau = false,
    bool gamutwarnung = false,
    bool papierfarbe = false,
    int intent = 1,
  }) {
    if (rgb.length % 3 != 0 ||
        rgb.length > 96000000 ||
        intent < 0 ||
        intent > 3 ||
        ((druckvorschau || gamutwarnung) && druck == null)) {
      throw const FarbprofilFehler();
    }
    Pointer<Uint8> inProfil = nullptr,
        outProfil = nullptr,
        proof = nullptr,
        eingang = nullptr,
        ausgang = nullptr;
    try {
      inProfil = _kopie(quelle);
      outProfil = _kopie(ziel);
      proof = _kopie(druck);
      eingang = malloc<Uint8>(rgb.length);
      ausgang = malloc<Uint8>(rgb.length);
      eingang.asTypedList(rgb.length).setAll(0, rgb);
      final status = native.transform(
        eingang,
        ausgang,
        rgb.length ~/ 3,
        inProfil,
        quelle?.length ?? 0,
        outProfil,
        ziel?.length ?? 0,
        proof,
        druck?.length ?? 0,
        (druckvorschau ? 1 : 0) |
            (gamutwarnung ? 2 : 0) |
            (papierfarbe ? 4 : 0),
        intent,
      );
      if (status != 0) throw const FarbprofilFehler();
      return Uint8List.fromList(ausgang.asTypedList(rgb.length));
    } finally {
      for (final p in [ausgang, eingang, proof, outProfil, inProfil]) {
        if (p != nullptr) malloc.free(p);
      }
    }
  }
}
