import 'package:flutter/material.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/laenderkatalog.dart';
import '../services/ortsuebersicht.dart' show Ortsebene;
import '../services/reisefortschritt.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import 'ortsansicht_screen.dart';

/// Jedes Land der Welt, und was du davon gesehen hast.
///
/// **Der Unterschied zu den Reisetagebüchern, die es sonst gibt:** Dort
/// hakt man die Länder von Hand ab. Hier stehen sie schon angehakt, weil
/// jede verortete Aufnahme Land, Region und Ort trägt. Von Hand markiert
/// wird nur, wovon es kein Bild gibt.
class LaenderlisteScreen extends StatefulWidget {
  final LibraryState library;
  const LaenderlisteScreen({super.key, required this.library});

  @override
  State<LaenderlisteScreen> createState() => _LaenderlisteScreenState();
}

enum _Filter { alle, vollstaendig, teilweise, nicht }

class _LaenderlisteScreenState extends State<LaenderlisteScreen> {
  List<Landstand>? _stand;
  String _suche = '';
  _Filter _filter = _Filter.alle;
  late final TextEditingController _suchfeld = TextEditingController();

  @override
  void initState() {
    super.initState();
    _laden();
  }

  @override
  void dispose() {
    _suchfeld.dispose();
    super.dispose();
  }

  Future<void> _laden() async {
    final geo = widget.library.geocoder;
    if (geo == null) {
      if (mounted) setState(() => _stand = const []);
      return;
    }
    final besucht = await widget.library.db.besuchteOrte();
    final marken = await widget.library.db.alleOrtsmarken();
    if (!mounted) return;
    setState(() {
      _stand = laenderstand(
        angaben: besucht,
        katalog: geo.laenderkatalog.laender,
        nachIso: geo.isoNachName,
        regionscodes: geo.regionscodes,
        marken: [
          for (final m in marken)
            (
              art: m.art,
              schluessel: m.schluessel,
              wert: m.status == 'geplant'
                  ? Markenart.geplant
                  : Markenart.besucht,
            ),
        ],
      );
    });
  }

  /// Die Sprache der Oberfläche – der Katalog kennt jedes Land englisch
  /// und deutsch (siehe [Landstand.anzeige]).
  String get _sprache => Localizations.localeOf(context).languageCode;

  List<Landstand> _gezeigt(String sprache) {
    final alle = _stand ?? const <Landstand>[];
    final suche = _suche.trim().toLowerCase();
    final liste = [
      for (final l in alle)
        if (switch (_filter) {
          _Filter.alle => true,
          _Filter.vollstaendig => l.grad == Besuchsgrad.vollstaendig,
          _Filter.teilweise => l.grad == Besuchsgrad.teilweise,
          _Filter.nicht => l.grad == Besuchsgrad.nicht,
        })
          // Gesucht wird in BEIDEN Namen. Wer „Germany" eintippt – weil er
          // ihn aus den Aufnahmen kennt –, soll Deutschland finden.
          if (suche.isEmpty ||
              l.anzeige(sprache).toLowerCase().contains(suche) ||
              l.name.toLowerCase().contains(suche) ||
              (l.hauptstadt?.toLowerCase().contains(suche) ?? false))
            l,
    ];
    // Der Katalog kommt nach dem englischen Namen sortiert. Auf Deutsch
    // stünde Deutschland dann unter G.
    liste.sort((a, b) => a.anzeige(sprache).compareTo(b.anzeige(sprache)));
    return liste;
  }

  Future<void> _markieren(Landstand land, Markenart? wert) async {
    final db = widget.library.db;
    if (wert == null) {
      await db.loescheOrtsmarke('land', land.iso);
    } else {
      await db.setzeOrtsmarke(OrtsmarkenCompanion.insert(
        art: 'land',
        schluessel: land.iso,
        // Der ENGLISCHE Name in die Datenbank: Die Marke soll nicht davon
        // abhängen, in welcher Sprache sie gesetzt wurde.
        name: land.name,
        status: wert == Markenart.geplant ? 'geplant' : 'besucht',
        angelegtAm: DateTime.now(),
      ));
    }
    await _laden();
  }

