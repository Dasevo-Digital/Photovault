import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/ai_tagging_service.dart';
import '../services/geo_data_catalog.dart';
import '../services/model_download_service.dart';
import '../services/geo_data_download_service.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/aktualisierungspruefung.dart';
import '../services/backup_service.dart';
import '../services/backup_verification_service.dart';
import '../services/library_location.dart';
import '../services/storage_paths.dart';
import '../services/model_catalog.dart';
import '../state/library_state.dart';
import '../services/platform/reveal_in_file_manager.dart';
import '../theme/app_spacing.dart';
import '../widgets/tastenkuerzel.dart';
import '../theme/app_theme.dart';
import '../widgets/pin_dialogs.dart';
import '../widgets/progress_dialog.dart';
import '../widgets/typed_confirm_dialog.dart';
import 'background_tasks_screen.dart';
import 'locked_folder_screen.dart';
import 'trash_screen.dart';
import '../services/kachelvorrat.dart';
import '../widgets/eigene_karte_einstellung.dart';
import '../widgets/kartenquellen_uebersicht.dart';
import '../widgets/mini_location_map.dart'
    show Kartenstil, setzeCartoSchluessel, setzeKarteHochaufloesend;
import 'kachelmitschnitt_screen.dart';
import 'map_screen.dart' show Kartenansicht;
import '../services/meldungsdienst.dart';
import '../services/groessentext.dart';

class SettingsScreen extends StatefulWidget {
  final LibraryState library;
  const SettingsScreen({super.key, required this.library});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Der Griff zum Formular für die eigene Kartenquelle. Über ihn
  /// schreibt die Quellenübersicht darüber eine Vorlage hinein und
  /// scrollt sie ins Bild.
  final _eigeneKarte = GlobalKey<EigeneKarteEinstellungState>();

