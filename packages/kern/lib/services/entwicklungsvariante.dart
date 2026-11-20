import 'dart:convert';
import 'package:path/path.dart' as p;
import '../db/database.dart';
import 'bildzuschnitt.dart';

class Entwicklungsstand {
  const Entwicklungsstand(
    this.originalSha256,
    this.einstellungen,
    this.masken,
    this.dateien,
  );
  final String originalSha256;
  final DevelopSettingsData einstellungen;
  final List<DevelopMaskData> masken;
  final Map<String, String> dateien;
  String encode() => jsonEncode({
    'fassung': 1,
    'original': originalSha256,
    'einstellungen': einstellungen.toJson(),
    'masken': [for (final m in masken) m.toJson()],
    'dateien': dateien,
  });

  factory Entwicklungsstand.decode(String text) {
    if (utf8.encode(text).length > 1024 * 1024) {
      throw const FormatException('pv_variante_umfang');
    }
    final j = jsonDecode(text) as Map;
    if (j['fassung'] != 1 || !_hash(j['original'])) {
      throw const FormatException('pv_variante_format');
    }
    final settings = DevelopSettingsData.fromJson(
      (j['einstellungen'] as Map).cast<String, dynamic>(),
    );
    Bildzuschnitt.aus(settings.cropJson);
    final masken = [
      for (final m in j['masken'] as List)
        DevelopMaskData.fromJson((m as Map).cast<String, dynamic>()),
    ];
    final dateien = (j['dateien'] as Map).cast<String, String>();
    if (masken.length > 100 || dateien.length > 256) {
      throw const FormatException('pv_variante_umfang');
    }
    for (final e in dateien.entries) {
      if (!erlaubterVariantenpfad(e.key) || !_hash(e.value)) {
        throw const FormatException('pv_variante_pfad');
      }
    }
    final benoetigt = [
      if (settings.lutPath != null) settings.lutPath!,
      for (final m in masken) m.maskRelativePath,
    ];
    if (benoetigt.any((x) => !dateien.containsKey(x))) {
      throw const FormatException('pv_variante_datei');
    }
    if (settings.lutPath != null && !settings.lutPath!.startsWith('luts/') ||
        masken.any((m) => !m.maskRelativePath.startsWith('masks/'))) {
      throw const FormatException('pv_variante_pfad');
    }
    if (masken.map((m) => m.id).toSet().length != masken.length) {
      throw const FormatException('pv_variante_maske');
    }
    for (final s in [
      settings.exposure,
      settings.contrast,
      settings.shadows,
      settings.highlights,
      settings.sharpness,
      settings.noiseReduction,
      settings.clarity,
      settings.vignette,
      settings.lutStrength,
      if (settings.temperature != null) settings.temperature!,
      if (settings.tint != null) settings.tint!,
    ]) {
      if (!s.isFinite || s.abs() > 100000) {
        throw const FormatException('pv_variante_regler');
      }
    }
    for (final m in masken) {
      for (final s in [
        m.exposure,
        m.contrast,
        m.shadows,
        m.highlights,
        m.sharpness,
        m.noiseReduction,
        if (m.temperature != null) m.temperature!,
        if (m.tint != null) m.tint!,
      ]) {
        if (!s.isFinite || s.abs() > 100000) {
          throw const FormatException('pv_variante_regler');
        }
      }
    }
    return Entwicklungsstand(
      j['original'] as String,
      settings,
      List.unmodifiable(masken),
      Map.unmodifiable(dateien),
    );
  }
  static bool _hash(Object? x) =>
      x is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(x);
}

bool erlaubterVariantenpfad(String pfad) {
  final teile = pfad.split('/');
  return !pfad.contains(r'\') &&
      !pfad.contains('\u0000') &&
      pfad.length <= 512 &&
      !p.posix.isAbsolute(pfad) &&
      teile.length == 2 &&
      {'masks', 'luts', 'developed'}.contains(teile.first) &&
      teile.last.isNotEmpty &&
      !teile.contains('..') &&
      !teile.contains('.');
}
