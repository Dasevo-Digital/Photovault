import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:kern/services/platform/desktop_image_tools.dart';
import 'package:path/path.dart' as p;
import 'package:kern/services/dateikopf.dart';

/// Eigener Weg ab dem RAW-Original. Keine Zwischenfassung in JPEG.
class RawPraezision {
  static const kanal = MethodChannel('photo_vault/image_convert');
  static const endungen = {
    '.dng',
    '.cr2',
    '.cr3',
    '.nef',
    '.nrw',
    '.arw',
    '.sr2',
    '.srf',
    '.orf',
    '.rw2',
    '.raf',
    '.pef',
    '.rwl',
    '.3fr',
    '.fff',
    '.iiq',
    '.kdc',
    '.mos',
    '.mrw',
    '.raw',
    '.srw',
    '.x3f',
  };
  static Future<Uint8List> entwickle(File original) async {
    if (!endungen.contains(p.extension(original.path).toLowerCase())) {
      throw const FormatException('pv_raw16_raw_erforderlich');
    }
    final kopf = leseRohkopf(original);
    if (kopf?.breite != null &&
        kopf?.hoehe != null &&
        kopf!.breite! * kopf.hoehe! > 50000000) {
      throw const FormatException('pv_raw16_speichergrenze');
    }
    final Uint8List? bytes;
    if (Platform.isMacOS) {
      bytes = await kanal.invokeMethod<Uint8List>('rawLinear16', {
        'path': original.path,
      });
    } else {
      bytes = await DesktopImageTools.rawLinear16(original);
    }
    if (bytes == null || !istTiff16(bytes)) {
      throw const FormatException('pv_raw16_nicht_moeglich');
    }
    return bytes;
  }

  /// Prüft IFD-Typen/Offsets und alle RGB-Kanäle, ohne das Bild zusätzlich
  /// zu dekodieren. BigTIFF und Gleitkomma-TIFF sind hier kein Ersatz.
  static bool istTiff16(Uint8List b) {
    try {
      if (b.length < 8) return false;
      final endian = b[0] == 0x49 && b[1] == 0x49
          ? Endian.little
          : b[0] == 0x4d && b[1] == 0x4d
          ? Endian.big
          : null;
      if (endian == null) return false;
      final d = ByteData.sublistView(b);
      int u16(int i) => d.getUint16(i, endian);
      int u32(int i) => d.getUint32(i, endian);
      if (u16(2) != 42) return false;
      final offset = u32(4), count = u16(offset);
      if (count > 4096 || offset + 2 + count * 12 + 4 > b.length) return false;
      final tags = <int, List<int>>{};
      for (var i = 0; i < count; i++) {
        final at = offset + 2 + i * 12,
            tag = u16(at),
            type = u16(at + 2),
            n = u32(at + 4);
        if (!{256, 257, 258, 262, 277, 339}.contains(tag)) continue;
        if (tags.containsKey(tag) ||
            n < 1 ||
            n > 4 ||
            (type != 3 && type != 4)) {
          return false;
        }
        final size = type == 3 ? 2 : 4;
        final start = n * size <= 4 ? at + 8 : u32(at + 8);
        tags[tag] = [
          for (var j = 0; j < n; j++)
            type == 3 ? u16(start + j * size) : u32(start + j * size),
        ];
      }
      final channels = tags[277]?.single ?? 1;
      return (tags[256]?.single ?? 0) > 0 &&
          (tags[257]?.single ?? 0) > 0 &&
          tags[262]?.single == 2 &&
          channels >= 3 &&
          channels <= 4 &&
          tags[258]?.length == channels &&
          tags[258]!.every((n) => n == 16) &&
          (tags[339] == null || tags[339]!.every((n) => n == 1));
    } on Object {
      return false;
    }
  }
}
