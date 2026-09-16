import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import 'namens_dialog.dart' show MitTextsteuerung;
import '../screens/photo_compare_screen.dart';
import '../screens/export_presets_screen.dart';
import '../services/export_service.dart';
import '../services/secure_share_service.dart';
import 'pin_dialogs.dart';
import 'progress_dialog.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import 'album_picker_dialog.dart';
import 'color_label_picker.dart';
import 'mini_location_map.dart';
import 'star_rating.dart';
import '../services/meldungsdienst.dart';

/// Schwebende Aktionsleiste am unteren Rand, sichtbar sobald in einem
/// Foto-Raster (Timeline, Jahresansicht, Suche, Album) mindestens ein Foto
/// per langem Druck ausgewählt wurde – analog zu Google Fotos/Apple Fotos.
/// Enthält nur die allgemeinen, überall gleichen Sammelaktionen; was
/// "Löschen" im jeweiligen Kontext genau bedeutet (einfaches Verschieben in
/// den Papierkorb vs. zusätzlich Entfernen aus einem Album), entscheidet der
/// Aufrufer über [onDelete] selbst.
class SelectionActionBar extends StatelessWidget {
  final int count;
  final VoidCallback onClear;
  final VoidCallback onFavorite;
  final VoidCallback onAddToAlbum;
  final VoidCallback onTag;
  final VoidCallback onSetRating;
  final VoidCallback onSetColorLabel;
  final VoidCallback onEditMetadata;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  /// Überträgt zuvor kopierte Entwicklungseinstellungen auf die Auswahl.
  /// Optional, weil der Knopf nur dort erscheinen soll, wo tatsächlich
  /// etwas in der Zwischenablage liegt – und weil die übrigen Ansichten,
  /// die diese Leiste benutzen, unverändert bleiben sollen.
  final VoidCallback? onPasteDevelop;

  /// Wendet eine benannte Entwicklungs-Vorgabe an. Anders als
  /// [onPasteDevelop] hängt der Knopf nicht davon ab, ob gerade etwas
  /// kopiert wurde – eine Vorgabe liegt in der Datenbank und ist immer da.
  final VoidCallback? onApplyPreset;

  /// Zwei Fotos nebeneinander stellen. Nur bei genau zwei ausgewählten
  /// gesetzt – bei drei wäre nicht zu erraten, welche zwei gemeint sind.
  final VoidCallback? onCompare;

  const SelectionActionBar({
    super.key,
    required this.count,
    required this.onClear,
    required this.onFavorite,
    required this.onAddToAlbum,
    required this.onTag,
    required this.onSetRating,
    required this.onSetColorLabel,
    required this.onEditMetadata,
    required this.onExport,
    required this.onDelete,
    this.onCompare,
    this.onPasteDevelop,
    this.onApplyPreset,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: t.auswAufheben,
                  onPressed: onClear,
                ),
                Text(t.auswAnzahl(count)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.favorite_border),
                    tooltip: t.auswFavorisieren,
                    onPressed: onFavorite),
                IconButton(
                    icon: const Icon(Icons.playlist_add),
                    tooltip: t.auswZuAlbum,
                    onPressed: onAddToAlbum),
                IconButton(
                    icon: const Icon(Icons.label_outline),
                    tooltip: t.auswTagHinzufuegen,
                    onPressed: onTag),
                IconButton(
                    icon: const Icon(Icons.star_outline),
                    tooltip: t.auswBewertungSetzen,
                    onPressed: onSetRating),
                IconButton(
                    icon: const Icon(Icons.circle_outlined),
                    tooltip: t.auswFarbeSetzen,
                    onPressed: onSetColorLabel),
                IconButton(
                    icon: const Icon(Icons.edit_note_outlined),
                    tooltip: t.auswMetadaten,
                    onPressed: onEditMetadata),
                if (onPasteDevelop != null)
                  IconButton(
                      icon: const Icon(Icons.auto_fix_high_outlined),
                      tooltip: t.auswEntwicklungUebertragen,
                      onPressed: onPasteDevelop),
                if (onApplyPreset != null)
                  IconButton(
                      icon: const Icon(Icons.bookmarks_outlined),
                      tooltip: t.auswVorgabeAnwenden,
                      onPressed: onApplyPreset),
                if (onCompare != null)
                  IconButton(
                      icon: const Icon(Icons.compare_outlined),
                      tooltip: t.auswVergleichen,
                      onPressed: onCompare),
                IconButton(
                    icon: const Icon(Icons.ios_share),
                    tooltip: t.auswExportieren,
                    onPressed: onExport),
                IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: t.allgLoeschen,
                    onPressed: onDelete),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Einfacher Ja/Nein-Bestätigungsdialog für Sammelaktionen, die sich nicht
