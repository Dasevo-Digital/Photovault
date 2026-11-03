import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';

import '../bilder.dart';
import '../formate.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'betrachter.dart';

/// Ein Vorschlag, wie ihn der Server schickt (`GET /api/v1/aufnahmedaten`),
/// mit der Zeile aus der Kopie der Bibliothek.
typedef Aufnahmedatenvorschlag = ({
  AssetData aufnahme,
  DateTime bisher,
  bool bisherGeschaetzt,
  DateTime neu,
  bool geschaetzt,
  String quelle,
});

/// Liest einen Vorschlag aus dem JSON des Servers (Liste und Angaben).
({DateTime neu, bool geschaetzt, String quelle}) vorschlagAus(Map v) => (
  neu: DateTime.parse(v['neu']! as String).toLocal(),
  geschaetzt: v['geschaetzt'] as bool? ?? false,
  quelle: v['quelle']! as String,
);

/// Das vorgeschlagene Datum zum Lesen: ohne Uhrzeit, wenn der Name nur den
/// Tag nennt.
String vorschlagsdatum(String sprache, DateTime neu, bool geschaetzt) =>
    (geschaetzt ? datumMittel(sprache) : datumZeitMittel(sprache)).format(neu);

/// Eine Schätzung für ein altes Foto, wie sie der Server schickt
/// (`GET /api/v1/datierung`, #279).
typedef Datierungsvorschlag = ({
  AssetData aufnahme,
  int jahr,
  int von,
  int bis,
  bool belastbar,
});

/// Aufnahmedaten wie im Browser (web/app.js, zeigeAufnahmedaten, #203): wo
/// der Dateiname ein anderes Datum nennt als die Bibliothek, und was gelten
/// sollte. **Geprüft wird auf dem Server**, nicht auf der Kopie: Bei einem
/// Teil der Aufnahmen muss dafür die Originaldatei gelesen werden, und die
/// liegt auf dem Telefon meist nicht. Übernommen wird über denselben Befehl
/// wie am Rechner und im Browser.
///
/// Darunter die Datierung alter Fotos (#279): Fotos ohne echtes Datum, die
/// alt aussehen, mit dem Jahrzehnt, das die Bildsuche schätzt – dieselbe
/// Liste wie am Rechner (Werkzeuge) und im Browser. Auch sie rechnet der
/// Server, der das Textmodell hat.
class Aufnahmedaten extends StatefulWidget {
  const Aufnahmedaten({super.key, required this.sitzung, this.verbindung});

  final Sitzung sitzung;

  /// Sonst die des Abgleichs (für Prüfstände ohne Abgleich).
  final Serververbindung? verbindung;

  @override
  State<Aufnahmedaten> createState() => _AufnahmedatenState();
}

class _AufnahmedatenState extends State<Aufnahmedaten> {
  List<Aufnahmedatenvorschlag>? _vorschlaege;
  final _gewaehlt = <String>{};
  var _prueft = false;
  String? _fehler;

  List<Datierungsvorschlag>? _funde;
  final _uebernommen = <String>{};
  String? _datierungHinweis;

  AppDatabase get _db => widget.sitzung.db;

  @override
  void initState() {
    super.initState();
    _pruefe();
  }

