import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_localizations.dart';
import '../services/meldungsdienst.dart';
import '../state/library_state.dart';
import 'person_picker_dialog.dart';

/// Was sich an einem Gesicht und an den Gesichtern eines Fotos tun lässt.
///
/// **Warum das an einer Stelle steht** (#495). Die Einträge gab es nur im
/// Rechtsklick-Menü der Gesichts-Bearbeitung. Wer beim Ansehen eines Fotos
/// ein Plakatgesicht wegräumen oder das Foto von der Suche ausnehmen
/// wollte, musste dorthin wechseln, dasselbe Foto dort noch einmal laden
/// und danach zurück. Jetzt zeigen das Vollbild und die
/// Gesichts-Bearbeitung dieselben Einträge aus dieser Datei – zwei
/// Fassungen liefen sonst auseinander, wie es die Rahmen schon einmal
/// taten (siehe `Gesichtsrahmen`).
enum Gesichtswahl {
  /// Benennen, oder eine andere Person zuordnen.
  benennen,

  /// Die Person vom Gesicht lösen; das Gesicht bleibt.
  loesen,

  /// Beiseitelegen – „kein Gesicht“ oder „interessiert mich nicht“.
  ignorieren,

  /// Ein beiseitegelegtes Gesicht wieder berücksichtigen.
  zurueckholen,

  /// Die Erkennung samt Ausschnitt löschen.
  loeschen,

  /// Alle unbenannten Gesichter des Fotos beiseitelegen.
  alleIgnorieren,

  /// Alle unbenannten Erkennungen des Fotos löschen (#192).
  alleLoeschen,

  /// Das Foto von der Gesichtssuche ausnehmen oder zurückholen.
  durchsuchen,
}

MenuItemButton _punkt(
  Gesichtswahl wahl,
  IconData symbol,
  String text,
  void Function(Gesichtswahl) waehle, {
  bool an = true,
}) => MenuItemButton(
  leadingIcon: Icon(symbol, size: 20),
  onPressed: an ? () => waehle(wahl) : null,
  child: Text(text),
);

/// Die Einträge für das eine Gesicht, auf das geklickt wurde.
List<Widget> gesichtsEintraege(
  AppTexte t,
  FaceData gesicht,
  void Function(Gesichtswahl) waehle,
) => [
  if (!gesicht.isIgnored)
    _punkt(
      Gesichtswahl.benennen,
      Icons.person_add_alt_1,
      gesicht.personId != null ? t.gesichtUmbenennen : t.gesichtBenennen,
      waehle,
    ),
  if (gesicht.personId != null)
    _punkt(
      Gesichtswahl.loesen,
      Icons.person_off_outlined,
      t.gesichtZuordnungLoesen,
      waehle,
    ),
  gesicht.isIgnored
      ? _punkt(
          Gesichtswahl.zurueckholen,
          Icons.visibility_outlined,
          t.gesichtNichtMehrIgnorieren,
          waehle,
        )
      : _punkt(
          Gesichtswahl.ignorieren,
          Icons.visibility_off_outlined,
          t.gesichtIgnorieren,
          waehle,
        ),
  _punkt(
    Gesichtswahl.loeschen,
    Icons.delete_outline,
    t.gesichtErkennungLoeschen,
    waehle,
  ),
];

/// Die beiden Einträge für alle unbenannten Gesichter von [gesichter].
///
/// Löschen trifft auch die beiseitegelegten – wie „Alle unbenannten
/// Erkennungen löschen“ bei den Personen. Ohne passende Gesichter sind die
/// Einträge ausgegraut statt weg: So sieht man, dass es sie gibt.
List<Widget> unbenannteEintraege(
  AppTexte t,
  List<FaceData> gesichter,
  void Function(Gesichtswahl) waehle,
) {
  final offen = gesichter
      .where((f) => f.personId == null && !f.isIgnored)
      .length;
  final unbenannt = gesichter.where((f) => f.personId == null).length;
  return [
    _punkt(
      Gesichtswahl.alleIgnorieren,
      Icons.visibility_off_outlined,
      t.gesichtAlleUnbenanntenIgnorieren(offen),
      waehle,
      an: offen > 0,
    ),
    _punkt(
      Gesichtswahl.alleLoeschen,
      Icons.delete_sweep_outlined,
      t.gesichtAlleUnbenanntenLoeschen(unbenannt),
      waehle,
      an: unbenannt > 0,
    ),
  ];
}

/// Der Eintrag, der [asset] von der Gesichtssuche ausnimmt oder es
/// zurückholt.
Widget durchsuchenEintrag(
  AppTexte t,
  AssetData asset,
  void Function(Gesichtswahl) waehle,
) => _punkt(
  Gesichtswahl.durchsuchen,
  asset.faceScanExcluded
      ? Icons.person_search_outlined
      : Icons.search_off_outlined,
  asset.faceScanExcluded
      ? t.gesichtWiederDurchsuchen
      : t.gesichtNichtMehrDurchsuchen,
  waehle,
);