/// (leicht) rückgängig machen lassen.
/// [vorschau] steht ueber dem Text, wenn es etwas zu sehen gibt.
///
/// Bei der Integritaetspruefung geht es um Dateien, die unwiderruflich
/// von der Platte verschwinden – und deren Pfad allein nicht verraet, was
/// darin steckt. Wer sehen kann, was er loescht, entscheidet anders.
/// [bestaetigen] beschriftet den Ja-Knopf. Ohne Angabe steht dort
/// „Löschen" – der Regelfall. Wo etwas anderes geschieht, muss dort
/// etwas anderes stehen: „Original wiederherstellen" mit einem Knopf
/// „Löschen" daneben liest sich, als werde das Original gelöscht.
Future<bool> confirmDialog(BuildContext context, String title, String message,
    {Widget? vorschau, String? bestaetigen}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: vorschau == null
          ? Text(message)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                vorschau,
                const SizedBox(height: 16),
                Text(message),
              ],
            ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppTexte.of(context).allgAbbrechen)),
        // Die Farbe des Themas für Fehler und nicht `Colors.red`: Weiss
        // auf `Colors.red` ergibt 3,68:1, wo Knopfschrift 4,5:1 braucht –
        // ausgerechnet an dem Knopf, bei dem man sicher sein muss, was
        // man drückt. `onError` auf `error` sind 6,46:1. Und beide Farben
        // gehören zusammen: Wer nur den Grund austauscht, lässt die
        // Schrift auf der Vorgabe stehen.
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(bestaetigen ?? AppTexte.of(context).allgLoeschen),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Markiert alle übergebenen Fotos als Favorit. Bewusst kein Toggle – bei
/// gemischter Auswahl (manche schon favorisiert, manche nicht) wäre ein
/// Umschalten mehrdeutig; "als Favorit markieren" ist wie in Google Fotos
/// die einzige Sammelaktion.
/// Öffnet den Vergleich für genau zwei ausgewählte Fotos.
///
/// Als gemeinsame Funktion, weil vier Bildschirme dieselbe Auswahlleiste
/// benutzen (Zeitleiste, Album, Suche, Kalender) und der Weg dorthin
/// überall derselbe sein muss.
///
/// Gibt `null` zurück, wenn nicht genau zwei ausgewählt sind – der Knopf
/// wird dann gar nicht erst angeboten.
VoidCallback? vergleichsAktion(
  BuildContext context,
  LibraryState library,
  List<String> ausgewaehlt,
) {
  if (ausgewaehlt.length != 2) return null;
  return () async {
    final assets = await library.db.assetsByIds(ausgewaehlt);
    if (assets.length != 2 || !context.mounted) return;
    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => PhotoCompareScreen(
        links: assets[0],
        rechts: assets[1],
        paths: library.paths,
      ),
    ));
  };
}

Future<void> runBatchFavorite(LibraryState library, List<String> assetIds) =>
    library.db.setFavoriteBulk(assetIds, true);

/// Zeigt eine Sternereihe zur Auswahl einer gemeinsamen Bewertung für alle
/// übergebenen Fotos ("Keine Bewertung" setzt explizit auf 0 zurück statt
/// den Dialog nur abzubrechen).
Future<void> runBatchSetRating(
    BuildContext context, LibraryState library, List<String> assetIds) async {
  final rating = await showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(AppTexte.of(context).auswBewertungTitel(assetIds.length)),
      content: StarRating(
          value: 0, size: 32, onChanged: (v) => Navigator.pop(context, v)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, 0),
            child: Text(AppTexte.of(context).auswKeineBewertung)),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppTexte.of(context).allgAbbrechen)),
      ],
    ),
  );
  if (rating == null) return;
  await library.db.setRatingBulk(assetIds, rating);
}

