import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/baumnavigation.dart';
import '../services/stammbaum.dart';
import '../services/verwandtschaftsgrad.dart';
import '../services/verwandte_anlegen.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../services/faechertafel.dart';
import '../services/familienorte.dart';
import '../services/familienstatistik.dart';
import '../services/fotostatistik.dart';
import '../services/gedcom_export.dart';
import '../services/gedcom_import.dart';
import '../services/lebenslauf.dart';
import '../services/zeitleiste.dart';
import '../services/tafel_pdf.dart';
import '../services/sanduhr.dart';
import '../widgets/faecher_ansicht.dart';
import '../widgets/familien_zeitleiste.dart';
import '../widgets/person_picker_dialog.dart';
import '../widgets/sanduhr_ansicht.dart';
import '../services/zierbaum.dart';
import '../theme/zierbaum_farben.dart';
import '../widgets/verwandtschaft_text.dart';
import '../widgets/zoomsteuerung.dart';
import '../widgets/zierbaum_ansicht.dart';
import '../widgets/zierbaum_maler.dart';
import 'familienfotos_screen.dart';
import 'familienorte_screen.dart';
import 'familienstatistik_screen.dart';
import 'lebenslauf_screen.dart';
import 'person_detail_screen.dart';
import '../services/meldungsdienst.dart';
import '../widgets/profilbild.dart';

/// Der Stammbaum um eine Person herum.
///
/// Gezeigt wird immer nur die unmittelbare Verwandtschaft: Eltern darüber,
/// Kinder darunter, Geschwister und Partner daneben. Großeltern und Enkel
/// fehlen mit Absicht – für sie ließe sich in einer gemeinsamen Reihe keine
/// Linie zeichnen, die stimmt (welcher Großelternteil zu welchem Elternteil
/// gehört, ginge verloren). Sie sind einen Klick entfernt: Wer auf eine
/// Karte tippt, rückt sie in die Mitte. Ein kleines Zeichen an der Karte
/// sagt vorher, ob dort etwas wartet.
/// Die beiden Sichten auf dieselbe Familie.
/// Wie eine Karte zur Person in der Mitte steht – nicht die Art der
/// gespeicherten Kante, sondern die Stelle im Bild.
///
/// Die Art selbst wird daraus im Netz nachgeschlagen (siehe
/// [_StammbaumScreenState._artFuer]); die Reihe kennt sie nicht.
enum _Bezug {
  /// Die Karte steht in der Elternreihe.
  elternteil,

  /// Die Karte steht in der Kinderreihe.
  kind,

  /// Die Karte steht in der Partnergruppe.
  partner,

  /// Geschwister und die Person in der Mitte selbst: Zwischen ihnen und
  /// der Mitte steht keine eigene Kante, die man lösen könnte.
  keiner,
}

enum _Ansicht {
  /// Der Baum: unmittelbare Verwandtschaft, räumlich angeordnet.
  baum,

  /// Der Fächer: bis zu vier Generationen Vorfahren als Ringe. Die
  /// gewählte Baumoptik – sie kann als einzige mehrere Generationen
  /// zeigen, ohne dass eine Linie mehrdeutig wird.
  faecher,

  /// Die Sanduhr: Vorfahren und Nachkommen über mehrere Generationen in
  /// einem Bild.
  sanduhr,

  /// Die Nachfahren als eingerückte Gliederung – die Gegenrichtung zum
  /// Fächer, der nur nach oben zeigen kann.
  nachfahren,

  /// Die Liste: **alle** Verwandten mit ihrer Bezeichnung, von den
  /// nächsten zu den entferntesten. Erst hier tauchen die Bezeichnungen
  /// auf, für die im Baum kein Platz ist – Urgroßvater, Cousine zweiten
  /// Grades, Schwägerin.
  liste,

  /// Die Zeitleiste: eine Zeile je Person auf einer gemeinsamen Achse.
  /// Die einzige Ansicht, die **Gleichzeitigkeit** zeigt – wer sich
  /// überlappte, wer sich um wenige Jahre verpasst hat.
  zeitleiste,
}

class StammbaumScreen extends StatefulWidget {
  final LibraryState library;

  /// Wer in der Mitte steht. `null`, wenn der Bildschirm über den
  /// Menüpunkt geöffnet wird und noch niemand gewählt ist – dann sucht er
  /// sich selbst eine Person aus (siehe [_StammbaumScreenState._startperson]).
  final String? startPersonId;

  const StammbaumScreen({
    super.key,
    required this.library,
    this.startPersonId,
  });

  @override
  State<StammbaumScreen> createState() => _StammbaumScreenState();
}

class _StammbaumScreenState extends State<StammbaumScreen> {
  String? _fokusId;
  _Ansicht _ansicht = _Ansicht.baum;

  /// Ob der gemerkte Stand schon eingelesen wurde.
  ///
  /// Das Lesen aus der Datenbank braucht einen Augenblick; wer in diesem
  /// Augenblick schon auf eine andere Ansicht tippt, soll seine Wahl
  /// behalten und nicht von der gemerkten überfahren werden.
  bool _standGelesen = false;

  /// Ob die Sanduhr die Seitenlinie mitzeigt – Geschwister, deren Kinder
  /// und die angeheirateten daneben.
  bool _seitenlinien = true;

  /// Ob der Baum die Seitenäste mitzeigt.
  ///
  /// Aus als Vorgabe, anders als bei der Sanduhr: Der Baum ist die
  /// Ansicht, die man aufschlägt, um die gerade Linie zu sehen. Wer die
  /// Verwandtschaft in der Breite sucht, schaltet sie dazu – und dann
  /// wird es merklich breiter.

  List<PersonData> _personen = [];
  Map<String, PersonData> _nachId = {};
  Verwandtschaftsnetz _netz = Verwandtschaftsnetz(const []);

  /// Die Bezeichnung jeder verwandten Person, bezogen auf [_fokusId].
  /// Einmal je Fokuswechsel gerechnet statt je Karte – für die Liste
  /// braucht es ohnehin alle.
  Map<String, Grad> _grade = const {};

  /// Alle Lebensereignisse, nach Person geordnet – nur die Zeitleiste
  /// braucht sie, und die braucht sie für Dutzende Personen zugleich.
  Map<String, List<LebensereignisseData>> _ereignisse = const {};
  bool _laedt = true;

  /// Der Weg, den man sich durch den Baum genommen hat – damit der
  /// Zurück-Pfeil in den vorigen Ausschnitt führt und nicht gleich aus dem
  /// Stammbaum heraus.
  final List<String> _pfad = [];

  /// Der Ausschnitt des Zierbaums: was verschoben und wie weit gezoomt
  /// ist. Liegt hier und nicht in der Ansicht, weil die Zoomknöpfe
  /// daneben stehen und ein Fokuswechsel ihn zurücksetzen muss.
  final TransformationController _blick = TransformationController();

  /// Auf welchen Baum der [_blick] eingestellt wurde – Mitte und
  /// Fenstergrösse. Ändert sich eines von beidem, wird neu eingepasst:
  /// Wer eine andere Person in die Mitte rückt, will sie sehen und nicht
  /// den Ausschnitt behalten, in dem sie gerade zufällig lag.
  ({String fokus, Size fenster})? _eingepasstAuf;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  @override
  void dispose() {
    _blick.dispose();
    super.dispose();
  }

  Future<void> _laden() async {
    final personen = widget.library.db.nachAlterSortiert(
        await widget.library.db.select(widget.library.db.people).get());
    final zeilen = await widget.library.db.alleBeziehungen();
    final ereignisse = await widget.library.db.alleEreignisse();
    final zuletzt = await widget.library.db.stammbaumZuletzt();
    if (!mounted) return;
    final nachPerson = <String, List<LebensereignisseData>>{};
    for (final e in ereignisse) {
      nachPerson.putIfAbsent(e.personId, () => []).add(e);
    }
    final netz = Verwandtschaftsnetz([
      for (final z in zeilen)
        if (artAusText(z.art) case final art?) kante(z.personId, z.andereId, art),
    ]);
    final vorhanden = {for (final p in personen) p.id};
    setState(() {
      _personen = personen;
      _nachId = {for (final p in personen) p.id: p};
      _netz = netz;
      _ereignisse = nachPerson;
      if (!_standGelesen) {
        _standGelesen = true;
        // Eine Ansicht, die es nicht mehr gibt, und eine Person, die
        // geloescht wurde, fallen still auf die bisherige Wahl zurueck.
        final gemerkt = _ansichtAusText(zuletzt.ansicht);
        if (gemerkt != null) _ansicht = gemerkt;
        final person = zuletzt.person;
        _fokusId ??= widget.startPersonId ??
            (person != null && vorhanden.contains(person) ? person : null) ??
            _startperson(personen, netz);
      } else {
        _fokusId ??= widget.startPersonId ?? _startperson(personen, netz);
      }
      _laedt = false;
    });
    _rechneGrade();
    _merken();
  }

  /// Haelt Ansicht und Person fest – aufgerufen bei jedem Wechsel.
  ///
  /// Ohne `await`: Wer durch den Baum klickt, soll nicht auf die Platte
  /// warten. Faellt der Schreibvorgang aus, ist der Preis, dass der Baum
  /// beim naechsten Mal eine Person zu frueh anfaengt.
  void _merken() {
    if (!_standGelesen) return;
    unawaited(widget.library.db
        .setzeStammbaumZuletzt(ansicht: _ansicht.name, person: _fokusId));
  }

  static _Ansicht? _ansichtAusText(String? text) {
    for (final a in _Ansicht.values) {
      if (a.name == text) return a;
    }
    return null;
  }