/// Führt [wahl] aus und liefert, ob sich etwas geändert hat – dann lädt
/// der Aufrufer die Gesichter (und bei [Gesichtswahl.durchsuchen] die
/// Aufnahme) neu.
///
/// [gesicht] ist für die Einträge aus [gesichtsEintraege] gesetzt,
/// [gesichter] sind alle Gesichter von [asset] für die Sammeleinträge.
Future<bool> fuehreGesichtswahlAus(
  BuildContext context, {
  required LibraryState library,
  required Gesichtswahl wahl,
  required AssetData asset,
  required List<FaceData> gesichter,
  FaceData? gesicht,
  String? aktuellerName,
}) async {
  final db = library.db;
  switch (wahl) {
    case Gesichtswahl.benennen:
      return gesichtBenennen(
        context,
        db: db,
        paths: library.paths,
        library: library,
        gesicht: gesicht!,
        aktuellerName: aktuellerName,
      );
    case Gesichtswahl.loesen:
      await db.fuehreAus(ZuordnungLoesen(gesicht!.id));
    case Gesichtswahl.ignorieren:
      await db.fuehreAus(GesichterBeiseitelegen([gesicht!.id], true));
    case Gesichtswahl.zurueckholen:
      await db.fuehreAus(GesichterBeiseitelegen([gesicht!.id], false));
    case Gesichtswahl.loeschen:
      await library.loescheGesicht(gesicht!.id);
    case Gesichtswahl.alleIgnorieren:
      final ids = [
        for (final f in gesichter)
          if (f.personId == null && !f.isIgnored) f.id,
      ];
      if (ids.isEmpty) return false;
      await db.fuehreAus(GesichterBeiseitelegen(ids, true));
    case Gesichtswahl.alleLoeschen:
      return _unbenannteLoeschen(context, library, gesichter);
    case Gesichtswahl.durchsuchen:
      await _durchsuchenUmschalten(context, db, asset);
  }
  return true;
}

/// Fragt, wer [gesicht] ist, und ordnet es zu – oder legt es beiseite,
/// wenn es noch keinen Namen hat.
///
/// [library] liefert den Vorschlag der Wiedererkennung; ohne sie gibt es
/// keinen (das Vollbild läuft auch ohne Bibliothek). [aktuellerName] ist
/// der Name, den das Gesicht schon trägt.
Future<bool> gesichtBenennen(
  BuildContext context, {
  required AppDatabase db,
  required StoragePaths paths,
  required FaceData gesicht,
  LibraryState? library,
  String? aktuellerName,
  String? titel,
}) async {
  final personen = await db.select(db.people).get();
  // Wer könnte das sein? Die Einbettung liegt am Gesicht.
  final vorschlag = await library?.personenvorschlag(
    gesicht.embedding,
    ausser: gesicht.personId,
  );
  if (!context.mounted) return false;
  final t = AppTexte.of(context);
  final wahl = await showPersonPickerDialog(
    context,
    personen,
    paths: paths,
    suggestedPerson: vorschlag,
    title:
        titel ??
        (aktuellerName != null ? t.gesichtUmbenennen : t.gesichtBenennen),
    currentName: aktuellerName,
    // Nur für noch namenlose Gesichter: Ein bereits benanntes beiseite-
    // zulegen hiesse, die Person still aus dem Foto zu entfernen – das
    // gehört nicht hinter dieselbe Schaltfläche.
    erlaubtIgnorieren: gesicht.personId == null,
  );
  if (wahl == null) return false;
  if (wahl.ignorieren) {
    await db.fuehreAus(GesichterBeiseitelegen([gesicht.id], true));
    return true;
  }
  final id = wahl.newName != null ? const Uuid().v4() : wahl.existingPersonId!;
  if (wahl.newName != null) {
    await db.fuehreAus(PersonAnlegen(id, wahl.newName!));
  }
  await db.fuehreAus(GesichterZuordnen([gesicht.id], id));
  return true;
}

/// Ein beiseitegelegtes Gesicht wieder berücksichtigen, nach einem Tipp
/// darauf.
///
/// Ein beiseitegelegtes Gesicht anzutippen heisst „doch nicht“ – dafür
/// braucht es keinen Dialog mit Namensfeld, der nur den einen Fall
/// verdeckte, den der Nutzer hier will.
Future<void> gesichtZurueckholen(
  BuildContext context,
  AppDatabase db,
  FaceData gesicht,
) async {
  final t = AppTexte.of(context);
  await db.fuehreAus(GesichterBeiseitelegen([gesicht.id], false));
  melde.erfolg(t.gesichtZurueckgeholt);
}

/// Die unbenannten Erkennungen eines Fotos auf einmal löschen (#192) –
/// für ein Bild, auf dem die Erkennung lauter Fehlgriffe gefunden hat.
Future<bool> _unbenannteLoeschen(
  BuildContext context,
  LibraryState library,
  List<FaceData> gesichter,
) async {
  final t = AppTexte.of(context);
  final ids = [
    for (final f in gesichter)
      if (f.personId == null) f.id,
  ];
  if (ids.isEmpty) return false;
  final ja = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      content: Text(t.gesichtUnbenannteLoeschenFrage(ids.length)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: Text(t.allgAbbrechen),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: Text(t.allgLoeschen),
        ),
      ],
    ),
  );
  if (ja != true) return false;
  await library.loescheGesichter(ids);
  return true;
}

/// Dieses Foto von der Gesichtssuche ausnehmen – oder zurückholen.
///
/// **Gedacht für Bilder, auf denen jeder Durchlauf neue „Gesichter“
/// findet:** eine Gemäldewand, ein Zeitungsfoto, ein Plakat. Ein
/// einzelnes Gesicht beiseitezulegen half dort nicht, weil beim nächsten
/// Durchlauf andere Stellen erkannt wurden.
///
/// Bereits erkannte Gesichter bleiben stehen – die Ausnahme gilt dem
/// Suchen, nicht dem Gefundenen.
Future<void> _durchsuchenUmschalten(
  BuildContext context,
  AppDatabase db,
  AssetData asset,
) async {
  final t = AppTexte.of(context);
  final neuerWert = !asset.faceScanExcluded;
  await db.fuehreAus(GesichtssucheAusnehmen(asset.id, neuerWert));
  melde.erfolg(
    neuerWert
        ? t.gesichtNichtMehrDurchsuchtHinweis
        : t.gesichtWiederDurchsuchtHinweis,
  );
}
