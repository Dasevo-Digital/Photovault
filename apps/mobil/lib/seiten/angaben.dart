import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/asset_format.dart' show assetFormatLabel;
import 'package:kern/services/aufnahmeangaben.dart';
import 'package:kern/services/laendernamen.dart';
import 'package:kern/services/namensdatum.dart';

import '../einfuegbares_menue.dart';
import '../formate.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'alben.dart';
import 'aufnahmedaten.dart';
import 'gesichter.dart';
import 'ort_waehlen.dart';
import 'personen.dart';
import 'raster.dart';
import 'varianten.dart';

/// Die Angaben zu einer Aufnahme – dieselben Zeilen wie im Browser
/// (web/app.js, zeigeAngaben) und wie die Info-Ansicht des Rechners:
/// Datum, Datei, Kamera, Ort, Personen, Schlagwörter, Alben, Beschreibung,
/// Bewertung, Serie, erkannter Text, Transkript. Beschreibung und
/// Bewertung lassen sich ändern, über dieselben Befehle wie überall.
Future<void> zeigeAngaben(
  BuildContext context,
  Sitzung sitzung,
  String id,
) async {
  final angaben = await aufnahmeangaben(sitzung.db, id);
  if (angaben == null || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scroll) =>
          Angabenliste(sitzung: sitzung, angaben: angaben, scroll: scroll),
    ),
  );
}

/// Die Zeilen der Angaben.
class Angabenliste extends StatefulWidget {
  const Angabenliste({
    super.key,
    required this.sitzung,
    required this.angaben,
    this.scroll,
  });

  final Sitzung sitzung;
  final Aufnahmeangaben angaben;
  final ScrollController? scroll;

  @override
  State<Angabenliste> createState() => _AngabenlisteState();
}

class _AngabenlisteState extends State<Angabenliste> {
  late final _beschreibung = TextEditingController(
    text: widget.angaben.aufnahme.description ?? '',
  );
  late int _bewertung = widget.angaben.aufnahme.rating;
  var _gespeichert = false;

  /// Was der Server aus dem Dateinamen vorschlägt (#203), und ob es
  /// übernommen ist.
  ({DateTime neu, bool geschaetzt, String quelle})? _vorschlag;
  ({DateTime neu, bool geschaetzt})? _uebernommen;

  AssetData get _a => _nachOrt ?? widget.angaben.aufnahme;

  /// Die Aufnahme, nachdem hier der Ort geändert wurde; die Angaben kamen
  /// fertig an.
  AssetData? _nachOrt;
  AppDatabase get _db => widget.sitzung.db;

  @override
  void initState() {
    super.initState();
    _holeVorschlag();
  }

  /// Die Fassungen eines Formatstapels (#374), Titelbild zuerst: Welche
  /// Formate darin liegen, sah man bisher nirgends, und an ein bestimmtes
  /// kam man nur über das Auflösen.
  late final Future<List<AssetData>> _formate = _ladeFormate();

  Future<List<AssetData>> _ladeFormate() async {
    final a = widget.angaben.aufnahme;
    if (!a.isStackCover || !istFormatstapel(a.stackId)) return const [];
    return [
      for (final f in await _db.assetsInStack(a.stackId!))
        if (!f.isTrashed && !f.isLocked) f,
    ]..sort(vergleicheFassungen);
  }