/// Zeigt die Farbmarkierungs-Palette zur Auswahl einer gemeinsamen
/// Farbmarkierung für alle übergebenen Fotos. Der leere String dient als
/// Sentinel für "Keine Farbe" (die eigentliche Spalte ist `null`) – so lässt
/// sich der Abbrechen-Fall (`null` vom Dialog-Barrier) vom bewussten
/// Löschen der Markierung unterscheiden.
Future<void> runBatchSetColorLabel(
    BuildContext context, LibraryState library, List<String> assetIds) async {
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(AppTexte.of(context).auswFarbeTitel(assetIds.length)),
      content: ColorLabelPicker(
          value: null,
          size: 32,
          onChanged: (c) => Navigator.pop(context, c ?? '')),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: Text(AppTexte.of(context).auswKeineFarbe)),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppTexte.of(context).allgAbbrechen)),
      ],
    ),
  );
  if (result == null) return;
  await library.db.setColorLabelBulk(assetIds, result.isEmpty ? null : result);
}

/// Dialog mit drei optionalen Feldern (Beschreibung, Datum, Ort) – nur
/// tatsächlich ausgefüllte/geänderte Felder werden geschrieben, damit die
/// Sammelbearbeitung keine bestehenden Werte der einzelnen Fotos mit
/// Leerwerten überschreibt.
Future<void> runBatchEditMetadataDialog(
    BuildContext context, LibraryState library, List<String> assetIds) async {
  final result = await showDialog<_BatchMetadataResult>(
    context: context,
    builder: (context) => _BatchMetadataDialog(count: assetIds.length),
  );
  if (result == null) return;
  if (result.description != null) {
    await library.db.setDescriptionBulk(assetIds, result.description!);
  }
  if (result.date != null) {
    // Über LibraryState und nicht über die Datenbankschicht: Das Datum
    // bestimmt den Ablageort, und die Datei muss mit (siehe
    // [LibraryState.setzeAufnahmedatumVonHand]).
    await library.setzeAufnahmedatumVonHand(assetIds, result.date!);
  }
  if (result.ortEntfernen) {
    await library.setzeOrtVonHand(assetIds, null, null);
  } else if (result.latitude != null && result.longitude != null) {
    await library.setzeOrtVonHand(assetIds, result.latitude, result.longitude);
  }
}

class _BatchMetadataResult {
  final String? description;
  final DateTime? date;
  final double? latitude;
  final double? longitude;

  /// Den Ort ganz wegnehmen statt einen neuen zu setzen.
  ///
  /// Einzeln ging das im Infoblatt seit jeher, für eine Auswahl gar nicht –
  /// und für eine Auswahl braucht man es: Eine Kamera mit verrutschtem
  /// Empfänger vergibt einen falschen Ort nicht einmal, sondern an alles,
  /// was in dieser Woche entstand.
  final bool ortEntfernen;

  const _BatchMetadataResult(
      {this.description,
      this.date,
      this.latitude,
      this.longitude,
      this.ortEntfernen = false});
}

class _BatchMetadataDialog extends StatefulWidget {
  final int count;
  const _BatchMetadataDialog({required this.count});

  @override
  State<_BatchMetadataDialog> createState() => _BatchMetadataDialogState();
}

class _BatchMetadataDialogState extends State<_BatchMetadataDialog> {
  final _descriptionCtrl = TextEditingController();
  DateTime? _date;
  double? _latitude;
  double? _longitude;
  bool _ortEntfernen = false;

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1970),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  void _save() {
    Navigator.pop(
      context,
      _BatchMetadataResult(
        description: _descriptionCtrl.text.trim().isEmpty
            ? null
            : _descriptionCtrl.text.trim(),
        date: _date,
        latitude: _latitude,
        longitude: _longitude,
        ortEntfernen: _ortEntfernen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppTexte.of(context).auswMetadatenTitel(widget.count)),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _descriptionCtrl,
                decoration: InputDecoration(
                  labelText: AppTexte.of(context).auswBeschreibungFeld,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_date == null
                    ? AppTexte.of(context).auswDatumUnveraendert
                    : AppTexte.of(context).auswDatumGesetzt(DateFormat.yMd(
                            Localizations.localeOf(context).toString())
                        .format(_date!))),
                trailing: TextButton(
                    onPressed: _pickDate,
                    child: Text(AppTexte.of(context).allgWaehlen)),
              ),
              const SizedBox(height: 12),
              Text(AppTexte.of(context).auswOrtHinweis),
              const SizedBox(height: 8),
              MiniLocationMap(
                latitude: _ortEntfernen ? null : _latitude,
                longitude: _ortEntfernen ? null : _longitude,
                onLocationChanged: (lat, lon) => setState(() {
                  _latitude = lat;
                  _longitude = lon;
                  // Wer auf die Karte tippt, meint einen Ort und nicht
                  // dessen Abwesenheit.
                  _ortEntfernen = false;
                }),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                value: _ortEntfernen,
                onChanged: (an) => setState(() => _ortEntfernen = an ?? false),
                title: Text(AppTexte.of(context).auswOrtEntfernen),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppTexte.of(context).allgAbbrechen)),
        FilledButton(
            onPressed: _save, child: Text(AppTexte.of(context).allgSpeichern)),
      ],
    );
  }
}

