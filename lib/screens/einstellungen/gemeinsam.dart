import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueListenable;
import '../../services/backup_koordinator.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';

import '../../l10n/app_localizations.dart';
import '../../services/aktualisierungspruefung.dart';
import '../../services/backup_service.dart';
import '../../services/backup_verification_service.dart';
import '../../services/geo_data_download_service.dart';
import '../../services/groessentext.dart';
import '../../services/library_location.dart';
import '../../services/meldungsdienst.dart';
import '../../services/serversperre.dart';
import 'package:kern/services/model_catalog.dart';
import 'package:kern/services/model_download_service.dart';
import '../../state/library_state.dart';
import 'einstellungsstand.dart';

// Was mehrere Gruppen der Einstellungen brauchen.

/// Datum in der Schreibweise der aktiven Sprache – 17.08.2026 gegen
/// 8/17/2026. Vorher stand hier `${d}.${m}.${y}` von Hand zusammengesetzt,
/// was in jeder Sprache deutsch aussah.
String datumText(BuildContext context, DateTime zeitpunkt) => DateFormat.yMd(
  Localizations.localeOf(context).toString(),
).format(zeitpunkt);

String datumZeitText(BuildContext context, DateTime zeitpunkt) {
  final sprache = Localizations.localeOf(context).toString();
  return '${DateFormat.yMd(sprache).format(zeitpunkt)} – '
      '${DateFormat.Hm(sprache).format(zeitpunkt)}';
}

/// Übersetzt die Fehler der beiden Download-Dienste.
///
/// Sie melden nur die Bestandteile (siehe [ModellDownloadFehler]); alles
/// andere geht unverändert durch, damit ein unerwarteter Fehler nicht
/// stillschweigend zu einer leeren Meldung wird.
String fehlertext(BuildContext context, Object fehler) {
  final t = AppTexte.of(context);
  if (istServersperre(fehler)) return t.nurOhneServer;
  return switch (fehler) {
    BackupBrauchtPassphrase() => t.backupPassphraseNoetig,
    BackupLaeuftBereits() => t.backupLaeuftBereits,
    WiederherstellungUnvollstaendig(:final ergebnis) =>
      t.backupRestoreUnvollstaendig(
        ergebnis.importiert,
        ergebnis.vorhanden,
        ergebnis.fehlend,
        ergebnis.gescheitert + ergebnis.probleme.length,
      ),
    BackupPruefungBrauchtPassphrase() => t.backupPassphraseNoetig,
    BackupOrdnerFehlt() => t.backupOrdnerFehlt,
    AktualisierungsFehler(
      problem: Aktualisierungsproblem.keineVeroeffentlichungen,
    ) =>
      t.aktualisierungKeineVeroeffentlichungen,
    AktualisierungsFehler(problem: Aktualisierungsproblem.keineVersion) =>
      t.aktualisierungKeineVersion,
    ModellDownloadFehler(
      :final datei,
      erhalten: final erhalten?,
      erwartet: final erwartet?,
    ) =>
      t.downloadPruefsummeFehler(datei, erhalten, erwartet),
    ModellDownloadFehler(:final datei, :final ursache) =>
      t.downloadFehlgeschlagen(datei, ursache ?? ''),
    GeoDownloadFehler(:final datei, groessengrenze: final grenze?) =>
      t.downloadZuGross(datei, grenze),
    GeoDownloadFehler(:final datei, ursache: null, beimEntpacken: true) =>
      t.downloadNichtImZip(datei),
    GeoDownloadFehler(:final datei, :final ursache, beimEntpacken: true) =>
      t.downloadEntpackenFehler(datei, ursache ?? ''),
    GeoDownloadFehler(:final datei, :final ursache) => t.downloadFehlgeschlagen(
      datei,
      ursache ?? '',
    ),
    TokenablageFehler() => t.serverTokenSpeichernFehler,
    _ => '$fehler',
  };
}