  /// Teilt das Original einer Fassung, etwa nur das RAW – wie „Teilen“ mit
  /// „Original“ im Betrachter.
  Future<void> _teileFassung(AssetData f) async {
    final t = AppTexte.of(context);
    final bote = ScaffoldMessenger.of(context);
    bote.showSnackBar(SnackBar(content: Text(t.betrachterLaedtOriginal)));
    try {
      final datei = await widget.sitzung.paths.bereit(f.relativePath);
      bote.hideCurrentSnackBar();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(datei.path)],
          fileNameOverrides: [f.originalFileName],
        ),
      );
    } catch (_) {
      bote
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(t.betrachterNichtGeladen)));
    }
  }

  /// Nur wenn der Name überhaupt ein anderes Datum nennt, wird gefragt –
  /// geprüft wird auf dem Server, weil dafür manchmal das Original gelesen
  /// werden muss (siehe Aufnahmedaten).
  /// Was hier umbenannt wurde (#273); die Angaben kamen fertig an.
  final _umbenannt = <String, String>{};

  /// Benennt ein Schlagwort um – an allen Fotos zugleich, wie am Rechner
  /// und im Browser. Einen vergebenen Namen lehnt die Bibliothek ab.
  Future<void> _schlagwortUmbenennen(TagData s) async {
    final t = AppTexte.of(context);
    final bote = ScaffoldMessenger.of(context);
    final alt = _umbenannt[s.id] ?? s.name;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _Umbenennen(vorgabe: alt),
    );
    if (name == null || name == alt) return;
    try {
      await widget.sitzung.db.fuehreAus(SchlagwortUmbenennen(s.id, name));
    } on StateError catch (e) {
      if (e.message != 'pv_schlagwort_vorhanden') rethrow;
      bote.showSnackBar(
        SnackBar(content: Text(t.angabenSchlagwortVorhanden(name))),
      );
      return;
    }
    if (mounted) setState(() => _umbenannt[s.id] = name);
  }

  Future<void> _holeVorschlag() async {
    final name = namensdatumAus(_a.originalFileName);
    final verbindung = widget.sitzung.abgleich?.verbindung;
    if (name == null || name.passtZu(_a.fileCreatedAt) || verbindung == null) {
      return;
    }
    try {
      final d = await verbindung.hole(
        'api/v1/aufnahmen/${Uri.encodeComponent(_a.id)}/angaben',
      );
      if (d['datumsvorschlag'] case final Map v when mounted) {
        setState(() => _vorschlag = vorschlagAus(v));
      }
    } catch (_) {
      // Ohne Verbindung eben ohne Vorschlag.
    }
  }

  Future<void> _datumUebernehmen() async {
    final v = _vorschlag!;
    await _db.fuehreAus(
      AufnahmedatenSetzen([
        (id: _a.id, zeitpunkt: v.neu, geschaetzt: v.geschaetzt),
      ]),
    );
    if (mounted) {
      setState(() => _uebernommen = (neu: v.neu, geschaetzt: v.geschaetzt));
    }
  }

  @override
  void dispose() {
    _beschreibung.dispose();
    super.dispose();
  }

  Future<void> _speichern() async {
    await _db.fuehreAus(BeschreibungSetzen([_a.id], _beschreibung.text));
    if (mounted) setState(() => _gespeichert = true);
  }

  Future<void> _ortAendern(bool hatOrt) async {
    final geaendert = await ortWaehlen(context, widget.sitzung, [
      _a.id,
    ], hatOrt: hatOrt);
    if (!geaendert) return;
    final neu = await _db.assetById(_a.id);
    if (mounted && neu != null) setState(() => _nachOrt = neu);
  }

  Future<void> _bewerten(int i) async {
    // Dieselbe Sterne noch einmal nimmt die Bewertung weg – wie im Browser.
    final neu = _bewertung == i ? 0 : i;
    await _db.fuehreAus(BewertungSetzen([_a.id], neu));
    if (mounted) setState(() => _bewertung = neu);
  }

  void _oeffne(Widget seite) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => seite));

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final sprache = Localizations.localeOf(context).toLanguageTag();
    final farben = Theme.of(context).colorScheme;
    final leise = TextStyle(color: farben.onSurfaceVariant);
    final a = _a;
    final g = widget.angaben;
    final datumZeit = datumZeitMittel(sprache);
    final datei = [
      if (a.widthPx != null && a.heightPx != null)
        '${a.widthPx} × ${a.heightPx}',
      if (a.fileSizeBytes > 0) groesseText(a.fileSizeBytes),
      if (a.dateiformat case final f? when f.isNotEmpty) f.toUpperCase(),
      if (a.durationSeconds case final d? when d > 0) '${d.round()} s',
      if (g.bearbeitet) t.angabenBearbeitet,
    ].join(' · ');
    final hersteller = a.cameraMake ?? '';
    final modell = a.cameraModel ?? '';
    final kamera =
        modell.isNotEmpty &&
            hersteller.isNotEmpty &&
            modell.toLowerCase().startsWith(hersteller.toLowerCase())
        ? modell
        : [hersteller, modell].where((s) => s.isNotEmpty).join(' ');
    final werte = [
      if (a.focalLengthMm case final f?) '${_zahl(f)} mm',
      if (a.fNumber case final f?) 'f/${_zahl(f)}',
      if (a.exposureTimeSeconds case final s?) belichtungText(s),
      if (a.iso case final i?) 'ISO $i',
    ].join(' · ');
    final hatOrt = a.latitude != null && a.longitude != null;
    final ortName = [
      a.locationCity,
      a.locationState,
      landAnzeige(a.locationCountry, sprache),
    ].whereType<String>().where((s) => s.isNotEmpty).join(', ');
    final ki = sprache.startsWith('de')
        ? (a.aiCaptionDe ?? a.aiCaption)
        : a.aiCaption;
    final serie = a.stackSize ?? 0;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(t.angabenTitel, style: Theme.of(context).textTheme.titleMedium),
        _Reihe(
          symbol: Icons.event_outlined,
          haupt: Text(
            datumZeit.format((_uebernommen?.neu ?? a.fileCreatedAt).toLocal()),
          ),
          neben: (_uebernommen?.geschaetzt ?? a.datumGeschaetzt)
              ? t.angabenDatumGeschaetzt
              : null,
          unten: switch (_vorschlag) {
            final v? when _uebernommen == null => Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  (v.quelle == 'dateiUndName'
                      ? t.angabenDateiNennt
                      : t.angabenNameNennt)(
                    vorschlagsdatum(sprache, v.neu, v.geschaetzt),
                  ),
                  style: leise,
                ),
                TextButton(
                  onPressed: _datumUebernehmen,
                  child: Text(t.angabenUebernehmen),
                ),
              ],
            ),
            _ => null,
          },
        ),
        _Reihe(
          symbol: Icons.image_outlined,
          haupt: Text(a.originalFileName),
          neben: datei.isEmpty ? null : datei,
        ),
        if (kamera.isNotEmpty)
          _Reihe(
            symbol: Icons.photo_camera_outlined,
            haupt: Text(kamera),
            neben: [?a.lensModel, if (werte.isNotEmpty) werte].join('\n'),
          ),
        _Reihe(
          symbol: Icons.place_outlined,
          haupt: Text(
            !hatOrt
                ? t.ortKeiner
                : ortName.isEmpty
                ? t.angabenStandortBekannt
                : ortName,
          ),
          neben: hatOrt
              ? '${a.latitude!.toStringAsFixed(5)}, '
                    '${a.longitude!.toStringAsFixed(5)}'
                    '${a.ortGeerbt ? ' · ${t.angabenGeerbt}' : ''}'
              : null,
          unten: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _ortAendern(hatOrt),
              child: Text(hatOrt ? t.ortAendern : t.ortSetzen),
            ),
          ),
        ),
        if (g.personen.isNotEmpty)
          _Reihe(
            symbol: Icons.person_outline,
            haupt: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final p in g.personen)
                  ActionChip(
                    label: Text(p.name),
                    onPressed: () => _oeffne(
                      PersonSeite(sitzung: widget.sitzung, person: p),
                    ),
                  ),
              ],
            ),
          ),
        // Jedes Gesicht für sich – zum Benennen und Ändern (wie im
        // Browser).
        GesichterDerAufnahme(
          sitzung: widget.sitzung,
          assetId: a.id,
          rahmen: (inhalt) =>
              _Reihe(symbol: Icons.face_outlined, haupt: inhalt),
        ),
        if (g.schlagwoerter.isNotEmpty)
          _Reihe(
            symbol: Icons.sell_outlined,
            haupt: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final s in g.schlagwoerter)
                  ActionChip(
                    label: Text(_umbenannt[s.id] ?? s.name),
                    tooltip: t.angabenSchlagwortUmbenennen,
                    onPressed: () => _schlagwortUmbenennen(s),
                  ),
              ],
            ),
          ),
        if (g.alben.isNotEmpty)
          _Reihe(
            symbol: Icons.photo_album_outlined,
            haupt: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final b in g.alben)
                  ActionChip(
                    label: Text(b.name),
                    onPressed: () =>
                        _oeffne(AlbumSeite(sitzung: widget.sitzung, album: b)),
                  ),
              ],
            ),
          ),
        _Reihe(
          symbol: Icons.edit_outlined,
          haupt: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _beschreibung,
                minLines: 2,
                maxLines: 5,
                contextMenuBuilder: einfuegbaresMenue,
                decoration: InputDecoration(
                  hintText: t.angabenBeschreibung,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) {
                  if (_gespeichert) setState(() => _gespeichert = false);
                },
              ),
              const SizedBox(height: 6),
              OutlinedButton(
                onPressed: _speichern,
                child: Text(
                  _gespeichert ? t.angabenGespeichert : t.angabenSpeichern,
                ),
              ),
            ],
          ),
          neben: (ki ?? '').isEmpty ? null : t.angabenAutomatisch(ki!),
        ),
        _Reihe(
          symbol: Icons.star_outline,
          haupt: Row(
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  tooltip: t.angabenSterne(i),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _bewerten(i),
                  icon: Icon(
                    i <= _bewertung ? Icons.star : Icons.star_border,
                    color: i <= _bewertung
                        ? const Color(0xFFE3A008)
                        : farben.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        if (a.stackId != null && serie > 1)
          _Reihe(
            symbol: Icons.burst_mode_outlined,
            haupt: InkWell(
              onTap: () => _oeffne(
                SerieSeite(sitzung: widget.sitzung, stackId: a.stackId!),
              ),
              child: Text(
                istVariantenstapel(a.stackId)
                    ? t.angabenVarianten(serie)
                    : t.angabenSerie(serie),
                style: TextStyle(color: farben.primary),
              ),
            ),
          ),
        FutureBuilder<List<AssetData>>(
          future: _formate,
          builder: (context, s) {
            final formate = s.data ?? const <AssetData>[];
            if (formate.length < 2) return const SizedBox.shrink();
            return _Reihe(
              symbol: Icons.download_outlined,
              haupt: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final f in formate)
                    ActionChip(
                      label: Text(
                        '${assetFormatLabel(f)} · '
                        '${groesseText(f.fileSizeBytes)}',
                      ),
                      tooltip: t.angabenFassungTeilen(f.originalFileName),
                      onPressed: () => _teileFassung(f),
                    ),
                ],
              ),
              neben: t.angabenFormate,
            );
          },
        ),
        if ((a.ocrText ?? '').isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(t.angabenText),
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: SelectableText(a.ocrText!, style: leise),
              ),
            ],
          ),
        if ((a.transkript ?? '').isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(t.angabenTranskript),
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: SelectableText(a.transkript!, style: leise),
              ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            t.angabenImportiert(datumZeit.format(a.importedAt.toLocal())),
            style: leise.copyWith(fontSize: 12),
          ),
        ),
      ],
    );
  }

  static String _zahl(double x) =>
      x == x.roundToDouble() ? x.round().toString() : x.toString();
}