  void _oeffne(Landstand land) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => OrtsansichtScreen(
            library: widget.library,
            ebene: Ortsebene.land,
            schluessel: land.iso,
            name: land.anzeige(_sprache),
          ),
        ))
        // Dort unten kann eine Marke gesetzt worden sein – auch auf einer
        // Region, und die zählt im Balken dieser Liste mit.
        .then((_) => _laden());
  }

  Future<void> _markenmenue(Landstand land) async {
    final t = AppTexte.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder: (blatt) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(land.anzeige(_sprache)),
              subtitle: Text(t.laenderHinweisMarke),
              subtitleTextStyle: TextStyle(
                  fontSize: 12,
                  color: Theme.of(blatt).colorScheme.onSurfaceVariant),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(t.laenderMarkeBesucht),
              selected: land.marke == Markenart.besucht,
              onTap: () {
                Navigator.pop(blatt);
                _markieren(land, Markenart.besucht);
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(t.laenderMarkeGeplant),
              selected: land.marke == Markenart.geplant,
              onTap: () {
                Navigator.pop(blatt);
                _markieren(land, Markenart.geplant);
              },
            ),
            if (land.marke != null)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline),
                title: Text(t.laenderMarkeWeg),
                onTap: () {
                  Navigator.pop(blatt);
                  _markieren(land, null);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final stand = _stand;
    return Scaffold(
      appBar: AppBar(title: Text(t.laenderTitel)),
      body: stand == null
          ? const Center(child: CircularProgressIndicator())
          : stand.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    child: Text(t.laenderOhneGeodaten,
                        textAlign: TextAlign.center),
                  ),
                )
              : Column(
                  children: [
                    _Kopfzeile(stand: stand),
                    _Werkzeugleiste(
                      feld: _suchfeld,
                      filter: _filter,
                      beiSuche: (text) => setState(() => _suche = text),
                      beiFilter: (f) => setState(() => _filter = f),
                    ),
                    const Divider(height: 1),
                    Expanded(child: _liste(t)),
                  ],
                ),
    );
  }

  Widget _liste(AppTexte t) {
    final gezeigt = _gezeigt(_sprache);
    if (gezeigt.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Text(t.laenderNichtsGefunden),
        ),
      );
    }
    return ListView.separated(
      itemCount: gezeigt.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) => _Landzeile(
        land: gezeigt[i],
        // Ein Klick führt jetzt hinein statt in ein Menü: Was in einem
        // Land war, ist die naheliegendere Frage als „welchen Haken
        // setze ich hier". Das Markieren steht drinnen weiterhin
        // bereit – und zusätzlich auf dem langen Druck, für den, der
        // durch die Liste geht und nur Haken setzt.
        beiTippen: () => _oeffne(gezeigt[i]),
        beiLangemDruck: () => _markenmenue(gezeigt[i]),
      ),
    );
  }
}

/// Die Zahlen über der Liste.
class _Kopfzeile extends StatelessWidget {
  final List<Landstand> stand;
  const _Kopfzeile({required this.stand});

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final besucht = stand.where((l) => l.besucht).length;
    final voll =
        stand.where((l) => l.grad == Besuchsgrad.vollstaendig).length;
    final teil = stand.where((l) => l.grad == Besuchsgrad.teilweise).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.laenderKopf(stand.length, besucht, teil),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _Zahl(wert: besucht, beschriftung: t.laenderBesucht),
              _Zahl(wert: voll, beschriftung: t.laenderVollstaendig),
              _Zahl(wert: teil, beschriftung: t.laenderTeilweise),
              _Zahl(
                  wert: stand.length - besucht,
                  beschriftung: t.laenderVerbleibend),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: LinearProgressIndicator(
              value: stand.isEmpty ? 0 : besucht / stand.length,
              minHeight: 6,
              backgroundColor: farben.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Warum 252 und nicht 195: Die Zahl wird erklärt und nicht
          // behauptet. Wer sie zum ersten Mal sieht, hält sie sonst für
          // einen Fehler.
          Text(
            t.fortschrittHinweis(stand.length),
            style: TextStyle(fontSize: 11, color: farben.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          const _Legende(),
        ],
      ),
    );
  }
}