  Future<void> _pruefe() async {
    setState(() {
      _prueft = true;
      _fehler = null;
    });
    try {
      final verbindung =
          widget.verbindung ?? widget.sitzung.abgleich?.verbindung;
      if (verbindung == null) throw KeineVerbindung('ohne Server');
      final d = await verbindung.hole(
        'api/v1/aufnahmedaten',
        zeitlimit: const Duration(minutes: 2),
      );
      final liste = <Aufnahmedatenvorschlag>[];
      for (final v in (d['vorschlaege']! as List).cast<Map>()) {
        // Was die Kopie noch nicht kennt, kommt beim nächsten Abgleich.
        final a = await _db.assetById((v['aufnahme']! as Map)['id']! as String);
        if (a == null) continue;
        final neu = vorschlagAus(v);
        liste.add((
          aufnahme: a,
          bisher: DateTime.parse(v['bisher']! as String).toLocal(),
          bisherGeschaetzt: v['bisherGeschaetzt'] as bool? ?? false,
          neu: neu.neu,
          geschaetzt: neu.geschaetzt,
          quelle: neu.quelle,
        ));
      }
      if (!mounted) return;
      setState(() {
        _vorschlaege = liste;
        _gewaehlt
          ..clear()
          ..addAll([for (final v in liste) v.aufnahme.id]);
      });
      await _datiere(verbindung);
    } on KeineVerbindung {
      if (mounted) {
        setState(() => _fehler = AppTexte.of(context).datenOhneServer);
      }
    } catch (x) {
      if (mounted) setState(() => _fehler = '$x');
    } finally {
      if (mounted) setState(() => _prueft = false);
    }
  }

  Future<void> _datiere(Serververbindung verbindung) async {
    final t = AppTexte.of(context);
    try {
      final d = await verbindung.hole(
        'api/v1/datierung',
        zeitlimit: const Duration(minutes: 2),
      );
      final funde = <Datierungsvorschlag>[];
      final schon = <String>{};
      for (final f in (d['funde']! as List).cast<Map>()) {
        final a = await _db.assetById((f['aufnahme']! as Map)['id']! as String);
        if (a == null) continue;
        funde.add((
          aufnahme: a,
          jahr: f['jahr']! as int,
          von: f['von']! as int,
          bis: f['bis']! as int,
          belastbar: f['belastbar'] as bool? ?? false,
        ));
        if (f['uebernommen'] == true) schon.add(a.id);
      }
      if (!mounted) return;
      setState(() {
        _funde = funde;
        _uebernommen
          ..clear()
          ..addAll(schon);
        _datierungHinweis = funde.isEmpty ? t.datierungKeine : null;
      });
    } on Serverfehler catch (x) {
      if (x.abgemeldet) rethrow;
      if (!mounted) return;
      setState(() {
        _funde = null;
        _datierungHinweis = x.status == 404 ? t.datierungOhneModell : '$x';
      });
    }
  }

  Future<void> _schaetzungUebernehmen(List<Datierungsvorschlag> welche) async {
    for (final f in welche) {
      await _db.fuehreAus(JahrSchaetzen(f.aufnahme.id, f.jahr));
    }
    if (mounted) {
      setState(
        () => _uebernommen.addAll([for (final f in welche) f.aufnahme.id]),
      );
    }
  }