  /// Wechselt die Oberflächensprache und bietet dabei einmalig an, das
  /// Schlagwort-Vokabular mitzuziehen.
  ///
  /// Die Reihenfolge ist Absicht: erst umstellen, dann fragen. So sieht der
  /// Nutzer den Dialog bereits in der neuen Sprache und kann beurteilen,
  /// worauf er sich einlässt. Lehnt er ab, bleibt es dabei – es gibt keine
  /// zweite Nachfrage bei jedem Start.
  Future<void> _wechsleSprache(String sprachcode) async {
    // Vor dem ersten await lesen: Danach kann der Kontext veraltet sein,
    // und die Sprache VOR der Umstellung ist genau das, was gebraucht wird.
    //
    // Massgeblich ist dabei, welche Sprache tatsächlich WIRKT, nicht welche
    // eingestellt ist: Wer von „System" (auf einem englischen Rechner) auf
    // „Deutsch" stellt, wechselt real von Englisch nach Deutsch – die
    // gespeicherten Werte allein ('system' -> 'de') verrieten das nicht.
    final vorher = Localizations.localeOf(context).languageCode;

    if (await widget.library.db.spracheWert() == sprachcode) return;
    await widget.library.db.setSprache(sprachcode);
    final nachher = sprachcode == 'system' ? _systemsprache() : sprachcode;

    final richtung = switch ((vorher, nachher)) {
      ('de', 'en') => aiTagVocabularyEnglisch,
      ('en', 'de') => {
          for (final e in aiTagVocabularyEnglisch.entries) e.value: e.key
        },
      _ => null,
    };
    if (richtung == null || !mounted) return;

    // Nur Begriffe anbieten, die auch wirklich im Vokabular stehen.
    final vorhandene = await widget.library.db.aiTagVocabularyTerms();
    final betroffen = {
      for (final e in richtung.entries)
        if (vorhandene.contains(e.key)) e.key: e.value,
    };
    if (betroffen.isEmpty || !mounted) return;
    final eigene = vorhandene.length - betroffen.length;

    final t = AppTexte.of(context);
    final uebersetzen = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.spracheVokabularTitel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.spracheVokabularText(betroffen.length, vorhandene.length)),
            if (eigene > 0) ...[
              const SizedBox(height: 10),
              Text(t.spracheVokabularSelbstAngelegt(eigene),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.spracheVokabularBehalten),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.spracheVokabularUebersetzen),
          ),
        ],
      ),
    );
    if (uebersetzen != true) return;

    final anzahl = await widget.library.db.uebersetzeVokabular(betroffen);
    // Die zwischengespeicherten Begriffs-Vektoren gehören zu den alten
    // Wörtern und wären danach nie wieder erreichbar.
    widget.library.aiTaggingService.leereBegriffsCache();
    if (!mounted) return;
    melde.erfolg(AppTexte.of(context).spracheVokabularFertig(anzahl));
  }

  /// Welche der unterstützten Sprachen bei "System" greift.
  ///
  /// Flutter würde bei einer nicht unterstützten Systemsprache auf den
  /// ersten Eintrag aus `supportedLocales` zurückfallen; genau das bildet
  /// diese Zeile nach, statt es zu raten.
  String _systemsprache() {
    final system =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return AppTexte.supportedLocales.any((l) => l.languageCode == system)
        ? system
        : AppTexte.supportedLocales.first.languageCode;
  }

  /// Was die Bibliothek belegt – aufgeschlüsselt, nicht nur die
  /// Originale. Siehe [StoragePaths.belegung].
  Bibliotheksbelegung? _belegung;
  BackupRecordData? _lastBackup;
  final Set<String> _downloading = {};

  /// Wo die Reihe steht, wenn alle fehlenden Modelle am Stueck geholt
  /// werden: (das wievielte, wie viele). `null`, wenn keine Reihe laeuft.
  (int, int)? _reihenstand;
  bool _encryptManualBackup = false;
  bool _downloadingGeoData = false;
  double _geoDataProgress = 0;
  final TextEditingController _aiTagVocabularyController =
      TextEditingController();

  /// Sucheingabe über den Gruppen. Filtert nach Titel UND Beschreibung –
  /// wer „Passphrase" eingibt, soll den gesperrten Ordner auch dann finden,
  /// wenn das Wort nur in der Beschreibung steht.
  final TextEditingController _suche = TextEditingController();

  /// Der eingetippte CARTO-Schlüssel.
  ///
  /// Nicht an einen `StreamBuilder` gebunden: Ein Feld, dessen Inhalt bei
  /// jedem Datenbankereignis von aussen neu gesetzt wird, springt beim
  /// Tippen mit dem Textzeiger. Der gespeicherte Wert wird einmal
  /// hineingeschrieben ([_ladeCartoSchluessel]), danach gehört das Feld
  /// dem Nutzer.
  final TextEditingController _cartoSchluessel = TextEditingController();
  bool _cartoGeladen = false;

  @override
  void dispose() {
    // Ohne das läuft das Vorladen weiter, nachdem der Bildschirm zu ist –
    // und `setState` auf einem abgeräumten Zustand wirft.
    _vorratLauf?.cancel();
    _aiTagVocabularyController.dispose();
    _suche.dispose();
    _cartoSchluessel.dispose();
    super.dispose();
  }

  /// Holt den gespeicherten Schlüssel einmalig ins Feld.
  Future<void> _ladeCartoSchluessel() async {
    if (_cartoGeladen) return;
    _cartoGeladen = true;
    final wert = await widget.library.db.cartoSchluesselWert();
    if (!mounted || wert == null) return;
    setState(() => _cartoSchluessel.text = wert);
  }

  Future<void> _speichereCartoSchluessel() async {
    final eingabe = _cartoSchluessel.text.trim();
    await widget.library.db.setzeCartoSchluesselWert(eingabe);
    // Auch von Hand setzen und nicht allein auf den Einstellungsstrom in
    // main.dart bauen: Der erreicht diesen Bildschirm zwar auch, aber
    // erst beim nächsten Aufbau. So steht die neue Karte schon da, wenn
    // jemand direkt von hier zur Karte wechselt.
    setzeCartoSchluessel(eingabe);
    if (!mounted) return;
    setState(() {});
    melde.erfolg(eingabe.isEmpty
        ? AppTexte.of(context).einstCartoEntfernt
        : AppTexte.of(context).einstCartoGespeichert);
  }

  Future<void> _addAiTagVocabularyTerm() async {
    final term = _aiTagVocabularyController.text.trim();
    if (term.isEmpty) return;
    _aiTagVocabularyController.clear();
    await widget.library.db.addAiTagTerm(term);
  }

  // Als Felder statt inline im FutureBuilder in build() erzeugt: ein dort
  // direkt aufgerufenes `future: someQuery()` würde bei JEDEM Rebuild dieses
  // Screens (z.B. durch den App-weiten Consumer<LibraryState>) ein neues
  // Future anstoßen und den jeweiligen FutureBuilder kurz in den Ladezustand
  // zurückfallen lassen. Gezielt per _reloadX() nach den Aktionen aktualisiert,
  // die den jeweiligen Wert tatsächlich ändern können.
  late Future<bool> _isCustomLocationFuture;
  late Future<bool> _hasPinSetFuture;
  late Future<bool> _hasBackupKeyFuture;
  late Future<BackupSettingsData?> _backupSettingsFuture;
  late Future<TrashSettingsData?> _trashSettingsFuture;
  late Future<List<BibliothekMitZustand>> _bibliothekenFuture;
  late Future<({String pfad, String? token})?> _ueberwachterOrdnerFuture;
  late Future<PackageInfo> _versionFuture;
  Aktualisierungsstand? _aktualisierungsstand;
  String? _aktualisierungsfehler;
  bool _pruefeAktualisierung = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _isCustomLocationFuture = LibraryLocation.isCustom;
    _bibliothekenFuture = LibraryLocation.bekannte();
    _ueberwachterOrdnerFuture = widget.library.db.ueberwachterOrdner();
    _versionFuture = PackageInfo.fromPlatform();
    _hasPinSetFuture = widget.library.db.hasPinSet();
    _hasBackupKeyFuture = widget.library.db.hasBackupKey();
    _backupSettingsFuture = widget.library.db.backupSettingsRow();
    _trashSettingsFuture = widget.library.db.trashSettingsRow();
  }

  void _reloadPinState() =>
      setState(() => _hasPinSetFuture = widget.library.db.hasPinSet());
  void _reloadBackupKeyState() =>
      setState(() => _hasBackupKeyFuture = widget.library.db.hasBackupKey());
  void _reloadBackupSettings() => setState(
      () => _backupSettingsFuture = widget.library.db.backupSettingsRow());
  void _reloadTrashSettings() => setState(
      () => _trashSettingsFuture = widget.library.db.trashSettingsRow());

  Future<void> _refresh() async {
    final belegt = await widget.library.paths.belegung();
    final last = await widget.library.db.lastBackupRecord();
    if (mounted) {
      setState(() {
        _belegung = belegt;
        _lastBackup = last;
      });
    }
  }

  /// Datum in der Schreibweise der aktiven Sprache – 17.08.2026 gegen
  /// 8/17/2026. Vorher stand hier `${d}.${m}.${y}` von Hand zusammengesetzt,
  /// was in jeder Sprache deutsch aussah.
  String _datum(DateTime zeitpunkt) =>
      DateFormat.yMd(Localizations.localeOf(context).toString())
          .format(zeitpunkt);

  String _datumZeit(DateTime zeitpunkt) {
    final sprache = Localizations.localeOf(context).toString();
    return '${DateFormat.yMd(sprache).format(zeitpunkt)} – '
        '${DateFormat.Hm(sprache).format(zeitpunkt)}';
  }

  /// Übersetzt die Fehler der beiden Download-Dienste.
  ///
  /// Sie melden nur die Bestandteile (siehe [ModellDownloadFehler]); alles
  /// andere geht unverändert durch, damit ein unerwarteter Fehler nicht
  /// stillschweigend zu einer leeren Meldung wird.
  static String _fehlertext(BuildContext context, Object fehler) {
    final t = AppTexte.of(context);
    return switch (fehler) {
      BackupBrauchtPassphrase() => t.backupPassphraseNoetig,
      BackupPruefungBrauchtPassphrase() => t.backupPassphraseNoetig,
      BackupOrdnerFehlt() => t.backupOrdnerFehlt,
      AktualisierungsFehler(
        problem: Aktualisierungsproblem.keineVeroeffentlichungen
      ) =>
        t.aktualisierungKeineVeroeffentlichungen,
      AktualisierungsFehler(problem: Aktualisierungsproblem.keineVersion) =>
        t.aktualisierungKeineVersion,
      ModellDownloadFehler(
        :final datei,
        erhalten: final erhalten?,
        erwartet: final erwartet?
      ) =>
        t.downloadPruefsummeFehler(datei, erhalten, erwartet),
      ModellDownloadFehler(:final datei, :final ursache) =>
        t.downloadFehlgeschlagen(datei, ursache ?? ''),
      GeoDownloadFehler(:final datei, ursache: null, beimEntpacken: true) =>
        t.downloadNichtImZip(datei),
      GeoDownloadFehler(:final datei, :final ursache, beimEntpacken: true) =>
        t.downloadEntpackenFehler(datei, ursache ?? ''),
      GeoDownloadFehler(:final datei, :final ursache) =>
        t.downloadFehlgeschlagen(datei, ursache ?? ''),
      _ => '$fehler',
    };
  }

  /// Eine Zeile Backup-Fortschritt.
  ///
  /// Der Dienst meldet nur Zahlen und Dateinamen; ob die Mengenbegrenzung
  /// gegriffen hat, steht als Zahl in [BackupProgress.grenzeOffen] und wird
  /// erst hier zu einem Satz.
  /// Die Zeile im Fortschrittsfenster der Wiederherstellung.
  ///
  /// Die Übernahme aus dem Datenbank-Schnappschuss muss dastehen: Sie ist
  /// der Unterschied zwischen „die Fotos sind zurück" und „die Bibliothek
  /// ist zurück", und ohne ein Wort dazu bemerkt man erst Tage später, dass
  /// die Namen an den Gesichtern fehlen.
  static String _wiederherstellZeile(AppTexte t, BackupProgress p) {
    if (p.uebernommeneZeilen != null) {
      return t.backupUebernommen(p.uebernommeneZeilen!);
    }
    if (p.ausschnitteNeu) {
      return '${t.backupAusschnitteNeu}  ${p.done} / ${p.total}';
    }
    return '${p.done} / ${p.total}'
        '${p.currentFile != null ? ' — ${p.currentFile}' : ''}';
  }

  static String _backupZeile(AppTexte t, BackupProgress p) {
    if (p.fehlgeschlagen != null) {
      return t.backupNichtGesichert(p.fehlgeschlagen!);
    }
    if (p.grenzeOffen != null) return t.backupGrenzeErreicht(p.grenzeOffen!);
    return '${p.done} / ${p.total}'
        '${p.currentFile != null ? ' — ${p.currentFile}' : ''}';
  }

  static String _backupPruefZeile(AppTexte t, BackupPrueffortschritt p) {
    if (p.abgeschlossen) {
      return p.erfolgreich
          ? t.einstBackupPruefungErfolgreich(p.gueltig)
          : t.einstBackupPruefungFehler(p.gueltig, p.fehlend, p.beschaedigt);
    }
    return '${p.erledigt} / ${p.gesamt}'
        '${p.datei != null ? ' — ${p.datei}' : ''}';
  }

  Future<void> _openInFinder(String path) async {
    final opened = await revealInFileManager(path);
    if (!opened && mounted) {
      melde.warnung(AppTexte.of(context).einstOrdnerNichtGeoeffnet(path));
    }
  }

  /// Rechnet die Prüfsummen aller installierten Modelle nach.
  ///
  /// Warum das nicht beim Programmstart läuft: Der Durchgang kostet
  /// gemessen rund 2,6 Sekunden (CLIP allein 1,12 s für 606 MB). Das ist
  /// wenig genug für einen Knopf und zu viel für jeden Start.
  Future<void> _pruefeModelle() async {
    var laeuft = '';
    void Function(void Function())? blattSetState;

    // Wie beim Herunterladen bewusst ohne `await`: Das Future des Sheets
    // löst erst beim Schliessen auf, die Prüfung darunter liefe sonst nie.
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => StatefulBuilder(builder: (context, setBlattState) {
        blattSetState = setBlattState;
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(AppTexte.of(context).einstModellePruefenTitel,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(AppTexte.of(context).einstModellePruefenLaeuft(laeuft),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        );
      }),
    );

    List<Modellbefund> befunde = const [];
    try {
      befunde =
          await widget.library.modelDownloadService.pruefeAlleInstallierten(
        ModelCatalog.all,
        fortschritt: (datei) {
          laeuft = datei;
          blattSetState?.call(() {});
        },
      );
    } finally {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
    if (!mounted) return;

    final auffaellig = befunde.where((b) => !b.inOrdnung).toList();
    if (befunde.isEmpty) {
      melde.hinweis(AppTexte.of(context).einstModellePruefenNichtsDa);
      return;
    }
    if (auffaellig.isEmpty) {
      melde.erfolg(
          AppTexte.of(context).einstModellePruefenAlleGut(befunde.length));
      return;
    }
    // Ein Fund gehört nicht in eine Meldung, die nach acht Sekunden
    // verblasst: Er verlangt eine Handlung, und die Dateinamen muss man
    // lesen können.
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppTexte.of(context).einstModellePruefenBefundTitel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppTexte.of(context).einstModellePruefenBefundText),
            const SizedBox(height: AppSpacing.md),
            for (final b in auffaellig)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                    '${b.dateiname} – ${_zustandstext(context, b.zustand)}',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppTexte.of(context).allgSchliessen)),
        ],
      ),
    );
  }

  String _zustandstext(BuildContext context, Modellzustand zustand) =>
      switch (zustand) {
        Modellzustand.fehlt => AppTexte.of(context).einstModellZustandFehlt,
        Modellzustand.zuKurz => AppTexte.of(context).einstModellZustandZuKurz,
        Modellzustand.weichtAb =>
          AppTexte.of(context).einstModellZustandWeichtAb,
        // Kommt hier nicht an – `auffaellig` filtert ihn weg. Ein
        // `default` würde einen neuen Zustand stillschweigend schlucken.
        Modellzustand.stimmt => '',
      };

  Future<void> _downloadModel(ModelCatalogEntry entry) async {
    setState(() => _downloading.add(entry.id));
    double progress = 0;
    void Function(void Function())? sheetSetState;

    // WICHTIG: hier bewusst NICHT auf showModalBottomSheet warten – das
    // Future davon löst erst auf, wenn das Sheet geschlossen wird (also
    // erst im finally unten). Würden wir hier awaiten, würde der Code
    // darunter (der eigentliche Download) nie ausgeführt werden.
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => StatefulBuilder(builder: (context, setSheetState) {
        sheetSetState = setSheetState;
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  AppTexte.of(context).einstModellLaedt(
                      modellTitel(AppTexte.of(context), entry.id)),
                  style: Theme.of(context).textTheme.titleMedium),
              // Bei einer Reihe steht sonst zwoelfmal dasselbe Fenster da
              // und man weiss nicht, wie weit es noch ist.
              if (_reihenstand != null) ...[
                const SizedBox(height: 4),
                Text(
                  AppTexte.of(context).einstAlleModelleLaeuft(
                      _reihenstand!.$1, _reihenstand!.$2),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress > 0 ? progress : null),
              const SizedBox(height: 8),
              Text('${(progress * 100).toStringAsFixed(0)} %'),
            ],
          ),
        );
      }),
    );

    try {
      await for (final p
          in widget.library.modelDownloadService.download(entry)) {
        progress = p.fraction;
        sheetSetState?.call(() {});
      }
      await widget.library.reloadModels();
    } catch (e) {
      if (mounted) {
        melde.fehler(_fehlertext(context, e));
      }
    } finally {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      setState(() => _downloading.remove(entry.id));
    }
  }

  /// Holt alle noch fehlenden Modelle nacheinander.
  ///
  /// Nacheinander und nicht gleichzeitig: Es sind zusammen ueber ein
  /// Gigabyte, und zwoelf offene Verbindungen machen keine davon
  /// schneller - sie machen nur den Fortschritt unlesbar. Bricht eines
  /// ab, laufen die uebrigen weiter; [_downloadModel] meldet den Fehler
  /// selbst und der naechste Anlauf holt genau das eine nach.
  Future<void> _alleModelleLaden(List<ModelCatalogEntry> fehlende) async {
    for (var i = 0; i < fehlende.length; i++) {
      if (!mounted) return;
      setState(() => _reihenstand = (i + 1, fehlende.length));
      await _downloadModel(fehlende[i]);
    }
    if (mounted) setState(() => _reihenstand = null);
  }

  Future<void> _deleteModel(ModelCatalogEntry entry) async {
    await widget.library.modelDownloadService.deleteEntry(entry);
    await widget.library.reloadModels();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _downloadGeoData() async {
    setState(() {
      _downloadingGeoData = true;
      _geoDataProgress = 0;
    });
    void Function(void Function())? sheetSetState;

    // Wie bei _downloadModel bewusst nicht auf das Sheet-Future warten – das
    // löst erst nach dem Schließen im finally unten auf.
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => StatefulBuilder(builder: (context, setSheetState) {
        sheetSetState = setSheetState;
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(AppTexte.of(context).einstGeoLaedt,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                  value: _geoDataProgress > 0 ? _geoDataProgress : null),
              const SizedBox(height: 8),
              Text('${(_geoDataProgress * 100).toStringAsFixed(0)} %'),
            ],
          ),
        );
      }),
    );

    try {
      await for (final p in widget.library.geoDataDownloadService.download()) {
        _geoDataProgress = p.fraction;
        sheetSetState?.call(() {});
      }
      await widget.library.reloadGeoData();
    } catch (e) {
      if (mounted) {
        melde.fehler(_fehlertext(context, e));
      }
    } finally {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      setState(() => _downloadingGeoData = false);
    }
  }

  Future<void> _deleteGeoData() async {
    await widget.library.geoDataDownloadService.deleteAll();
    await widget.library.reloadGeoData();
    if (!mounted) return;
    setState(() {});
  }

  /// Wechselt die geöffnete Bibliothek. Verschiebt NICHTS – siehe
  /// [LibraryLocation.wechsleZu]. Danach ist ein Neustart nötig, weil
  /// Datenbankverbindung, StoragePaths und sämtliche Zwischenspeicher am
  /// alten Ort hängen.
  /// Fragt beim öffentlichen Veröffentlichungsverzeichnis nach einer
  /// neueren Fassung – nur auf diesen Knopfdruck hin, nie von selbst
  /// (siehe Aktualisierungspruefung).
  Future<void> _sucheAktualisierung(String installiert) async {
    setState(() {
      _pruefeAktualisierung = true;
      _aktualisierungsfehler = null;
      _aktualisierungsstand = null;
    });
    try {
      final stand = await Aktualisierungspruefung().pruefe(installiert);
      if (mounted) setState(() => _aktualisierungsstand = stand);
    } catch (e) {
      if (mounted) {
        // Den tatsächlichen Grund nennen statt auf die Internetverbindung
        // zu raten: Beim ersten Fehlerbericht bestand die Verbindung
        // durchaus, die Abfrage war schlicht falsch gestellt.
        setState(() => _aktualisierungsfehler = AppTexte.of(context)
            .einstAktualisierungFehler(e is DioException
                ? (e.message ?? e.type.name)
                : _fehlertext(context, e)));
      }
    } finally {
      if (mounted) setState(() => _pruefeAktualisierung = false);
    }
  }

  Future<void> _waehleUeberwachtenOrdner() async {
    final picked = await LibraryLocation.pickFolder(
      dialogMessage: AppTexte.of(context).einstUeberwachtAuswahl,
    );
    if (picked == null || !mounted) return;
    await widget.library.db
        .setzeUeberwachtenOrdner(pfad: picked.path, token: picked.token);
    if (!mounted) return;
    setState(() =>
        _ueberwachterOrdnerFuture = widget.library.db.ueberwachterOrdner());
    final neue = await widget.library.pruefeUeberwachtenOrdner();
    if (!mounted) return;
    melde.hinweis(neue > 0
        ? AppTexte.of(context).einstUeberwachtUebernommen(neue)
        : AppTexte.of(context).einstUeberwachtNichtsNeues);
  }

  Future<void> _beendeUeberwachung() async {
    await widget.library.db.setzeUeberwachtenOrdner(pfad: null, token: null);
    if (!mounted) return;
    setState(() =>
        _ueberwachterOrdnerFuture = widget.library.db.ueberwachterOrdner());
  }

  Future<void> _wechsleBibliothek(BibliothekMitZustand ziel) async {
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title:
            Text(AppTexte.of(context).einstBibWechselnTitel(ziel.eintrag.name)),
        content: Text(
          AppTexte.of(context).einstBibWechselnText,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppTexte.of(context).allgAbbrechen)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppTexte.of(context).einstBibWechselnAktion)),
        ],
      ),
    );
    if (bestaetigt != true || !mounted) return;

    await _runRelocation(
      loadingText: AppTexte.of(context).einstBibWechselnLaeuft,
      restartMessage: AppTexte.of(context).einstBibGewechselt,
      errorPrefix: AppTexte.of(context).einstWechselnFehlgeschlagen,
      action: () async {
        // Reihenfolge mit Bedacht: ERST den Zeiger schreiben, DANN die
        // Datenbank schliessen. Andersherum liefe die App bei einem Fehler
        // im Schreibvorgang mit geschlossener Datenbank weiter und wäre
        // unbrauchbar, obwohl gar nichts passiert ist. Das Schliessen ist
        // hier ohnehin nur Höflichkeit vor dem Beenden (WAL sauber
        // abschliessen) – der Wechsel selbst rührt die Bibliothek nicht an.
        await LibraryLocation.wechsleZu(ziel.eintrag);
        await widget.library.db.close();
      },
    );
  }

  /// Nimmt einen Ordner in die Liste auf, ohne ihn zu öffnen.
  Future<void> _bibliothekHinzufuegen() async {
    final picked = await LibraryLocation.pickFolder(
      dialogMessage: AppTexte.of(context).einstBibHinzufuegenAuswahl,
    );
    if (picked == null || !mounted) return;

    final vorhanden = File(p.join(picked.path, 'library.sqlite')).existsSync();
    await LibraryLocation.fuegeHinzu(picked);
    if (!mounted) return;
    setState(() => _bibliothekenFuture = LibraryLocation.bekannte());
    melde.erfolg(vorhanden
        ? AppTexte.of(context).einstBibBestehendHinzugefuegt
        : AppTexte.of(context).einstBibLeerHinzugefuegt);
  }

  /// Streicht einen Eintrag aus der Liste. Die Fotos bleiben, wo sie sind.
  Future<void> _entferneBibliothek(BibliothekMitZustand b) async {
    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title:
            Text(AppTexte.of(context).einstBibEntfernenTitel(b.eintrag.name)),
        content: Text(
          AppTexte.of(context).einstBibEntfernenText,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppTexte.of(context).allgAbbrechen)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppTexte.of(context).allgEntfernen)),
        ],
      ),
    );
    if (bestaetigt != true) return;
    final entfernt = await LibraryLocation.entferneAusListe(b.eintrag.path);
    if (!mounted) return;
    setState(() => _bibliothekenFuture = LibraryLocation.bekannte());
    if (!entfernt) {
      melde.warnung(AppTexte.of(context).einstBibNichtEntfernbar);
    }
  }

  Future<void> _changeLibraryLocation() async {
    final picked = await LibraryLocation.pickFolder(
      // "Neuer Ordner" im nativen Dialog funktioniert bei ad-hoc-signierten
      // Entwickler-Builds auf macOS 26 nicht (bekannte, von Apple auf
      // XPC-Ebene eingeführte Einschränkung für Apps ohne Entwickler-
      // Zertifikat) – für PhotoVault reicht aber jeder bereits vorhandene
      // Ordner, ein neuer muss also nicht extra im Dialog angelegt werden.
      dialogMessage: AppTexte.of(context).einstSpeicherortWaehlen,
    );
    if (picked == null || !mounted) return;

    final fortschritt = ValueNotifier<BibliotheksVerschiebefortschritt?>(null);
    try {
      await _runRelocation(
        loadingText: AppTexte.of(context).einstSpeicherortVerschiebenLaeuft,
        progress: fortschritt,
        action: () => LibraryLocation.applyRoot(
          picked,
          beforeMove: () => widget.library.db.close(),
          onProgress: (wert) => fortschritt.value = wert,
        ),
      );
    } finally {
      fortschritt.dispose();
    }
  }

  Future<void> _resetLibraryLocation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppTexte.of(context).einstSpeicherortZuruecksetzenTitel),
        content: Text(
          AppTexte.of(context).einstSpeicherortZuruecksetzenText,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppTexte.of(context).allgAbbrechen)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppTexte.of(context).einstZuruecksetzen)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final fortschritt = ValueNotifier<BibliotheksVerschiebefortschritt?>(null);
    try {
      await _runRelocation(
        loadingText: AppTexte.of(context).einstSpeicherortZuruecksetzenLaeuft,
        progress: fortschritt,
        action: () => widget.library.resetLibraryLocation(
          onProgress: (wert) => fortschritt.value = wert,
        ),
      );
    } finally {
      fortschritt.dispose();
    }
  }

  /// Gemeinsamer Ablauf für Verlegen/Zurücksetzen/Reset: Ladeanzeige → Aktion
  /// ausführen (schließt dabei die DB-Verbindung) → bei Erfolg zum Neustart
  /// auffordern und die App schließen, bei Fehler die bisherigen Daten
  /// unangetastet lassen (siehe [LibraryLocation]) und den Fehler anzeigen.
  Future<void> _runRelocation({
    required String loadingText,
    required Future<void> Function() action,
    ValueListenable<BibliotheksVerschiebefortschritt?>? progress,
    // Kein Vorgabewert im Kopf: Ein übersetzter Text braucht den Kontext,
    // den es dort noch nicht gibt. null heisst „der übliche Text".
    String? restartMessage,
    String? errorPrefix,
  }) async {
    restartMessage ??= AppTexte.of(context).einstSpeicherortGeaendert;
    errorPrefix ??= AppTexte.of(context).einstVerschiebenFehlgeschlagen;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
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

    try {
      await action();
      if (!mounted) return;
      Navigator.of(context).pop(); // Ladeanzeige schließen
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(AppTexte.of(context).einstNeustartTitel),
          content: Text(restartMessage!),
          actions: [
            FilledButton(
                onPressed: () => exit(0),
                child: Text(AppTexte.of(context).allgSchliessen)),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Ladeanzeige schließen
        melde.fehler('$errorPrefix: $e');
      }
    }
  }

  /// Fragt per Wort-Bestätigung nach (siehe [showTypedConfirmDialog], reicht
  /// ein normales Ja/Nein bei so einer unumkehrbaren Aktion nicht) und löscht
  /// danach über [LibraryState.eraseLibraryCompletely] wirklich ALLES – jede
  /// Original-/Vorschaudatei und die komplette Datenbank. Nutzt denselben
  /// Ladeanzeige-/Neustart-Ablauf wie das Verlegen des Speicherorts, da beide
  /// Fälle strukturell identisch sind: die laufende DB-Datei wird unter der
  /// offenen Verbindung weggenommen, ein Neustart ist deshalb zwingend.
  Future<void> _resetDatabase() async {
    final confirmed = await showTypedConfirmDialog(
      context,
      title: AppTexte.of(context).einstResetBestaetigenTitel,
      message: AppTexte.of(context).einstResetBestaetigenText,
      confirmationWord: AppTexte.of(context).einstResetWort,
      confirmLabel: AppTexte.of(context).einstResetEndgueltig,
    );
    if (!confirmed || !mounted) return;

    await _runRelocation(
      loadingText: AppTexte.of(context).einstResetLaeuft,
      action: () => widget.library.eraseLibraryCompletely(),
      restartMessage: AppTexte.of(context).einstResetFertig,
      errorPrefix: AppTexte.of(context).einstResetFehlgeschlagen,
    );
  }

  Future<void> _setupPin() async {
    final ok = await ensureVaultUnlocked(context, widget.library);
    if (ok && mounted) _reloadPinState();
  }

  Future<void> _openLockedFolder() async {
    final ok = await ensureVaultUnlocked(context, widget.library);
    if (!ok || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LockedFolderScreen(library: widget.library)));
  }

  Future<void> _changePin() async {
    final unlocked = await ensureVaultUnlocked(context, widget.library);
    if (!unlocked || !mounted) return;
    final newPin = await showSetPinDialog(context);
    if (newPin == null) return;
    await widget.library.changeVaultPin(newPin);
  }

  Future<void> _removePin() async {
    final unlocked = await ensureVaultUnlocked(context, widget.library);
    if (!unlocked || !mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppTexte.of(context).einstGesperrtAufloesenTitel),
        content: Text(
          AppTexte.of(context).einstGesperrtAufloesenText,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppTexte.of(context).allgAbbrechen)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppTexte.of(context).allgEntfernen)),
        ],
      ),
    );
    if (confirm == true) {
      await widget.library.removeVaultPin();
      if (mounted) _reloadPinState();
    }
  }

  Future<void> _lockVaultSession() async {
    await widget.library.sperreTresor();
    if (mounted) setState(() {});
  }

  Future<void> _runBackup() async {
    if (_encryptManualBackup) {
      final ok = await ensureBackupKeyAvailable(context, widget.library);
      if (!ok || !mounted) return;
    }
    final destination = await FilePicker.platform.getDirectoryPath(
      dialogTitle: AppTexte.of(context).einstBackupZielWaehlen,
    );
    if (destination == null || !mounted) return;
    final t = AppTexte.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ProgressDialog(
        title: AppTexte.of(context).einstBackupSichertLaeuft,
        stream: widget.library
            .runManualBackup(destination, encrypt: _encryptManualBackup)
            .map((p) => _backupZeile(t, p)),
      ),
    );
    _refresh();
  }

  Future<void> _runRestore() async {
    final source = await FilePicker.platform.getDirectoryPath(
      dialogTitle: AppTexte.of(context).einstBackupOrdnerWaehlen,
    );
    if (source == null || !mounted) return;

    final wurzel = await BackupPruefdienst.findeBackupWurzel(source);
    String? passphrase;
    if (await File(p.join(wurzel, 'vault.key')).exists()) {
      if (!mounted) return;
      passphrase = await showEnterPassphraseDialog(context,
          title: AppTexte.of(context).einstBackupPassphraseEingeben);
      if (passphrase == null) return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // Die Texte einmal hier holen und nicht im Rückruf des Stroms: Der
        // läuft später, und der Prüfer nimmt den Kontext dann zu Recht
        // nicht mehr an.
        final t = AppTexte.of(dialogContext);
        return ProgressDialog(
          title: t.einstBackupWiederherstellenLaeuft,
          fehlerText: (e) => _fehlertext(dialogContext, e),
          stream: widget.library.backupService
              .restoreFromBackup(wurzel, widget.library.importService,
                  passphrase: passphrase)
              .map((p) => _wiederherstellZeile(t, p)),
        );
      },
    );
    _refresh();
  }

  Future<void> _pruefeBackup() async {
    final source = await FilePicker.platform.getDirectoryPath(
      dialogTitle: AppTexte.of(context).einstBackupOrdnerWaehlen,
    );
    if (source == null || !mounted) return;
    final wurzel = await BackupPruefdienst.findeBackupWurzel(source);
    String? passphrase;
    if (await File(p.join(wurzel, 'vault.key')).exists()) {
      if (!mounted) return;
      passphrase = await showEnterPassphraseDialog(context,
          title: AppTexte.of(context).einstBackupPassphraseEingeben);
      if (passphrase == null) return;
    }
    if (!mounted) return;
    final t = AppTexte.of(context);
    BackupPrueffortschritt? letzter;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => ProgressDialog(
        title: t.einstBackupPruefungLaeuft,
        fehlerText: (e) => _fehlertext(dialog, e),
        stream: BackupPruefdienst()
            .pruefe(wurzel, passphrase: passphrase)
            .map((fortschritt) {
          letzter = fortschritt;
          return _backupPruefZeile(t, fortschritt);
        }),
      ),
    );
    if (!mounted || letzter == null) return;
    if (letzter!.erfolgreich) {
      melde.erfolg(t.einstBackupPruefungErfolgreich(letzter!.gueltig));
    } else {
      melde.warnung(t.einstBackupPruefungFehler(
          letzter!.gueltig, letzter!.fehlend, letzter!.beschaedigt));
    }
  }

  Future<void> _setupBackupPassphrase() async {
    final ok = await ensureBackupKeyAvailable(context, widget.library);
    if (ok && mounted) _reloadBackupKeyState();
  }

  Future<void> _changeBackupPassphrase() async {
    final unlocked = await ensureBackupKeyAvailable(context, widget.library);
    if (!unlocked || !mounted) return;
    final newPass = await showSetPassphraseDialog(context);
    if (newPass == null) return;
    await widget.library.changeBackupPassphrase(newPass);
  }

  Future<void> _removeBackupEncryption() async {
    final unlocked = await ensureBackupKeyAvailable(context, widget.library);
    if (!unlocked || !mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppTexte.of(context).einstBackupEntschluesselnTitel),
        content: Text(
          AppTexte.of(context).einstBackupEntschluesselnText,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppTexte.of(context).allgAbbrechen)),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppTexte.of(context).allgEntfernen)),
        ],
      ),
    );
    if (confirm == true) {
      await widget.library.removeBackupEncryption();
      if (mounted) _reloadBackupKeyState();
    }
  }

  Future<void> _runAutoBackupNow() async {
    final ok = await ensureBackupKeyAvailable(context, widget.library);
    if (!ok || !mounted) return;
    final config = await widget.library.db.backupSettingsRow();
    final destination = config?.autoBackupDestination;
    if (destination == null || !mounted) return;
    // Vorher auflösen: Der Mapper unten läuft bei jedem Fortschritts-Ereignis,
    // also lange nach dem Aufbau des Dialogs. Einen BuildContext so lange
    // festzuhalten ist genau das, wovor `use_build_context_synchronously`
    // warnt – der Text selbst ändert sich in dieser Zeit ohnehin nicht.
    final keineNeuen = AppTexte.of(context).einstBackupKeineNeuen;
    final t = AppTexte.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ProgressDialog(
        title: AppTexte.of(context).einstBackupLaeuft,
        stream: widget.library
            .runAutoBackupNow(destination)
            .map((p) => p.total == 0 ? keineNeuen : _backupZeile(t, p)),
      ),
    );
    if (mounted) _reloadBackupSettings();
  }

  /// Alle Gruppen in ihrer Reihenfolge. Die Beschreibung ist nicht nur
  /// Zierde: Sie ist das, wonach die Suche oben sucht, und der einzige
  /// Hinweis darauf, was in einer zugeklappten Gruppe steckt.
  List<_Gruppe> _gruppen(AppTexte t) => [
        _Gruppe(
          icon: Icons.contrast_outlined,
          titel: t.einstAbschnittErscheinungsbild,
          beschreibung: t.einstBeschrErscheinungsbild,
          inhalt: _gruppeErscheinungsbild,
        ),
        _Gruppe(
          icon: Icons.translate_outlined,
          titel: t.spracheTitel,
          beschreibung: t.einstBeschrSprache,
          inhalt: _gruppeSprache,
        ),
        _Gruppe(
          icon: Icons.folder_special_outlined,
          titel: t.einstUeberwachtTitel,
          beschreibung: t.einstBeschrUeberwacht,
          inhalt: _gruppeUeberwacht,
        ),
        _Gruppe(
          icon: Icons.photo_library_outlined,
          titel: t.einstBibListe,
          beschreibung: t.einstBeschrBibliotheken,
          inhalt: _gruppeBibliotheken,
        ),
        _Gruppe(
          icon: Icons.sd_storage_outlined,
          titel: t.einstSpeicherortTitel,
          beschreibung: t.einstBeschrSpeicherort,
          inhalt: _gruppeSpeicherort,
        ),
        _Gruppe(
          icon: Icons.memory_outlined,
          titel: t.einstAbschnittModelle,
          beschreibung: t.einstBeschrModelle,
          inhalt: _gruppeModelle,
        ),
        _Gruppe(
          icon: Icons.autorenew_outlined,
          titel: t.einstAbschnittHintergrund,
          beschreibung: t.einstBeschrHintergrund,
          inhalt: _gruppeHintergrund,
        ),
        _Gruppe(
          icon: Icons.sell_outlined,
          titel: t.einstAbschnittVokabular,
          beschreibung: t.einstBeschrVokabular,
          inhalt: _gruppeVokabular,
        ),
        _Gruppe(
          icon: Icons.public_outlined,
          titel: t.einstAbschnittStandortdaten,
          beschreibung: t.einstBeschrStandortdaten,
          inhalt: _gruppeStandortdaten,
        ),
        _Gruppe(
          icon: Icons.map_outlined,
          titel: t.einstAbschnittKarte,
          beschreibung: t.einstBeschrKarte,
          inhalt: _gruppeKarte,
        ),
        _Gruppe(
          icon: Icons.lock_outline,
          titel: t.einstAbschnittGesperrterOrdner,
          beschreibung: t.einstBeschrGesperrt,
          inhalt: _gruppeGesperrt,
        ),
        _Gruppe(
          icon: Icons.key_outlined,
          titel: t.einstBackupVerschluesselungTitel,
          beschreibung: t.einstBeschrBackupSchluessel,
          inhalt: _gruppeBackupSchluessel,
        ),
        _Gruppe(
          icon: Icons.cloud_upload_outlined,
          titel: t.einstAbschnittManuellesBackup,
          beschreibung: t.einstBeschrBackupManuell,
          inhalt: _gruppeBackupManuell,
        ),
        _Gruppe(
          icon: Icons.schedule_outlined,
          titel: t.einstAbschnittAutoBackup,
          beschreibung: t.einstBeschrBackupAuto,
          inhalt: _gruppeBackupAuto,
        ),
        _Gruppe(
          icon: Icons.delete_sweep_outlined,
          titel: t.einstAbschnittPapierkorb,
          beschreibung: t.einstBeschrPapierkorb,
          inhalt: _gruppePapierkorb,
        ),
        _Gruppe(
          icon: Icons.warning_amber_outlined,
          titel: t.einstAbschnittGefahrenzone,
          beschreibung: t.einstBeschrGefahr,
          inhalt: _gruppeGefahr,
        ),
        // Die Tafel gab es schon; erreichbar war sie nur über „?" – eine
        // Taste, die nirgends stand. Hier ist sie auffindbar, und die
        // Suche oben findet sie mit (Befund der 19. Prüfrunde).
        _Gruppe(
          icon: Icons.keyboard_outlined,
          titel: t.kuerzelTitel,
          beschreibung: t.einstBeschrKuerzel,
          inhalt: _gruppeKuerzel,
        ),
        _Gruppe(
          icon: Icons.info_outline,
          titel: t.einstUeberTitel,
          beschreibung: t.einstBeschrUeber,
          inhalt: _gruppeUeber,
        ),
      ];

  List<Widget> _gruppeKuerzel() => const [
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          child: Tastenkuerzeltafel(),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final suche = _suche.text.trim().toLowerCase();
    final alle = _gruppen(t);
    final sichtbar = suche.isEmpty
        ? alle
        : [
            for (final g in alle)
              if (g.titel.toLowerCase().contains(suche) ||
                  g.beschreibung.toLowerCase().contains(suche))
                g,
          ];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        SearchBar(
          controller: _suche,
          hintText: t.einstSuche,
          leading: const Icon(Icons.search),
          trailing: [
            if (suche.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: t.allgAbbrechen,
                onPressed: () => setState(_suche.clear),
              ),
          ],
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (sichtbar.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxxl),
            child: Text(t.einstNichtsGefunden, textAlign: TextAlign.center),
          ),
        for (final gruppe in sichtbar)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _GruppenKarte(
              // Der Schlüssel enthält, ob gesucht wird: Bei einem Treffer
              // soll die Gruppe offen erscheinen, und das entscheidet sich
              // beim Neuaufbau. Ohne diesen Teil im Schlüssel behielte sie
              // ihren vorherigen Zustand bei.
              key: ValueKey('${gruppe.titel}|${suche.isNotEmpty}'),
              gruppe: gruppe,
              anfangsOffen: suche.isNotEmpty,
            ),
          ),
      ],
    );
  }

  List<Widget> _gruppeErscheinungsbild() => [
        Card(
          child: StreamBuilder<AppSettingsData?>(
            stream: widget.library.db.watchAppSettings(),
            builder: (context, snapshot) {
              final mode = themeModeFromString(snapshot.data?.themeMode);
              return ListTile(
                leading: const Icon(Icons.contrast_outlined),
                title: Text(AppTexte.of(context).einstDesign),
                subtitle: SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(
                        value: ThemeMode.light,
                        label: Text(AppTexte.of(context).einstDesignHell),
                        icon: const Icon(Icons.light_mode_outlined)),
                    ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text(AppTexte.of(context).einstDesignDunkel),
                        icon: const Icon(Icons.dark_mode_outlined)),
                    ButtonSegment(
                        value: ThemeMode.system,
                        label: Text(AppTexte.of(context).einstDesignSystem),
                        icon: const Icon(Icons.brightness_auto_outlined)),
                  ],
                  selected: {mode},
                  onSelectionChanged: (selection) => widget.library.db
                      .setThemeMode(themeModeToString(selection.first)),
                ),
              );
            },
          ),
        ),
        // Die Schwebe-Vorschau steht beim Erscheinungsbild und nicht bei
        // den Videos: Sie aendert nicht, wie ein Video abgespielt wird,
        // sondern wie sich die Kachelwand anfuehlt.
        Card(
          child: StreamBuilder<AppSettingsData?>(
            stream: widget.library.db.watchAppSettings(),
            builder: (context, snapshot) {
              final t = AppTexte.of(context);
              return SwitchListTile(
                secondary: const Icon(Icons.slow_motion_video_outlined),
                title: Text(t.einstSchwebeVorschauTitel),
                subtitle: Text(t.einstSchwebeVorschauText),
                value: snapshot.data?.schwebeVorschau ?? true,
                onChanged: (an) => widget.library.db.setzeSchwebeVorschau(an),
              );
            },
          ),
        ),
      ];

  List<Widget> _gruppeSprache() => [
        Card(
          child: StreamBuilder<AppSettingsData?>(
            stream: widget.library.db.watchAppSettings(),
            builder: (context, snapshot) {
              final t = AppTexte.of(context);
              final aktuell = snapshot.data?.sprache ?? 'system';
              return ListTile(
                leading: const Icon(Icons.translate_outlined),
                title: Text(t.spracheTitel),
                isThreeLine: true,
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                            value: 'system', label: Text(t.spracheSystem)),
                        // Sprachnamen stehen bewusst in ihrer eigenen Sprache
                        // da – wer die Oberfläche nicht versteht, findet
                        // "English" trotzdem, "Englisch" womöglich nicht.
                        ButtonSegment(
                            value: 'de', label: Text(t.spracheDeutsch)),
                        ButtonSegment(
                            value: 'en', label: Text(t.spracheEnglisch)),
                      ],
                      selected: {aktuell},
                      showSelectedIcon: false,
                      onSelectionChanged: (auswahl) =>
                          _wechsleSprache(auswahl.first),
                    ),
                    const SizedBox(height: 6),
                    Text(t.spracheHinweis,
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ],
                ),
              );
            },
          ),
        ),
      ];

  List<Widget> _gruppeUeberwacht() => [
        Card(
          child: FutureBuilder<({String pfad, String? token})?>(
            future: _ueberwachterOrdnerFuture,
            builder: (context, snapshot) {
              final eintrag = snapshot.data;
              return Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.folder_special_outlined),
                    title: Text(eintrag == null
                        ? AppTexte.of(context).einstUeberwachtKeiner
                        : eintrag.pfad),
                    subtitle: Text(eintrag == null
                        ? AppTexte.of(context).einstUeberwachtErklaerung
                        : AppTexte.of(context).einstUeberwachtAktiv),
                    isThreeLine: eintrag == null,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _waehleUeberwachtenOrdner,
                            icon: const Icon(Icons.folder_open_outlined),
                            label: Text(eintrag == null
                                ? AppTexte.of(context).einstUeberwachtWaehlen
                                : AppTexte.of(context)
                                    .einstUeberwachtAndererWaehlen),
                          ),
                        ),
                        if (eintrag != null) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _beendeUeberwachung,
                              icon: const Icon(Icons.stop_circle_outlined),
                              label: Text(
                                  AppTexte.of(context).einstUeberwachtBeenden),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ];

  List<Widget> _gruppeBibliotheken() => [
        Card(
          child: FutureBuilder<List<BibliothekMitZustand>>(
            future: _bibliothekenFuture,
            builder: (context, snapshot) {
              final eintraege = snapshot.data;
              if (eintraege == null) {
                return const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child:
                      Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              return Column(
                children: [
                  for (final b in eintraege)
                    ListTile(
                      leading: Icon(
                        b.istAktiv
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: b.istAktiv
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(
                        b.eintrag.name,
                        style: b.erreichbar
                            ? null
                            : TextStyle(color: Theme.of(context).disabledColor),
                      ),
                      subtitle: Text(
                        b.erreichbar
                            ? b.eintrag.path
                            : AppTexte.of(context).einstBibNichtGefunden,
                      ),
                      // `enabled` steuert die Einfärbung, nicht die
                      // Antippbarkeit: Die aktive Bibliothek ist zwar nicht
                      // antippbar (man ist ja schon drin), darf aber nicht
                      // ausgegraut erscheinen – ausgegraut heißt hier
                      // "nicht erreichbar".
                      enabled: b.erreichbar,
                      onTap: b.erreichbar && !b.istAktiv
                          ? () => _wechsleBibliothek(b)
                          : null,
                      // Der Standardordner lässt sich nicht entfernen: Er
                      // wird erzeugt, nicht gespeichert, und es gibt ihn
                      // immer. Ihm einen Knopf zu geben, der nichts tut,
                      // war der Fehler der ersten Fassung.
                      trailing: b.istAktiv
                          ? Text(AppTexte.of(context).einstBibAktiv)
                          : b.entfernbar
                              ? IconButton(
                                  icon: const Icon(Icons.playlist_remove),
                                  tooltip: AppTexte.of(context)
                                      .einstBibAusListeEntfernen,
                                  onPressed: () => _entferneBibliothek(b),
                                )
                              : Text(
                                  AppTexte.of(context).einstBibImmerVorhanden,
                                  style: const TextStyle(fontSize: 12)),
                    ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _bibliothekHinzufuegen,
                            icon: const Icon(Icons.library_add_outlined),
                            label:
                                Text(AppTexte.of(context).einstBibHinzufuegen),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
                    child: Text(
                      AppTexte.of(context).einstBibWechselHinweis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ];

  List<Widget> _gruppeSpeicherort() => [
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(AppTexte.of(context).einstSpeicherort),
                subtitle: Text(widget.library.paths.root.path),
                trailing: IconButton(
                  icon: const Icon(Icons.open_in_new),
                  tooltip: AppTexte.of(context).einstImFinderAnzeigen,
                  onPressed: () =>
                      _openInFinder(widget.library.paths.root.path),
                ),
              ),
              const Divider(height: 1),
              FutureBuilder<bool>(
                future: _isCustomLocationFuture,
                builder: (context, snapshot) {
                  final isCustom = snapshot.data ?? false;
                  return Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _changeLibraryLocation,
                            icon: const Icon(Icons.drive_file_move_outline),
                            label: Text(AppTexte.of(context).einstAendern),
                          ),
                        ),
                        if (isCustom) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _resetLibraryLocation,
                              icon: const Icon(Icons.restart_alt),
                              label:
                                  Text(AppTexte.of(context).einstZuruecksetzen),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
              // **Aufgeschlüsselt und nicht als eine Zahl.** Hier stand
              // allein die Summe der Originale; im Finder war der Ordner
              // deutlich grösser, und niemand konnte sehen, warum. Die
              // Teile, die die App selbst anlegt – Vorschauen,
              // Miniaturen, Gesichtsausschnitte, die Datenbank – sind
              // gerade die, die man beurteilen will.
              if (_belegung == null)
                ListTile(
                  leading: const Icon(Icons.sd_storage_outlined),
                  title: Text(AppTexte.of(context).einstSpeicherbedarf),
                  subtitle: Text(AppTexte.of(context).einstWirdBerechnet),
                )
              else
                ExpansionTile(
                  leading: const Icon(Icons.sd_storage_outlined),
                  title: Text(AppTexte.of(context).einstSpeicherbedarf),
                  subtitle: Text(groessentext(_belegung!.gesamt)),
                  childrenPadding: const EdgeInsets.only(
                      left: AppSpacing.xxl,
                      right: AppSpacing.lg,
                      bottom: AppSpacing.sm),
                  children: [
                    for (final posten in _belegung!.posten)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                belegungName(AppTexte.of(context), posten.name),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            Text(
                              groessentext(posten.bytes),
                              // Ziffern in einer Spalte gehören
                              // untereinander.
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                      fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ];

  /// Die Modelle, die zur eingestellten Oberflächensprache passen –
  /// siehe [ModelCatalog.fuerSprache].
  List<ModelCatalogEntry> _modelle(BuildContext context) =>
      ModelCatalog.fuerSprache(Localizations.localeOf(context).languageCode,
          istInstalliert: widget.library.isModelInstalled);

  List<Widget> _gruppeModelle() => [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text(
            AppTexte.of(context).einstKiHinweis,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        FutureBuilder<bool>(
          key: const ValueKey('auto-analyse'),
          future: widget.library.db.autoAnalyzeAfterImportEnabled(),
          builder: (context, snapshot) {
            final an = snapshot.data ?? true;
            return Card(
              child: SwitchListTile(
                value: an,
                onChanged: (v) async {
                  await widget.library.db.setAutoAnalyzeAfterImport(v);
                  if (mounted) setState(() {});
                },
                secondary: const Icon(Icons.schedule_outlined),
                title: Text(AppTexte.of(context).einstAutoAnalyseTitel),
                isThreeLine: true,
                subtitle: Text(
                  AppTexte.of(context).einstAutoAnalyseText,
                ),
              ),
            );
          },
        ),
        // Beide Schalter übersetzen zwischen Englisch und Deutsch. Steht die
        // Oberfläche auf Englisch, sind sie gegenstandslos: Beschreibungen
        // und Vokabular liegen dann bereits in der Sprache vor, in der man
        // sucht. Ausgeblendet statt wirkungslos angeboten – die gespeicherte
        // Einstellung bleibt erhalten und ist beim Zurückwechseln wieder da.
        if (Localizations.localeOf(context).languageCode == 'de') ...[
          _uebersetzungsSchalter(
            icon: Icons.translate_outlined,
            titel: AppTexte.of(context).einstUebersetzeBeschreibungTitel,
            beschreibung: AppTexte.of(context).einstUebersetzeBeschreibungText,
            installiert: widget.library.uebersetzungEnDeHalter.installiert,
            lesen: widget.library.db.uebersetzeBeschreibungen,
            schreiben: widget.library.db.setzeUebersetzeBeschreibungen,
          ),
          _uebersetzungsSchalter(
            icon: Icons.search_outlined,
            titel: AppTexte.of(context).einstUebersetzeSucheTitel,
            beschreibung: AppTexte.of(context).einstUebersetzeSucheText,
            installiert: widget.library.uebersetzungDeEnHalter.installiert,
            lesen: widget.library.db.uebersetzeSucheUndTags,
            schreiben: (an) async {
              await widget.library.db.setzeUebersetzeSucheUndTags(an);
              // Die zwischengespeicherten Begriffs-Vektoren stammen sonst
              // noch aus der anderen Sprache und die Umstellung bliebe bis
              // zum nächsten Programmstart wirkungslos.
              widget.library.aiTaggingService.leereBegriffsCache();
            },
          ),
        ],
        const SizedBox(height: 12),
        // Zwoelf Modelle einzeln anzutippen und jedes Mal zu warten, war
        // der erste Weg, den ein neuer Nutzer vor sich hatte - einen Knopf
        // dafuer gab es nicht. Er laedt nur, was fehlt: Wer die
        // Uebersetzung nicht braucht, loescht sie danach einmal und
        // bekommt sie nicht wieder aufgedraengt.
        Builder(builder: (context) {
          final fehlende = [
            for (final e in _modelle(context))
              if (!widget.library.isModelInstalled(e)) e,
          ];
          return Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                icon: const Icon(Icons.cloud_download_outlined, size: 18),
                onPressed: (fehlende.isEmpty || _downloading.isNotEmpty)
                    ? null
                    : () => _alleModelleLaden(fehlende),
                label: Text(fehlende.isEmpty
                    ? AppTexte.of(context).einstAlleModelleDa
                    : AppTexte.of(context)
                        .einstAlleModelleLaden(fehlende.length)),
              ),
            ),
          );
        }),
        for (final entry in _modelle(context))
          _ModelCard(
            entry: entry,
            installed: widget.library.isModelInstalled(entry),
            downloading: _downloading.contains(entry.id),
            groesse: widget.library.isModelInstalled(entry)
                ? groessentext(
                    widget.library.modelDownloadService.belegteBytes(entry))
                : null,
            onDownload: () => _downloadModel(entry),
            onDelete: () => _deleteModel(entry),
          ),
        // Der Modellordner wächst schnell auf über ein Gigabyte, ohne dass
        // das bisher irgendwo stand.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            AppTexte.of(context).einstModelleBelegterPlatz(groessentext(
                widget.library.modelDownloadService.gesamteBytes())),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        // Die Prüfsumme im Katalog wirkte bis zur 21. Prüfrunde genau
        // einmal – beim Herunterladen. Danach entschied allein, ob die
        // Datei da ist. Hier ist der Weg, sie noch einmal zu befragen.
        Card(
          child: ListTile(
            leading: const Icon(Icons.verified_outlined),
            title: Text(AppTexte.of(context).einstModellePruefenTitel),
            subtitle: Text(AppTexte.of(context).einstModellePruefenText),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pruefeModelle,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.face_outlined),
            title: Text(AppTexte.of(context).einstGesichtserkennungAktiv),
            subtitle: Text(widget.library.faceDetectionAvailable
                ? (widget.library.faceRecognitionAvailable
                    ? AppTexte.of(context).einstGesichtserkennungBeides
                    : AppTexte.of(context).einstNurErkennung)
                : AppTexte.of(context).einstGesichtserkennungInaktiv),
          ),
        ),
      ];

  List<Widget> _gruppeHintergrund() => [
        Card(
          child: ListTile(
            leading: const Icon(Icons.pending_actions_outlined),
            title: Text(AppTexte.of(context).einstAufgabenTitel),
            subtitle: Text(AppTexte.of(context).einstAufgabenText),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) =>
                      BackgroundTasksScreen(library: widget.library)),
            ),
          ),
        ),
      ];

  List<Widget> _gruppeVokabular() => [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text(
            AppTexte.of(context).einstVokabularText,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StreamBuilder<List<AiTagVocabularyData>>(
                  stream: widget.library.db.watchAiTagVocabulary(),
                  builder: (context, snapshot) {
                    final terms = snapshot.data ?? [];
                    if (terms.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final entry in terms)
                            InputChip(
                              label: Text(entry.term),
                              onDeleted: () =>
                                  widget.library.db.removeAiTagTerm(entry.id),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _aiTagVocabularyController,
                        decoration: InputDecoration(
                          hintText:
                              AppTexte.of(context).einstBegriffHinzufuegenFeld,
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _addAiTagVocabularyTerm(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: AppTexte.of(context).einstBegriffHinzufuegen,
                      onPressed: _addAiTagVocabularyTerm,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Der Weg zurück. Er steht hier und nicht bei den Werkzeugen,
        // weil er zum Vokabular gehört: Wer die Begriffe ändert, will
        // meist auch die damit vergebenen Schlagwörter neu haben.
        FutureBuilder<int>(
          future: widget.library.db.kiTagAnzahl(),
          builder: (context, schnappschuss) {
            final anzahl = schnappschuss.data;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.auto_delete_outlined),
              title: Text(AppTexte.of(context).einstKiTagsZurueck),
              subtitle: Text(anzahl == null
                  ? AppTexte.of(context).einstKiTagsZurueckText
                  : AppTexte.of(context).einstKiTagsZurueckAnzahl(anzahl)),
              enabled: anzahl != null && anzahl > 0,
              onTap: anzahl == null || anzahl == 0
                  ? null
                  : () => _nimmKiTagsZurueck(anzahl),
            );
          },
        ),
      ];

  /// Nimmt alle von der Bilderkennung vergebenen Schlagwörter zurück.
  ///
  /// Mit Rückfrage und mit **Zahl** darin: „94.040 Schlagwörter werden
  /// entfernt" wiegt anders als „alle KI-Schlagwörter entfernen".
  /// Läuft gerade ein Vorladen? Dann steht hier der Stand.
  Vorratsstand? _vorrat;
  StreamSubscription<Vorratsstand>? _vorratLauf;

  /// Lädt die Kartengebiete der eigenen Fotos auf die Platte.
  ///
  /// **Warum das der bessere Weg ist als ein zweiter Kartenanbieter.**
  /// Ein anderer Server löst das Problem nicht, er verschiebt es: Auch
  /// er kann klemmen, und graue Löcher entstehen genau dann, wenn eine
  /// Kachel im Augenblick des Hinsehens nicht da ist. Wer seine Gebiete
  /// einmal vorlädt, ist davon frei – und schont die gespendeten
  /// Kachelserver, weil dieselbe Kachel nicht bei jedem Ansehen erneut
  /// über die Leitung geht.
  /// Ob die Karte in doppelter Auflösung zeichnet. Beim Aufbau der
  /// Kartengruppe aus der Einstellung geholt (siehe [_ladeKarteScharf]).
  bool _karteScharf = true;
  bool _karteScharfGeladen = false;

  Future<void> _ladeKarteScharf() async {
    if (_karteScharfGeladen) return;
    _karteScharfGeladen = true;
    final an = await widget.library.db.karteHochaufloesendWert();
    if (!mounted) return;
    setState(() => _karteScharf = an);
  }

  Future<void> _karteScharfSetzen(bool an) async {
    setState(() => _karteScharf = an);
    await widget.library.db.setzeKarteHochaufloesend(an);
    // Sofort und nicht erst beim nächsten Start – dieselbe Handhabung wie
    // beim CARTO-Schlüssel und bei der eigenen Quelle.
    setzeKarteHochaufloesend(an);
  }

  Future<void> _kartenVorladen() async {
    final t = AppTexte.of(context);
    final verortete = await widget.library.db.assetsWithLocation();
    if (!mounted) return;
    final gebiete = gebieteAus([
      for (final a in verortete) (breite: a.latitude!, laenge: a.longitude!)
    ]);
    if (gebiete.isEmpty) {
      melde.warnung(t.einstVorladenKeineOrte);
      return;
    }
    // Erst der Stil, dann die Zahl: Wie viele Kacheln zu laden sind,
    // haengt daran, ob die Karte die doppelte Aufloesung nachbildet -
    // dann liegt jede Anzeigestufe eine Serverstufe hoeher, und die
    // hoechste Stufe hat viermal so viele Kacheln. Vorher stand die Zahl
    // im Dialog, bevor der Stil ueberhaupt feststand.
    //
    // Der gerade gewaehlte Stil, nicht ein fest verdrahteter: Der
    // Speicher haengt an der Adresse, und eine fuer Topo geladene Kachel
    // hilft der hellen Karte nicht.
    final stil = switch (
        Kartenansicht.ausText(await widget.library.db.kartenansicht())) {
      Kartenansicht.hell => Kartenstil.hell,
      Kartenansicht.topo => Kartenstil.topo,
      // Ohne diese Zeile lüde der Vorrat für die eigene Quelle
      // stillschweigend die dunkle Karte vor – und offline bliebe genau
      // die Karte leer, für die jemand vorgeladen hat.
      Kartenansicht.eigene => Kartenstil.eigene,
      _ => Kartenstil.dunkel,
    };
    if (!mounted) return;
    final stufen = vorratStufen(stil, MediaQuery.devicePixelRatioOf(context));
    final kacheln = kachelListe(gebiete, von: stufen.von, bis: stufen.bis);
    final ja = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(t.einstVorladenTitel),
        // Zahl UND geschätzte Grösse: „29.039 Kacheln" sagt niemandem
        // etwas, „rund 850 MB" schon.
        content: Text(t.einstVorladenFrage(gebiete.length, kacheln.length,
            (kacheln.length * 30 / 1024).round())),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(t.allgAbbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(t.einstVorladenStarten),
          ),
        ],
      ),
    );
    if (ja != true || !mounted) return;

    await _vorratLauf?.cancel();
    _vorratLauf =
        ladeVorrat(gebiete, stil, von: stufen.von, bis: stufen.bis).listen(
      (stand) {
        if (mounted) setState(() => _vorrat = stand);
      },
      onDone: () {
        final stand = _vorrat;
        if (mounted) setState(() => _vorrat = null);
        if (stand != null) {
          melde.erfolg(t.einstVorladenFertig(stand.geladen, stand.fehler));
        }
      },
    );
  }

  Future<void> _nimmKiTagsZurueck(int anzahl) async {
    final t = AppTexte.of(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(t.einstKiTagsZurueck),
        content: Text(t.einstKiTagsZurueckFrage(anzahl)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(t.allgAbbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(t.einstKiTagsZurueckJetzt),
          ),
        ],
      ),
    );
    if (ja != true) return;
    final entfernt = await widget.library.db.nimmKiTagsZurueck();
    if (!mounted) return;
    setState(() {});
    melde.erfolg(t.einstKiTagsZurueckFertig(entfernt));
  }

  List<Widget> _gruppeKarte() {
    // Beim Öffnen der Gruppe, nicht beim Aufbau des Bildschirms: Die
    // Gruppeninhalte werden erst gebaut, wenn jemand sie aufklappt
    // (siehe [_Gruppe.inhalt]). [_ladeCartoSchluessel] schützt sich
    // selbst gegen den zweiten Aufruf.
    unawaited(_ladeCartoSchluessel());
    unawaited(_ladeKarteScharf());
    final t = AppTexte.of(context);
    final aktiv = _cartoSchluessel.text.trim().isNotEmpty;
    return [
      // Der einzige Weg, auf dem die App ohne Knopfdruck mit einem
      // fremden Server spricht – und in jeder Kacheladresse steht, welchen
      // Ausschnitt jemand ansieht. Bis zur 17. Prüfrunde stand das
      // nirgends; der Text zum Ortsverzeichnis daneben betonte sogar
      // „komplett lokal", was für die Geokodierung stimmt und deshalb
      // umso leichter falsch gelesen wird.
      Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.public_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                t.einstKartenNetzHinweis,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(
          t.einstCartoText,
          style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    aktiv ? Icons.check_circle : Icons.dark_mode_outlined,
                    color: aktiv ? context.semantik.erfolg : null,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      aktiv ? t.einstCartoAktiv : t.einstCartoOhne,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cartoSchluessel,
                      decoration: InputDecoration(
                        labelText: t.einstCartoFeld,
                        hintText: t.einstCartoFeldHinweis,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _speichereCartoSchluessel(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    onPressed: _speichereCartoSchluessel,
                    child: Text(t.allgSpeichern),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                t.einstCartoQuelle,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
      const Divider(height: AppSpacing.xl),
      // Die eigene Quelle steht zwischen CARTO und dem Vorrat, weil sie
      // zu beidem gehört: Sie ist die zweite Stelle, an der ein fremder
      // Schlüssel ins Spiel kommt, und sie ist das, was der Vorrat
      // danach vorlädt.
      // Erst die Auskunft, dann das Eingabefeld: Wer eine eigene Quelle
      // eintraegt, will vorher wissen, was es ueberhaupt gibt und wie
      // tief es traegt.
      // Die doppelte Auflösung steht VOR den Quellen: Sie gilt für alle
      // und ist die eine Stellschraube, die sich am Bildschirm sofort
      // bemerkbar macht.
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.hd_outlined),
        title: Text(t.einstKarteScharfTitel),
        subtitle: Text(t.einstKarteScharfText),
        value: _karteScharf,
        onChanged: _karteScharfSetzen,
      ),
      const Divider(height: AppSpacing.xl),
      Text(t.einstKartenquellenTitel,
          style: Theme.of(context).textTheme.titleSmall),
      KartenquellenUebersicht(
        library: widget.library,
        // Eine Vorlage mit Schlüssel kann die Übersicht nicht selbst
        // einschalten – sie reicht sie ins Formular durch und scrollt
        // dorthin, damit der Sprung nicht ins Leere geht.
        aufVorlage: (v) {
          _eigeneKarte.currentState?.vorlageEinsetzen(v);
          final ziel = _eigeneKarte.currentContext;
          if (ziel != null) {
            unawaited(Scrollable.ensureVisible(ziel,
                duration: const Duration(milliseconds: 250), alignment: 0.1));
          }
        },
      ),
      const Divider(height: AppSpacing.xl),
      Text(t.einstEigeneKarteTitel,
          style: Theme.of(context).textTheme.titleSmall),
      EigeneKarteEinstellung(key: _eigeneKarte, library: widget.library),
      const Divider(height: AppSpacing.xl),
      // Der Vorrat. Er steht bei der Karte und nicht bei den Werkzeugen,
      // weil er zum Kartenbild gehört: Wer graue Löcher loswerden will,
      // sucht hier.
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.download_for_offline_outlined),
        title: Text(t.einstVorladenTitel),
        subtitle: Text(_vorrat == null
            ? t.einstVorladenText
            : t.einstVorladenStand(_vorrat!.fertig, _vorrat!.gesamt)),
        trailing: _vorrat == null
            ? const Icon(Icons.chevron_right)
            : SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: _vorrat!.gesamt == 0
                      ? null
                      : _vorrat!.fertig / _vorrat!.gesamt,
                ),
              ),
        onTap: _vorrat == null ? _kartenVorladen : null,
      ),
      // Der Mitschnitt steht bewusst hier und nicht bei den Werkzeugen:
      // Wer graue Kacheln sieht, sucht bei der Karte – und findet dann
      // beides nebeneinander, das Vorladen als Abhilfe und den
      // Mitschnitt als Frage nach dem Warum.
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.troubleshoot_outlined),
        title: Text(t.einstMitschnittTitel),
        subtitle: Text(t.einstMitschnittText),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const KachelmitschnittScreen()),
        ),
      ),
    ];
  }

  List<Widget> _gruppeStandortdaten() => [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text(
            AppTexte.of(context).einstOrteText,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(
              widget.library.geoDataAvailable
                  ? Icons.check_circle
                  : Icons.cloud_download_outlined,
              color: widget.library.geoDataAvailable
                  ? context.semantik.erfolg
                  : null,
            ),
            title: Text(AppTexte.of(context).einstGeoTitel),
            subtitle: Text(
              AppTexte.of(context).einstGeoText(GeoDataCatalog.license),
            ),
            trailing: _downloadingGeoData
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : widget.library.geoDataAvailable
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: AppTexte.of(context).einstGeoLoeschen,
                        onPressed: _deleteGeoData,
                      )
                    : FilledButton(
                        onPressed: _downloadGeoData,
                        child: Text(AppTexte.of(context).allgHerunterladen)),
          ),
        ),
      ];

  List<Widget> _gruppeGesperrt() => [
        Card(
          child: FutureBuilder<bool>(
            future: _hasPinSetFuture,
            builder: (context, snapshot) {
              final hasPin = snapshot.data ?? false;
              if (!hasPin) {
                return ListTile(
                  leading: const Icon(Icons.enhanced_encryption_outlined),
                  title: Text(AppTexte.of(context).einstPinEinrichten),
                  subtitle: Text(
                    AppTexte.of(context).einstGesperrtText,
                  ),
                  isThreeLine: true,
                  trailing: FilledButton(
                      onPressed: _setupPin,
                      child: Text(AppTexte.of(context).allgEinrichten)),
                );
              }
              final unlocked = widget.library.vaultUnlockedThisSession;
              return Column(
                children: [
                  ListTile(
                    leading: Icon(unlocked
                        ? Icons.lock_open_outlined
                        : Icons.lock_outline),
                    title: Text(AppTexte.of(context).einstGesperrterOrdner),
                    subtitle: Text(unlocked
                        ? AppTexte.of(context).einstGesperrtEntsperrt
                        : AppTexte.of(context).einstPinEingerichtet),
                    trailing: FilledButton.icon(
                      onPressed: _openLockedFolder,
                      icon: const Icon(Icons.lock_open_outlined),
                      label: Text(AppTexte.of(context).einstGesperrtOeffnen),
                    ),
                  ),
                  const Divider(height: 1),
                  FutureBuilder<PrivacySettingsData?>(
                    future: widget.library.db.privacySettingsRow(),
                    builder: (context, privacy) => SwitchListTile(
                      secondary: const Icon(Icons.visibility_off_outlined),
                      title:
                          Text(AppTexte.of(context).einstPrivateMetadatenTitel),
                      subtitle:
                          Text(AppTexte.of(context).einstPrivateMetadatenText),
                      value: privacy.data?.protectMetadata ?? true,
                      onChanged: (value) async {
                        await widget.library.db
                            .setProtectPrivateMetadata(value);
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                              onPressed: _changePin,
                              child:
                                  Text(AppTexte.of(context).einstPinAendern)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                              onPressed: _removePin,
                              child:
                                  Text(AppTexte.of(context).einstPinEntfernen)),
                        ),
                      ],
                    ),
                  ),
                  if (unlocked)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
                      child: SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: _lockVaultSession,
                          icon: const Icon(Icons.lock_clock_outlined),
                          label: Text(AppTexte.of(context).einstSitzungSperren),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ];

  List<Widget> _gruppeBackupSchluessel() => [
        Card(
          child: FutureBuilder<bool>(
            future: _hasBackupKeyFuture,
            builder: (context, snapshot) {
              final hasKey = snapshot.data ?? false;
              if (!hasKey) {
                return ListTile(
                  leading: const Icon(Icons.enhanced_encryption_outlined),
                  title: Text(AppTexte.of(context).einstPassphraseEinrichten),
                  subtitle: Text(
                    AppTexte.of(context).einstBackupVerschluesselungText,
                  ),
                  isThreeLine: true,
                  trailing: FilledButton(
                      onPressed: _setupBackupPassphrase,
                      child: Text(AppTexte.of(context).allgEinrichten)),
                );
              }
              final unlocked = widget.library.backupKeyAvailableThisSession;
              return Column(
                children: [
                  ListTile(
                    leading: Icon(unlocked
                        ? Icons.lock_open_outlined
                        : Icons.lock_outline),
                    title: Text(AppTexte.of(context).einstBackupPassphrase),
                    subtitle: Text(unlocked
                        ? AppTexte.of(context).einstBackupEntsperrt
                        : AppTexte.of(context).einstBackupGesperrt),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                              onPressed: _changeBackupPassphrase,
                              child: Text(
                                  AppTexte.of(context).einstBackupAendern)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                              onPressed: _removeBackupEncryption,
                              child: Text(AppTexte.of(context).allgEntfernen)),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ];

  List<Widget> _gruppeBackupManuell() => [
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(AppTexte.of(context).einstLetztesBackup),
                subtitle: Text(_lastBackup == null
                    ? AppTexte.of(context).einstBackupNieGesichert
                    : AppTexte.of(context).einstBackupZusammenfassung(
                        _datum(_lastBackup!.performedAt),
                        _lastBackup!.fileCount,
                        _lastBackup!.destinationPath)),
              ),
              const Divider(height: 1),
              CheckboxListTile(
                value: _encryptManualBackup,
                onChanged: (v) =>
                    setState(() => _encryptManualBackup = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(AppTexte.of(context).einstBackupVerschluesseln),
                subtitle:
                    Text(AppTexte.of(context).einstBackupPassphraseAbfrage),
              ),
              // Was mitkommt und was nicht. Der Hinweis stand nirgends, und
              // der Unterschied ist erheblich: Ohne Passphrase liegt kein
              // Schnappschuss der Datenbank in der Sicherung, und damit
              // kämen Personen, Stammbaum, Reisen und Aktivitäten beim
              // Zurückspielen nicht wieder (Befund der 19. Prüfrunde).
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
                child: Text(
                  AppTexte.of(context).einstBackupManuellHinweis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _runBackup,
                        icon: const Icon(Icons.backup_outlined),
                        label: Text(AppTexte.of(context).einstJetztSichern),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _runRestore,
                        icon: const Icon(Icons.settings_backup_restore),
                        label: Text(AppTexte.of(context).einstWiederherstellen),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _pruefeBackup,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(AppTexte.of(context).einstBackupPruefen),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                child: Text(
                  AppTexte.of(context).einstBackupZielHinweis,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ];

  List<Widget> _gruppeBackupAuto() => [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text(
            AppTexte.of(context).einstBackupAutoHinweis,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        Card(
          child: FutureBuilder<BackupSettingsData?>(
            future: _backupSettingsFuture,
            builder: (context, snapshot) {
              final config = snapshot.data;
              final enabled = config?.autoBackupEnabled ?? false;
              final destination = config?.autoBackupDestination;
              final intervalHours = config?.autoBackupIntervalHours ?? 24;
              final maxMbPerRun = config?.autoBackupMaxMbPerRun ?? 0;
              final lastRun = config?.lastAutoBackupAt;
              final keyReady = widget.library.backupKeyAvailableThisSession;

              return Column(
                children: [
                  SwitchListTile(
                    value: enabled,
                    onChanged: destination == null
                        ? null
                        : (v) async {
                            await widget.library.db
                                .setAutoBackupConfig(enabled: v);
                            if (mounted) _reloadBackupSettings();
                          },
                    title: Text(AppTexte.of(context).allgAktiv),
                    subtitle: Text(destination ??
                        AppTexte.of(context).einstBackupZuerstZiel),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(AppTexte.of(context).einstZielordner),
                    subtitle: Text(destination ??
                        AppTexte.of(context).einstBackupKeinOrdner),
                    trailing: OutlinedButton(
                      onPressed: () async {
                        final picked =
                            await FilePicker.platform.getDirectoryPath(
                          dialogTitle:
                              AppTexte.of(context).einstBackupAutoZielWaehlen,
                        );
                        if (picked == null) return;
                        await widget.library.db.setAutoBackupConfig(
                            enabled: enabled, destination: picked);
                        if (mounted) _reloadBackupSettings();
                      },
                      child: Text(AppTexte.of(context).einstWaehlen),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.schedule_outlined),
                    title: Text(AppTexte.of(context).einstIntervall),
                    trailing: DropdownButton<int>(
                      value: intervalHours,
                      items: [
                        DropdownMenuItem(
                            value: 1,
                            child: Text(AppTexte.of(context).einstStuendlich)),
                        DropdownMenuItem(
                            value: 6,
                            child: Text(AppTexte.of(context)
                                .einstIntervallSechsStunden)),
                        DropdownMenuItem(
                            value: 24,
                            child: Text(AppTexte.of(context).einstTaeglich)),
                        DropdownMenuItem(
                            value: 168,
                            child:
                                Text(AppTexte.of(context).einstWoechentlich)),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        await widget.library.db.setAutoBackupConfig(
                            enabled: enabled, intervalHours: v);
                        if (mounted) _reloadBackupSettings();
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.speed_outlined),
                    title: Text(AppTexte.of(context).einstMengeJeLauf),
                    subtitle: Text(
                      AppTexte.of(context).einstBackupGrenzeText,
                      style: const TextStyle(fontSize: 12),
                    ),
                    isThreeLine: true,
                    trailing: DropdownButton<int>(
                      value: maxMbPerRun,
                      items: [
                        DropdownMenuItem(
                            value: 0,
                            child: Text(AppTexte.of(context).einstUnbegrenzt)),
                        const DropdownMenuItem(
                            value: 500, child: Text('500 MB')),
                        const DropdownMenuItem(
                            value: 2000, child: Text('2 GB')),
                        const DropdownMenuItem(
                            value: 10000, child: Text('10 GB')),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        await widget.library.db.setAutoBackupMaxMbPerRun(v);
                        if (mounted) _reloadBackupSettings();
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(AppTexte.of(context).einstLetzterLauf),
                    subtitle: Text(lastRun == null
                        ? AppTexte.of(context).einstNieAusgefuehrt
                        : _datumZeit(lastRun)),
                  ),
                  if (enabled && !keyReady)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                          AppSpacing.sm, AppSpacing.lg, AppSpacing.xs),
                      child: Text(
                        AppTexte.of(context).einstBackupPassphraseGesperrt,
                        style: TextStyle(
                            fontSize: 12, color: context.semantik.warnung),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed:
                            destination == null ? null : _runAutoBackupNow,
                        icon: const Icon(Icons.sync),
                        label: Text(
                            AppTexte.of(context).einstJetztSynchronisieren),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ];

  List<Widget> _gruppePapierkorb() => [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text(
            AppTexte.of(context).einstPapierkorbText,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        Card(
          child: FutureBuilder<TrashSettingsData?>(
            future: _trashSettingsFuture,
            builder: (context, snapshot) {
              final config = snapshot.data;
              final enabled = config?.autoDeleteEnabled ?? false;
              final afterDays = config?.autoDeleteAfterDays ?? 30;
              final lastRun = config?.lastPurgeAt;

              return Column(
                children: [
                  // **Der Weg in den Papierkorb selbst.** Er fehlte seit
                  // dem ersten Commit: TrashScreen war vollständig
                  // gebaut - Wiederherstellen, endgültig Löschen, leerer
                  // Zustand, alle Texte - und wurde von keiner einzigen
                  // Stelle aufgerufen. Gelöschte Fotos lagen also in
                  // einem Behälter, den niemand öffnen konnte, bis die
                  // automatische Leerung sie nach dreissig Tagen
                  // endgültig entfernte. Die Duplikatsuche versprach
                  // dabei ausdrücklich „über den Papierkorb
                  // wiederherstellbar".
                  //
                  // Hier und nicht in der Leiste: Der gesperrte Ordner
                  // wird ebenso von den Einstellungen aus geöffnet, und
                  // seine Einstellung steht daneben.
                  StreamBuilder<Papierkorbumfang>(
                    // **Wieviel Platz hier liegt, stand nirgends.** An
                    // einer gewachsenen Bibliothek waren es 619
                    // Aufnahmen und 6,01 GB – sieben Prozent des
                    // Bestands, unsichtbar. Die Zahl der Fotos allein
                    // sagt darüber nichts: 619 Bildschirmfotos wären
                    // ein Bruchteil davon.
                    //
                    // Beides rechnet die Datenbank, statt jede Zeile des
                    // Papierkorbs herzuschicken: 0,3 statt 13,0 ms je
                    // Abo, und dieser Aufbau läuft bei jeder Meldung des
                    // Bibliothekszustands.
                    stream: widget.library.db.watchPapierkorbUmfang(),
                    builder: (context, papierkorb) {
                      final anzahl = papierkorb.data?.anzahl ?? 0;
                      final platz = papierkorb.data?.bytes ?? 0;
                      return ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: Text(AppTexte.of(context).papierkorbTitel),
                        subtitle: Text(anzahl == 0
                            ? AppTexte.of(context).papierkorbLeer
                            : AppTexte.of(context)
                                .papierkorbUmfang(anzahl, groessentext(platz))),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => TrashScreen(library: widget.library),
                        )),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    value: enabled,
                    onChanged: (v) async {
                      await widget.library.db
                          .setTrashAutoDeleteConfig(enabled: v);
                      if (mounted) _reloadTrashSettings();
                    },
                    title: Text(AppTexte.of(context).allgAktiv),
                    subtitle: Text(AppTexte.of(context).einstPapierkorbAus),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.timelapse_outlined),
                    title: Text(AppTexte.of(context).einstNachTagen),
                    trailing: DropdownButton<int>(
                      value: afterDays,
                      items: [
                        for (final tage in [7, 14, 30, 60, 90])
                          DropdownMenuItem(
                              value: tage,
                              child: Text(AppTexte.of(context)
                                  .einstTageDropdown(tage))),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        await widget.library.db.setTrashAutoDeleteConfig(
                            enabled: enabled, afterDays: v);
                        if (mounted) _reloadTrashSettings();
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(AppTexte.of(context).einstLetzterLauf),
                    subtitle: Text(lastRun == null
                        ? AppTexte.of(context).einstNieAusgefuehrt
                        : _datumZeit(lastRun)),
                  ),
                ],
              );
            },
          ),
        ),
      ];

  List<Widget> _gruppeGefahr() => [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text(
            AppTexte.of(context).einstResetText,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(
                color:
                    Theme.of(context).colorScheme.error.withValues(alpha: 0.4)),
          ),
          child: ListTile(
            leading: Icon(Icons.warning_amber_outlined,
                color: Theme.of(context).colorScheme.error),
            title: Text(AppTexte.of(context).einstResetTitel),
            subtitle: Text(AppTexte.of(context).einstResetKurz),
            trailing: OutlinedButton(
              style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error),
              onPressed: _resetDatabase,
              child: Text(AppTexte.of(context).einstResetKnopf),
            ),
          ),
        ),
      ];

  List<Widget> _gruppeUeber() => [
        Card(
          child: FutureBuilder<PackageInfo>(
            future: _versionFuture,
            builder: (context, snapshot) {
              final info = snapshot.data;
              final version = info?.version ?? '…';
              // Dieselbe Auswahl wie in der Modellgruppe: Sonst stuende
              // hier auf Englisch fuer immer „9 von 11".
              final katalog = _modelle(context);
              final modelle = katalog
                  .where((e) => widget.library.isModelInstalled(e))
                  .toList();
              return Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text('Photo Vault $version'),
                    subtitle: Text(info == null
                        ? ''
                        : AppTexte.of(context).einstBauZeile(
                            info.buildNumber,
                            Platform.operatingSystem,
                            Platform.operatingSystemVersion)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.storage_outlined),
                    title: Text(AppTexte.of(context).einstDatenbank),
                    subtitle: Text(AppTexte.of(context)
                        .einstDatenbankStand(widget.library.db.schemaVersion)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.memory_outlined),
                    title: Text(modelle.isEmpty
                        ? AppTexte.of(context).einstKeineModelle
                        : AppTexte.of(context).einstModelleGeladen(
                            modelle.length, katalog.length)),
                    subtitle: Text(modelle.isEmpty
                        ? AppTexte.of(context).einstModelleUnbenutzt
                        : modelle
                            .map((e) => modellTitel(AppTexte.of(context), e.id))
                            .join(' · ')),
                    isThreeLine: modelle.isNotEmpty,
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
                    child: Text(
                      AppTexte.of(context).einstAktualisierungHinweis,
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  if (_aktualisierungsstand != null)
                    ListTile(
                      leading: Icon(
                        _aktualisierungsstand!.istNeuereVerfuegbar
                            ? Icons.new_releases_outlined
                            : Icons.check_circle_outline,
                        color: _aktualisierungsstand!.istNeuereVerfuegbar
                            ? Theme.of(context).colorScheme.primary
                            : context.semantik.erfolg,
                      ),
                      title: Text(_aktualisierungsstand!.istNeuereVerfuegbar
                          ? AppTexte.of(context).einstAktualisierungNeuer(
                              _aktualisierungsstand!.neueste)
                          : AppTexte.of(context).einstAktualisierungAktuell),
                      subtitle: _aktualisierungsstand!.istNeuereVerfuegbar
                          ? Text(_aktualisierungsstand!.seitenUrl ?? '')
                          : null,
                    ),
                  if (_aktualisierungsfehler != null)
                    ListTile(
                      leading: const Icon(Icons.cloud_off_outlined),
                      title: Text(_aktualisierungsfehler!),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: (_pruefeAktualisierung || info == null)
                                ? null
                                : () => _sucheAktualisierung(version),
                            icon: _pruefeAktualisierung
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.system_update_alt_outlined),
                            label: Text(AppTexte.of(context)
                                .einstNachAktualisierungSuchen),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // **Der Weg zu den Lizenzen.** Die App liefert seit dem
                  // Zierbaum zwei Schriften mit, und die SIL Open Font
                  // License verlangt, dass ihr Text mitgeht. Er ging
                  // mit – nur konnte ihn niemand lesen: Es gab keine
                  // Übersicht, in der die angemeldeten Lizenzen
                  // aufgetaucht wären. Eine Datei im Paket, die
                  // unerreichbar ist, erfüllt die Auflage dem Buchstaben
                  // nach und dem Sinn nach nicht.
                  ListTile(
                    leading: const Icon(Icons.gavel_outlined),
                    title: Text(AppTexte.of(context).einstLizenzen),
                    subtitle: Text(AppTexte.of(context).einstLizenzenText),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'Photo Vault',
                      applicationVersion: version,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ];

  /// Ein Schalter für eine Übersetzungsrichtung.
  ///
  /// Ohne das zugehörige Modell bleibt er sichtbar, aber abgeschaltet, und
  /// sagt warum – ein Schalter, der ohne Erklärung nichts tut, ist
  /// schlimmer als keiner. Die Modellkarte dazu steht direkt darunter.
  Widget _uebersetzungsSchalter({
    required IconData icon,
    required String titel,
    required String beschreibung,
    required bool installiert,
    required Future<bool> Function() lesen,
    required Future<void> Function(bool) schreiben,
  }) {
    return FutureBuilder<bool>(
      key: ValueKey('uebersetzung-$titel'),
      future: lesen(),
      builder: (context, snapshot) {
        final an = snapshot.data ?? false;
        return Card(
          child: SwitchListTile(
            value: an && installiert,
            onChanged: installiert
                ? (v) async {
                    await schreiben(v);
                    if (mounted) setState(() {});
                  }
                : null,
            secondary: Icon(icon),
            isThreeLine: true,
            title: Text(titel),
            subtitle: Text(
              installiert
                  ? beschreibung
                  : AppTexte.of(context).einstModellNichtGeladen(beschreibung),
              style: TextStyle(
                fontSize: 12,
                color:
                    installiert ? null : Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ModelCard extends StatelessWidget {
  final ModelCatalogEntry entry;
  final bool installed;
  final bool downloading;

  /// Belegter Platz, bereits lesbar formatiert – null, solange das Modell
  /// nicht installiert ist. Vorher lässt sich die Grösse nicht angeben:
  /// Der Katalog führt nur Dateinamen und Prüfsummen, keine Längen.
  final String? groesse;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  const _ModelCard({
    required this.entry,
    required this.installed,
    required this.downloading,
    required this.groesse,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          installed ? Icons.check_circle : Icons.cloud_download_outlined,
          color: installed ? context.semantik.erfolg : null,
        ),
        title: Text(modellTitel(AppTexte.of(context), entry.id)),
        subtitle: Text([
          modellBeschreibung(AppTexte.of(context), entry.id),
          AppTexte.of(context).einstModellLizenzZeile(
                  modellLizenz(AppTexte.of(context), entry.id)) +
              (groesse != null ? ' · $groesse' : ''),
        ].join('\n')),
        isThreeLine: true,
        trailing: downloading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))
            : installed
                ? IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: AppTexte.of(context).einstModellLoeschen,
                    onPressed: onDelete,
                  )
                : FilledButton(
                    onPressed: onDownload,
                    child: Text(AppTexte.of(context).allgHerunterladen)),
      ),
    );
  }
}

/// Eine zusammenklappbare Gruppe von Einstellungen.
///
/// Der Bildschirm hatte sechzehn Abschnitte hintereinander – über 900
/// Zeilen Oberfläche, durch die man scrollen musste, um an die
/// Gefahrenzone ganz unten zu kommen. Als Gruppen ist zugeklappt der
/// Normalfall: Man sieht sechzehn Zeilen und öffnet die eine, die man
/// braucht.
class _Gruppe {
  final IconData icon;
  final String titel;
  final String beschreibung;

  /// Als Funktion, nicht als fertige Liste: Der Inhalt einer zugeklappten
  /// Gruppe soll gar nicht erst gebaut werden. Bei sechzehn Gruppen mit
  /// StreamBuildern, Dateigrössen-Abfragen und Modell-Listen ist das der
  /// Unterschied zwischen „alles immer" und „nur das Geöffnete".
  final List<Widget> Function() inhalt;

  const _Gruppe({
    required this.icon,
    required this.titel,
    required this.beschreibung,
    required this.inhalt,
  });
}

class _GruppenKarte extends StatelessWidget {
  final _Gruppe gruppe;
  final bool anfangsOffen;

  const _GruppenKarte({
    super.key,
    required this.gruppe,
    required this.anfangsOffen,
  });

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final rand = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      side: BorderSide(color: farben.outlineVariant),
    );
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: farben.surface,
      shape: rand,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        // Ohne diese beiden hat ExpansionTile im geöffneten Zustand eigene
        // Trennlinien oben und unten, die quer zur Kartenkontur laufen.
        shape: const Border(),
        collapsedShape: const Border(),
        initiallyExpanded: anfangsOffen,
        leading: Icon(gruppe.icon, color: farben.primary),
        title: Text(
          gruppe.titel,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: farben.primary,
                fontWeight: FontWeight.w600,
              ),
        ),
        subtitle: Text(
          gruppe.beschreibung,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: gruppe.inhalt(),
      ),
    );
  }
}
