import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../services/bilddekodierung.dart';
import '../services/gesicht_von_hand.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/asset_info_sheet.dart';
import '../widgets/gesichtsrahmen.dart';
import '../widgets/person_picker_dialog.dart';
import '../widgets/pin_dialogs.dart';
import '../services/meldungsdienst.dart';

/// Zeigt ein Foto in Vollbild mit allen erkannten Gesichtern als Rahmen
/// darüber. Tippen auf einen Rahmen ordnet dieses Gesicht einer Person zu
/// (oder benennt sie um). Im "Gesicht hinzufügen"-Modus kann man zusätzlich
/// per Ziehen einen neuen Rahmen aufziehen, um ein von der automatischen
/// Erkennung übersehenes Gesicht manuell zu markieren und zu benennen.
///
/// [assets] ist die Reihe, durch die sich mit Pfeiltasten oder den Pfeilen
/// in der Titelleiste blättern lässt. Gesichter benennt man selten einzeln:
/// Wer im Raster ein unbenanntes Gesicht anklickt, will meist gleich die
/// nächsten mitnehmen – bisher hiess das jedes Mal zurück, suchen, wieder
/// öffnen. Eine Liste mit einem einzigen Eintrag ist erlaubt; dann sind die
/// Pfeile abgeschaltet.
class FaceReviewScreen extends StatefulWidget {
  final LibraryState library;
  final List<AssetData> assets;
  final int startIndex;
  const FaceReviewScreen({
    super.key,
    required this.library,
    required this.assets,
    this.startIndex = 0,
  }) : assert(assets.length > 0);

  @override
  State<FaceReviewScreen> createState() => _FaceReviewScreenState();
}

class _FaceReviewScreenState extends State<FaceReviewScreen> {
  /// Eigene Kopie der Reihe, nicht [FaceReviewScreen.assets] selbst: Ein
  /// gelöschtes Foto muss hier verschwinden, sonst blätterte man gleich
  /// danach wieder auf ein Bild, das es nicht mehr gibt. Die Info-Ansicht
  /// tauscht ebenfalls Einträge aus, wenn sie Datum oder Ort ändert.
  late final List<AssetData> _assets = List.of(widget.assets);
  late int _index = widget.startIndex.clamp(0, _assets.length - 1);
  AssetData get _asset => _assets[_index];

  /// Ob die Info-Ansicht neben dem Foto steht.
  ///
  /// Sie fehlte hier ganz: Wer aus der Personenansicht ein Foto öffnete,
  /// sah die Gesichter, aber weder Datum noch Kamera noch Ort – und musste
  /// dafür zurück in die Zeitleiste und das Foto dort erneut suchen.
  bool _infoSichtbar = false;

  List<FaceData> _faces = [];
  Map<String, String> _personNames = {}; // personId -> Name
  double? _aspectRatio;
  bool _addMode = false;

  /// Ob die Rahmen über dem Foto gezeichnet werden.
  ///
  /// Bei einem Gruppenfoto liegen schnell ein Dutzend Kästen mit
  /// Beschriftung über dem Bild – man sieht dann die Rahmen und nicht mehr
  /// das Foto. Der Schalter gilt für die ganze Sitzung dieses Bildschirms,
  /// also auch beim Weiterblättern: Wer sie einmal weggeschaltet hat, will
  /// sie nicht auf jedem Foto neu wegschalten.
  bool _rahmenSichtbar = true;
  Offset? _dragStart;
  Offset? _dragCurrent;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Blättert um [schritt] Fotos weiter und lädt neu.
  ///
  /// Am Rand der Liste passiert bewusst nichts – kein Umlauf zum Anfang.
  /// Wer am Ende ankommt, soll das merken, statt unbemerkt wieder von vorn
  /// dieselben Gesichter zu benennen.
  void _springe(int schritt) {
    final ziel = _index + schritt;
    if (ziel < 0 || ziel >= _assets.length) return;
    setState(() {
      _index = ziel;
      _faces = [];
      _aspectRatio = null;
      // Ein halb aufgezogener Rahmen gehört zum vorherigen Foto.
      _addMode = false;
      _dragStart = null;
      _dragCurrent = null;
    });
    _load();
  }