  /// Wen der Bildschirm zeigt, wenn er ohne Vorgabe geöffnet wird.
  ///
  /// Die Person mit den meisten eingetragenen Verwandten – dort ist am
  /// meisten zu sehen. Die erste Person der Liste wäre die schlechtere
  /// Wahl: Das ist die älteste oder alphabetisch erste, und die steht
  /// typischerweise am Rand des Baums, nicht in seiner Mitte.
  String? _startperson(List<PersonData> personen, Verwandtschaftsnetz netz) {
    if (personen.isEmpty) return null;
    var beste = personen.first;
    var meiste = -1;
    for (final p in personen) {
      final anzahl = netz.eltern(p.id).length +
          netz.kinder(p.id).length +
          netz.partner(p.id).length;
      if (anzahl > meiste) {
        meiste = anzahl;
        beste = p;
      }
    }
    return beste.id;
  }

  void _rechneGrade() {
    final fokus = _fokusId;
    if (fokus == null) return;
    setState(() {
      _grade = alleGrade(_netz, fokus, [for (final p in _personen) p.id]);
      _rangImBaum = {
        for (var i = 0; i < _personen.length; i++) _personen[i].id: i
      };
    });
  }

  /// Die Bezeichnung einer Person, bezogen auf die Person in der Mitte.
  ///
  /// Für alles, wofür die Sprache ein Wort hat, ist das dieses Wort. Für
  /// den Rest – die Eltern des Schwagers, die Geschwister der Schwägerin –
  /// wird der Weg dorthin beschrieben ([umwegZu]). „Angeheiratet" bleibt
  /// nur, wo auch das nicht trägt.
  String? _bezeichnung(PersonData person) {
    final grad = _grade[person.id];
    if (grad == null) return null;
    if (grad.art == Gradart.angeheiratet) {
      final umweg = umwegZu(_netz, _fokusId!, person.id,
          reihenfolge: (id) => _rangImBaum[id] ?? 1 << 30);
      if (umweg != null) {
        final zwischen = _nachId[umweg.ueber];
        if (zwischen != null) {
          return verwandtschaftUeberWegText(
            context,
            umweg,
            zwischen.name,
            geschlecht: geschlechtAusText(person.geschlecht),
            geschlechtZwischen: geschlechtAusText(zwischen.geschlecht),
          );
        }
      }
    }
    return verwandtschaftText(
        context, grad, geschlechtAusText(person.geschlecht));
  }

  /// Der Platz jeder Person in der ohnehin geführten Reihenfolge
  /// (Geburtsdatum, dann Name).
  ///
  /// Gebraucht, damit [umwegZu] bei zwei gleich guten Wegen immer
  /// denselben wählt – sonst hiesse dieselbe Person bei jedem Aufbau
  /// anders, und das fiele als Flackern auf, nicht als Fehler.
  Map<String, int> _rangImBaum = const {};

  void _ruecke(String id) {
    if (id == _fokusId) return;
    setState(() {
      _pfad.add(_fokusId!);
      _fokusId = id;
    });
    _rechneGrade();
    _merken();
  }

  bool _zurueck() {
    if (_pfad.isEmpty) return false;
    setState(() => _fokusId = _pfad.removeLast());
    _rechneGrade();
    _merken();
    return true;
  }

  /// Fragt nach einer Person und trägt sie als [art] ein.
  ///
  /// [umgekehrt] dreht die Richtung: Ein Kind ist keine eigene Art, sondern
  /// dieselbe Elternkante von der anderen Seite gelesen. Ohne diesen
  /// Schalter bräuchte es eine zweite Art, die dasselbe bedeutet – und
  /// zwei Schreibweisen für einen Sachverhalt laufen früher oder später
  /// auseinander.
  Future<void> _hinzufuegen(Verwandtschaft art, {bool umgekehrt = false}) async {
    final fokusId = _fokusId;
    if (fokusId == null) return;
    final t = AppTexte.of(context);
    final titel = art == Verwandtschaft.partner
        ? t.stammbaumPartnerHinzufuegen
        : umgekehrt
            ? t.stammbaumKindHinzufuegen
            : t.stammbaumElternteilHinzufuegen;
    final wahl = await showPersonPickerDialog(
      context,
      // Die Person in der Mitte steht nicht zur Auswahl – mit sich selbst
      // verwandt zu sein wäre der einzige Fehler, den dieser Dialog
      // überhaupt anbieten könnte.
      _personen.where((p) => p.id != fokusId).toList(),
      paths: widget.library.paths,
      title: titel,
    );
    if (wahl == null || !mounted) return;

    String andereId;
    if (wahl.newName != null) {
      andereId = const Uuid().v4();
      await widget.library.db.createPerson(
        PeopleCompanion.insert(id: andereId, name: wahl.newName!),
      );
    } else {
      andereId = wahl.existingPersonId!;
    }

    final fehler = umgekehrt
        ? await widget.library.db.fuegeBeziehungHinzu(andereId, fokusId, art)
        : await widget.library.db.fuegeBeziehungHinzu(fokusId, andereId, art);
    await _laden();
    if (fehler != null && mounted) _meldeFehler(fehler);
  }

  /// Legt einen Verwandten an, der nicht unmittelbar an der Person in der
  /// Mitte hängt – einen Neffen, eine Großtante, ein Schwiegerkind.
  ///
  /// Gespeichert werden weiterhin nur Eltern, Kinder und Partner; alles
  /// andere ist ausgerechnet (siehe verwandtschaftsgrad.dart). Dieser Weg
  /// ist deshalb keine neue Kantenart, sondern eine Abkürzung: Er hängt
  /// die neue Person an der Stelle ein, an der ihre Bezeichnung hinterher
  /// stimmt – nachgerechnet in verwandte_anlegen.dart.
  Future<void> _verwandtenHinzufuegen() async {
    final fokusId = _fokusId;
    final fokus = _nachId[fokusId];
    if (fokusId == null || fokus == null) return;
    final t = AppTexte.of(context);

    final grad = await _gradWaehlen(fokus);
    if (grad == null || !mounted) return;

    final rang = {for (var i = 0; i < _personen.length; i++) _personen[i].id: i};
    final wege = wegeFuer(_netz, fokusId, grad,
        reihenfolge: (id) => rang[id] ?? 1 << 30);
    if (wege.isEmpty) {
      _kurzerHinweis(_fehltText(t, fehlendeVoraussetzung(grad), fokus.name));
      return;
    }

    // Bei genau einem Weg gibt es nichts zu fragen.
    final weg = wege.length == 1
        ? wege.first
        : await _wegWaehlen(wege, t.stammbaumUeberWen(_gradName(t, grad)));
    if (weg == null || !mounted) return;

    final wahl = await showPersonPickerDialog(
      context,
      // Weder die Mitte noch die Anker stehen zur Auswahl: Beides wäre
      // ein Kreis oder eine Verwandtschaft mit sich selbst.
      _personen
          .where((p) => p.id != fokusId && !weg.anker.contains(p.id))
          .toList(),
      paths: widget.library.paths,
      title: _gradName(t, grad),
    );
    if (wahl == null || !mounted) return;

    String neueId;
    if (wahl.newName != null) {
      neueId = const Uuid().v4();
      await widget.library.db.createPerson(
        PeopleCompanion.insert(id: neueId, name: wahl.newName!),
      );
    } else {
      neueId = wahl.existingPersonId!;
    }

    final fehler = await widget.library.db
        .fuegeBeziehungenHinzu(kantenFuer(weg, neueId));
    await _laden();
    if (!mounted) return;
    if (fehler != null) {
      _meldeFehler(fehler);
      return;
    }
    // Ein Neffe taucht im Ausschnitt um die Mitte gar nicht auf – ohne
    // Rückmeldung sähe es aus, als sei nichts geschehen. Genannt wird die
    // AUSGERECHNETE Bezeichnung, nicht die gewählte: Sie ist die Probe
    // darauf, dass die Person an der richtigen Stelle hängt.
    final person = _nachId[neueId];
    final gerechnet = _grade[neueId];
    if (person != null && gerechnet != null) {
      _kurzerHinweis(t.stammbaumVerwandterEingetragen(
        person.name,
        verwandtschaftText(
            context, gerechnet, geschlechtAusText(person.geschlecht)),
      ));
    }
  }