  Future<void> _uebernehmen() async {
    final t = AppTexte.of(context);
    final daten = [
      for (final v in _vorschlaege!)
        if (_gewaehlt.contains(v.aufnahme.id))
          (id: v.aufnahme.id, zeitpunkt: v.neu, geschaetzt: v.geschaetzt),
    ];
    if (daten.isEmpty) return;
    final ja =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            content: Text(t.datenFrage(daten.length)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t.abbrechen),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('OK'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ja) return;
    // In Stücken, wie im Browser. Der Befehl wirkt hier sofort und geht
    // über die Warteschlange zum Server – darum fallen die Einträge gleich
    // aus der Liste, statt den Server zu fragen, ehe er sie kennt.
    for (var i = 0; i < daten.length; i += 200) {
      await _db.fuehreAus(
        AufnahmedatenSetzen(daten.sublist(i, math.min(i + 200, daten.length))),
      );
    }
    if (!mounted) return;
    final erledigt = {for (final d in daten) d.id};
    setState(() {
      _vorschlaege = [
        for (final v in _vorschlaege!)
          if (!erledigt.contains(v.aufnahme.id)) v,
      ];
      _gewaehlt.removeAll(erledigt);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final sprache = Localizations.localeOf(context).toLanguageTag();
    final datumZeit = datumZeitMittel(sprache);
    final v = _vorschlaege;
    final hinweis = _prueft
        ? t.datenPrueft
        : _fehler ??
              (v == null
                  ? ''
                  : v.isEmpty
                  ? t.datenKeine
                  : t.datenHinweis(v.length));
    final zeilen = [for (final x in v ?? const []) Rasterzeile.aus(x.aufnahme)];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                hinweis,
                style: TextStyle(color: farben.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _prueft ? null : _pruefe,
              child: Text(t.datenPruefen),
            ),
          ],
        ),
        if (!_prueft && _gewaehlt.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton(
                onPressed: _uebernehmen,
                child: Text(t.datenUebernehmen(_gewaehlt.length)),
              ),
            ),
          ),
        if (!_prueft && v != null)
          for (final (i, x) in v.indexed)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _gewaehlt.contains(x.aufnahme.id),
              onChanged: (an) => setState(
                () => an == true
                    ? _gewaehlt.add(x.aufnahme.id)
                    : _gewaehlt.remove(x.aufnahme.id),
              ),
              secondary: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  betrachterWeg(
                    Betrachter(
                      sitzung: widget.sitzung,
                      zeilen: zeilen,
                      start: i,
                    ),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: Miniatur(
                      paths: widget.sitzung.paths,
                      relativ: x.aufnahme.thumbnailRelativePath,
                    ),
                  ),
                ),
              ),
              title: Text(
                x.aufnahme.originalFileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  '${datumZeit.format(x.bisher)}'
                      '${x.bisherGeschaetzt ? ' (${t.datenGeschaetzt})' : ''}'
                      ' → ${vorschlagsdatum(sprache, x.neu, x.geschaetzt)}',
                  [
                    x.quelle == 'dateiUndName'
                        ? t.datenLautDatei
                        : t.datenLautName,
                    if (x.geschaetzt) t.datenNurTag,
                  ].join(' · '),
                ].join('\n'),
              ),
            ),
        if (!_prueft) ..._datierung(context, t),
      ],
    );
  }

  List<Widget> _datierung(BuildContext context, AppTexte t) {
    final funde = _funde;
    final hinweis = _datierungHinweis;
    if (funde == null && hinweis == null) return const [];
    final farben = Theme.of(context).colorScheme;
    final klein = TextStyle(color: farben.onSurfaceVariant);
    final offen = [
      for (final f in funde ?? const <Datierungsvorschlag>[])
        if (f.belastbar && !_uebernommen.contains(f.aufnahme.id)) f,
    ];
    final zeilen = [
      for (final f in funde ?? const <Datierungsvorschlag>[])
        Rasterzeile.aus(f.aufnahme),
    ];
    return [
      const Divider(height: 32),
      Text(t.datierungTitel, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(hinweis ?? t.datierungEinleitung, style: klein),
      if (offen.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(
              onPressed: () => _schaetzungUebernehmen(offen),
              child: Text(t.datierungAlle(offen.length)),
            ),
          ),
        ),
      for (final (i, f) in (funde ?? const <Datierungsvorschlag>[]).indexed)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: GestureDetector(
            onTap: () => Navigator.of(context).push(
              betrachterWeg(
                Betrachter(sitzung: widget.sitzung, zeilen: zeilen, start: i),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 56,
                height: 56,
                child: Miniatur(
                  paths: widget.sitzung.paths,
                  relativ: f.aufnahme.thumbnailRelativePath,
                ),
              ),
            ),
          ),
          title: Text(t.datierungUm('${f.jahr}')),
          subtitle: Text(
            f.belastbar
                ? t.datierungSpanne('${f.von}', '${f.bis}')
                : t.datierungUnsicher('${f.von}', '${f.bis}'),
          ),
          trailing: _uebernommen.contains(f.aufnahme.id)
              ? Text(t.datierungIstUebernommen, style: klein)
              : f.belastbar
              ? TextButton(
                  onPressed: () => _schaetzungUebernehmen([f]),
                  child: Text(t.datierungUebernehmen),
                )
              : null,
        ),
    ];
  }
}