  KeyEventResult _taste(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Im "Gesicht hinzufügen"-Modus wäre ein Sprung zum nächsten Foto
    // mitten im Aufziehen verwirrend; dort bleiben die Pfeile stumm.
    if (!_addMode && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _springe(-1);
      return KeyEventResult.handled;
    }
    if (!_addMode && event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _springe(1);
      return KeyEventResult.handled;
    }
    // F wie im grossen Betrachter. Der Tooltip nennt die Taste – ohne
    // diese Zeile wäre das ein Versprechen, das die Ansicht nicht hält.
    // Nicht im Hinzufügen-Modus: Dort zieht man gerade einen Rahmen auf.
    if (!_addMode &&
        !_asset.isLocked &&
        event.logicalKey == LogicalKeyboardKey.keyF) {
      _favoritUmschalten();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_addMode) {
        setState(() {
          _addMode = false;
          _dragStart = null;
          _dragCurrent = null;
        });
      } else {
        Navigator.of(context).maybePop();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Datei, die tatsächlich angezeigt/für Crops verwendet wird: die
  /// konvertierte Vorschau, falls das Originalformat (z.B. HEIC/DNG) von
  /// Flutter nicht direkt gerendert werden kann – sonst das Original.
  File get _displayFile =>
      widget.library.paths.absolute(_asset.previewRelativePath ?? _asset.relativePath);

  /// Seitenverhältnis eines Fotos, dessen Maße nicht in der Datenbank
  /// stehen (in der Praxis eine Handvoll Altfälle).
  ///
  /// Über den Kopf der Datei, nicht über das ganze Bild: Ein vollständiges
  /// Dekodieren nur für zwei Zahlen liefe auf dem UI-Strang und kostete bei
  /// einem 48-Megapixel-Foto 183 MB und eine spürbare Pause – für eine
  /// Angabe, die in den ersten Bytes steht.
  ///
  /// Der Rückfall auf das vollständige Dekodieren bleibt: Das image-Paket
  /// kennt Formate, die Flutters eigener Dekodierer nicht kennt. Zeigen
  /// liesse sich so ein Foto hier zwar ohnehin nicht, aber die Rahmen
  /// säßen wenigstens richtig.
  Future<double?> _seitenverhaeltnisAusDatei() async {
    final bytes = await _displayFile.readAsBytes();
    try {
      final puffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final kopf = await ui.ImageDescriptor.encoded(puffer);
      final verhaeltnis = kopf.height > 0 ? kopf.width / kopf.height : null;
      kopf.dispose();
      puffer.dispose();
      if (verhaeltnis != null) return verhaeltnis;
    } catch (_) {
      // Unbekanntes Format – unten weiter.
    }
    final decoded = img.decodeImage(bytes);
    return decoded == null ? null : decoded.width / decoded.height;
  }

  Future<void> _load() async {
    // Redundant zur Sperre in asset_viewer_screen.dart: schützt auch dann,
    // falls dieser Screen je aus einem anderen Kontext heraus geöffnet
    // würde, bevor die Original-/Vorschau-Datei (noch verschlüsselt)
    // angefasst wird – dasselbe Muster wie DevelopScreen._init. Steht seit
    // dem Blättern hier statt in initState, weil die Sperre pro Foto gilt
    // und nicht pro geöffnetem Bildschirm.
    if (_asset.isLocked) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final gefragtesAsset = _asset.id;
    final faces = await widget.library.db.facesForAsset(_asset.id);
    final people = await widget.library.db.select(widget.library.db.people).get();

    double? aspect;
    if (_asset.widthPx != null && _asset.heightPx != null && _asset.heightPx! > 0) {
      aspect = _asset.widthPx! / _asset.heightPx!;
    } else {
      aspect = await _seitenverhaeltnisAusDatei();
    }

    // Beim schnellen Durchblättern kann ein früherer Ladevorgang später
    // fertig werden als ein späterer. Ohne diese Prüfung landeten die
    // Rahmen des vorigen Fotos auf dem aktuellen.
    if (mounted && _asset.id == gefragtesAsset) {
      setState(() {
        _faces = faces;
        _personNames = {for (final p in people) p.id: p.name};
        _aspectRatio = aspect ?? 1.0;
        _loading = false;
      });
    }
  }

  Future<void> _tapFace(FaceData face) async {
    // Ein beiseitegelegtes Gesicht anzutippen heisst „doch nicht" – dafür
    // braucht es keinen Dialog mit Namensfeld, der nur den einen Fall
    // verdeckte, den der Nutzer hier will.
    if (face.isIgnored) {
      await widget.library.db.setFacesIgnored([face.id], false);
      if (mounted) {
        melde.erfolg(AppTexte.of(context).gesichtZurueckgeholt);
      }
      _load();
      return;
    }

    final people = await widget.library.db.select(widget.library.db.people).get();
    // Wer könnte das sein? Die Einbettung liegt am Gesicht, die Rechnung
    // gab es längst - sie stand nur in der Sammelzuordnung fest.
    final vorschlag = await widget.library
        .personenvorschlag(face.embedding, ausser: face.personId);
    if (!mounted) return;
    final currentName = face.personId != null ? _personNames[face.personId] : null;
    final choice = await showPersonPickerDialog(
      context,
      people,
      suggestedPerson: vorschlag,
      paths: widget.library.paths,
      title: currentName != null
          ? AppTexte.of(context).gesichtUmbenennen
          : AppTexte.of(context).gesichtBenennen,
      currentName: currentName,
      // Nur für noch namenlose Gesichter: Ein bereits benanntes beiseite-
      // zulegen hiesse, die Person still aus dem Foto zu entfernen – das
      // gehört nicht hinter dieselbe Schaltfläche.
      erlaubtIgnorieren: face.personId == null,
    );
    if (choice == null) return;

    if (choice.ignorieren) {
      await widget.library.db.setFacesIgnored([face.id], true);
      _load();
      return;
    }

    String personId;
    if (choice.newName != null) {
      personId = const Uuid().v4();
      await widget.library.db.createPerson(PeopleCompanion.insert(id: personId, name: choice.newName!));
    } else {
      personId = choice.existingPersonId!;
    }
    await widget.library.db.assignFacesToPerson([face.id], personId);
    _load();
  }

  /// Das Kontextmenü (Rechtsklick). [face] ist gesetzt, wenn auf einen
  /// Rahmen geklickt wurde, sonst wurde daneben geklickt.
  ///
  /// Dass es hier eines gibt, ist kein Beiwerk: Dies ist der Bildschirm, auf
  /// dem man unter „Personen" tatsächlich arbeitet. Bisher führte jede
  /// Handlung über einen Linksklick, der immer denselben Dialog öffnete –
  /// wer ein Fehlerkennung nur wegräumen wollte, musste erst den
  /// Namensdialog aufmachen.
  Future<void> _kontextmenue(Offset position, FaceData? face) async {
    final t = AppTexte.of(context);
    final wo = Overlay.of(context).context.findRenderObject() as RenderBox;
    final unbenannte = _faces.where((f) => f.personId == null && !f.isIgnored).length;

    final wahl = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(position & Size.zero, Offset.zero & wo.size),
      items: [
        if (face != null) ...[
          if (!face.isIgnored)
            PopupMenuItem(
              value: 'benennen',
              child: _eintrag(
                  Icons.person_add_alt_1,
                  face.personId != null
                      ? t.gesichtUmbenennen
                      : t.gesichtBenennen),
            ),
          if (face.personId != null)
            PopupMenuItem(
              value: 'loesen',
              child: _eintrag(Icons.person_off_outlined, t.gesichtZuordnungLoesen),
            ),
          PopupMenuItem(
            value: face.isIgnored ? 'zurueck' : 'ignorieren',
            child: _eintrag(
                face.isIgnored ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                face.isIgnored ? t.gesichtNichtMehrIgnorieren : t.gesichtIgnorieren),
          ),
          PopupMenuItem(
            value: 'loeschen',
            child: _eintrag(Icons.delete_outline, t.gesichtErkennungLoeschen),
          ),
          const PopupMenuDivider(),
        ],
        // Auch hier, nicht nur in der Titelleiste: Sind die Rahmen weg,
        // sucht man den Weg zurück dort, wo man gerade hinsieht.
        PopupMenuItem(
          value: 'rahmen',
          child: _eintrag(
              _rahmenSichtbar ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              _rahmenSichtbar ? t.gesichtRahmenAusblenden : t.gesichtRahmenEinblenden),
        ),
        PopupMenuItem(
          value: 'hinzufuegen',
          child: _eintrag(Icons.add_a_photo_outlined, t.gesichtManuellHinzufuegen),
        ),
        PopupMenuItem(
          value: 'alleIgnorieren',
          enabled: unbenannte > 0,
          child: _eintrag(Icons.visibility_off_outlined,
              t.gesichtAlleUnbenanntenIgnorieren(unbenannte)),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'info',
          child: _eintrag(Icons.info_outline, t.viewerInfo),
        ),
        // Das Foto selbst, nicht eine Erkennung darauf – deshalb unten und
        // hinter einem Trenner: Die Einträge darüber ändern nur, was über
        // dem Bild liegt.
        PopupMenuItem(
          value: 'nichtMehrSuchen',
          child: _eintrag(
              _asset.faceScanExcluded
                  ? Icons.person_search_outlined
                  : Icons.search_off_outlined,
              _asset.faceScanExcluded
                  ? t.gesichtWiederDurchsuchen
                  : t.gesichtNichtMehrDurchsuchen),
        ),
        PopupMenuItem(
          value: 'fotoLoeschen',
          child: _eintrag(Icons.delete_outline, t.gesichtFotoLoeschen),
        ),
      ],
    );
    if (!mounted || wahl == null) return;

    switch (wahl) {
      case 'benennen':
        await _tapFace(face!);
      case 'loesen':
        await widget.library.db.loeseZuordnung(face!.id);
        _load();
      case 'ignorieren':
        await widget.library.db.setFacesIgnored([face!.id], true);
        _load();
      case 'zurueck':
        await widget.library.db.setFacesIgnored([face!.id], false);
        _load();
      case 'loeschen':
        await widget.library.loescheGesicht(face!.id);
        _load();
      case 'rahmen':
        setState(() => _rahmenSichtbar = !_rahmenSichtbar);
      case 'hinzufuegen':
        setState(() {
          _addMode = true;
          _dragStart = null;
          _dragCurrent = null;
        });
      case 'alleIgnorieren':
        await widget.library.db.setFacesIgnored(
          [for (final f in _faces) if (f.personId == null && !f.isIgnored) f.id],
          true,
        );
        _load();
      case 'info':
        setState(() => _infoSichtbar = true);
      case 'nichtMehrSuchen':
        _durchsuchenUmschalten();
      case 'fotoLoeschen':
        await _loescheFoto();
    }
  }

  /// Verschiebt das gerade gezeigte Foto in den Papierkorb.
  ///
  /// Danach wird nicht geschlossen, sondern weitergeblättert: Wer eine
  /// Reihe durchsieht und dabei aussortiert, will an derselben Stelle
  /// weitermachen. Erst wenn das letzte Foto der Reihe weg ist, geht der
  /// Bildschirm zu.
  /// Favorit umschalten – dieselbe Rolle wie im grossen Betrachter.
  ///
  /// Beim Sichten der Gesichter sieht man das Foto oft zum ersten Mal in
  /// Ruhe; wer dann merkt, dass es ein gutes ist, sollte es hier festhalten
  /// können statt es sich zu merken.
  Future<void> _favoritUmschalten() async {
    final neuerWert = !_asset.isFavorite;
    await widget.library.db.setFavorite(_asset.id, neuerWert);
    if (!mounted) return;
    // Die Zeile in der eigenen Liste nachziehen: Sie stammt aus dem
    // aufrufenden Bildschirm und weiss von der Änderung nichts.
    setState(() => _assets[_index] = _asset.copyWith(isFavorite: neuerWert));
    melde.erfolg(neuerWert
        ? AppTexte.of(context).gesichtFavoritGesetzt
        : AppTexte.of(context).gesichtFavoritEntfernt);
  }

  /// Das Foto in den gesperrten Ordner legen.
  ///
  /// **Danach ist es hier nicht mehr zu sehen**, und das ist kein
  /// Nebeneffekt, sondern der Zweck: Die Gesichter-Sichtung zeigt
  /// gesperrte Fotos nicht. Die Ansicht verlässt das Bild deshalb sofort –
  /// so wie der grosse Betrachter es auch tut.
  Future<void> _inGesperrtenOrdner() async {
    if (!await ensureVaultUnlocked(context, widget.library)) return;
    if (!mounted) return;
    final t = AppTexte.of(context);
    try {
      await widget.library.lockAsset(_asset);
    } catch (e) {
      if (mounted) melde.fehler(t.gesichtSperrenFehlgeschlagen);
      return;
    }
    if (!mounted) return;
    melde.erfolg(t.gesichtInGesperrtemOrdner);
    if (_assets.length == 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _assets.removeAt(_index);
      if (_index >= _assets.length) _index = _assets.length - 1;
      _faces = [];
      _aspectRatio = null;
      _addMode = false;
      _dragStart = null;
      _dragCurrent = null;
    });
    _load();
  }