/// Die Modelle, die zur eingestellten Oberflächensprache passen –
/// siehe [ModelCatalog.fuerSprache].
List<ModelCatalogEntry> modelleFuerSprache(
  BuildContext context,
  LibraryState library,
) => ModelCatalog.fuerSprache(
  Localizations.localeOf(context).languageCode,
  istInstalliert: library.isModelInstalled,
);

/// Gemeinsamer Ablauf für Verlegen/Zurücksetzen/Reset: Ladeanzeige → Aktion
/// ausführen (schließt dabei die DB-Verbindung) → bei Erfolg zum Neustart
/// auffordern und die App schließen, bei Fehler die bisherigen Daten
/// unangetastet lassen (siehe [LibraryLocation]) und den Fehler anzeigen.
Future<void> verlegeBibliothek(
  Einstellungsstand stand, {
  required String loadingText,
  required Future<void> Function() action,
  ValueListenable<BibliotheksVerschiebefortschritt?>? progress,
  // Kein Vorgabewert im Kopf: Ein übersetzter Text braucht den Kontext,
  // den es dort noch nicht gibt. null heisst „der übliche Text".
  String? restartMessage,
  String? errorPrefix,
}) async {
  final context = stand.kontext;
  restartMessage ??= AppTexte.of(context).einstSpeicherortGeaendert;
  errorPrefix ??= AppTexte.of(context).einstVerschiebenFehlgeschlagen;
  // Als eigene Route statt über showDialog: Beim Scheitern wartet der
  // Ablauf, bis das Fenster wirklich weg ist (siehe unten).
  final navigator = Navigator.of(context, rootNavigator: true);
  final ladeanzeige = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    builder: (context) {
      Widget inhalt(BibliotheksVerschiebefortschritt? wert) => Semantics(
        label: loadingText,
        value: wert?.anteil == null
            ? null
            : '${(wert!.anteil! * 100).round()} %',
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(loadingText),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: wert?.anteil),
              if (wert != null) ...[
                const SizedBox(height: 10),
                Text(
                  AppTexte.of(context).einstSpeicherortFortschritt(
                    groessentext(wert.kopierteBytes),
                    groessentext(wert.gesamtBytes),
                    wert.kopierteDateien,
                    wert.gesamtDateien,
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      );

      return AlertDialog(
        content: progress == null
            ? inhalt(null)
            : ValueListenableBuilder<BibliotheksVerschiebefortschritt?>(
                valueListenable: progress,
                builder: (context, wert, _) => inhalt(wert),
              ),
      );
    },
  );
  unawaited(navigator.push(ladeanzeige));
  // Obenauf mit dem üblichen Ausblenden, sonst genau dieses Fenster.
  void ladeanzeigeSchliessen() => ladeanzeige.isCurrent
      ? navigator.pop()
      : navigator.removeRoute(ladeanzeige);

  Future<void> neustart(String text) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(AppTexte.of(context).einstNeustartTitel),
      content: Text(text),
      actions: [
        FilledButton(
          onPressed: () => exit(0),
          child: Text(AppTexte.of(context).allgSchliessen),
        ),
      ],
    ),
  );

  try {
    await action();
    if (!context.mounted) return;
    // Das Fenster liegt auf dem Wurzel-Navigator; der nächste Navigator
    // über [context] wäre der des Arbeitsbereichs (#406).
    ladeanzeigeSchliessen();
    await neustart(restartMessage);
  } catch (e) {
    if (!context.mounted) return;
    ladeanzeigeSchliessen();
    melde.fehler('$errorPrefix: ${fehlertext(context, e)}');
    // Erst zurückkehren, wenn das Fenster abgebaut ist: Der Aufrufer
    // entsorgt danach [progress], und ein Fenster, das im Ausblenden noch
    // mit dem Notifier baut, warf „A ValueNotifier … was used after being
    // disposed“.
    await ladeanzeige.completed;
    // War die Datenbank schon zu, als es scheiterte, geht bis zum Neustart
    // nichts mehr – das muss die App sagen, statt mit einer Fehlermeldung
    // unbedienbar weiterzulaufen (GRU-101).
    if (stand.library.datenbankGeschlossen && context.mounted) {
      await neustart(AppTexte.of(context).einstNeustartNachFehler);
    }
  }
}