/// Fragt einen einzelnen Tag-Namen ab und fügt ihn allen übergebenen Fotos
/// hinzu.
Future<void> runBatchTagDialog(
    BuildContext context, LibraryState library, List<String> assetIds) async {
  final tag = await showDialog<String>(
    context: context,
    builder: (context) => MitTextsteuerung(
        builder: (context, ctrl) => AlertDialog(
              title: Text(AppTexte.of(context).auswTagTitel(assetIds.length)),
              content: TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: InputDecoration(
                      labelText: AppTexte.of(context).auswTagFeld)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(AppTexte.of(context).allgAbbrechen)),
                FilledButton(
                    onPressed: () => Navigator.pop(context, ctrl.text.trim()),
                    child: Text(AppTexte.of(context).allgHinzufuegen)),
              ],
            )),
  );
  if (tag == null || tag.isEmpty) return;
  await library.db.tagAssetsBulk(assetIds, tag);
}

/// Zeigt den Album-Auswahl-Dialog und fügt die übergebenen Fotos danach dem
/// gewählten (oder neu angelegten) Album hinzu.
Future<void> runBatchAddToAlbumDialog(
    BuildContext context, LibraryState library, List<String> assetIds) async {
  final existingAlbums = await library.db.watchAlbums().first;
  if (!context.mounted) return;
  final choice = await showAlbumPickerDialog(context, existingAlbums);
  if (choice == null) return;

  final String albumId;
  if (choice.newName != null) {
    albumId = const Uuid().v4();
    await library.db.createAlbum(
      AlbumsCompanion.insert(
          id: albumId, name: choice.newName!, createdAt: DateTime.now()),
    );
  } else {
    albumId = choice.existingAlbumId!;
  }
  await library.db.addAssetsToAlbum(albumId, assetIds);
}

/// Exportiert alle übergebenen Fotos in einen vom Nutzer gewählten Ordner,
/// mit Fortschrittsanzeige – dieselbe Logik wie der bisherige, nur an ein
/// Album gebundene "Album exportieren"-Button in AlbumDetailScreen, jetzt
/// für eine beliebige Auswahl nutzbar.
/// Was der Export-Dialog zurückgibt: entweder eine fertige Vorgabe oder der
/// Wunsch, erst die Voreinstellungen zu verwalten.
///
/// Ein eigener Typ statt `Exportvorgabe?`, weil „abgebrochen" und „zeig mir
/// die Verwaltung" sonst beide als `null` zurückkämen und der Aufrufer sie
/// nicht auseinanderhalten könnte.
sealed class _Exportwahl {
  const _Exportwahl();
}

class _WahlVorgabe extends _Exportwahl {
  final Exportvorgabe vorgabe;
  const _WahlVorgabe(this.vorgabe);
}

class _WahlVerwalten extends _Exportwahl {
  const _WahlVerwalten();
}

class _WahlSicherTeilen extends _Exportwahl {
  const _WahlSicherTeilen();
}

