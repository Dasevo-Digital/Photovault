import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kern/services/backup_service.dart';
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../../services/sicherungsziel.dart';
import 'gemeinsam.dart';

/// Zeigt einen historischen Stichprobennachweis. Er ist ausdrücklich
/// keine Zusage, dass sämtliche Originale vollständig geprüft wurden.
class BackupProbeStatus extends StatelessWidget {
  const BackupProbeStatus({
    super.key,
    required this.dienst,
    required this.ziel,
    required this.letzterLauf,
  });

  final BackupService dienst;
  final String ziel;
  final DateTime? letzterLauf;

  Future<BackupProbeErgebnis?> _lese() async {
    try {
      final ordner = await Sicherungsziel.oeffne(ziel);
      return await dienst.letzteProbe(
        p.join(ordner, BackupService.autoBackupFolderName),
      );
    } on FileSystemException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<BackupProbeErgebnis?>(
    key: ValueKey((ziel, letzterLauf)),
    future: _lese(),
    builder: (context, s) {
      final t = AppTexte.of(context);
      final probe = s.data;
      return ListTile(
        leading: const Icon(Icons.fact_check_outlined),
        title: Text(t.backupProbeTitel),
        subtitle: Text(
          probe == null
              ? t.backupProbeNochNie
              : backupProbeText(context, probe),
        ),
      );
    },
  );
}

String backupProbeText(BuildContext context, BackupProbeErgebnis probe) =>
    backupProbeTextMit(
      AppTexte.of(context),
      probe,
      (d) => datumZeitText(context, d),
    );

String backupProbeTextMit(
  AppTexte t,
  BackupProbeErgebnis probe,
  String Function(DateTime) datum,
) {
  final wann = datum(probe.am.toLocal());
  if (!probe.erfolgreich) {
    final fehler = probe.fehler == 'pv_probe_stichprobe_zu_gross'
        ? t.backupProbeZuGross(wann)
        : t.backupProbeFehler(wann);
    return probe.letzterErfolg == null
        ? fehler
        : '$fehler\n${t.backupProbeLetzterErfolg(datum(probe.letzterErfolg!.toLocal()))}';
  }
  final erfolg = t.backupProbeErfolg(
    wann,
    probe.originale,
    probe.gesamt,
    probe.datenbank ? t.backupProbeMitDatenbank : t.backupProbeMitMetadaten,
  );
  return probe.passphraseGeprueft == false
      ? '$erfolg\n${t.backupProbePassphraseOffen}'
      : erfolg;
}