/// „1/250 s“, „2 s“ – wie im Browser.
String belichtungText(double s) =>
    s >= 1 ? '${_kurz(s)} s' : '1/${(1 / s).round()} s';

String _kurz(double x) =>
    x == x.roundToDouble() ? x.round().toString() : x.toString();

/// „2.4 MB“ – wie im Browser.
String groesseText(int b) => b >= 1073741824
    ? '${(b / 1073741824).toStringAsFixed(1)} GB'
    : b >= 1048576
    ? '${(b / 1048576).toStringAsFixed(1)} MB'
    : '${(b / 1024).round()} KB';

/// Eine Zeile: Zeichen, darin der Inhalt und darunter, leiser, die
/// Einzelheiten.
/// Fragt nach dem neuen Namen eines Schlagworts. Eigenes Widget, damit das
/// Feld erst mit dem Dialog verschwindet (siehe alben.dart).
class _Umbenennen extends StatefulWidget {
  const _Umbenennen({required this.vorgabe});

  final String vorgabe;

  @override
  State<_Umbenennen> createState() => _UmbenennenState();
}

class _UmbenennenState extends State<_Umbenennen> {
  late final _feld = TextEditingController(text: widget.vorgabe);

  @override
  void dispose() {
    _feld.dispose();
    super.dispose();
  }