  /// Der Wähler für den Verwandtschaftsgrad.
  ///
  /// Alle Grade stehen immer da, auch die gerade nicht eintragbaren – nur
  /// grau und mit dem Grund darunter. Sie auszublenden hiesse, dem Nutzer
  /// zu verschweigen, dass es sie gibt; so lernt er nebenbei, welche
  /// Zwischenperson noch fehlt.
  Future<Zusatzgrad?> _gradWaehlen(PersonData fokus) async {
    final t = AppTexte.of(context);
    final fokusId = fokus.id;
    final gruppen = <String, List<Zusatzgrad>>{
      t.stammbaumGruppeVorfahren: [
        Zusatzgrad.grosselternteil,
        Zusatzgrad.urgrosselternteil,
      ],
      t.stammbaumGruppeNachkommen: [
        Zusatzgrad.enkelkind,
        Zusatzgrad.urenkelkind,
      ],
      t.stammbaumGruppeSeitenlinie: [
        Zusatzgrad.geschwisterkind,
        Zusatzgrad.halbgeschwisterkind,
        Zusatzgrad.onkelTante,
        Zusatzgrad.neffeNichte,
        Zusatzgrad.cousin,
      ],
      t.stammbaumGruppeAngeheiratet: [
        Zusatzgrad.schwiegerelternteil,
        Zusatzgrad.schwiegerkind,
        Zusatzgrad.schwager,
        Zusatzgrad.stiefelternteil,
        Zusatzgrad.stiefkind,
      ],
    };

    return showDialog<Zusatzgrad>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(t.stammbaumVerwandtenHinzufuegen),
        content: SizedBox(
          width: 420,
          // Aus dem Fenster abgeleitet statt fest: Die Liste ist mit
          // Überschriften rund 700 Punkte hoch. Auf einem gewöhnlichen
          // Bildschirm steht sie damit vollständig da; erst auf einem
          // kleinen muss gerollt werden.
          height: math.min(MediaQuery.of(dialog).size.height * 0.62, 720),
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  t.stammbaumNurEintragbares(fokus.name),
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(dialog).colorScheme.onSurfaceVariant),
                ),
              ),
              for (final eintrag in gruppen.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      0, AppSpacing.md, 0, AppSpacing.xs),
                  child: Text(
                    eintrag.key,
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.1,
                      color: Theme.of(dialog).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final grad in eintrag.value)
                  _gradZeile(dialog, grad, fokus, fokusId),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(t.allgAbbrechen)),
        ],
      ),
    );
  }

  Widget _gradZeile(
      BuildContext dialog, Zusatzgrad grad, PersonData fokus, String fokusId) {
    final t = AppTexte.of(dialog);
    final moeglich = wegeFuer(_netz, fokusId, grad).isNotEmpty;
    return ListTile(
      dense: true,
      enabled: moeglich,
      title: Text(_gradName(t, grad)),
      subtitle: moeglich
          ? null
          : Text(_fehltText(t, fehlendeVoraussetzung(grad), fokus.name),
              style: const TextStyle(fontSize: 11)),
      onTap: moeglich ? () => Navigator.pop(dialog, grad) : null,
    );
  }

  String _gradName(AppTexte t, Zusatzgrad grad) => switch (grad) {
        Zusatzgrad.grosselternteil => t.stammbaumGradGrosselternteil,
        Zusatzgrad.urgrosselternteil => t.stammbaumGradUrgrosselternteil,
        Zusatzgrad.enkelkind => t.stammbaumGradEnkelkind,
        Zusatzgrad.urenkelkind => t.stammbaumGradUrenkelkind,
        Zusatzgrad.geschwisterkind => t.stammbaumGradGeschwisterkind,
        Zusatzgrad.halbgeschwisterkind => t.stammbaumGradHalbgeschwisterkind,
        Zusatzgrad.onkelTante => t.stammbaumGradOnkelTante,
        Zusatzgrad.neffeNichte => t.stammbaumGradNeffeNichte,
        Zusatzgrad.cousin => t.stammbaumGradCousin,
        Zusatzgrad.schwiegerelternteil => t.stammbaumGradSchwiegerelternteil,
        Zusatzgrad.schwiegerkind => t.stammbaumGradSchwiegerkind,
        Zusatzgrad.schwager => t.stammbaumGradSchwager,
        Zusatzgrad.stiefelternteil => t.stammbaumGradStiefelternteil,
        Zusatzgrad.stiefkind => t.stammbaumGradStiefkind,
      };

  String _fehltText(AppTexte t, Fehlt fehlt, String name) => switch (fehlt) {
        Fehlt.elternteil => t.stammbaumFehltElternteil(name),
        Fehlt.grosselternteil => t.stammbaumFehltGrosselternteil(name),
        Fehlt.kind => t.stammbaumFehltKind(name),
        Fehlt.enkelkind => t.stammbaumFehltEnkelkind(name),
        Fehlt.geschwister => t.stammbaumFehltGeschwister(name),
        Fehlt.onkelTante => t.stammbaumFehltOnkelTante(name),
        Fehlt.partner => t.stammbaumFehltPartner(name),
        Fehlt.geschwisterOderPartner =>
          t.stammbaumFehltGeschwisterOderPartner(name),
      };

  /// Ein kurzer Hinweis am unteren Rand – für die Fälle, in denen der
  /// Wunsch verständlich, aber (noch) nicht ausführbar ist.
  void _kurzerHinweis(String text) {
    melde.hinweis(text);
  }

  /// Fragt, über welche Bezugsperson die neue eingehängt werden soll.
  ///
  /// Jede Zeile nennt neben dem Namen die Bezeichnung dieser Person – bei
  /// „Schwager" stehen Geschwister und Partner nebeneinander in der Liste,
  /// und erst die Bezeichnung macht die beiden Lesarten unterscheidbar.
  Future<Einhaengeweg?> _wegWaehlen(
      List<Einhaengeweg> wege, String titel) async {
    return showDialog<Einhaengeweg>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: Text(titel),
        children: [
          for (final weg in wege)
            if (_nachId[weg.bezugsperson] case final p?)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog, weg),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Profilbild(
                    datei: p.coverFaceCropPath == null
                        ? null
                        : widget.library.paths
                            .absolute(p.coverFaceCropPath!),
                    radius: 18,
                    symbolgroesse: 18,
                  ),
                  title: Text(p.name),
                  subtitle:
                      _bezeichnung(p) == null ? null : Text(_bezeichnung(p)!),
                ),
              ),
        ],
      ),
    );
  }

  void _meldeFehler(Beziehungsfehler fehler) {
    final t = AppTexte.of(context);
    melde.warnung(switch (fehler) {
          Beziehungsfehler.mitSichSelbst => t.stammbaumFehlerSelbst,
          Beziehungsfehler.kreis => t.stammbaumFehlerKreis,
          Beziehungsfehler.schonVorhanden => t.stammbaumFehlerVorhanden,
        });
  }

  /// Das Menü einer Karte. [art] und [umgekehrt] beschreiben, wie die
  /// Person zur Mitte steht – nur dann lässt sich die Verbindung wieder
  /// lösen. Bei Geschwistern ist beides null: Sie hängen nicht an einer
  /// eigenen Kante, sondern an den gemeinsamen Eltern.
  Future<void> _karteMenue(
    Offset position,
    PersonData person, {
    Verwandtschaft? art,
    bool umgekehrt = false,
  }) async {
    final t = AppTexte.of(context);
    final wo = Overlay.of(context).context.findRenderObject() as RenderBox;
    final wahl = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(position & Size.zero, Offset.zero & wo.size),
      items: [
        if (person.id != _fokusId)
          PopupMenuItem(
            value: 'mitte',
            child: _zeile(Icons.center_focus_strong_outlined, t.stammbaumInDieMitte),
          ),
        PopupMenuItem(
          value: 'lebensdaten',
          child: _zeile(Icons.event_outlined, t.stammbaumLebensdaten),
        ),
        PopupMenuItem(
          value: 'lebenslauf',
          child: _zeile(Icons.timeline_outlined, t.stammbaumLebenslauf),
        ),
        PopupMenuItem(
          value: 'fotos',
          child: _zeile(Icons.photo_library_outlined, t.stammbaumFotosZeigen),
        ),
        if (art != null) ...[
          const PopupMenuDivider(),
          // Nur für Elternverbindungen: Zwischen Partnern gibt es keine
          // Arten, und zwischen Geschwistern keine eigene Kante.
          if (istElternArt(art))
            PopupMenuItem(
              value: 'art',
              child: _zeile(Icons.swap_horiz, t.stammbaumVerbindungsart),
            ),
          PopupMenuItem(
            value: 'loesen',
            child: _zeile(Icons.link_off, t.stammbaumVerbindungEntfernen),
          ),
        ],
      ],
    );
    if (!mounted || wahl == null) return;
    switch (wahl) {
      case 'mitte':
        _ruecke(person.id);
      case 'lebensdaten':
        await _lebensdatenBearbeiten(person);
      case 'lebenslauf':
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => LebenslaufScreen(library: widget.library, person: person),
        ));
      case 'fotos':
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PersonDetailScreen(library: widget.library, person: person),
        ));
        await _laden();
      case 'art':
        await _verbindungsartAendern(person, art!, umgekehrt);
      case 'loesen':
        await _verbindungLoesen(person, art!, umgekehrt);
    }
  }

  /// Ändert eine bestehende Elternverbindung zwischen „leiblich",
  /// „Adoptiv" und „Pflege".
  ///
  /// Bisher blieb nur, die Verbindung zu lösen und neu zu legen – und wer
  /// das tat, verlor dabei nichts, musste aber die Person im Wähler erneut
  /// suchen. Die Art ist eine Eigenschaft der Verbindung; sie zu ändern
  /// sollte die Verbindung nicht antasten.
  Future<void> _verbindungsartAendern(
      PersonData person, Verwandtschaft art, bool umgekehrt) async {
    final fokusId = _fokusId;
    if (fokusId == null) return;
    // Wer ist hier das Kind? In der Elternreihe die Mitte, in der
    // Kinderreihe die angeklickte Person.
    final kindId = umgekehrt ? person.id : fokusId;
    final elternteilId = umgekehrt ? fokusId : person.id;
    final t = AppTexte.of(context);

    final neueArt = await showDialog<Verwandtschaft>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(t.stammbaumVerbindungsartTitel(
          _nachId[kindId]?.name ?? '',
          _nachId[elternteilId]?.name ?? '',
        )),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (kandidat, symbol, text) in [
              (Verwandtschaft.elternteil, Icons.person_outline, t.stammbaumLeiblich),
              (Verwandtschaft.adoptivelternteil, Icons.family_restroom, t.stammbaumAdoptiv),
              (
                Verwandtschaft.pflegeelternteil,
                Icons.volunteer_activism_outlined,
                t.stammbaumPflege
              ),
            ])
              ListTile(
                leading: Icon(symbol),
                title: Text(text),
                selected: kandidat == art,
                // Ein Haken statt eines Auswahlknopfes: Die Liste hat drei
                // Einträge, jeder schliesst den Dialog sofort. Ein
                // Auswahlknopf verspräche ein späteres „Übernehmen", das es
                // hier nicht gibt.
                trailing: kandidat == art ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(dialog, kandidat),
              ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              t.stammbaumVerbindungsartHinweis,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(t.allgAbbrechen)),
        ],
      ),
    );
    if (neueArt == null || neueArt == art) return;
    await widget.library.db.aendereElternart(kindId, elternteilId, neueArt);
    await _laden();
  }

  Future<void> _verbindungLoesen(
      PersonData person, Verwandtschaft art, bool umgekehrt) async {
    final t = AppTexte.of(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(t.stammbaumVerbindungEntfernen),
        content: Text(t.stammbaumVerbindungEntfernenFrage(
            person.name, _nachId[_fokusId]?.name ?? '')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(t.allgAbbrechen)),
          FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(t.allgEntfernen)),
        ],
      ),
    );
    if (ja != true) return;
    final fokusId = _fokusId!;
    final entfernt = umgekehrt
        ? await widget.library.db.entferneBeziehung(person.id, fokusId, art)
        : await widget.library.db.entferneBeziehung(fokusId, person.id, art);
    await _laden();
    // Ein Griff ins Leere soll nicht als Erfolg aussehen. Genau das war
    // der Fehler bei Adoptiv- und Pflegeeltern: Es passierte nichts, und
    // nichts sagte es.
    if (!entfernt && mounted) {
      melde.warnung(t.stammbaumNichtsEntfernt);
    }
  }

  Future<void> _lebensdatenBearbeiten(PersonData person) async {
    final ergebnis =
        await showDialog<({DateTime? geburt, DateTime? tod, Geschlecht? geschlecht})>(
      context: context,
      builder: (_) => _LebensdatenDialog(person: person),
    );
    if (ergebnis == null) return;
    await widget.library.db.setzeLebensdaten(person.id,
        geburt: ergebnis.geburt, tod: ergebnis.tod);
    await widget.library.db.setzeGeschlecht(person.id, ergebnis.geschlecht);
    await _laden();
  }

  /// Wechselt die Person in der Mitte über die bekannte Personenauswahl.
  ///
  /// Ein neuer Name ist dort erlaubt und legt die Person an – so lässt
  /// sich ein Stammbaum auch dann beginnen, wenn noch niemand benannt ist.
  Future<void> _waehlePerson() async {
    final wahl = await showPersonPickerDialog(
      context,
      _personen,
      paths: widget.library.paths,
      title: AppTexte.of(context).stammbaumAndereWaehlen,
    );
    if (wahl == null || !mounted) return;
    if (wahl.newName != null) {
      final id = const Uuid().v4();
      await widget.library.db
          .createPerson(PeopleCompanion.insert(id: id, name: wahl.newName!));
      if (!mounted) return;
      setState(() => _fokusId = id);
      await _laden();
      return;
    }
    _ruecke(wahl.existingPersonId!);
  }

  /// Öffnet alle Fotos, auf denen jemand aus dieser Familie zu sehen ist.
  ///
  /// Die Funktion, die diese App von einem Ahnenprogramm unterscheidet:
  /// Die Gesichter sind bereits Personen zugeordnet, die Verwandtschaft
  /// steht daneben – es fehlte nur die Abfrage, die beides verbindet.
  Future<void> _fotosDerFamilie() async {
    final fokus = _fokusId;
    if (fokus == null) return;
    final t = AppTexte.of(context);
    // Die Person selbst gehört dazu, sonst fehlten ausgerechnet ihre
    // eigenen Fotos.
    final ids = [fokus, ..._grade.keys];
    final assets = await widget.library.db.assetsFuerPersonen(ids);
    if (!mounted) return;
    if (assets.isEmpty) {
      melde.hinweis(t.stammbaumKeineFamilienfotos);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FamilienfotosScreen(
        library: widget.library,
        titel: t.stammbaumFamilienfotosVon(_nachId[fokus]?.name ?? ''),
        assets: assets,
      ),
    ));
  }

  /// Zeigt die Fotos der Familie auf einer Karte, eingefärbt nach
  /// Verwandtschaftsrichtung.
  Future<void> _orteDerFamilie() async {
    final fokus = _fokusId;
    if (fokus == null) return;
    final t = AppTexte.of(context);
    final personen = [fokus, ..._grade.keys];
    final roh = await widget.library.db.verorteteAssetsFuerPersonen(personen);
    // Lebensereignisse gehören auf dieselbe Karte: Wo jemand gelebt hat,
    // ist dieselbe Frage wie, wo fotografiert wurde – nur aus der
    // anderen Quelle.
    final ereignisse =
        await widget.library.db.verorteteEreignisseFuerPersonen(personen);
    if (!mounted) return;
    final orte = <Familienort>[
      for (final e in roh)
        if (gruppeFuerFoto(e.personen, _grade, fokus: fokus) case final g?)
          (asset: e.asset, gruppe: g),
    ];
    // Erst wenn BEIDES leer ist, gibt es nichts zu zeigen. Ein Stammbaum
    // kann verortete Ereignisse haben, ohne dass ein Foto verortet wäre.
    if (orte.isEmpty && ereignisse.isEmpty) {
      melde.hinweis(t.stammbaumKeineFamilienorte);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FamilienorteScreen(
        library: widget.library,
        titel: t.stammbaumFamilienorteVon(_nachId[fokus]?.name ?? ''),
        orte: orte,
        ereignisse: ereignisse,
      ),
    ));
  }

  /// Zahlen über die Familie – siehe [FamilienstatistikScreen].
  ///
  /// Gerechnet wird hier und nicht dort: Die Angaben liegen in diesem
  /// Bildschirm bereits vollständig vor, und der Statistikbildschirm
  /// bekommt ein fertiges Ergebnis statt einer zweiten Datenquelle.
  Future<void> _familienstatistik() async {
    final fokus = _fokusId;
    if (fokus == null) return;
    final ids = {fokus, ..._grade.keys};

    // Die Bilder kommen aus der Datenbank und nicht aus diesem
    // Bildschirm: Gesichter stehen hier nicht herum, und sie für alle
    // Ansichten mitzuladen hiesse, sie fast immer umsonst zu laden.
    final auftritte = await widget.library.db.auftritteFuerPersonen(ids);
    if (!mounted) return;
    final statistik = familienstatistik(
      personen: [
        for (final p in _personen)
          if (ids.contains(p.id))
            (
              id: p.id,
              name: p.name,
              geschlecht: geschlechtAusText(p.geschlecht),
              geburt: p.geburtsdatum,
              tod: p.sterbedatum,
            ),
      ],
      netz: _netz,
      fokus: fokus,
      ereignisse: [
        for (final id in ids)
          for (final e in _ereignisse[id] ?? const [])
            (
              personId: id,
              art: ereignisartAusText(e.art),
              datum: e.datum,
            ),
      ],
    );
    final bilder = fotostatistik(
      auftritte: auftritte,
      betrachtet: ids,
      geburt: {
        for (final p in _personen)
          if (ids.contains(p.id)) p.id: p.geburtsdatum,
      },
    );
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FamilienstatistikScreen(
        statistik: statistik,
        fokusName: _nachId[fokus]?.name ?? '',
        foto: bilder,
        namen: {
          for (final p in _personen)
            if (ids.contains(p.id)) p.id: p.name,
        },
      ),
    ));
  }

  /// Schreibt den Fächer als PDF – die Tafel zum Aufhängen.
  ///
  /// Gezeichnet wird mit **derselben** Routine wie auf dem Bildschirm,
  /// nur auf eine viel größere Leinwand; das Ergebnis wandert als Bild in
  /// die Seite. Die Alternative – den Fächer ein zweites Mal mit den
  /// Zeichenbefehlen der PDF-Bibliothek zu bauen – hätte zwei
  /// Darstellungen ergeben, die auseinanderlaufen können.
  Future<void> _tafelDrucken() async {
    final fokus = _fokusId;
    if (fokus == null) return;
    final t = AppTexte.of(context);
    final rang = {for (var i = 0; i < _personen.length; i++) _personen[i].id: i};
    final plaetze = faechertafel(_netz, fokus, (id) => rang[id] ?? 1 << 30);

    final ziel = await FilePicker.platform.saveFile(
      dialogTitle: t.stammbaumTafelDrucken,
      fileName: tafelDateiname,
      type: FileType.custom,
      allowedExtensions: const [tafelEndungOhnePunkt],
    );
    if (ziel == null || !mounted) return;

    final bytes = await baueTafelPdf(
      plaetze: plaetze,
      personen: _nachId,
      titel: _nachId[fokus]?.name ?? '',
      farben: Theme.of(context).colorScheme,
      textRichtung: Directionality.of(context),
    );
    await File(mitTafelEndung(ziel)).writeAsBytes(bytes);
    if (!mounted) return;
    melde.erfolg(t.stammbaumTafelFertig);
  }

  /// Schreibt den Zierbaum als PDF – das Blatt an die Wand.
  ///
  /// Dieselbe Zeichenroutine wie auf dem Bildschirm, nur dreifach so
  /// gross. Ohne Porträts: Auf dem Blatt gibt es nichts anzutippen, und
  /// eine Zeichnung wartet nicht darauf, dass Bilder geladen sind.
  Future<void> _zierbaumDrucken() async {
    final fokus = _fokusId;
    if (fokus == null) return;
    final t = AppTexte.of(context);
    final geflecht =
        geflechtUm(_netz, fokus, [for (final p in _personen) p.id]);
    final farben = Zierbaumfarben.fuer(Theme.of(context).brightness);
    final richtung = Directionality.of(context);
    final name = haeufigsterNachname(
        [for (final id in geflecht.personen) _nachId[id]!.name]);
    Schildinhalt inhalt(String id) {
      final person = _nachId[id]!;
      return Schildinhalt(
        name: person.name,
        verwandtschaft: id == fokus ? null : _bezeichnung(person),
        lebensspanne: lebensspanne(person.geburtsdatum, person.sterbedatum),
      );
    }

    final ziel = await FilePicker.platform.saveFile(
      dialogTitle: t.stammbaumZierbaumDrucken,
      fileName: zierbaumDateiname,
      type: FileType.custom,
      allowedExtensions: const [tafelEndungOhnePunkt],
    );
    if (ziel == null || !mounted) return;

    final bytes = await baueZierbaumPdf(
      geflecht: geflecht,
      beschriftung: inhalt,
      familienname: name,
      farben: farben,
      textRichtung: richtung,
    );
    await File(mitTafelEndung(ziel)).writeAsBytes(bytes);
    if (!mounted) return;
    melde.erfolg(t.stammbaumTafelFertig);
  }

  /// Schreibt den Bestand als GEDCOM-Datei.
  ///
  /// Ohne diesen Weg wären die eingetragenen Verwandtschaften in dieser
  /// App gefangen – Fotos lassen sich immer noch kopieren, ein
  /// Verwandtschaftsnetz nicht.
  Future<void> _gedcomExport() async {
    final t = AppTexte.of(context);
    final ziel = await FilePicker.platform.saveFile(
      dialogTitle: t.stammbaumGedcomExport,
      fileName: gedcomDateiname,
      type: FileType.custom,
      allowedExtensions: const [gedcomEndungOhnePunkt],
    );
    if (ziel == null || !mounted) return;

    final inhalt = schreibeGedcom(
      [
        for (final p in _personen)
          (
            id: p.id,
            name: p.name,
            geschlecht: geschlechtAusText(p.geschlecht),
            geburt: p.geburtsdatum,
            tod: p.sterbedatum,
          ),
      ],
      _netz,
      erzeuger: gedcomErzeuger,
      // Aus dem Paket statt als feste Zeichenkette – sonst stünde in der
      // exportierten Datei irgendwann eine Version, die es nicht gibt.
      version: (await PackageInfo.fromPlatform()).version,
    );
    if (!mounted) return;
    // Ausdrücklich UTF-8: Der Kopf der Datei kündigt es an, und die
    // Standard-Kodierung von `writeAsString` ist es nicht überall.
    await File(mitEndung(ziel)).writeAsString(inhalt, encoding: utf8);
    if (!mounted) return;
    melde.erfolg(t.stammbaumGedcomFertig(_personen.length));
  }

  /// Liest eine GEDCOM-Datei ein – der Weg *hinein*.
  ///
  /// Ausgegeben hat diese App von Anfang an; gelesen hat sie nie. Wer
  /// anderswo geforscht hatte, musste alles von Hand abtippen.
  ///
  /// **Es wird immer neu angelegt, nie zusammengeführt.** Ein Programm,
  /// das selbsttätig entscheidet, welche zwei Großmütter dieselbe sind,
  /// liegt irgendwann falsch – und eine falsch verschmolzene Person ist
  /// nicht mehr zu trennen. Was doppelt aussieht, steht danach im
  /// Bericht und wartet auf eine Entscheidung.
  Future<void> _gedcomImport() async {
    final t = AppTexte.of(context);
    final wahl = await FilePicker.platform.pickFiles(
      dialogTitle: t.stammbaumGedcomImport,
      type: FileType.custom,
      allowedExtensions: const [gedcomEndungOhnePunkt],
    );
    if (wahl == null || wahl.files.isEmpty || !mounted) return;
    final pfad = wahl.files.first.path;
    if (pfad == null) return;

    final GedcomEingelesen gelesen;
    try {
      gelesen = liesGedcom(
        await File(pfad).readAsBytes(),
        // Die Beschriftungen kommen von hier und stehen nicht im Dienst:
        // So bleibt das Einlesen ohne Oberfläche prüfbar, und die Notiz
        // steht trotzdem in der eingestellten Sprache.
        texte: (
          geburtsort: t.gedcomOrtGeburt,
          sterbeort: t.gedcomOrtTod,
          taufe: t.gedcomOrtTaufe,
          bestattung: t.gedcomOrtBestattung,
          ohneNamen: t.gedcomOhneNamen,
        ),
      );
    } on GedcomAbbruchFehler catch (fehler) {
      if (!mounted) return;
      await _gedcomMeldung(t.gedcomFehlerTitel, [
        switch (fehler.grund) {
          GedcomAbbruch.keinKopf => t.gedcomFehlerKeinKopf,
          GedcomAbbruch.keinePersonen => t.gedcomFehlerKeinePersonen,
          GedcomAbbruch.kodierung =>
            t.gedcomFehlerKodierung(fehler.einzelheit ?? '?'),
        },
      ]);
      return;
    }
    if (!mounted) return;

    final ja = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(t.gedcomImportTitel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.gedcomImportGefunden(gelesen.personen.length,
                gelesen.kanten.length, gelesen.anzahlEreignisse)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              t.gedcomImportNeuHinweis,
              style: Theme.of(dialog).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(t.allgAbbrechen)),
          FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(t.gedcomImportUebernehmen)),
        ],
      ),
    );
    if (ja != true || !mounted) return;

    // Gegen den Bestand verglichen wird VOR dem Schreiben – danach
    // stünden die frisch angelegten selbst mit in der Liste und wären
    // ihre eigenen Doppelgänger.
    final verdacht = moeglicheDoppelte(
      [
        for (final p in gelesen.personen)
          (kennung: p.kennung, name: p.name, geburt: p.geburt),
      ],
      [
        for (final p in _personen)
          (kennung: p.id, name: p.name, geburt: p.geburtsdatum),
      ],
    );

    final neueKennung = {
      for (final p in gelesen.personen) p.kennung: const Uuid().v4(),
    };
    await widget.library.db.uebernehmeGedcom(
      personen: [
        for (final p in gelesen.personen)
          PeopleCompanion.insert(
            id: neueKennung[p.kennung]!,
            name: p.name,
            geschlecht: Value(p.geschlecht == null
                ? null
                : geschlechtZuText(p.geschlecht!)),
            geburtsdatum: Value(p.geburt),
            sterbedatum: Value(p.tod),
          ),
      ],
      kanten: mitNeuenKennungen(gelesen.kanten, neueKennung),
      ereignisse: [
        for (final p in gelesen.personen)
          for (final e in p.ereignisse)
            LebensereignisseCompanion.insert(
              id: const Uuid().v4(),
              personId: neueKennung[p.kennung]!,
              art: ereignisartZuText(e.art),
              datum: Value(e.datum),
              ort: Value(e.ort),
              notiz: Value(e.notiz),
            ),
      ],
    );
    // Die eingelesenen Ortsnamen bekommen jetzt ihre Koordinaten – das
    // ist der Grund, warum die Verortung vor dem Einlesen gebaut wurde.
    // Sonst läse man dreihundert Personen ein und sähe davon nichts.
    await widget.library.trageEreignisorteNach();
    await _laden();
    if (!mounted) return;

    final doppelteNamen = {for (final v in verdacht) v.name}.toList()..sort();
    final zuBerichten = <String>[
      if (doppelteNamen.isNotEmpty) ...[
        t.gedcomBerichtDoppelte(doppelteNamen.length),
        _gekuerzt(doppelteNamen),
        t.gedcomBerichtDoppelteHinweis,
      ],
      for (final (art, satz) in [
        (GedcomHinweisart.ungenauesDatum, t.gedcomBerichtUngenaueDaten),
        (GedcomHinweisart.kreisVerhindert, t.gedcomBerichtKreise),
        (GedcomHinweisart.ohneNamen, t.gedcomBerichtOhneNamen),
        (GedcomHinweisart.uebersprungen, t.gedcomBerichtUebersprungen),
      ])
        if (gelesen.hinweiseMit(art) case final anzahl when anzahl > 0)
          satz(anzahl),
    ];
    // Auch wenn nichts auffiel, wird der Bericht gezeigt – und sagt das
    // dann. Ein Fenster, das nur bei Ärger erscheint, lässt im guten Fall
    // offen, ob überhaupt etwas geprüft wurde.
    await _gedcomMeldung(t.gedcomBerichtTitel, [
      t.gedcomImportFertig(gelesen.personen.length),
      if (zuBerichten.isEmpty) t.gedcomBerichtSauber else ...zuBerichten,
    ]);
  }

  /// Eine Aufzählung, die nicht über den Bildschirm hinauswächst.
  static String _gekuerzt(List<String> namen, {int hoechstens = 12}) =>
      namen.length <= hoechstens
          ? namen.join(', ')
          : '${namen.take(hoechstens).join(', ')} …';

  /// Ein Fenster mit mehreren Absätzen, zum Lesen und Wegklicken.
  Future<void> _gedcomMeldung(String titel, List<String> absaetze) =>
      showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(titel),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final a in absaetze)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(a),
                  ),
              ],
            ),
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(dialog),
                child: Text(AppTexte.of(dialog).allgSchliessen)),
          ],
        ),
      );

  /// Der Fächer – siehe [FaecherAnsicht].
  Widget _faecher(BuildContext context, PersonData fokus) {
    final rang = {for (var i = 0; i < _personen.length; i++) _personen[i].id: i};
    final plaetze = faechertafel(
      _netz,
      fokus.id,
      (id) => rang[id] ?? 1 << 30,
    );
    // Nicht "nur ein Platz": Für eine Person ohne Eltern liefert die
    // Tafel zwei leere Elternplätze mit – die Lücke ist gewollt. Leer ist
    // der Fächer erst, wenn außerhalb der Mitte niemand steht.
    if (plaetze.every((p) => p.ring == 0 || p.istLeer)) {
      return _hinweis(context, AppTexte.of(context).stammbaumKeineVorfahren);
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: FaecherAnsicht(
        plaetze: plaetze,
        personen: _nachId,
        onTippen: _ruecke,
      ),
    );
  }

  /// Die Sanduhr – siehe [SanduhrAnsicht].
  Widget _sanduhr(BuildContext context, PersonData fokus) {
    final t = AppTexte.of(context);
    final rang = {for (var i = 0; i < _personen.length; i++) _personen[i].id: i};
    final s = ordneSanduhr(_netz, fokus.id, (id) => rang[id] ?? 1 << 30,
        seitenlinien: _seitenlinien);
    return Column(
      children: [
        // Der Schalter steht über der Zeichnung und nicht in einem Menü:
        // Er verändert, was zu sehen ist, und das gehört neben das
        // Gesehene. Angeschaltet als Vorgabe – eine Familienansicht, die
        // die eigene Schwester weglässt, überrascht mehr als eine, die
        // etwas breiter ist.
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            children: [
              FilterChip(
                selected: _seitenlinien,
                onSelected: (an) => setState(() => _seitenlinien = an),
                avatar: const Icon(Icons.hub_outlined, size: 18),
                label: Text(t.stammbaumSeitenlinien),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  t.stammbaumSeitenlinienHinweis,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: s.knoten.length == 1
              ? _hinweis(context, t.stammbaumLeer)
              : SanduhrAnsicht(
                  sanduhr: s,
                  personen: _nachId,
                  fokusId: fokus.id,
                  onTippen: _ruecke,
                ),
        ),
      ],
    );
  }

  /// Die Nachkommen als eingerückte Gliederung.
  Widget _nachfahrenTafel(BuildContext context, PersonData fokus) {
    final rang = {for (var i = 0; i < _personen.length; i++) _personen[i].id: i};
    final zeilen = nachfahren(_netz, fokus.id, (id) => rang[id] ?? 1 << 30);
    if (zeilen.length == 1) {
      return _hinweis(context, AppTexte.of(context).stammbaumKeineNachfahren);
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: zeilen.length,
      itemBuilder: (context, index) {
        final zeile = zeilen[index];
        final person = _nachId[zeile.personId];
        if (person == null) return const SizedBox.shrink();
        final spanne = lebensspanne(person.geburtsdatum, person.sterbedatum);
        return InkWell(
          onTap: () => _ruecke(person.id),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                AppSpacing.lg + zeile.stufe * 24.0,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.sm),
            child: Row(
              children: [
                // Ein Winkel statt eines Aufzählungspunkts: Er zeigt an,
                // dass die Zeile an der darüber hängt.
                Icon(
                  zeile.stufe == 0
                      ? Icons.person_outline
                      : Icons.subdirectory_arrow_right,
                  size: 16,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  person.name,
                  style: TextStyle(
                    fontWeight:
                        zeile.stufe == 0 ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (spanne != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(spanne,
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _hinweis(BuildContext context, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: SizedBox(
            width: 420,
            child: Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ),
      );

  /// Alle Verwandten mit ihrer Bezeichnung, von den nächsten zu den
  /// entferntesten.
  ///
  /// Der Grund, warum es diese Sicht neben dem Baum gibt: Im Baum steht
  /// nur die unmittelbare Verwandtschaft, dort tauchen „Urgroßvater" oder
  /// „Cousine zweiten Grades" nie auf. Hier schon.
  /// Die Familien-Zeitleiste – siehe [FamilienZeitleiste].
  ///
  /// Gezeigt wird dieselbe Menge wie bei Familienfotos und Familienorten:
  /// die Person in der Mitte und alle, zu denen sich eine Verwandtschaft
  /// ausrechnen lässt. Der ganze Bestand wäre etwas anderes – in einer
  /// Bibliothek mit zweihundert erkannten Gesichtern stünden auf der
  /// Leiste überwiegend Leute, die mit dieser Familie nichts zu tun
  /// haben.
  Widget _zeitleiste(BuildContext context, PersonData fokus) {
    final t = AppTexte.of(context);
    final zeilen = <Zeitzeile>[
      for (final id in [fokus.id, ..._grade.keys])
        if (_nachId[id] case final person?)
          zeitzeile(
            personId: person.id,
            name: person.name,
            geburt: person.geburtsdatum,
            tod: person.sterbedatum,
            ereignisse: [
              for (final e in _ereignisse[person.id] ?? const [])
                (
                  id: e.id,
                  art: ereignisartAusText(e.art),
                  datum: e.datum,
                  ort: e.ort,
                  notiz: e.notiz,
                ),
            ],
          ),
    ];

    // Nicht „keine Verwandten": Eine einzelne Person mit Lebensdaten
    // ergibt sehr wohl eine Leiste. Leer ist sie erst, wenn nirgends ein
    // Datum steht – dann gäbe es keine Achse, auf der etwas läge.
    if (zeilen.every((z) => !z.datiert)) {
      return _hinweis(context, t.stammbaumZeitleisteOhneDaten);
    }

    return FamilienZeitleiste(
      zeilen: zeilen,
      fokusId: fokus.id,
      onTippen: (id) {
        setState(() {
          _fokusId = id;
          _rechneGrade();
        });
        _merken();
      },
      beschriftung: (z) => [
        z.name,
        lebensspanne(z.geburt, z.tod,
                geboren: '${t.stammbaumGeboren} ',
                gestorben: '${t.stammbaumGestorben} ') ??
            t.zeitleisteOhneDatum,
        if (z.marken.isNotEmpty) t.zeitleisteEreignisse(z.marken.length),
      ].join(', '),
    );
  }

  Widget _verwandtenListe(BuildContext context, PersonData fokus) {
    final t = AppTexte.of(context);
    final eintraege = _grade.entries
        .where((e) => _nachId.containsKey(e.key))
        .toList()
      ..sort((a, b) {
        final rang = naeheRang(a.value).compareTo(naeheRang(b.value));
        if (rang != 0) return rang;
        return _nachId[a.key]!.name.toLowerCase().compareTo(
            _nachId[b.key]!.name.toLowerCase());
      });

    if (eintraege.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: SizedBox(
            width: 420,
            child: Text(t.stammbaumLeer, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: eintraege.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
            child: Text(
              t.stammbaumListeKopf(fokus.name, eintraege.length),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          );
        }
        final eintrag = eintraege[index - 1];
        final person = _nachId[eintrag.key]!;
        final spanne = lebensspanne(person.geburtsdatum, person.sterbedatum);
        return ListTile(
          leading: Profilbild(
            datei: person.coverFaceCropPath == null
                ? null
                : widget.library.paths.absolute(person.coverFaceCropPath!),
            radius: 20,
            hintergrund: Theme.of(context).colorScheme.surfaceContainerHigh,
            symbolgroesse: 18,
          ),
          title: Text(person.name),
          // Ueber [_bezeichnung] und nicht ueber verwandtschaftText: Sonst
          // stuende in der Liste weiter "angeheiratet", waehrend im Baum
          // schon der Weg dorthin steht. Zwei Stellen, dieselbe Frage.
          subtitle: Text(
            _bezeichnung(person) ?? '',
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (spanne != null)
                Text(spanne,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12)),
              Builder(
                builder: (knopfKontext) => IconButton(
                  tooltip: t.stammbaumMenue,
                  icon: const Icon(Icons.more_vert),
                  onPressed: () {
                    final kasten =
                        knopfKontext.findRenderObject() as RenderBox;
                    final bezug = _bezugZurMitte(person.id);
                    _karteMenue(
                      kasten.localToGlobal(
                          kasten.size.bottomLeft(Offset.zero)),
                      person,
                      art: _artFuer(person, bezug),
                      umgekehrt: bezug == _Bezug.kind,
                    );
                  },
                ),
              ),
            ],
          ),
          // Kein langes Drücken wie auf einer Karte: Hier steht der Knopf
          // sichtbar daneben, eine zweite verborgene Geste wäre nur eine
          // weitere Möglichkeit, dasselbe zu tun.
          onTap: () => _ruecke(person.id),
        );
      },
    );
  }

  /// Der Knopf zum Hinzufügen eines Elternteils bzw. Kindes.
  ///
  /// Ein Menü statt eines einfachen Knopfes, seit es drei Arten von
  /// Elternschaft gibt. Die Alternative wäre gewesen, nach der Auswahl
  /// der Person noch nach der Art zu fragen – ein zweiter Dialog bei
  /// jedem Eintrag, für eine Angabe, die in den allermeisten Fällen
  /// „leiblich“ lautet.
  Widget _elternMenue(AppTexte t, PersonData? fokus, {required bool umgekehrt}) {
    return PopupMenuButton<Verwandtschaft>(
      tooltip: umgekehrt ? t.stammbaumKindHinzufuegen : t.stammbaumElternteilHinzufuegen,
      icon: Icon(umgekehrt ? Icons.child_care_outlined : Icons.person_add_alt),
      enabled: fokus != null,
      onSelected: (art) => _hinzufuegen(art, umgekehrt: umgekehrt),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: Verwandtschaft.elternteil,
          child: _zeile(Icons.person_outline, t.stammbaumLeiblich),
        ),
        PopupMenuItem(
          value: Verwandtschaft.adoptivelternteil,
          child: _zeile(Icons.family_restroom, t.stammbaumAdoptiv),
        ),
        PopupMenuItem(
          value: Verwandtschaft.pflegeelternteil,
          child: _zeile(Icons.volunteer_activism_outlined, t.stammbaumPflege),
        ),
      ],
    );
  }

  Widget _zeile(IconData icon, String text) => Row(children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Flexible(child: Text(text)),
      ]);

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final fokus = _nachId[_fokusId];
    return PopScope(
      // Der Zurück-Pfeil folgt erst dem eigenen Weg durch den Baum und
      // verlässt den Bildschirm erst, wenn keiner mehr übrig ist.
      canPop: _pfad.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _zurueck();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Flexible(
                child: Text(fokus == null
                    ? t.stammbaumTitel
                    : t.stammbaumTitelVon(fokus.name)),
              ),
              if (fokus != null) ...[
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  tooltip: t.stammbaumAndereWaehlen,
                  icon: const Icon(Icons.swap_horiz, size: 20),
                  onPressed: _waehlePerson,
                ),
              ],
            ],
          ),
          bottom: fokus == null
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(44),
                  // Waagerecht rollbar statt umbrechend: Bei knapp 480
                  // Punkten Fensterbreite brachen die vier Beschriftungen
                  // zweizeilig um, und die Abschnitte bekamen
                  // unterschiedliche Höhen. Lieber eine Zeile, die sich
                  // schieben lässt.
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: SegmentedButton<_Ansicht>(
                      // Ohne Symbole: Vier Abschnitte mit Symbol UND
                      // Beschriftung laufen in einem schmalen Fenster über.
                      segments: [
                        ButtonSegment(
                          value: _Ansicht.baum,
                          label: Text(t.stammbaumAnsichtBaum),
                        ),
                        ButtonSegment(
                          value: _Ansicht.faecher,
                          label: Text(t.stammbaumAnsichtFaecher),
                        ),
                        ButtonSegment(
                          value: _Ansicht.sanduhr,
                          label: Text(t.stammbaumAnsichtSanduhr),
                        ),
                        ButtonSegment(
                          value: _Ansicht.nachfahren,
                          label: Text(t.stammbaumAnsichtNachfahren),
                        ),
                        ButtonSegment(
                          value: _Ansicht.liste,
                          label: Text(t.stammbaumAnsichtListe),
                        ),
                        ButtonSegment(
                          value: _Ansicht.zeitleiste,
                          label: Text(t.stammbaumAnsichtZeitleiste),
                        ),
                      ],
                      selected: {_ansicht},
                      showSelectedIcon: false,
                      onSelectionChanged: (w) {
                        setState(() => _ansicht = w.first);
                        _merken();
                      },
                    ),
                  ),
                ),
          actions: [
            _elternMenue(t, fokus, umgekehrt: false),
            IconButton(
              tooltip: t.stammbaumPartnerHinzufuegen,
              icon: const Icon(Icons.favorite_border),
              onPressed: fokus == null ? null : () => _hinzufuegen(Verwandtschaft.partner),
            ),
            _elternMenue(t, fokus, umgekehrt: true),
            PopupMenuButton<String>(
              tooltip: t.allgMehr,
              onSelected: (w) => switch (w) {
                'verwandter' => _verwandtenHinzufuegen(),
                'fotos' => _fotosDerFamilie(),
                'orte' => _orteDerFamilie(),
                'statistik' => _familienstatistik(),
                'tafel' => _tafelDrucken(),
                'zierbaum' => _zierbaumDrucken(),
                'gedcom' => _gedcomExport(),
                _ => _gedcomImport(),
              },
              itemBuilder: (context) => [
                // Verwandte, die nicht unmittelbar an der Mitte hängen.
                // Die Knöpfe daneben legen Eltern, Kinder und Partner an –
                // das sind die Kanten, die es wirklich gibt. Was hier
                // steht, hängt die neue Person an einer Zwischenperson ein.
                PopupMenuItem(
                  enabled: false,
                  height: 32,
                  child: Text(
                    t.stammbaumWeitereVerwandte,
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.1,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: 'verwandter',
                  enabled: fokus != null,
                  child: _zeile(
                      Icons.diversity_1_outlined, t.stammbaumVerwandtenHinzufuegen),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'fotos',
                  enabled: fokus != null,
                  child: _zeile(Icons.photo_library_outlined, t.stammbaumFamilienfotos),
                ),
                PopupMenuItem(
                  value: 'orte',
                  enabled: fokus != null,
                  child: _zeile(Icons.map_outlined, t.stammbaumFamilienorte),
                ),
                PopupMenuItem(
                  value: 'statistik',
                  enabled: fokus != null,
                  child: _zeile(
                      Icons.bar_chart_outlined, t.stammbaumFamilienstatistik),
                ),
                PopupMenuItem(
                  value: 'tafel',
                  enabled: fokus != null,
                  child: _zeile(Icons.print_outlined, t.stammbaumTafelDrucken),
                ),
                PopupMenuItem(
                  value: 'zierbaum',
                  enabled: fokus != null,
                  child: _zeile(
                      Icons.park_outlined, t.stammbaumZierbaumDrucken),
                ),
                PopupMenuItem(
                  value: 'gedcom',
                  enabled: _personen.isNotEmpty,
                  child: _zeile(Icons.ios_share, t.stammbaumGedcomExport),
                ),
                // Ohne Bedingung: Der Eingang ist gerade dann gefragt,
                // wenn noch niemand eingetragen ist.
                PopupMenuItem(
                  value: 'gedcom_import',
                  child: _zeile(
                      Icons.file_download_outlined, t.stammbaumGedcomImport),
                ),
              ],
            ),
          ],
        ),
        body: _laedt
            ? const Center(child: CircularProgressIndicator())
            : fokus == null
                ? Center(child: Text(_personen.isEmpty
                    ? t.stammbaumKeinePersonen
                    : t.stammbaumPersonFehlt))
                : switch (_ansicht) {
                    _Ansicht.baum => _baum(context, fokus),
                    _Ansicht.faecher => _faecher(context, fokus),
                    _Ansicht.sanduhr => _sanduhr(context, fokus),
                    _Ansicht.nachfahren => _nachfahrenTafel(context, fokus),
                    _Ansicht.liste => _verwandtenListe(context, fokus),
                    _Ansicht.zeitleiste => _zeitleiste(context, fokus),
                  },
      ),
    );
  }

  /// Der Zierbaum.
  ///
  /// **Er ersetzt die Kartenreihen, er steht nicht daneben.** Die Reihen
  /// stellten die Verwandtschaft nach Rolle auf und konnten damit die
  /// Frage nicht beantworten, um die es geht: zu WELCHER Schwester ein
  /// Schwager gehört. Zwei Bäume nebeneinander wären zwei Orte für
  /// dieselbe Sache gewesen – derselbe Fehler, den die
  /// Aufgabenverwaltung gerade abgelegt hat.
  Widget _baum(BuildContext context, PersonData fokus) {
    final t = AppTexte.of(context);
    final geflecht =
        geflechtUm(_netz, fokus.id, [for (final p in _personen) p.id]);
    // **Der Baum wächst mit der Systemschrift.** Ein Schild ist 132 auf
    // 108 Punkte gross, und in seine Tafel passen genau drei Zeilen:
    // 56,6 von 67 Punkten. Wer die Schrift des Systems auf 120 Prozent
    // stellt, braucht 67,9 – und dann malt der Text über den Rand,
    // genau wie beim gemeldeten Fehler mit den zwei Mehrzeichen. Ein
    // Schild lässt sich nicht dehnen; also wird der ganze Baum grösser,
    // mit demselben Kunstgriff, mit dem die Tafel zum Aufhängen
    // dreifach vergrössert wird.
    final schriftfaktor = MediaQuery.textScalerOf(context).scale(14) / 14;
    final schildmasse = const Schildmasse().mal(schriftfaktor);
    final plan = zierbaumplan(geflecht,
        masse: const Zierbaummasse().mal(schriftfaktor));
    final farben = Zierbaumfarben.fuer(Theme.of(context).brightness);

    if (plan.schilder.length <= 1) {
      return Center(
        child: SizedBox(
          width: 420,
          child: Text(
            t.stammbaumLeer,
            textAlign: TextAlign.center,
            style:
                TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Column(children: [
      if (geflecht.verschwiegen > 0)
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            children: [
              Icon(Icons.more_horiz,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  t.stammbaumZuVieleHaushalte(geflecht.verschwiegen),
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      Expanded(
        // Verschieben und Zoomen statt zweier ineinandergesteckter
        // Rollbereiche. Die konnten zwar in beide Richtungen rollen, aber
        // ein Baum mit angeheirateter Verwandtschaft ist breiter als
        // jedes Fenster – man bekam ihn nie ganz zu sehen, und ohne
        // Rollbalken (Tastfläche, Magic Mouse) kam man nicht einmal an
        // seinen Rand.
        //
        // Die Mindestmasse sind der Grund für den LayoutBuilder: Ein
        // unbeschränkter Bereich gibt seinem Kind unbegrenzten Platz, und
        // ein Kind, das nur so gross ist wie sein Inhalt, hört dort auf.
        // Der gemalte Grund endete dann mitten im Fenster, und daneben
        // stand die gewöhnliche Hintergrundfarbe – ein Bild mit einer
        // Kante. Herausgezoomt bleibt genau das übrig, deshalb liegt
        // derselbe Grundton auch unter der ganzen Fläche.
        child: LayoutBuilder(builder: (context, platz) {
          final fenster = Size(platz.maxWidth, platz.maxHeight);
          _passeEin(fokus.id, fenster, plan);
          return Stack(children: [
              // Der Grund liegt HINTER dem verschiebbaren Bereich und
              // bleibt stehen. Läge er darin, wäre er so gross wie der
              // Baum – und beim Verschieben sähe man seine Kante mitten
              // im Fenster.
              Positioned.fill(
                child: CustomPaint(painter: Zierbaumgrund(farben: farben)),
              ),
              Positioned.fill(
                child: InteractiveViewer(
          transformationController: _blick,
          // Der Baum behält seine eigene Grösse, statt ins Fenster
          // gequetscht zu werden – sonst gäbe es nichts zu verschieben.
          constrained: false,
          minScale: kleinsterBaumzoom,
          maxScale: groessterBaumzoom,
          // Ohne Rand liesse sich ein Baum, der schmaler ist als das
          // Fenster, überhaupt nicht bewegen; mit unendlichem Rand
          // schöbe man ihn versehentlich ganz aus dem Bild und stünde vor
          // einer leeren Fläche. Eine Fensterbreite ringsum ist beides
          // nicht: Jedes Schild lässt sich bis an die gegenüberliegende
          // Kante ziehen, und irgendetwas bleibt immer zu sehen.
          boundaryMargin: EdgeInsets.symmetric(
              horizontal: platz.maxWidth, vertical: platz.maxHeight),
          // Wischen auf einer Tastfläche oder Magic Mouse zoomt, wie auf
          // der Karte. Ohne diese Zeile verschöbe es nur – und die
          // Geräte, die kein Rad haben, hätten wieder keinen Zoom.
          trackpadScrollCausesScale: true,
          // Die Schriftgrössen stecken schon in den Massen – ohne diese
          // Zeile käme der Faktor ein zweites Mal obendrauf.
          child: MediaQuery.withNoTextScaling(
            child: ZierbaumAnsicht(
              // Kein Mindestmass mehr: Der Grund steht dahinter, also
              // darf der Baum genau so gross sein, wie er ist.
              malGrund: false,
              schildmasse: schildmasse,
              plan: plan,
              farben: farben,
              fokusId: fokus.id,
              menueHinweis: t.stammbaumMenue,
              familienname: haeufigsterNachname(
                  [for (final id in geflecht.personen) _nachId[id]!.name]),
              inhalt: (id) {
                final person = _nachId[id]!;
                final bild = person.coverFaceCropPath;
                return Schildinhalt(
                  name: person.name,
                  verwandtschaft: id == fokus.id ? null : _bezeichnung(person),
                  bild:
                      bild == null ? null : widget.library.paths.absolute(bild),
                  lebensspanne: lebensspanne(
                      person.geburtsdatum, person.sterbedatum),
                  weitereOben: geflecht.weitereOben[id] ?? false,
                  weitereUnten: geflecht.weitereUnten[id] ?? false,
                );
              },
              beiTipp: _ruecke,
              beiMenue: (id, stelle) {
                final person = _nachId[id]!;
                final bezug = _bezugZurMitte(id);
                _karteMenue(stelle, person,
                    art: _artFuer(person, bezug),
                    umgekehrt: bezug == _Bezug.kind);
              },
            ),
          ),
                ),
              ),
              Positioned(
                right: AppSpacing.sm,
                bottom: AppSpacing.sm,
                child: Zoomsteuerung(
                  beiNaeher: () => _baumZoomen(baumZoomschritt, fenster),
                  beiWeiter: () => _baumZoomen(1 / baumZoomschritt, fenster),
                  beiEinpassen: () => _blick.value = baumEingepasst(
                      Size(plan.breite, plan.hoehe), fenster),
                ),
              ),
          ]);
        }),
      ),
    ]);
  }

  /// Stellt den Ausschnitt neu ein, wenn ein anderer Baum davorsteht.
  ///
  /// **Nicht eingepasst, sondern auf die Mitte gerückt.** Ein Baum mit
  /// angeheirateter Verwandtschaft passt nur bei einem Drittel seiner
  /// Grösse ins Fenster, und dort ist keine Beschriftung mehr zu lesen –
  /// „ganz zeigen" ist deshalb ein Knopf und keine Vorgabe. Gezeigt wird
  /// in voller Grösse die Person, um die es geht. Vorher begann der
  /// Ausschnitt am linken Rand des Baumes, also bei irgendeinem
  /// Urgrossvater.
  ///
  /// Läuft mitten im Aufbau und darf deshalb kein `setState` auslösen –
  /// der [TransformationController] benachrichtigt den
  /// [InteractiveViewer] selbst, und der zeichnet sich neu.
  void _passeEin(String fokus, Size fenster, Zierbaumplan plan) {
    if (_eingepasstAuf?.fokus == fokus && _eingepasstAuf?.fenster == fenster) {
      return;
    }
    _eingepasstAuf = (fokus: fokus, fenster: fenster);
    final baum = Size(plan.breite, plan.hoehe);
    final schild = plan.schilder.where((s) => s.personId == fokus).firstOrNull;
    if (schild == null) {
      _blick.value = baumEingepasst(baum, fenster);
      return;
    }
    _blick.value = baumErsterBlick(
      baum: baum,
      fenster: fenster,
      fokusSchild:
          Rect.fromLTWH(schild.links, schild.oben, schild.breite, schild.hoehe),
    );
  }

  /// Ein Zoomschritt über die Knöpfe, festgehalten an der Fenstermitte.
  void _baumZoomen(double faktor, Size fenster) {
    _blick.value = baumGezoomt(_blick.value, faktor,
        Offset(fenster.width / 2, fenster.height / 2));
  }

  /// Wie [person] zur Mitte steht, aus dem Netz hergeleitet.
  ///
  /// Für die Sichten ohne feste Reihen – die Verwandtenliste zeigt auch
  /// eine Großtante, zu der es gar keine eigene Kante gibt. Dann
  /// [_Bezug.keiner], und das Menü bietet folgerichtig kein Lösen an.
  _Bezug _bezugZurMitte(String personId) {
    final fokus = _fokusId;
    if (fokus == null || personId == fokus) return _Bezug.keiner;
    if (_netz.eltern(fokus).contains(personId)) return _Bezug.elternteil;
    if (_netz.kinder(fokus).contains(personId)) return _Bezug.kind;
    if (_netz.partner(fokus).contains(personId)) return _Bezug.partner;
    return _Bezug.keiner;
  }

  /// Die tatsächlich gespeicherte Art der Verbindung zwischen [person] und
  /// der Person in der Mitte.
  ///
  /// Aus dem Netz nachgeschlagen statt aus der Reihe abgeleitet: Eine
  /// Elternreihe kann einen leiblichen und daneben einen Adoptivvater
  /// enthalten. Die Reihe weiß nur, dass es Eltern sind – welcher Art,
  /// weiß nur die Kante.
  ///
  /// Genau hier lag der Fehler: Beide Elternreihen übergaben fest
  /// „leiblich", und das Lösen einer Adoptivverbindung traf deshalb keine
  /// Zeile.
  Verwandtschaft? _artFuer(PersonData person, _Bezug bezug) {
    final fokus = _fokusId;
    if (fokus == null) return null;
    return switch (bezug) {
      _Bezug.elternteil => _netz.elternArt(fokus, person.id),
      _Bezug.kind => _netz.elternArt(person.id, fokus),
      _Bezug.partner => Verwandtschaft.partner,
      _Bezug.keiner => null,
    };
  }
}

/// Geschlecht sowie Geburts- und Sterbedatum einer Person.
///
/// Beide freiwillig und einzeln löschbar. Der Bereich beginnt 1800: Eine
/// Fotobibliothek reicht selten weiter zurück, und ein Auswahldialog, der
/// bis ins Mittelalter blättert, macht das Suchen des richtigen
/// Jahrzehnts mühsamer.
class _LebensdatenDialog extends StatefulWidget {
  final PersonData person;
  const _LebensdatenDialog({required this.person});

  @override
  State<_LebensdatenDialog> createState() => _LebensdatenDialogState();
}

class _LebensdatenDialogState extends State<_LebensdatenDialog> {
  late DateTime? _geburt = widget.person.geburtsdatum;
  late DateTime? _tod = widget.person.sterbedatum;
  late Geschlecht? _geschlecht = geschlechtAusText(widget.person.geschlecht);

  Future<void> _waehle({required bool geburt}) async {
    final jetzt = DateTime.now();
    final gewaehlt = await showDatePicker(
      context: context,
      initialDate: (geburt ? _geburt : _tod) ?? DateTime(jetzt.year - 40),
      firstDate: DateTime(1800),
      lastDate: jetzt,
    );
    if (gewaehlt == null || !mounted) return;
    setState(() => geburt ? _geburt = gewaehlt : _tod = gewaehlt);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return AlertDialog(
      title: Text(t.stammbaumAngaben),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(width: 96, child: Text(t.stammbaumGeschlecht)),
              Expanded(
                child: DropdownButton<Geschlecht?>(
                  value: _geschlecht,
                  isExpanded: true,
                  isDense: true,
                  onChanged: (w) => setState(() => _geschlecht = w),
                  items: [
                    DropdownMenuItem(value: null, child: Text(t.stammbaumGeschlechtOffen)),
                    DropdownMenuItem(
                        value: Geschlecht.weiblich,
                        child: Text(t.stammbaumGeschlechtWeiblich)),
                    DropdownMenuItem(
                        value: Geschlecht.maennlich,
                        child: Text(t.stammbaumGeschlechtMaennlich)),
                    DropdownMenuItem(
                        value: Geschlecht.divers,
                        child: Text(t.stammbaumGeschlechtDivers)),
                  ],
                ),
              ),
              const SizedBox(width: 40),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              t.stammbaumGeschlechtHinweis,
              style: TextStyle(
                  fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          _Datumszeile(
            beschriftung: t.stammbaumGeboren,
            wert: _geburt,
            onWaehlen: () => _waehle(geburt: true),
            onLoeschen: () => setState(() => _geburt = null),
          ),
          _Datumszeile(
            beschriftung: t.stammbaumGestorben,
            wert: _tod,
            onWaehlen: () => _waehle(geburt: false),
            onLoeschen: () => setState(() => _tod = null),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            t.stammbaumNurJahrHinweis,
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(t.allgAbbrechen)),
        FilledButton(
          onPressed: () => Navigator.pop(
              context, (geburt: _geburt, tod: _tod, geschlecht: _geschlecht)),
          child: Text(t.allgSpeichern),
        ),
      ],
    );
  }
}

class _Datumszeile extends StatelessWidget {
  final String beschriftung;
  final DateTime? wert;
  final VoidCallback onWaehlen;
  final VoidCallback onLoeschen;

  const _Datumszeile({
    required this.beschriftung,
    required this.wert,
    required this.onWaehlen,
    required this.onLoeschen,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Row(
      children: [
        SizedBox(width: 96, child: Text(beschriftung)),
        Expanded(
          child: OutlinedButton(
            onPressed: onWaehlen,
            child: Text(wert == null
                ? t.stammbaumUnbekannt
                : '${wert!.day}.${wert!.month}.${wert!.year}'),
          ),
        ),
        IconButton(
          tooltip: t.allgEntfernen,
          icon: const Icon(Icons.clear, size: 18),
          onPressed: wert == null ? null : onLoeschen,
        ),
      ],
    );
  }
}
