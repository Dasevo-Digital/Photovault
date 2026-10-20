import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/familientage.dart';
import 'package:kern/services/rueckblickseite.dart';
import 'package:zierbild/bibliothek_eintraege.dart';

import '../bilder.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'betrachter.dart';
import 'erinnerungen.dart';
import 'personen.dart';
import 'raster.dart';
import 'reisen.dart';

/// „Rückblick“ wie am Rechner und im Browser (Issue #185): das Jahr in
/// Zahlen und Bildern, Familientage aus dem Stammbaum, „Vor x Jahren“, die
/// Erinnerungen der letzten zwei Wochen zum Merken und die schönsten
/// Reisen. Gerechnet im Kern (rueckblickseite.dart).
class Rueckblick extends StatefulWidget {
  const Rueckblick({super.key, required this.sitzung, this.heute});

  final Sitzung sitzung;

  /// Für Tests; sonst jetzt.
  final DateTime? heute;

  @override
  State<Rueckblick> createState() => _RueckblickState();
}

typedef _Stand = ({
  List<FamilientagMitFotos> tage,
  Erinnerungsstand erinnerungen,
});

class _RueckblickState extends State<Rueckblick> {
  DateTime get _heute {
    final h = widget.heute ?? DateTime.now();
    return DateTime(h.year, h.month, h.day);
  }

  late Future<_Stand> _stand = _lade();

  Future<_Stand> _lade() async {
    final db = widget.sitzung.db;
    return (
      tage: await familientageMitFotos(db, heute: _heute),
      erinnerungen: await erinnerungsstand(db, heute: _heute),
    );
  }

  // Mit Block: Ein Pfeil gäbe die Zukunft an setState zurück, und das
  // lehnt Flutter ab.
  void _neu() => setState(() {
    _stand = _lade();
  });

