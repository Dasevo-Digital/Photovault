import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Ein vom Betriebssystem gemeldetes Dateisystem, keine Aussage über
/// unabhängige physische Sicherungsmedien.
class Speicherlaufwerk {
  const Speicherlaufwerk(this.id, this.name, this.pfad);
  final String id, name, pfad;
}

abstract final class Laufwerksauskunft {
  static const _kanal = MethodChannel('photo_vault/library_location');

  static Future<Speicherlaufwerk?> fuer(String pfad) async {
    if (!p.isAbsolute(pfad)) return null;
    try {
      if (Platform.isMacOS) {
        final v = await _kanal.invokeMapMethod<String, dynamic>(
          'storageVolume',
          {'path': pfad},
        );
        if (v == null ||
            v['id'] is! String ||
            v['name'] is! String ||
            v['path'] is! String ||
            !p.isAbsolute(v['path'] as String)) {
          return null;
        }
        return Speicherlaufwerk('mac:${v['id']}', v['name'], v['path']);
      }
      if (Platform.isWindows) {
        return await Isolate.run(() => _WindowsLaufwerk().abfragen(pfad));
      }
      if (Platform.isLinux) {
        final datei = File('/proc/self/mountinfo');
        final text = StringBuffer();
        var groesse = 0;
        await for (final teil in datei.openRead().transform(utf8.decoder)) {
          groesse += teil.length;
          if (groesse > 2 * 1024 * 1024) return null;
          text.write(teil);
        }
        return ausLinuxMountinfo(pfad, text.toString());
      }
    } on Object {
      return null;
    }
    return null;
  }

  /// Der längste tatsächlich passende Einhängepfad gewinnt. Leerzeichen
  /// und Rückstriche sind in mountinfo oktal maskiert.
  static Speicherlaufwerk? ausLinuxMountinfo(String pfad, String text) {
    if (!p.posix.isAbsolute(pfad)) return null;
    final normal = p.posix.normalize(pfad);
    Speicherlaufwerk? gefunden;
    var mehrdeutig = false;
    for (final zeile in text.split('\n')) {
      final teile = zeile.split(' ');
      final trenner = teile.indexOf('-');
      if (teile.length < 10 || trenner < 6 || trenner + 2 >= teile.length) {
        continue;
      }
      final art = teile[trenner + 1];
      if (art == 'autofs') continue;
      final ort = teile[4].replaceAllMapped(
        RegExp(r'\\([0-7]{3})'),
        (m) => String.fromCharCode(int.parse(m[1]!, radix: 8)),
      );
      if (!p.posix.isAbsolute(ort) ||
          !(p.posix.equals(ort, normal) || p.posix.isWithin(ort, normal))) {
        continue;
      }
      if (gefunden != null && gefunden.pfad.length > ort.length) continue;
      if (gefunden != null && gefunden.pfad.length == ort.length) {
        if (gefunden.id != 'linux:${teile[2]}') mehrdeutig = true;
        continue;
      }
      mehrdeutig = false;
      final name = ort == '/' ? '/' : p.posix.basename(ort);
      gefunden = Speicherlaufwerk('linux:${teile[2]}', name, ort);
    }
    return mehrdeutig ? null : gefunden;
  }
}

class _WindowsLaufwerk {
  final _lib = DynamicLibrary.open('kernel32.dll');
  late final _alloc = _lib
      .lookupFunction<
        Pointer<Uint8> Function(Uint32, IntPtr),
        Pointer<Uint8> Function(int, int)
      >('LocalAlloc');
  late final _free = _lib
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Uint8>),
        Pointer<Uint8> Function(Pointer<Uint8>)
      >('LocalFree');
  late final _wurzel = _lib
      .lookupFunction<
        Int32 Function(Pointer<Uint16>, Pointer<Uint16>, Uint32),
        int Function(Pointer<Uint16>, Pointer<Uint16>, int)
      >('GetVolumePathNameW');
  late final _kennung = _lib
      .lookupFunction<
        Int32 Function(Pointer<Uint16>, Pointer<Uint16>, Uint32),
        int Function(Pointer<Uint16>, Pointer<Uint16>, int)
      >('GetVolumeNameForVolumeMountPointW');
  late final _angaben = _lib
      .lookupFunction<
        Int32 Function(
          Pointer<Uint16>,
          Pointer<Uint16>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Uint32>,
          Pointer<Uint32>,
          Pointer<Uint16>,
          Uint32,
        ),
        int Function(
          Pointer<Uint16>,
          Pointer<Uint16>,
          int,
          Pointer<Uint32>,
          Pointer<Uint32>,
          Pointer<Uint32>,
          Pointer<Uint16>,
          int,
        )
      >('GetVolumeInformationW');

  Speicherlaufwerk? abfragen(String pfad) {
    if (pfad.length >= 32767 || pfad.codeUnits.contains(0)) return null;
    final bloecke = <Pointer<Uint8>>[];
    Pointer<Uint16> neu(int laenge) {
      final b = _alloc(0x40, laenge * 2);
      if (b == nullptr) throw StateError('pv_laufwerk_speicher');
      bloecke.add(b);
      return b.cast<Uint16>();
    }

    String lesen(Pointer<Uint16> s) =>
        String.fromCharCodes(s.asTypedList(32768).takeWhile((c) => c != 0));
    try {
      final eingabe = neu(32768),
          ort = neu(32768),
          name = neu(32768),
          id = neu(32768);
      eingabe.asTypedList(pfad.length).setAll(0, pfad.codeUnits);
      if (_wurzel(eingabe, ort, 32768) == 0) return null;
      final root = lesen(ort);
      if (!p.windows.isAbsolute(root)) return null;
      final hatId = _kennung(ort, id, 32768) != 0;
      final hatName =
          _angaben(ort, name, 32768, nullptr, nullptr, nullptr, nullptr, 0) !=
          0;
      return Speicherlaufwerk(
        'windows:${hatId ? lesen(id).toLowerCase() : root.toLowerCase()}',
        hatName && lesen(name).isNotEmpty ? lesen(name) : root,
        root,
      );
    } finally {
      for (final b in bloecke) {
        _free(b);
      }
    }
  }
}
