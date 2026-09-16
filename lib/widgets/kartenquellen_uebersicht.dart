import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../screens/map_screen.dart' show Kartenansicht;
import '../services/eigenkarte.dart';
import '../services/meldungsdienst.dart';
import '../services/platform/webseite_oeffnen.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import 'eigene_karte_einstellung.dart' show zeigeKartenwarnung;
import 'mini_location_map.dart';

/// Was diese App an Kartenquellen kennt – und was sich damit tun lässt.
///
/// **Warum eine Übersicht und nicht nur das Vorlagenmenü.** Die Vorlagen
/// stehen hinter einem Knopf, und dort sieht man immer nur eine Zeile.
/// Die Frage, um die es tatsächlich geht – „wie nah komme ich mit
/// welcher Karte heran, und was kostet mich das" – lässt sich nur
/// beantworten, wenn alle nebeneinanderstehen.
///
/// **Und warum in Metern.** Zoomstufen sind eine Erfindung der
/// Kartenserver. „Bis Stufe 17" sagt niemandem etwas, „bis rund 74 m"
/// schon (siehe [massstabMeter]).
///
/// **Warum aus der Auskunft Knöpfe geworden sind.** Eine Liste, die
/// sagt, welche Karte am tiefsten trägt, und den Anwender die
/// Adressvorlage anschliessend von Hand abschreiben lässt, hat ihre
/// eigene Empfehlung nicht zu Ende gedacht. Jede Zeile führt deshalb
/// dorthin, wo sie hingehört:
///
/// | Zeile | Knopf |
/// |---|---|
/// | mitgeliefert | als Standardansicht merken |
/// | Vorlage ohne Schlüssel | einschalten und als Standard merken |
/// | Vorlage mit Schlüssel | ins Formular darunter schreiben |
///
/// Die Vorlagen mit Schlüssel bleiben aussen vor, weil das eine Stück,
/// das ihnen fehlt, niemand für sie beschaffen kann.
class KartenquellenUebersicht extends StatefulWidget {
  const KartenquellenUebersicht({
    super.key,
    required this.library,
    this.aufVorlage,
  });

  final LibraryState library;

  /// Wohin eine Vorlage mit Schlüssel gereicht wird – in der Regel das
  /// Formular unter dieser Übersicht.
  final void Function(Kartenvorlage)? aufVorlage;

  @override
  State<KartenquellenUebersicht> createState() =>
      _KartenquellenUebersichtState();
}

class _KartenquellenUebersichtState extends State<KartenquellenUebersicht> {
  /// Die gemerkte Kartenansicht, damit die Übersicht zeigen kann, welche
  /// Zeile gerade der Standard ist. Vor dem Laden `null` – dann trägt
  /// noch keine Zeile die Marke, statt kurz die falsche zu tragen.
  Kartenansicht? _standard;

  @override
  void initState() {
    super.initState();
    widget.library.db.kartenansicht().then((text) {
      if (!mounted) return;
      setState(() => _standard = Kartenansicht.ausText(text));
    });
  }

  Future<void> _seiteOeffnen(String adresse) async {
    final t = AppTexte.of(context);
    if (!await oeffneWebseite(adresse)) {
      melde.warnung(t.einstKartenquellenSeiteFehler(adresse));
    }
  }

  /// Merkt eine mitgelieferte Ansicht als Standard.
  Future<void> _standardSetzen(Kartenansicht ansicht, String name) async {
    final t = AppTexte.of(context);
    await widget.library.db.setzeKartenansicht(ansicht.alsText);
    if (!mounted) return;
    setState(() => _standard = ansicht);
    melde.erfolg(t.einstKartenquellenStandardGesetzt(name));
  }

