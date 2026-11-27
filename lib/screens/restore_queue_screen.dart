import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/dauertext.dart';

import 'package:kern/db/database.dart';
import '../services/hochskalieren.dart';
import '../services/restore_queue_service.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/empty_state.dart';
import 'asset_viewer_screen.dart';

/// Übersicht aller KI-Restaurierungs-Aufträge (siehe RestoreQueueService,
/// RestoreJobs) – erreichbar über den Warteschlangen-Indikator in
/// [HomeShell]. Ein Auftrag läuft oft mehrere Minuten; diese Liste zeigt
/// den Fortschritt live (über [AppDatabase.watchRestoreJobs]) und erlaubt
/// Abbrechen (wartend/laufend), Öffnen (fertig) und Entfernen aus der Liste
/// (fertig/fehlgeschlagen/abgebrochen – betrifft nur den Warteschlangen-
/// Eintrag, nicht das Foto selbst).
class RestoreQueueScreen extends StatefulWidget {
  final LibraryState library;
  const RestoreQueueScreen({super.key, required this.library});

  @override
  State<RestoreQueueScreen> createState() => _RestoreQueueScreenState();
}

class _RestoreQueueScreenState extends State<RestoreQueueScreen> {
  LibraryState get library => widget.library;

  Future<void> _openAsset(BuildContext context, RestoreJobData job) async {
    final asset = await ergebnisDesAuftrags(library.db, job);
    if (asset == null || !context.mounted) return;
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => AssetViewerScreen(
          assets: [asset],
          initialIndex: 0,
          paths: library.paths,
          db: library.db,
          library: library,
        ),
      ),
    );
  }

  String _statusLabel(BuildContext context, RestoreJobData job) {
    final t = AppTexte.of(context);
    return switch (job.status) {
      'queued' => t.restaurWartet,
      'running' => restaurLaufText(t, job),
      'done' => t.allgFertig,
      'cancelled' => t.restaurAbgebrochen,
      'failed' =>
        job.errorMessage == null
            ? t.restaurFehlgeschlagenKurz
            : t.restaurFehlgeschlagen(_grundText(t, job.errorMessage!)),
      _ => job.status,
    };
  }

  /// Der Dienst legt die Kennung des Grundes ab (siehe
  /// [RestaurierungsGrund]), bei einem Ladefehler gefolgt von der Ursache.
  /// Was zu keiner Kennung passt, stammt aus einer älteren Fassung, die den
  /// fertigen Satz gespeichert hat – der wird dann unverändert gezeigt,
  /// statt dem Nutzer eine Kennung vorzusetzen.
  String _grundText(AppTexte t, String gespeichert) {
    final trenner = gespeichert.indexOf(': ');
    if (trenner > 0) {
      final kennung = gespeichert.substring(0, trenner);
      final ursache = gespeichert.substring(trenner + 2);
      final uebersetzt = _kennung(t, kennung);
      if (uebersetzt != null) return '$uebersetzt $ursache';
    }
    return _kennung(t, gespeichert) ?? gespeichert;
  }

  String? _kennung(AppTexte t, String gespeichert) => switch (gespeichert) {
    'modellLaedtNicht' => t.restaurGrundModellLaedtNicht,
    'modellWeg' => t.restaurGrundModellWeg,
    'fotoWeg' => t.restaurGrundFotoWeg,
    'gesperrt' => t.restaurGrundGesperrt,
    'aufloesungUnbekannt' => t.restaurGrundAufloesung,
    'nichtGerendert' => t.restaurGrundNichtGerendert,
    'nichtDekodiert' => t.restaurGrundNichtDekodiert,
    'speicherbudget' => t.restaurGrundSpeicherbudget,
    'zuGross' => t.restaurGrundZuGross(
      hochskalierMaxKante,
      hochskalierMaxPixel ~/ 1000000,
    ),
    'keinFoto' => t.restaurGrundKeinFoto,
    'unbekannteArt' => t.restaurGrundUnbekannteArt,
    _ => null,
  };

  /// Gemerkte Auftrags-Fotos. Ein Auftrag zeigt immer dasselbe Foto, die
  /// Abfrage muss also genau einmal laufen.
  final Map<String, Future<AssetData?>> _assets = {};

  Future<AssetData?> _asset(String assetId) =>
      _assets.putIfAbsent(assetId, () => library.db.assetById(assetId));

  IconData _statusIcon(String status) => switch (status) {
    'queued' => Icons.schedule_outlined,
    'running' => Icons.auto_awesome_outlined,
    'done' => Icons.check_circle_outline,
    'cancelled' => Icons.cancel_outlined,
    'failed' => Icons.error_outline,
    _ => Icons.help_outline,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppTexte.of(context).restaurTitel)),
      body: StreamBuilder<List<RestoreJobData>>(
        stream: library.db.watchRestoreJobs(),
        builder: (context, snapshot) {
          final jobs = snapshot.data ?? [];
          if (jobs.isEmpty) {
            return EmptyState(
              icon: Icons.auto_awesome_outlined,
              message: AppTexte.of(context).restaurLeer,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: jobs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final job = jobs[index];
              final isActive =
                  job.status == 'queued' || job.status == 'running';
              return FutureBuilder<AssetData?>(
                // Nicht `library.db.assetById(...)` direkt: Dieser
                // Bildschirm baut bei jeder fertigen Kachel neu, und der
                // Aufruf hier würde dann je Auftrag eine Abfrage auslösen –
                // bei einem 12-MP-Foto rund 63 Stück ohne neue Information.
                future: _asset(job.assetId),
                builder: (context, assetSnapshot) {
                  final asset = assetSnapshot.data;
                  final name = asset?.originalFileName ?? job.assetId;
                  // Hochskalieren (#500) teilt sich die Warteschlange.
                  final faktor = hochskalierfaktor(job.id);
                  return ListTile(
                    leading: Icon(_statusIcon(job.status)),
                    title: Text(
                      faktor == null
                          ? name
                          : AppTexte.of(
                              context,
                            ).hochskalierenAuftragName(name, faktor),
                    ),
                    subtitle: Text(_statusLabel(context, job)),
                    onTap: job.status == 'done'
                        ? () => _openAsset(context, job)
                        : null,
                    trailing: isActive
                        ? IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: AppTexte.of(context).allgAbbrechen,
                            onPressed: () =>
                                library.restoreQueue.cancel(job.id),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Liegt das Ergebnis schon vor, wird nur noch
                              // abgelegt (siehe Auftragsergebnisse).
                              if (job.status == 'failed' ||
                                  job.status == 'cancelled')
                                IconButton(
                                  icon: const Icon(Icons.refresh),
                                  tooltip: AppTexte.of(
                                    context,
                                  ).allgErneutVersuchen,
                                  onPressed: () =>
                                      library.restoreQueue.wiederholen(job.id),
                                ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: AppTexte.of(context).restaurAusListe,
                                onPressed: () =>
                                    library.restoreQueue.entferne(job.id),
                              ),
                            ],
                          ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Was ein Klick auf einen fertigen Auftrag öffnet: bei einer Restaurierung
/// das Foto, bei einem Hochskalieren (#500) das Ergebnis – die jüngste
/// Aufnahme dieses Namens im Stapel des Originals. Bis hierher öffnete auch
/// das Hochskalieren das Original, und das Ergebnis lag verdeckt im Stapel.
/// Ist es nicht mehr zu finden (herausgenommen, gelöscht, umbenannt), bleibt
/// es beim Original.
Future<AssetData?> ergebnisDesAuftrags(
  AppDatabase db,
  RestoreJobData job,
) async {
  final original = await db.assetById(job.assetId);
  final faktor = hochskalierfaktor(job.id);
  final stapel = original?.stackId;
  if (original == null || faktor == null || stapel == null) return original;
  final name = hochskalierName(original.originalFileName, faktor);
  final treffer = [
    for (final m in await db.assetsInStack(stapel))
      if (m.id != original.id &&
          m.originalFileName == name &&
          !m.isTrashed &&
          !m.isLocked)
        m,
  ]..sort((a, b) => b.importedAt.compareTo(a.importedAt));
  return treffer.firstOrNull ?? original;
}

/// Was die Zeile eines laufenden Auftrags sagt.
///
/// **Nicht mehr „Kachel 12 von 20".** „Kachel" ist ein Wort aus dem
/// Maschinenraum – Real-ESRGAN zerlegt das Bild in Stücke, weil es nicht
/// auf einmal durch das Modell passt. Von aussen ist das keine Auskunft,
/// sondern eine Zumutung. Prozent und Restzeit beantworten die Frage,
/// die man wirklich stellt.
///
/// Als eigene Funktion und nicht als Rumpf des Bildschirms: Der
/// Entwickeln-Bildschirm zeigt denselben Fortschritt an der Stelle, an
/// der man ihn ausgelöst hat, und zwei Fassungen desselben Satzes wären
/// zwei Fassungen, die auseinanderlaufen.
String restaurLaufText(AppTexte t, RestoreJobData job) {
  final prozent = fortschrittProzent(job);
  if (prozent == null) return t.restaurWirdGestartet;
  final rest = restzeitSchaetzung(job);
  // Ohne Startzeit oder ohne eine einzige fertige Kachel gibt es keine
  // Restzeit. Dann steht sie eben nicht da – eine geratene wäre
  // schlimmer als keine.
  if (rest == null || rest == Duration.zero) {
    return t.restaurZeileLaeuft(prozent);
  }
  return t.restaurZeileMitRest(prozent, dauerText(t, rest));
}

/// Was das Band über der App-Hülle zur Warteschlange sagt – `null`, solange
/// nichts wartet und nichts läuft (dann ist das Band nicht zu sehen).
///
/// Prozent statt „Kachel 12 von 20": Die Kachel ist ein Begriff aus dem
/// Modell, nicht aus der Welt des Nutzers. Die Restzeit steht nur da, wenn
/// sie sich aus bereits erledigten Kacheln wirklich rechnen lässt (siehe
/// [restzeitSchaetzung]).
///
/// **Hochskalieren (#500)** läuft in derselben Warteschlange und sagt es
/// auch: „KI-Restaurierung läuft“ wäre für ein Foto, das man eben zum
/// Vergrössern geschickt hat, eine falsche Auskunft. Hier und nicht mehr im
/// Band selbst, damit sich das prüfen lässt, ohne die ganze Hülle zu bauen.
String? restaurierungsbandText(
  AppTexte t,
  List<RestoreJobData> jobs, {
  DateTime? jetzt,
}) {
  final running = jobs.where((j) => j.status == 'running').firstOrNull;
  final wartend = jobs.where((j) => j.status == 'queued').toList();
  final queuedCount = wartend.length;
  if (running == null && queuedCount == 0) return null;
  if (running == null) {
    return wartend.every((j) => istHochskalierauftrag(j.id))
        ? t.hochskalierenWartend(queuedCount)
        : t.restaurierungWartend(queuedCount);
  }
  final faktor = hochskalierfaktor(running.id);
  if (faktor != null) {
    return t.hochskalierenBand(
      t.hochskalierenAuftrag(faktor),
      restaurLaufText(t, running),
    );
  }
  final prozent = fortschrittProzent(running);
  final rest = restzeitSchaetzung(running, jetzt: jetzt);
  // Die Gesamtzahl der Kacheln steht erst fest, wenn das Bild dekodiert
  // ist. Bis dahin gibt es keinen Anteil zu zeigen.
  if (prozent == null) return t.restaurierungWirdVorbereitet;
  if (queuedCount > 0) {
    return t.restaurProzentMitWarteschlange(prozent, queuedCount);
  }
  if (rest != null && rest > Duration.zero) {
    return t.restaurProzentMitRest(prozent, dauerText(t, rest));
  }
  return t.restaurProzentLaeuft(prozent);
}
