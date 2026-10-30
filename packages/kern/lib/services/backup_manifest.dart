import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'backup_modelle.dart';

class BackupAufnahme {
  BackupAufnahme(Map<String, dynamic> werte) : werte = Map.unmodifiable(werte) {
    if (pruefsumme.isEmpty || name.isEmpty) {
      throw const FormatException('pv_restore_manifest');
    }
  }
  final Map<String, dynamic> werte;
  String get pruefsumme => werte['checksum'] as String;
  String get name => werte['originalFileName'] as String;
  String? get ablage => werte['backupRelativePath'] as String?;
}

/// Was an der Aufnahme selbst von Hand gesetzt wurde und sonst in keiner
/// Sicherung stand (#244): die Zugehörigkeit zu einer Serie oder einem
/// Variantenstapel samt Titelbild, eine von Hand geschriebene
/// Bildbeschreibung und der Ausschluss von der Gesichtssuche. Nach einer
/// Wiederherstellung waren alle Stapel aufgelöst, und die Bilderkennung
/// schrieb die korrigierten Beschreibungen neu.
///
/// Nur, was gesetzt ist: Eine Beschreibung, die das Modell schrieb,
/// entsteht von selbst neu, und eine Sicherung ohne diese Schlüssel
/// (vor #244) bedeutet „nichts dazu“, nicht „zurücksetzen“.
Map<String, Object?> handarbeitAnDerAufnahme({
  required String? stackId,
  required bool isStackCover,
  required bool aiCaptionEdited,
  required String? aiCaption,
  required String? aiCaptionDe,
  required bool faceScanExcluded,
}) => {
  if (stackId != null) ...{'stackId': stackId, 'isStackCover': isStackCover},
  if (aiCaptionEdited) ...{
    'aiCaptionEdited': true,
    'aiCaption': aiCaption,
    'aiCaptionDe': aiCaptionDe,
  },
  if (faceScanExcluded) 'faceScanExcluded': true,
};

class BackupAlbum {
  BackupAlbum({required this.name, required List<String> aufnahmen})
    : aufnahmen = List.unmodifiable(aufnahmen);
  final String name;
  final List<String> aufnahmen;
  Map<String, Object?> alsJson() => {'name': name, 'assetChecksums': aufnahmen};
}

/// Gemeinsamer Vertrag von Manifest-Parser, Snapshot und Wiederherstellung.
class BackupManifest {
  BackupManifest({
    List<BackupAufnahme> aufnahmen = const [],
    List<BackupAlbum> alben = const [],
    List<RestoreProblem> probleme = const [],
    this.exportiertAm,
  }) : aufnahmen = List.unmodifiable(aufnahmen),
       alben = List.unmodifiable(alben),
       probleme = List.unmodifiable(probleme);
  final DateTime? exportiertAm;
  final List<BackupAufnahme> aufnahmen;
  final List<BackupAlbum> alben;
  final List<RestoreProblem> probleme;

  factory BackupManifest.ausText(String text, {bool streng = false}) {
    final j = (jsonDecode(text) as Map).cast<String, dynamic>();
    if (j['format'] != null && j['format'] != 1) {
      throw const FormatException('pv_restore_manifest_format');
    }
    final fotos = <BackupAufnahme>[], alben = <BackupAlbum>[];
    final gesehen = <String>{};
    final probleme = <RestoreProblem>[];
    for (final row in j['assets'] as List? ?? const []) {
      try {
        final a = BackupAufnahme((row as Map).cast<String, dynamic>());
        // Getrennte Validierung hält einen defekten Eintrag aus dem Plan.
        if (!gesehen.add(a.pruefsumme)) {
          throw const FormatException('pv_restore_manifest_doppelt');
        }
        fotos.add(a);
      } on Object {
        if (streng) rethrow;
        probleme.add(const RestoreProblem('pv_restore_manifest_aufnahme'));
      }
    }
    for (final row in j['albums'] as List? ?? const []) {
      try {
        final a = row as Map;
        alben.add(
          BackupAlbum(
            name: a['name'] as String? ?? 'Wiederhergestelltes Album',
            aufnahmen: (a['assetChecksums'] as List? ?? const [])
                .cast<String>(),
          ),
        );
      } on Object {
        if (streng) rethrow;
        probleme.add(const RestoreProblem('pv_restore_manifest_album'));
      }
    }
    return BackupManifest(
      aufnahmen: fotos,
      alben: alben,
      probleme: probleme,
      exportiertAm: DateTime.tryParse('${j['exportedAt']}'),
    );
  }

  Map<String, dynamic> alsJson() => {
    'format': 1,
    if (exportiertAm != null)
      'exportedAt': exportiertAm!.toUtc().toIso8601String(),
    'assets': [for (final a in aufnahmen) a.werte],
    'albums': [for (final a in alben) a.alsJson()],
  };
}

class RestoreDatei {
  const RestoreDatei(this.quelle, this.endung, {this.pruefsumme});
  final File quelle;
  final String endung;
  final String? pruefsumme;
}

/// Ein Plan gehört genau einem Datenbankstand. Das private Zwischenlager
/// hält die entschlüsselten Beilagen bis zum Ende oder Abbruch des Streams.
class RestorePlan {
  RestorePlan({
    required this.manifest,
    required List<RestoreDatei> dateien,
    required this.zwischenlager,
    this.schluessel,
    this.schnappschuss,
  }) : dateien = List.unmodifiable(dateien);
  final BackupManifest manifest;
  final List<RestoreDatei> dateien;
  final Directory zwischenlager;
  final SecretKey? schluessel;
  final File? schnappschuss;
}