  /// Schaltet eine Vorlage ohne Schlüssel ein und merkt sie als Standard.
  ///
  /// Derselbe Weg wie beim Speichern im Formular darunter – Warnung
  /// zuerst, dann in die Einstellungen, dann sofort in den laufenden
  /// Kartenweg (`setzeEigeneKarte`). Ohne den letzten Schritt zeigte die
  /// Karte die neue Quelle erst nach einem Neustart.
  Future<void> _uebernehmen(Kartenvorlage v) async {
    final t = AppTexte.of(context);
    if (await zeigeKartenwarnung(context) != true || !mounted) return;
    final karte = Eigenkarte.vonVorlage(v);
    await widget.library.db.setzeEigeneKarteWert(karte);
    setzeEigeneKarte(karte);
    await widget.library.db.setzeKartenansicht(Kartenansicht.eigene.alsText);
    if (!mounted) return;
    setState(() => _standard = Kartenansicht.eigene);
    melde.erfolg(t.einstKartenquellenUebernommen(v.name));
  }

  Future<void> _eintragen(Kartenvorlage v) async {
    widget.aufVorlage?.call(v);
    melde.hinweis(AppTexte.of(context).einstKartenquellenEingetragen(v.name));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final eigene = eigeneKarte;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text(
            '${t.einstKartenquellenText}\n\n${t.einstKartenquellenKnoepfe}',
            style: TextStyle(fontSize: 12, color: farben.onSurfaceVariant),
          ),
        ),
        Card(
          child: Column(
            children: [
              // Die drei mitgelieferten. Ihre Namen stehen in der
              // Oberfläche und nicht im Aufzählungstyp – deshalb hier und
              // nicht in [Kartenstil].
              _mitgeliefert(Icons.light_mode_outlined, t.karteHell,
                  Kartenstil.hell, Kartenansicht.hell),
              _mitgeliefert(Icons.dark_mode_outlined, t.karteDunkel,
                  Kartenstil.dunkel, Kartenansicht.dunkel,
                  // Mit CARTO-Schlüssel kommen Kacheln in doppelter
                  // Auflösung vom Server, ohne wird sie nachgebildet.
                  hochaufloesend: cartoSchluessel != null),
              _mitgeliefert(Icons.terrain_outlined, t.karteTopografie,
                  Kartenstil.topo, Kartenansicht.topo),
              const Divider(height: 1),
              for (final v in kartenvorlagen)
                _Zeile(
                  symbol: v.brauchtSchluessel
                      ? Icons.vpn_key_outlined
                      : Icons.public_outlined,
                  name: v.name,
                  stufe: v.stufe,
                  gemessen: v.gemessen,
                  mitgeliefert: false,
                  schluessel: v.brauchtSchluessel,
                  hochaufloesend: v.url.contains('{r}'),
                  nennung: v.nennung,
                  // Standard ist eine Vorlage nur dann, wenn sie
                  // eingeschaltet IST und die Karte auf „eigene" steht –
                  // die Adresse allein sagt nur, welche Zeile gemeint
                  // wäre.
                  standard: _standard == Kartenansicht.eigene &&
                      eigene?.url == v.url,
                  seite: v.seite,
                  aufSeite: _seiteOeffnen,
                  aktion: v.sofortNutzbar
                      ? _Aktion(
                          text: t.einstKartenquellenUebernehmen,
                          hinweis: t.einstKartenquellenUebernehmenHinweis,
                          tun: () => _uebernehmen(v),
                        )
                      : _Aktion(
                          text: t.einstKartenquellenEintragen,
                          hinweis: t.einstKartenquellenEintragenHinweis,
                          tun: () => _eintragen(v),
                        ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mitgeliefert(
    IconData symbol,
    String name,
    Kartenstil stil,
    Kartenansicht ansicht, {
    bool hochaufloesend = false,
  }) {
    final t = AppTexte.of(context);
    return _Zeile(
      symbol: symbol,
      name: name,
      stufe: stil.hoechsteEchteStufe!,
      gemessen: true,
      mitgeliefert: true,
      hochaufloesend: hochaufloesend,
      nennung: stil.namensnennung,
      standard: _standard == ansicht,
      seite: stil.seite,
      aufSeite: _seiteOeffnen,
      aktion: _Aktion(
        text: t.einstKartenquellenAlsStandard,
        hinweis: t.einstKartenquellenAlsStandardHinweis,
        tun: () => _standardSetzen(ansicht, name),
      ),
    );
  }
}

/// Was der Knopf am rechten Rand einer Zeile tut.
class _Aktion {
  const _Aktion({required this.text, required this.hinweis, required this.tun});

  final String text;
  final String hinweis;
  final Future<void> Function() tun;
}

class _Zeile extends StatelessWidget {
  const _Zeile({
    required this.symbol,
    required this.name,
    required this.stufe,
    required this.gemessen,
    required this.mitgeliefert,
    required this.nennung,
    required this.standard,
    required this.aktion,
    this.seite,
    this.aufSeite,
    this.schluessel = false,
    this.hochaufloesend = false,
  });

  final IconData symbol;
  final String name;
  final int stufe;
  final bool gemessen;
  final bool mitgeliefert;
  final bool schluessel;
  final bool hochaufloesend;
  final String nennung;

  /// Ob diese Quelle die gemerkte Kartenansicht ist.
  final bool standard;

  /// Die Seite des Anbieters, falls es eine gibt.
  final String? seite;
  final Future<void> Function(String)? aufSeite;

  final _Aktion aktion;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final meter = massstabMeter(stufe);
    // Unter tausend Metern ganze Meter, darüber Kilometer – eine
    // Nachkommastelle bei 1.234 m wäre eine Genauigkeit, die die
    // Rechnung gar nicht hat.
    final massstab = meter >= 1000
        ? '${(meter / 1000).toStringAsFixed(1)} km'
        : '${meter.round()} m';

    // Was auf DIESEM Bildschirm passiert, nicht was allgemein möglich
    // wäre: Auf einem gewöhnlichen Bildschirm ist die doppelte Auflösung
    // gar kein Thema, und ein Hinweis darauf wäre nur Lärm.
    final dicht = MediaQuery.of(context).devicePixelRatio > 1.0;
    final marken = <String>[
      mitgeliefert
          ? t.einstKartenquellenMitgeliefert
          : t.einstKartenquellenVorlage,
      gemessen
          ? t.einstKartenquellenGemessen
          : t.einstKartenquellenLautAnbieter,
      if (schluessel) t.einstKartenquellenSchluessel,
      if (dicht && hochaufloesend) t.einstKartenquellenHochaufloesend,
      if (dicht && !hochaufloesend) t.einstKartenquellenSimuliert,
    ];

    return ListTile(
      dense: true,
      leading: Icon(symbol, size: 20, color: farben.onSurfaceVariant),
      title: Row(
        children: [
          Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
          if (standard) ...[
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.check_circle, size: 14, color: farben.primary),
            const SizedBox(width: 4),
            Text(
              t.einstKartenquellenStandard,
              style: TextStyle(fontSize: 11, color: farben.primary),
            ),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.einstKartenquellenTiefe('$stufe', massstab),
            style: TextStyle(fontSize: 12, color: farben.onSurfaceVariant),
          ),
          Text(
            [...marken, nennung].join(' · '),
            style: TextStyle(fontSize: 11, color: farben.onSurfaceVariant),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (seite case final adresse?)
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 18),
              tooltip: t.einstKartenquellenSeite,
              onPressed: () => aufSeite?.call(adresse),
            ),
          // Der Standard braucht keinen Knopf, der ihn zum Standard
          // macht – an seiner Stelle steht die Marke im Titel.
          if (!standard)
            Tooltip(
              message: aktion.hinweis,
              child: TextButton(
                onPressed: aktion.tun,
                child: Text(aktion.text),
              ),
            ),
        ],
      ),
    );
  }
}