/// Fragt die Ausgabe ab: die vier festen Grössen und, sofern angelegt, die
/// eigenen Voreinstellungen. `null` bedeutet Abbruch.
Future<_Exportwahl?> _frageExportgroesse(
    BuildContext context, LibraryState library, int anzahl) async {
  final vorgaben = await library.db.alleExportPresets();
  if (!context.mounted) return null;

  return showDialog<_Exportwahl>(
    context: context,
    builder: (context) {
      final t = AppTexte.of(context);
      return SimpleDialog(
        title: Text(t.auswExportTitel(anzahl)),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, const _WahlSicherTeilen()),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.enhanced_encryption_outlined),
              title: Text(t.sicherTeilenTitel),
              subtitle: Text(t.sicherTeilenText),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(
                context, _WahlVorgabe(Exportvorgabe.datenschutz())),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(t.datenschutzExportTitel),
              subtitle: Text(t.datenschutzExportText),
            ),
          ),
          const Divider(),
          for (final g in Exportgroesse.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(
                  context, _WahlVorgabe(Exportvorgabe.ausGroesse(g))),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(exportgroesseBezeichnung(t, g)),
                subtitle: Text(g.maxKante == null
                    ? t.exportUnveraendert
                    : t.exportJpegKante(g.maxKante!)),
              ),
            ),
          if (vorgaben.isNotEmpty) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Text(t.exportEigeneVorgaben,
                  style: Theme.of(context).textTheme.labelMedium),
            ),
            for (final v in vorgaben)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(
                    context, _WahlVorgabe(Exportvorgabe.ausPreset(v))),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(v.name),
                  subtitle: Text(vorgabeZusammenfassung(t, v)),
                ),
              ),
          ],
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, const _WahlVerwalten()),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tune_outlined),
              title: Text(t.exportVorgabenVerwalten),
            ),
          ),
        ],
      );
    },
  );
}

/// Wendet eine benannte Entwicklungs-Vorgabe auf [assetIds] an.
///
/// Läuft durch denselben Weg wie das Übertragen aus der Zwischenablage
/// (siehe [runBatchPasteDevelop]) – der Unterschied ist nur, woher die
/// Werte kommen. Zwei Übertragungswege nebeneinander wären die
/// naheliegendste Art, dass einer beim nächsten neuen Regler etwas
/// vergisst.
Future<void> runBatchApplyPreset(
    BuildContext context, LibraryState library, List<String> assetIds) async {
  final t = AppTexte.of(context);
  final vorgaben = await library.db.alleDevelopPresets();
  if (!context.mounted) return;
  if (vorgaben.isEmpty) {
    melde.hinweis(t.entwKeineVorgaben);
    return;
  }

  final gewaehlt = await showDialog<DevelopPresetData>(
    context: context,
    builder: (context) => SimpleDialog(
      title:
          Text(AppTexte.of(context).auswVorgabeAnwendenTitel(assetIds.length)),
      children: [
        for (final v in vorgaben)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, v),
            child: Text(v.name),
          ),
      ],
    ),
  );
  if (gewaehlt == null || !context.mounted) return;

  final werte = await library.werteAusVorgabe(gewaehlt);
  if (!context.mounted) return;

  // Vor dem Dialog auflösen, wie beim Übertragen: Der Mapper unten läuft
  // lange nachdem dieser Kontext gültig war.
  final keineGeeigneten = AppTexte.of(context).auswKeineGeeigneten;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ProgressDialog(
      title: AppTexte.of(context).auswUebertrageLaeuft,
      stream: library.uebertrageEntwicklung(assetIds, vorgabe: werte).map(
            (p) => p.total == 0
                ? keineGeeigneten
                : '${p.done} / ${p.total}${p.currentFile != null ? ' — ${p.currentFile}' : ''}',
          ),
    ),
  );
}

/// Überträgt die zuvor kopierten Entwicklungseinstellungen auf [assets].
///
/// Als gemeinsame Funktion neben [runBatchExport], damit alle Ansichten mit
/// Mehrfachauswahl dasselbe tun – die erste Fassung hatte das nur in der
/// Übersicht, und dort suchte es niemand (Fehlerbericht).
Future<void> runBatchPasteDevelop(
    BuildContext context, LibraryState library, List<String> assetIds) async {
  final quelle = library.kopierteEntwicklung;
  if (quelle == null) return;

  final bestaetigt = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(AppTexte.of(context).auswUebertragenTitel(assetIds.length)),
      content: Text(AppTexte.of(context).auswUebertragenText),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppTexte.of(context).allgAbbrechen)),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppTexte.of(context).auswUebertragen)),
      ],
    ),
  );
  if (bestaetigt != true || !context.mounted) return;

  // Vor dem Dialog auflösen: Der Mapper unten läuft bei jedem Ereignis, also
  // lange nachdem dieser Kontext gültig war.
  final keineGeeigneten = AppTexte.of(context).auswKeineGeeigneten;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ProgressDialog(
      title: AppTexte.of(context).auswUebertrageLaeuft,
      stream: library.uebertrageEntwicklung(assetIds).map(
            (p) => p.total == 0
                ? keineGeeigneten
                : '${p.done} / ${p.total}${p.currentFile != null ? ' — ${p.currentFile}' : ''}',
          ),
    ),
  );
}