  /// Dieses Foto von der Gesichtssuche ausnehmen – oder zurückholen.
  ///
  /// **Gedacht für Bilder, auf denen jeder Durchlauf neue „Gesichter"
  /// findet:** eine Gemäldewand, ein Zeitungsfoto, ein Plakat. Ein
  /// einzelnes Gesicht beiseitezulegen half dort nicht, weil beim
  /// nächsten Durchlauf andere Stellen erkannt wurden.
  ///
  /// Bereits erkannte Gesichter bleiben stehen – die Ausnahme gilt dem
  /// Suchen, nicht dem Gefundenen.
  Future<void> _durchsuchenUmschalten() async {
    final neuerWert = !_asset.faceScanExcluded;
    await widget.library.db
        .setzeGesichtssucheAusgenommen(_asset.id, neuerWert);
    if (!mounted) return;
    setState(() =>
        _assets[_index] = _asset.copyWith(faceScanExcluded: neuerWert));
    melde.erfolg(neuerWert
        ? AppTexte.of(context).gesichtNichtMehrDurchsuchtHinweis
        : AppTexte.of(context).gesichtWiederDurchsuchtHinweis);
  }

  Future<void> _loescheFoto() async {
    final t = AppTexte.of(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(t.loeschenTitel(1)),
        content: Text(t.loeschenHinweis(1)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(t.allgAbbrechen)),
          FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(t.allgLoeschen)),
        ],
      ),
    );
    if (ja != true || !mounted) return;

    await widget.library.db.moveToTrash([_asset.id]);
    if (!mounted) return;
    if (_assets.length == 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _assets.removeAt(_index);
      // Am Ende der Reihe eins zurück, sonst bleibt der Index stehen und
      // zeigt damit von selbst auf das nachgerückte Foto.
      if (_index >= _assets.length) _index = _assets.length - 1;
      _faces = [];
      _aspectRatio = null;
      _addMode = false;
      _dragStart = null;
      _dragCurrent = null;
    });
    _load();
  }

  /// Eine Menüzeile. Der Text ist [Flexible], weil ein Popup-Menü seine
  /// Breite begrenzt und eine feste Zeile sonst überläuft – genau das
  /// passierte beim längsten Eintrag.
  Widget _eintrag(IconData icon, String text) => Row(children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Flexible(child: Text(text)),
      ]);

  Future<void> _finishManualBox(Rect normalizedRect) async {
    final people = await widget.library.db.select(widget.library.db.people).get();
    if (!mounted) return;
    // Kein Vorschlag: Der Rahmen ist gerade erst aufgezogen, eine
    // Einbettung dazu gibt es noch nicht. Sie entsteht weiter unten.
    final choice = await showPersonPickerDialog(context, people,
        paths: widget.library.paths, title: AppTexte.of(context).gesichtNeuBenennen);
    if (choice == null) return;

    String personId;
    if (choice.newName != null) {
      personId = const Uuid().v4();
      await widget.library.db.createPerson(PeopleCompanion.insert(id: personId, name: choice.newName!));
    } else {
      personId = choice.existingPersonId!;
    }

    // Ausschnitt, Einbettung und Zeile entstehen an einer Stelle - die
    // Vollbildansicht kann dasselbe und darf keinen zweiten Weg dafür haben.
    await gesichtVonHandAnlegen(
      library: widget.library,
      assetId: _asset.id,
      bilddatei: _displayFile,
      kasten: normalizedRect,
      personId: personId,
      beiEinbettungsfehler: (e) {
        if (mounted) melde.fehler(AppTexte.of(context).gesichtEmbeddingFehler('$e'));
      },
    );

    if (!mounted) return;
    setState(() {
      _addMode = false;
      _dragStart = null;
      _dragCurrent = null;
    });
    _load();
  }

  /// Titelleiste, für beide Zustände (gesperrt und normal) dieselbe – nur
  /// so bleiben die Pfeile beim Blättern an ihrem Platz, auch wenn
  /// zwischendurch ein gesperrtes Foto in der Reihe liegt.
  PreferredSizeWidget _leiste(BuildContext context, {required bool gesperrt}) {
    final mehrere = _assets.length > 1;
    return AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Row(
        children: [
          Flexible(
            child: Text(_asset.originalFileName, overflow: TextOverflow.ellipsis),
          ),
          if (mehrere) ...[
            const SizedBox(width: 12),
            Text(
              AppTexte.of(context).gesichtPosition(_index + 1, _assets.length),
              style: const TextStyle(color: DunkleFlaeche.hinweis, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        if (mehrere) ...[
          IconButton(
            tooltip: AppTexte.of(context).gesichtVoriges,
            icon: const Icon(Icons.chevron_left),
            onPressed: _index > 0 ? () => _springe(-1) : null,
          ),
          IconButton(
            tooltip: AppTexte.of(context).gesichtNaechstes,
            icon: const Icon(Icons.chevron_right),
            onPressed: _index < _assets.length - 1 ? () => _springe(1) : null,
          ),
        ],
        if (!gesperrt)
          IconButton(
            tooltip: _rahmenSichtbar
                ? AppTexte.of(context).gesichtRahmenAusblenden
                : AppTexte.of(context).gesichtRahmenEinblenden,
            icon: Icon(_rahmenSichtbar
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _rahmenSichtbar = !_rahmenSichtbar),
          ),
        if (!gesperrt)
          IconButton(
            tooltip: _addMode
                ? AppTexte.of(context).gesichtHinzufuegenBeenden
                : AppTexte.of(context).gesichtManuellHinzufuegen,
            icon: Icon(_addMode ? Icons.close : Icons.add_a_photo_outlined),
            onPressed: () => setState(() {
              _addMode = !_addMode;
              _dragStart = null;
              _dragCurrent = null;
            }),
          ),
        // Bei gesperrtem Foto bleiben beide weg. Die Info-Ansicht ist
        // nicht bloß Text: Sie zeigt in der Personen-Zeile die
        // Gesichts-Ausschnitte AUS DIESEM FOTO – bei einem gesperrten Bild
        // wäre genau das ein Blick auf den verborgenen Inhalt.
        if (!gesperrt) ...[
          IconButton(
            tooltip: _asset.isFavorite
                ? AppTexte.of(context).viewerFavoritEntfernen
                : AppTexte.of(context).viewerFavoritSetzen,
            icon: Icon(_asset.isFavorite
                ? Icons.favorite
                : Icons.favorite_border),
            onPressed: _favoritUmschalten,
          ),
          IconButton(
            tooltip: AppTexte.of(context).viewerInGesperrtenOrdner,
            icon: const Icon(Icons.lock_outline),
            onPressed: _inGesperrtenOrdner,
          ),
          IconButton(
            tooltip: AppTexte.of(context).viewerInfo,
            icon: Icon(_infoSichtbar ? Icons.info : Icons.info_outline),
            onPressed: () => setState(() => _infoSichtbar = !_infoSichtbar),
          ),
          IconButton(
            tooltip: AppTexte.of(context).gesichtFotoLoeschen,
            icon: const Icon(Icons.delete_outline),
            onPressed: _loescheFoto,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Der Fokus sitzt aussen um beide Zustände, damit die Pfeiltasten auch
    // dann weiterblättern, wenn gerade ein gesperrtes Foto angezeigt wird.
    return Focus(
      autofocus: true,
      onKeyEvent: _taste,
      child: _asset.isLocked ? _gesperrt(context) : _inhalt(context),
    );
  }

  Widget _gesperrt(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _leiste(context, gesperrt: true),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Text(
            AppTexte.of(context).gesichtGesperrt,
            style: const TextStyle(color: DunkleFlaeche.zweitText),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _inhalt(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _leiste(context, gesperrt: false),
      // Foto links, Info rechts daneben – dieselbe Aufteilung wie in der
      // Vollbildansicht (siehe AssetViewerScreen), damit die Info-Ansicht
      // an beiden Stellen gleich aussieht und gleich breit ist.
      body: Row(
        children: [
          Expanded(child: _fotoFlaeche(context)),
          if (_infoSichtbar) ...[
            const VerticalDivider(width: 1, color: Colors.white24),
            SizedBox(
              width: 340,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: AssetInfoSheet(
                  // Ohne den Schlüssel behielte die Info-Ansicht beim
                  // Weiterblättern den Zustand des vorigen Fotos.
                  key: ValueKey(_asset.id),
                  asset: _asset,
                  db: widget.library.db,
                  paths: widget.library.paths,
                  onUpdated: (aktualisiert) =>
                      setState(() => _assets[_index] = aktualisiert),
                  onClose: () => setState(() => _infoSichtbar = false),
                ),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: _addMode
          ? Container(
              color: Colors.black87,
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                AppTexte.of(context).gesichtRechteckHinweis,
                style: const TextStyle(color: DunkleFlaeche.zweitText),
                textAlign: TextAlign.center,
              ),
            )
          : null,
    );
  }

  Widget _fotoFlaeche(BuildContext context) {
    return _loading || _aspectRatio == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: AspectRatio(
                aspectRatio: _aspectRatio!,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final h = constraints.maxHeight;
                    return GestureDetector(
                      // Rechtsklick auf die freie Fläche. Liegt auf
                      // derselben Geste wie das Aufziehen, damit beides
                      // dieselbe Fläche abdeckt.
                      onSecondaryTapDown: (d) => _kontextmenue(d.globalPosition, null),
                      onPanStart: _addMode ? (d) => setState(() {
                            _dragStart = d.localPosition;
                            _dragCurrent = d.localPosition;
                          }) : null,
                      onPanUpdate: _addMode ? (d) => setState(() => _dragCurrent = d.localPosition) : null,
                      onPanEnd: _addMode
                          ? (_) {
                              if (_dragStart == null || _dragCurrent == null) return;
                              final rect = Rect.fromPoints(_dragStart!, _dragCurrent!);
                              if (rect.width < 10 || rect.height < 10) {
                                setState(() {
                                  _dragStart = null;
                                  _dragCurrent = null;
                                });
                                return;
                              }
                              final normalized = Rect.fromLTWH(
                                (rect.left / w).clamp(0.0, 1.0),
                                (rect.top / h).clamp(0.0, 1.0),
                                (rect.width / w).clamp(0.0, 1.0),
                                (rect.height / h).clamp(0.0, 1.0),
                              );
                              _finishManualBox(normalized);
                            }
                          : null,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            _displayFile,
                            fit: BoxFit.fill,
                            // Nur so gross dekodieren, wie es angezeigt wird.
                            // Dieser Bildschirm kann nicht zoomen (anders als
                            // der Vollbildbetrachter, wo die volle Auflösung
                            // gebraucht wird) – ein 48-Megapixel-Foto voll zu
                            // dekodieren kostet 183 MB statt 22 MB, gemessen.
                            // Beim Durchblättern summiert sich das über den
                            // Bildcache.
                            // In Stufen (siehe [dekodierbreite]): Diese
                            // Ansicht zeigt die volle Vorschau, und ihre
                            // Breite hängt am Fenster. Ohne die Stufen
                            // wird beim Ziehen am Rand bei jedem
                            // Zwischenschritt neu dekodiert – hier ist
                            // das kein Vorschaubild, sondern das grosse.
                            cacheWidth: dekodierbreite(
                                w, MediaQuery.devicePixelRatioOf(context)),
                          ),
                          if (_rahmenSichtbar)
                            for (final face in _faces)
                              Gesichtsrahmen(
                                gesicht: face,
                                personName: _personNames[face.personId],
                                flaeche: Size(w, h),
                                beiTipp: () => _tapFace(face),
                                beiMenue: (stelle) => _kontextmenue(stelle, face),
                              ),
                          if (_addMode && _dragStart != null && _dragCurrent != null)
                            Positioned.fromRect(
                              rect: Rect.fromPoints(_dragStart!, _dragCurrent!),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.cyanAccent, width: 2),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            );
  }
}