  String _satz(AppTexte t, FamilientagMitFotos f) {
    final name = f.namen.join(' & ');
    final satz = switch (f.tag.art) {
      Familientagart.geburtstag =>
        f.tag.verstorben
            ? t.rbGeburtstagVerstorben(name, f.tag.jahre)
            : t.rbGeburtstag(name, f.tag.jahre),
      Familientagart.todestag => t.rbTodestag(name, f.tag.jahre),
      Familientagart.hochzeitstag => t.rbHochzeitstag(name, f.tag.jahre),
    };
    return switch (f.tag.inTagen) {
      0 => t.rbHeute(satz),
      1 => t.rbMorgen(satz),
      _ => t.rbInTagen(f.tag.inTagen, satz),
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final sprache = Localizations.localeOf(context).toLanguageTag();
    final datum = DateFormat.yMMMMd(sprache);
    return FutureBuilder<_Stand>(
      future: _stand,
      builder: (context, s) {
        final d = s.data;
        if (d == null) return const Center(child: CircularProgressIndicator());
        final e = d.erinnerungen;
        final gemerkt = {for (final g in e.gemerkt) g.e.id};
        final jahr = jahresrueckblickJahr(_heute);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _Jahreskarte(
              titel: t.rbJahr(jahr),
              untertitel: t.rbJahrUntertitel,
              onTap: () => _oeffne(
                context,
                t.rbJahr(jahr),
                Jahresrueckblick(sitzung: widget.sitzung, jahr: jahr),
                ohneTitel: true,
              ),
            ),
            if (d.tage.isNotEmpty) ...[
              _Kopf(t.rbFamilientage),
              for (final f in d.tage)
                _Eintrag(
                  sitzung: widget.sitzung,
                  titel: _satz(t, f),
                  dinge: f.fotos,
                ),
            ],
            Erinnerungsstreifen(sitzung: widget.sitzung, heute: _heute),
            if (e.gemerkt.isNotEmpty) ...[
              _Kopf(t.rbGemerkt),
              for (final g in e.gemerkt)
                if (g.dinge.isNotEmpty)
                  _Eintrag(
                    sitzung: widget.sitzung,
                    titel: g.e.titel,
                    dinge: g.dinge,
                    aktion: TextButton(
                      onPressed: () async {
                        await widget.sitzung.db.fuehreAus(
                          ErinnerungVergessen(g.e.id),
                        );
                        _neu();
                      },
                      child: Text(t.rbVergessen),
                    ),
                  ),
            ],
            _Kopf(t.rbLetzteTage),
            if (e.letzte.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(t.rbKeine),
              ),
            for (final l in e.letzte)
              () {
                final wann = DateTime(
                  l.tag.year - l.jahreHer,
                  l.tag.month,
                  l.tag.day,
                );
                final titel = t.rbTagVorJahren(datum.format(wann), l.jahreHer);
                final kennung = erinnerungsKennung(l.tag, l.jahreHer);
                return _Eintrag(
                  sitzung: widget.sitzung,
                  titel: titel,
                  dinge: l.dinge,
                  aktion: gemerkt.contains(kennung)
                      ? null
                      : TextButton(
                          onPressed: () async {
                            await widget.sitzung.db.fuehreAus(
                              ErinnerungMerken(
                                erinnerungId: kennung,
                                titel: titel,
                                tag: wann,
                                ids: [for (final a in l.dinge) a.id],
                              ),
                            );
                            _neu();
                          },
                          child: Text(t.rbMerken),
                        ),
                );
              }(),
            if (e.reisen.isNotEmpty) ...[
              _Kopf(t.rbSchoensteReisen),
              for (final r in e.reisen)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Bibliothekssymbole.reisen,
                    color: Bibliotheksfarben.reisen,
                  ),
                  title: Text(r.reise.name),
                  subtitle: Text(
                    t.rbReise(r.reise.von.toLocal().year, r.lieblinge),
                  ),
                  onTap: () => _oeffne(
                    context,
                    r.reise.name,
                    ReiseSeite(sitzung: widget.sitzung, reiseId: r.reise.id),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

void _oeffne(
  BuildContext context,
  String titel,
  Widget inhalt, {
  bool ohneTitel = false,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => ohneTitel
        ? inhalt
        : Scaffold(
            appBar: AppBar(title: Text(titel)),
            body: inhalt,
          ),
  ),
);

class _Kopf extends StatelessWidget {
  const _Kopf(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
  );
}

class _Jahreskarte extends StatelessWidget {
  const _Jahreskarte({
    required this.titel,
    required this.untertitel,
    required this.onTap,
  });

  final String titel;
  final String untertitel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Material(
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Bibliotheksfarben.rueckblick,
                Bibliotheksfarben.kalender,
              ],
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                untertitel,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Ein Tag oder Anlass mit einem waagerechten Streifen seiner Fotos.
class _Eintrag extends StatelessWidget {
  const _Eintrag({
    required this.sitzung,
    required this.titel,
    required this.dinge,
    this.aktion,
  });

  final Sitzung sitzung;
  final String titel;
  final List<AssetData> dinge;
  final Widget? aktion;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                titel,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ?aktion,
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: dinge.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, i) => GestureDetector(
              onTap: () => Navigator.of(context).push(
                betrachterWeg(
                  Betrachter(
                    sitzung: sitzung,
                    zeilen: [for (final a in dinge) Rasterzeile.aus(a)],
                    start: i,
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox.square(
                  dimension: 96,
                  child: Miniatur(
                    paths: sitzung.paths,
                    relativ: dinge[i].thumbnailRelativePath,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Ein Jahr in Zahlen und Bildern – wie am Rechner.
class Jahresrueckblick extends StatefulWidget {
  const Jahresrueckblick({
    super.key,
    required this.sitzung,
    required this.jahr,
  });

  final Sitzung sitzung;
  final int jahr;

  @override
  State<Jahresrueckblick> createState() => _JahresrueckblickState();
}

class _JahresrueckblickState extends State<Jahresrueckblick> {
  late int _jahr = widget.jahr;
  late Future<Jahresinhalt> _inhalt = jahresinhalt(widget.sitzung.db, _jahr);

  void _wechsle(int jahr) => setState(() {
    _jahr = jahr;
    _inhalt = jahresinhalt(widget.sitzung.db, jahr);
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final sprache = Localizations.localeOf(context).toLanguageTag();
    final zahl = NumberFormat.decimalPattern(sprache);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.rbJahr(_jahr)),
        actions: [
          IconButton(
            tooltip: t.jrVorjahr,
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _wechsle(_jahr - 1),
          ),
          IconButton(
            tooltip: t.jrFolgejahr,
            icon: const Icon(Icons.chevron_right),
            onPressed: _jahr >= DateTime.now().year
                ? null
                : () => _wechsle(_jahr + 1),
          ),
        ],
      ),
      body: FutureBuilder<Jahresinhalt>(
        future: _inhalt,
        builder: (context, s) {
          final i = s.data;
          if (i == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final z = i.zahlen;
          if (z.fotos + z.videos == 0) {
            return Center(child: Text(t.jrLeer(_jahr)));
          }
          final monat = z.staerksterMonat;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Zahl(zahl.format(z.fotos), t.jrFotos),
                  _Zahl(zahl.format(z.videos), t.jrVideos),
                  _Zahl(zahl.format(z.tage), t.jrTage),
                  _Zahl(zahl.format(z.laender.length), t.jrLaender),
                  _Zahl(zahl.format(z.orte.length), t.jrOrte),
                  if (monat != null)
                    _Zahl(
                      DateFormat.MMMM(sprache).format(DateTime(_jahr, monat)),
                      t.jrStaerksterMonat,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _Monatsbalken(jeMonat: z.jeMonat, sprache: sprache),
              if (i.auswahl.isNotEmpty) ...[
                _Kopf(t.jrAuswahl),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  children: [
                    for (final (n, a) in i.auswahl.indexed)
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          betrachterWeg(
                            Betrachter(
                              sitzung: widget.sitzung,
                              zeilen: [
                                for (final x in i.auswahl) Rasterzeile.aus(x),
                              ],
                              start: n,
                            ),
                          ),
                        ),
                        child: Miniatur(
                          paths: widget.sitzung.paths,
                          relativ: a.thumbnailRelativePath,
                        ),
                      ),
                  ],
                ),
              ],
              if (i.personen.isNotEmpty) ...[
                _Kopf(t.jrPersonen),
                for (final p in i.personen.take(12))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: SizedBox.square(
                      dimension: 40,
                      child: Personenbild(
                        paths: widget.sitzung.paths,
                        name: p.person.name,
                        relativ: p.person.coverFaceCropPath,
                      ),
                    ),
                    title: Text(p.person.name),
                    trailing: Text(t.erinnerungenAnzahl(p.anzahl)),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PersonSeite(
                          sitzung: widget.sitzung,
                          person: p.person,
                        ),
                      ),
                    ),
                  ),
              ],
              if (i.reisen.isNotEmpty) ...[
                _Kopf(t.jrReisen),
                for (final r in i.reisen)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Bibliothekssymbole.reisen,
                      color: Bibliotheksfarben.reisen,
                    ),
                    title: Text(r.name),
                    subtitle: Text(
                      DateFormat.yMMMMd(sprache).format(r.von.toLocal()),
                    ),
                    onTap: () => _oeffne(
                      context,
                      r.name,
                      ReiseSeite(sitzung: widget.sitzung, reiseId: r.id),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Zahl extends StatelessWidget {
  const _Zahl(this.wert, this.name);

  final String wert;
  final String name;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return Container(
      width: 104,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: farben.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: farben.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            wert,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          Text(
            name,
            style: TextStyle(fontSize: 12, color: farben.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Monatsbalken extends StatelessWidget {
  const _Monatsbalken({required this.jeMonat, required this.sprache});

  final List<int> jeMonat;
  final String sprache;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final hoechst = jeMonat.fold(0, (a, b) => a > b ? a : b);
    final kurz = DateFormat.MMM(sprache);
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var m = 0; m < 12; m++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: hoechst == 0 ? 0 : 90 * jeMonat[m] / hoechst,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: farben.primary,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    kurz.format(DateTime(2000, m + 1)).substring(0, 1),
                    style: TextStyle(
                      fontSize: 11,
                      color: farben.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Der Kalender wie am Rechner: die Jahre, darin die Monate, darin die
/// Aufnahmen.
class Kalender extends StatelessWidget {
  const Kalender({super.key, required this.sitzung, this.jahr});

  final Sitzung sitzung;

  /// Gesetzt: die Monate dieses Jahres statt der Jahre.
  final int? jahr;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final sprache = Localizations.localeOf(context).toLanguageTag();
    final j = jahr;
    return FutureBuilder<List<Kalenderfeld>>(
      future: j == null
          ? kalenderjahre(sitzung.db)
          : kalendermonate(sitzung.db, j),
      builder: (context, s) {
        final felder = s.data;
        if (felder == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (felder.isEmpty) return Center(child: Text(t.kalLeer));
        String name(Kalenderfeld f) => j == null
            ? '${f.nummer}'
            : DateFormat.MMMM(sprache).format(DateTime(j, f.nummer));
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.82,
          ),
          itemCount: felder.length + (j == null ? 0 : 1),
          itemBuilder: (context, i) {
            if (i == felder.length) {
              return _Jahreskarte(
                titel: t.rbJahr(j!),
                untertitel: t.rbJahrUntertitel,
                onTap: () => _oeffne(
                  context,
                  t.rbJahr(j),
                  Jahresrueckblick(sitzung: sitzung, jahr: j),
                  ohneTitel: true,
                ),
              );
            }
            final f = felder[i];
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => j == null
                  ? _oeffne(
                      context,
                      name(f),
                      Kalender(sitzung: sitzung, jahr: f.nummer),
                    )
                  : _oeffne(
                      context,
                      '${name(f)} $j',
                      _Monat(sitzung: sitzung, jahr: j, monat: f.nummer),
                    ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox.expand(
                        child: Miniatur(
                          paths: sitzung.paths,
                          relativ: f.titelbild?.thumbnailRelativePath,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    name(f),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    t.erinnerungenAnzahl(f.anzahl),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _Monat extends StatelessWidget {
  const _Monat({
    required this.sitzung,
    required this.jahr,
    required this.monat,
  });

  final Sitzung sitzung;
  final int jahr;
  final int monat;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<AssetData>>(
    future: sitzung.db.aufnahmenImMonat(jahr, monat),
    builder: (context, s) {
      final a = s.data;
      if (a == null) return const Center(child: CircularProgressIndicator());
      return AufnahmenRaster(
        sitzung: sitzung,
        zeilen: [for (final x in a) Rasterzeile.aus(x)],
        nachTagen: true,
      );
    },
  );
}