Future<void> runBatchExport(
    BuildContext context, LibraryState library, List<AssetData> assets) async {
  final wahl = await _frageExportgroesse(context, library, assets.length);
  if (wahl == null || !context.mounted) return;

  // „Verwalten" führt in die Verwaltung und danach zurück in die Auswahl.
  // Ohne das zweite Öffnen stünde jemand, der gerade eine Voreinstellung
  // angelegt hat, wieder vor der Übersicht – und müsste den Export neu
  // anstossen, um sie zu benutzen.
  if (wahl is _WahlVerwalten) {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ExportPresetsScreen(library: library),
    ));
    if (!context.mounted) return;
    return runBatchExport(context, library, assets);
  }
  if (wahl is _WahlSicherTeilen) {
    final passphrase = await showSetPassphraseDialog(context);
    if (passphrase == null || !context.mounted) return;
    final texte = AppTexte.of(context);
    final defaultName = texte.sicherTeilenDateiname;
    final extension = p.extension(defaultName);
    final selected = await FilePicker.platform.saveFile(
      dialogTitle: texte.sicherTeilenZiel,
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: [extension.substring(1)],
    );
    if (selected == null || !context.mounted) return;
    final path = selected.toLowerCase().endsWith(extension.toLowerCase())
        ? selected
        : '$selected$extension';
    try {
      await SecureShareService(ExportService(library.paths, library: library))
          .createPackage(assets, File(path), passphrase);
      if (context.mounted) {
        melde.erfolg(AppTexte.of(context).sicherTeilenFertig(path));
      }
    } catch (error) {
      if (context.mounted) {
        melde.fehler(AppTexte.of(context).sicherTeilenFehler('$error'));
      }
    }
    return;
  }
  final vorgabe = (wahl as _WahlVorgabe).vorgabe;

  final destination = await FilePicker.platform.getDirectoryPath(
    dialogTitle: AppTexte.of(context).auswZielordner(assets.length),
  );
  if (destination == null || !context.mounted) return;

  final exporter = ExportService(library.paths, library: library);
  var done = 0;
  void Function(void Function())? setDialogState;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      setDialogState = setState;
      return AlertDialog(
        content: Row(
          children: [
            const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 16),
            Expanded(
                child: Text(AppTexte.of(context)
                    .auswExportiereLaeuft(done, assets.length))),
          ],
        ),
      );
    }),
  );

  var exported = 0;
  var ausgelassen = 0;
  for (final asset in assets) {
    try {
      // Die laufende Nummer zählt die Fotos des Laufs, nicht die
      // erfolgreichen – sonst bekämen zwei Fotos dieselbe Nummer, sobald
      // eines dazwischen fehlschlägt.
      await exporter.exportAsset(asset, destination,
          vorgabe: vorgabe, nummer: done + 1);
      exported++;
    } on DatenschutzNichtMoeglich {
      // Eigener Zweig, weil das kein Fehlschlag ist, sondern eine
      // eingehaltene Zusage: Diese Aufnahme liesse sich nur ungesäubert
      // ausliefern, also bleibt sie liegen. Stillschweigend mitzählen wäre
      // das Schlimmste von beidem – der Nutzer hielte die Auswahl für
      // gesäubert und hätte eine Datei weniger, ohne zu wissen welche.
      ausgelassen++;
    } catch (_) {
      // Einzelne fehlgeschlagene Datei überspringen, Rest weiter exportieren.
    }
    done++;
    setDialogState?.call(() {});
  }

  if (context.mounted) {
    Navigator.of(context).pop();
    final t = AppTexte.of(context);
    melde.erfolg(t.auswExportFertig(exported, assets.length, destination));
    // Nach der Erfolgsmeldung und als Warnung, nicht als Hinweis: Sie
    // schränkt die Zeile darüber ein, und wer sie überliest, hält den
    // Export für vollständig.
    if (ausgelassen > 0) melde.warnung(t.datenschutzAusgelassen(ausgelassen));
  }
}