  void _fertig() {
    final name = _feld.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return AlertDialog(
      title: Text(t.angabenSchlagwortUmbenennen),
      content: TextField(
        controller: _feld,
        autofocus: true,
        contextMenuBuilder: einfuegbaresMenue,
        decoration: InputDecoration(
          labelText: t.angabenSchlagwortUmbenennenFeld,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _fertig(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(onPressed: _fertig, child: Text(t.angabenUmbenennen)),
      ],
    );
  }
}

class _Reihe extends StatelessWidget {
  const _Reihe({
    required this.symbol,
    required this.haupt,
    this.neben,
    this.unten,
  });

  final IconData symbol;
  final Widget haupt;
  final String? neben;

  /// Unter allem, etwa der Vorschlag aus dem Dateinamen (#203).
  final Widget? unten;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final neben = this.neben;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: farben.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 12),
            child: Icon(symbol, size: 20, color: farben.primary),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DefaultTextStyle.merge(
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  child: haupt,
                ),
                if (neben != null && neben.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      neben,
                      style: TextStyle(color: farben.onSurfaceVariant),
                    ),
                  ),
                ?unten,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Die Aufnahmen einer Serie, Titelbild zuerst – wie im Browser. Bei
/// Varianten (#219) lässt sich oben die Hauptversion wechseln oder der
/// Stapel auflösen, wie am Rechner.
class SerieSeite extends StatefulWidget {
  const SerieSeite({super.key, required this.sitzung, required this.stackId});