class _Zahl extends StatelessWidget {
  final int wert;
  final String beschriftung;
  const _Zahl({required this.wert, required this.beschriftung});

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$wert', style: Theme.of(context).textTheme.headlineSmall),
          Text(beschriftung,
              style: TextStyle(fontSize: 11, color: farben.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Suchfeld und Filter.
class _Werkzeugleiste extends StatelessWidget {
  final TextEditingController feld;
  final _Filter filter;
  final ValueChanged<String> beiSuche;
  final ValueChanged<_Filter> beiFilter;

  const _Werkzeugleiste({
    required this.feld,
    required this.filter,
    required this.beiSuche,
    required this.beiFilter,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: [
          TextField(
            controller: feld,
            onChanged: beiSuche,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: t.laenderSuchen,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(t.laenderFilter,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (wert, text) in [
                        (_Filter.alle, t.laenderAlle),
                        (_Filter.vollstaendig, t.laenderVollstaendig),
                        (_Filter.teilweise, t.laenderTeilweise),
                        (_Filter.nicht, t.laenderNichtBesucht),
                      ]) ...[
                        ChoiceChip(
                          label: Text(text),
                          selected: filter == wert,
                          onSelected: (an) {
                            if (an) beiFilter(wert);
                          },
                        ),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

/// Eine Zeile der Länderliste.
class _Landzeile extends StatelessWidget {
  final Landstand land;
  final VoidCallback beiTippen;
  final VoidCallback beiLangemDruck;

  const _Landzeile({
    required this.land,
    required this.beiTippen,
    required this.beiLangemDruck,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final flagge = flaggeAus(land.iso);

    final unterzeile = [
      erdteilName(t, land.kontinent),
      if (land.hauptstadt case final h?) h,
      if (land.aufnahmen > 0) t.laenderAufnahmen(land.aufnahmen),
      // Nur, wo für den Haken KEIN Foto spricht. Vorher stand „von Hand"
      // an jedem Land mit einer Marke – auch an denen, die längst durch
      // hunderte Aufnahmen belegt waren, und auch an bloss geplanten.
      if (land.nurVonHand) t.laenderVonHand,
      // Monaco und der Vatikan haben keine Region im Datensatz. Das
      // gehört gesagt: Ein leerer Platz, wo bei allen anderen ein Balken
      // steht, sieht aus wie ein Fehler. In die Unterzeile und nicht in
      // die schmale Spalte rechts – dort sprengte der Satz die Zeile.
      if (land.regionenGesamt == 0) t.laenderOhneRegionen,
    ].join(' · ');

    return ListTile(
      onTap: beiTippen,
      onLongPress: beiLangemDruck,
      leading: flagge == null
          ? const Icon(Icons.flag_outlined)
          // Nicht jede Plattform hat Flaggen in ihrer Schrift. Die Zeile
          // bleibt auch dann lesbar – der Name steht daneben, nicht darin.
          : Text(flagge, style: const TextStyle(fontSize: 24)),
      title: Text(land.anzeige(Localizations.localeOf(context).languageCode)),
      subtitle: Text(unterzeile,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: farben.onSurfaceVariant)),
      trailing: SizedBox(
        width: 148,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (land.regionenGesamt > 0)
              Tooltip(
                // Die Zahlen stehen kurz da, weil die Zeile schmal ist –
                // ausgeschrieben erklärt der Tooltip, was „1/2" heisst.
                message: t.laenderRegionen(
                    land.regionenBesucht, land.regionenGesamt),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 60,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        child: LinearProgressIndicator(
                          value: land.regionenBesucht / land.regionenGesamt,
                          minHeight: 5,
                          backgroundColor: farben.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text('${land.regionenBesucht}/${land.regionenGesamt}',
                        style: TextStyle(
                            fontSize: 11, color: farben.onSurfaceVariant)),
                  ],
                ),
              ),
            const SizedBox(width: AppSpacing.sm),
            _Statuspunkt(land: land),
          ],
        ),
      ),
    );
  }
}

/// Der Zustand als Farbe **und** als Symbol.
///
/// Nicht nur als Farbe: Rotgrünblindheit ist häufig, und drei Stufen, die
/// sich allein durch den Farbton unterscheiden, sind dann eine Stufe.
class _Statuspunkt extends StatelessWidget {
  final Landstand land;
  const _Statuspunkt({required this.land});

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final (symbol, farbe, text) = switch (land.grad) {
      Besuchsgrad.vollstaendig => (
          Icons.check_circle,
          farben.primary,
          t.laenderVollstaendig
        ),
      Besuchsgrad.teilweise => (
          Icons.adjust,
          farben.tertiary,
          t.laenderTeilweise
        ),
      Besuchsgrad.nicht => land.marke == Markenart.geplant
          ? (Icons.flag_outlined, farben.secondary, t.laenderGeplant)
          : (
              Icons.circle_outlined,
              farben.outline,
              t.laenderNichtBesucht
            ),
    };
    final punkt = Tooltip(
      message: text,
      child: Icon(symbol, size: 18, color: farbe),
    );
    // **Worauf der Haken beruht**, als eigenes Zeichen davor: die Kamera,
    // wenn Aufnahmen dafür sprechen, sonst die Hand. Beides in derselben
    // Farbe darzustellen waere eine Behauptung, die die Liste nicht
    // halten kann – und die Legende darunter erklaert beide.
    final (herkunft, hinweis) = land.aufnahmen > 0
        ? (Icons.photo_camera_outlined, t.laenderAusFotos)
        : land.nurVonHand
            ? (Icons.back_hand_outlined, t.laenderNurVonHand)
            : (null, '');
    if (herkunft == null) return punkt;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: hinweis,
          child: Icon(herkunft, size: 14, color: farben.onSurfaceVariant),
        ),
        const SizedBox(width: 4),
        punkt,
      ],
    );
  }
}

/// Was die Zeichen rechts in der Liste bedeuten.
///
/// **Warum es sie braucht.** Vier Zustände als Kringel, Halbkreis, Haken
/// und Fähnchen, dazu ein Handzeichen davor – jedes davon hatte einen
/// Kurzhinweis, den man nur sieht, wenn man mit dem Zeiger daraufbleibt.
/// Auf einem Schirm ohne Zeiger sah man ihn nie. Und die eigentliche
/// Frage der Liste – zählt dieses Land, weil ich dort fotografiert habe,
/// oder weil ich es abgehakt habe – stand nirgends.
class _Legende extends StatelessWidget {
  const _Legende();

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final stil = TextStyle(fontSize: 11, color: farben.onSurfaceVariant);

    Widget eintrag(IconData symbol, Color farbe, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(symbol, size: 14, color: farbe),
            const SizedBox(width: 4),
            Text(text, style: stil),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.laenderLegende,
            style: stil.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        // Umbrechend und nicht in einer Reihe: Fuenf Eintraege passen in
        // ein breites Fenster, in ein schmales nicht - und eine Reihe,
        // die ueberlaeuft, ist schlimmer als eine, die umbricht.
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: 4,
          children: [
            eintrag(Icons.check_circle, farben.primary, t.laenderVollstaendig),
            eintrag(Icons.adjust, farben.tertiary, t.laenderTeilweise),
            eintrag(Icons.flag_outlined, farben.secondary, t.laenderGeplant),
            eintrag(
                Icons.circle_outlined, farben.outline, t.laenderNichtBesucht),
            eintrag(Icons.photo_camera_outlined, farben.onSurfaceVariant,
                t.laenderAusFotos),
            eintrag(Icons.back_hand_outlined, farben.onSurfaceVariant,
                t.laenderNurVonHand),
          ],
        ),
      ],
    );
  }
}

/// Der ausgeschriebene Erdteil zum Kürzel des Datensatzes.
String erdteilName(AppTexte t, String kuerzel) => switch (kuerzel) {
      'EU' => t.erdteilEU,
      'AS' => t.erdteilAS,
      'NA' => t.erdteilNA,
      'SA' => t.erdteilSA,
      'AF' => t.erdteilAF,
      'OC' => t.erdteilOC,
      'AN' => t.erdteilAN,
      _ => t.erdteilUnbekannt,
    };
