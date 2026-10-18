import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/duplikatsuche.dart';

import '../bilder.dart';
import '../formate.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'betrachter.dart';

/// Duplikate wie im Browser (web/app.js, zeigeDuplikate): Ähnlichkeit
/// wählen, suchen, je Gruppe „Behalten“ oder „Keine Duplikate“, und alle
/// auf einmal aufräumen. Gesucht wird mit derselben Rechnung im Kern
/// (duplikatsuche.dart) auf der Kopie der Bibliothek; entschieden wird über
/// dieselben Befehle, also auch am Rechner und im Browser sichtbar.
class Duplikate extends StatefulWidget {
  const Duplikate({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  State<Duplikate> createState() => _DuplikateState();
}

class _DuplikateState extends State<Duplikate> {
  var _schwelle = 0.92;
  Duplikatergebnis? _ergebnis;
  var _sucht = false;
  String? _fehler;

  AppDatabase get _db => widget.sitzung.db;

  @override
  void initState() {
    super.initState();
    _suche();
  }

  Future<void> _suche() async {
    setState(() {
      _sucht = true;
      _fehler = null;
    });
    try {
      final e = await sucheDuplikate(_db, _schwelle);
      if (mounted) setState(() => _ergebnis = e);
    } catch (x) {
      if (mounted) setState(() => _fehler = '$x');
    } finally {
      if (mounted) setState(() => _sucht = false);
    }
  }

  static String _prozent(double w) => '${(w * 100).round()} %';

  void _entferne(Duplikatgruppe g) {
    final e = _ergebnis;
    if (e == null) return;
    setState(
      () => _ergebnis = (
        einbettungen: e.einbettungen,
        ausnahmen: e.ausnahmen,
        schwelle: e.schwelle,
        gruppen: [
          for (final x in e.gruppen)
            if (!identical(x, g)) x,
        ],
      ),
    );
  }

  Future<bool> _frage(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppTexte.of(context).abbrechen),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('OK'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _behalten(Duplikatgruppe g, AssetData a) async {
    final t = AppTexte.of(context);
    final andere = [
      for (final x in g.aufnahmen)
        if (x.id != a.id) x.id,
    ];
    final ja = await _frage(
      andere.length == 1
          ? t.duplBehaltenEine(a.originalFileName)
          : t.duplBehaltenMehrere(a.originalFileName, andere.length),
    );
    if (!ja) return;
    await _db.fuehreAus(
      DuplikateZusammenfuehren(behaltenId: a.id, duplikatIds: andere),
    );
    _entferne(g);
  }

  Future<void> _keineDuplikate(Duplikatgruppe g) async {
    await _db.fuehreAus(
      DuplikatgruppeIgnorieren([for (final a in g.aufnahmen) a.id]),
    );
    _entferne(g);
  }

  Future<void> _alleAufraeumen() async {
    final t = AppTexte.of(context);
    final faellig = [
      for (final g in _ergebnis!.gruppen)
        if (g.loeschbar.isNotEmpty) g,
    ];
    final n = faellig.fold(0, (s, g) => s + g.loeschbar.length);
    if (!await _frage(t.duplAlleFrage(n, faellig.length))) return;
    for (final g in faellig) {
      await _db.fuehreAus(
        DuplikateZusammenfuehren(
          behaltenId: g.behalten.id,
          duplikatIds: [for (final a in g.loeschbar) a.id],
        ),
      );
    }
    await _suche();
  }

  String _hinweis(AppTexte t, Duplikatergebnis e) {
    if (e.einbettungen == 0) return t.duplKeineEinbettungen;
    final p = _prozent(e.schwelle);
    if (e.gruppen.isEmpty) {
      return [
        t.duplKeine(p),
        if (e.ausnahmen > 0) t.duplAusnahmen(e.ausnahmen),
      ].join(' ');
    }
    return t.duplGruppen(e.gruppen.length, p);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final e = _ergebnis;
    final loeschbar = e?.gruppen.fold(0, (s, g) => s + g.loeschbar.length);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Row(
          children: [
            Text(t.duplAehnlichkeit),
            Expanded(
              child: Slider(
                value: _schwelle,
                min: 0.85,
                max: 0.99,
                divisions: 14,
                label: _prozent(_schwelle),
                onChanged: (w) => setState(() => _schwelle = w),
              ),
            ),
            Text(_prozent(_schwelle)),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _sucht ? null : _suche,
              child: Text(t.duplSuchen),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            _sucht ? t.duplSucht : _fehler ?? (e == null ? '' : _hinweis(t, e)),
            style: TextStyle(color: farben.onSurfaceVariant),
          ),
        ),
        if (!_sucht && (loeschbar ?? 0) > 0)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: farben.error),
              onPressed: _alleAufraeumen,
              child: Text(t.duplAlle(loeschbar!)),
            ),
          ),
        if (!_sucht && e != null)
          for (final g in e.gruppen)
            _Gruppe(
              sitzung: widget.sitzung,
              gruppe: g,
              behalten: (a) => _behalten(g, a),
              keine: () => _keineDuplikate(g),
            ),
      ],
    );
  }
}

class _Gruppe extends StatelessWidget {
  const _Gruppe({
    required this.sitzung,
    required this.gruppe,
    required this.behalten,
    required this.keine,
  });

  final Sitzung sitzung;
  final Duplikatgruppe gruppe;
  final void Function(AssetData) behalten;
  final VoidCallback keine;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final sprache = Localizations.localeOf(context).toLanguageTag();
    final datumZeit = datumZeitMittel(sprache);
    final g = gruppe;
    final zeilen = [for (final a in g.aufnahmen) Rasterzeile.aus(a)];
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    g.loeschbar.isNotEmpty
                        ? t.anzahlAufnahmen(g.aufnahmen.length)
                        : t.duplNurVonHand(g.aufnahmen.length),
                    style: TextStyle(color: farben.onSurfaceVariant),
                  ),
                ),
                OutlinedButton(
                  onPressed: keine,
                  child: Text(t.duplKeineDuplikate),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 262,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: g.aufnahmen.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final a = g.aufnahmen[i];
                  final beste = a.id == g.behalten.id;
                  final angaben = [
                    if (a.widthPx != null && a.heightPx != null)
                      '${a.widthPx} × ${a.heightPx}',
                    datumZeit.format(a.fileCreatedAt.toLocal()),
                    if (a.isFavorite) '♥',
                    if (a.rating > 0) '★' * a.rating,
                  ].join(' · ');
                  return SizedBox(
                    width: 150,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            betrachterWeg(
                              Betrachter(
                                sitzung: sitzung,
                                zeilen: zeilen,
                                start: i,
                              ),
                            ),
                          ),
                          child: Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: beste
                                  ? Border.all(color: farben.primary, width: 3)
                                  : null,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Miniatur(
                              paths: sitzung.paths,
                              relativ: a.thumbnailRelativePath,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          a.originalFileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          angaben,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: farben.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        beste
                            ? FilledButton(
                                onPressed: () => behalten(a),
                                child: Text(t.duplBehalten),
                              )
                            : OutlinedButton(
                                onPressed: () => behalten(a),
                                child: Text(t.duplBehalten),
                              ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