  final Sitzung sitzung;
  final String stackId;

  @override
  State<SerieSeite> createState() => _SerieSeiteState();
}

class _SerieSeiteState extends State<SerieSeite> {
  late Future<List<AssetData>> _mitglieder = _lade();

  Future<List<AssetData>> _lade() =>
      serieZumAnsehen(widget.sitzung.db, widget.stackId);

  @override
  Widget build(BuildContext context) => FutureBuilder<List<AssetData>>(
    future: _mitglieder,
    builder: (context, snap) {
      final a = snap.data;
      final t = AppTexte.of(context);
      final varianten = istVariantenstapel(widget.stackId);
      return Scaffold(
        appBar: AppBar(
          title: a == null
              ? null
              : Text(
                  varianten
                      ? t.angabenVariantenTitel(a.length)
                      : t.angabenSerieTitel(a.length),
                ),
          actions: [
            if (varianten && a != null && a.length > 1) ...[
              IconButton(
                tooltip: t.variantenHauptWaehlen,
                icon: const Icon(Icons.star_outline),
                onPressed: () async {
                  if (await hauptversionWechseln(
                        context,
                        widget.sitzung,
                        widget.stackId,
                        a,
                      ) &&
                      mounted) {
                    setState(() => _mitglieder = _lade());
                  }
                },
              ),
              IconButton(
                tooltip: t.variantenEinzeln,
                icon: const Icon(Icons.layers_clear_outlined),
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  if (await variantenAufloesen(
                    context,
                    widget.sitzung,
                    widget.stackId,
                    a.length,
                  )) {
                    navigator.pop();
                  }
                },
              ),
            ],
          ],
        ),
        body: a == null
            ? const Center(child: CircularProgressIndicator())
            : AufnahmenRaster(
                sitzung: widget.sitzung,
                zeilen: [for (final x in a) Rasterzeile.aus(x)],
              ),
      );
    },
  );
}
