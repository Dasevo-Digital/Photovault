import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/eigenkarte.dart';
import '../services/meldungsdienst.dart';
import '../services/platform/webseite_oeffnen.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import 'mini_location_map.dart';

/// Die Einstellung für eine selbst eingetragene Kartenquelle.
///
/// **Eigene Datei und nicht im Einstellungsbildschirm**, weil sie
/// Zustand mitbringt – fünf Textfelder, eine gewählte Vorlage, ein
/// laufender Sitzungsabruf. Der Einstellungsbildschirm hält bereits
/// über zwanzig solcher Felder; noch fünf hineinzulegen hiesse, sie
/// beim Lesen nicht mehr auseinanderhalten zu können.
class EigeneKarteEinstellung extends StatefulWidget {
  const EigeneKarteEinstellung({super.key, required this.library});

  final LibraryState library;

  @override
  State<EigeneKarteEinstellung> createState() => EigeneKarteEinstellungState();
}

class EigeneKarteEinstellungState extends State<EigeneKarteEinstellung> {
  final _name = TextEditingController();
  final _adresse = TextEditingController();
  final _nennung = TextEditingController();
  final _stufe = TextEditingController();

  bool _geladen = false;
  bool _sitzungLaeuft = false;
  Kartenvorlage? _vorlage;

  @override
  void initState() {
    super.initState();
    unawaitedLaden();
  }

  void unawaitedLaden() {
    widget.library.db.eigeneKarteWert().then((karte) {
      if (!mounted) return;
      setState(() {
        _geladen = true;
        if (karte == null) return;
        _name.text = karte.name;
        _adresse.text = karte.url;
        _nennung.text = karte.nennung;
        _stufe.text = karte.stufe?.toString() ?? '';
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _adresse.dispose();
    _nennung.dispose();
    _stufe.dispose();
    super.dispose();
  }

  /// Schreibt eine Vorlage in die Felder – gespeichert wird damit noch
  /// nichts.
  ///
  /// **Öffentlich**, weil die Quellenübersicht darüber hierher
  /// verweist: Vorlagen mit Schlüssel kann sie nicht selbst einschalten,
  /// wohl aber alles ausfüllen ausser dem Schlüssel.
  void vorlageEinsetzen(Kartenvorlage v) {
    setState(() {
      _vorlage = v;
      _name.text = v.name;
      _adresse.text = v.url;
      _nennung.text = v.nennung;
      _stufe.text = '${v.stufe}';
    });
  }

  /// Holt bei Google eine Sitzung und setzt sie in die Adresse ein.
  Future<void> _sitzungHolen() async {
    final t = AppTexte.of(context);
    final adresse = _adresse.text.trim();
    // Der Schlüssel steht in der Adresse (siehe [Eigenkarte.url]) – also
    // wird er auch von dort geholt, statt ein zweites Feld dafür zu
    // führen, das mit der Adresse auseinanderlaufen könnte.
    final schluessel = schluesselAusAdresse(adresse);
    if (schluessel == null) {
      melde.warnung(t.einstEigeneKarteSitzungOhneSchluessel);
      return;
    }
    setState(() => _sitzungLaeuft = true);
    final antwort = await googleSitzung(schluessel);
    if (!mounted) return;
    setState(() => _sitzungLaeuft = false);
    if (antwort.sitzung == null) {
      melde.warnung(t.einstEigeneKarteSitzungFehler(antwort.fehler ?? ''));
      return;
    }
    setState(() {
      _adresse.text = sitzungEinsetzen(adresse, antwort.sitzung!);
    });
    melde.erfolg(t.einstEigeneKarteSitzungOk);
  }

  Future<void> _seiteOeffnen(String adresse) async {
    final t = AppTexte.of(context);
    if (!await oeffneWebseite(adresse)) {
      melde.warnung(t.einstKartenquellenSeiteFehler(adresse));
    }
  }

  String? _adressfehlertext(AppTexte t) {
    final fehler = Eigenkarte.adressfehler(_adresse.text);
    return switch (fehler) {
      null => null,
      Adressfehler.leer => t.einstEigeneKarteFehlerLeer,
      Adressfehler.keinHttp => t.einstEigeneKarteFehlerHttp,
      Adressfehler.platzhalterFehlt =>
        t.einstEigeneKarteFehlerPlatzhalter('{z}, {x}, {y}'),
      Adressfehler.platzhalterUnbekannt =>
        t.einstEigeneKarteFehlerUnbekannt('{z}, {x}, {y}, {s}, {r}'),
      Adressfehler.schluesselFehlt => t.einstEigeneKarteFehlerSchluessel,
    };
  }

  Future<void> _speichern() async {
    final t = AppTexte.of(context);
    final fehler = _adressfehlertext(t);
    if (fehler != null) {
      melde.warnung(fehler);
      return;
    }
    if (_nennung.text.trim().isEmpty) {
      melde.warnung(t.einstEigeneKarteFehlerNennung);
      return;
    }
    // Der Hinweis kommt vor dem Speichern und nicht danach: Wer ihn
    // abbricht, soll nichts eingeschaltet haben.
    final ja = await zeigeKartenwarnung(context);
    if (ja != true || !mounted) return;

    final karte = Eigenkarte(
      name: _name.text.trim(),
      url: _adresse.text.trim(),
      nennung: _nennung.text.trim(),
      stufe: int.tryParse(_stufe.text.trim()),
      zugestimmt: true,
    );
    await widget.library.db.setzeEigeneKarteWert(karte);
    // Sofort und nicht erst beim nächsten Start – dieselbe Handhabung wie
    // beim CARTO-Schlüssel.
    setzeEigeneKarte(karte);
    if (!mounted) return;
    setState(() {});
    melde.erfolg(t.einstEigeneKarteGespeichert);
  }

  Future<void> _entfernen() async {
    final t = AppTexte.of(context);
    await widget.library.db.setzeEigeneKarteWert(null);
    setzeEigeneKarte(null);
    if (!mounted) return;
    setState(() {
      _name.clear();
      _adresse.clear();
      _nennung.clear();
      _stufe.clear();
      _vorlage = null;
    });
    melde.hinweis(t.einstEigeneKarteEntfernt);
  }


  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final eingerichtet = eigeneKarte;
    if (!_geladen) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Text(
            t.einstEigeneKarteText,
            style: TextStyle(fontSize: 12, color: farben.onSurfaceVariant),
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
                      eingerichtet != null
                          ? Icons.check_circle
                          : Icons.travel_explore_outlined,
                      color: eingerichtet != null
                          ? context.semantik.erfolg
                          : null,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        eingerichtet == null
                            ? t.einstEigeneKarteOhne
                            : t.einstEigeneKarteAktiv(
                                eingerichtet.name.isEmpty
                                    ? t.karteEigene
                                    : eingerichtet.name),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                PopupMenuButton<Kartenvorlage>(
                  onSelected: vorlageEinsetzen,
                  itemBuilder: (context) => [
                    for (final v in kartenvorlagen)
                      PopupMenuItem(
                        value: v,
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(v.name),
                          subtitle: Text(v.gemessen
                              ? t.einstEigeneKarteVorlageGemessen('${v.stufe}')
                              : t.einstEigeneKarteVorlageLautAnbieter(
                                  '${v.stufe}')),
                        ),
                      ),
                  ],
                  child: OutlinedButton.icon(
                    // Der Knopf öffnet das Menü nicht selbst – das tut der
                    // PopupMenuButton darum herum. `onPressed: null` machte
                    // ihn grau, deshalb ein leerer Rückruf.
                    onPressed: null,
                    icon: const Icon(Icons.playlist_add_outlined),
                    label: Text(t.einstEigeneKarteVorlage),
                  ),
                ),
                // Anklickbar und nicht nur genannt: Wer hier steht,
                // braucht als Naechstes genau diese Seite - und muesste
                // den Namen sonst abtippen.
                if (_vorlage case final v? when v.woher != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _seiteOeffnen(v.seite),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text(t.einstEigeneKarteWoher(v.woher!)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                if (_vorlage?.brauchtSchluessel ?? false)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      t.einstEigeneKarteSchluesselHinweis(schluesselMarke),
                      style:
                          TextStyle(fontSize: 12, color: farben.onSurfaceVariant),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: t.einstEigeneKarteName,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _adresse,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: t.einstEigeneKarteAdresse,
                    hintText: t.einstEigeneKarteAdresseHinweis('{z}/{x}/{y}'),
                    errorText:
                        _adresse.text.isEmpty ? null : _adressfehlertext(t),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _nennung,
                  decoration: InputDecoration(
                    labelText: t.einstEigeneKarteNennung,
                    hintText: t.einstEigeneKarteNennungHinweis,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _stufe,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: t.einstEigeneKarteStufe,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                if (brauchtSitzung(_adresse.text)) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    t.einstEigeneKarteSitzungText,
                    style: TextStyle(
                        fontSize: 12, color: farben.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  OutlinedButton.icon(
                    onPressed: _sitzungLaeuft ? null : _sitzungHolen,
                    icon: _sitzungLaeuft
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.vpn_key_outlined),
                    label: Text(t.einstEigeneKarteSitzung),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    FilledButton(
                      onPressed: _speichern,
                      child: Text(t.allgSpeichern),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    if (eingerichtet != null)
                      TextButton(
                        onPressed: _entfernen,
                        child: Text(t.einstEigeneKarteEntfernen),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Warnzeile extends StatelessWidget {
  const _Warnzeile({required this.symbol, required this.text});

  final IconData symbol;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(symbol,
              size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text)),
        ],
      );
}

/// Der Hinweis, der vor dem Einschalten einer fremden Kartenquelle
/// stehen muss: Datenübermittlung, Offline-Nutzung, Nutzungsregeln.
///
/// **Als Funktion und nicht als Methode**, seit die Quellenübersicht
/// Vorlagen mit einem Klick einschalten kann. Beide Wege führen zu
/// derselben Einstellung – und beide müssen deshalb dieselbe Warnung
/// zeigen. Zwei Fassungen wären zwei Stände.
Future<bool?> zeigeKartenwarnung(BuildContext context) {
  final t = AppTexte.of(context);
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t.einstEigeneKarteWarnungTitel),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Warnzeile(
                symbol: Icons.cell_tower_outlined,
                text: t.einstEigeneKarteWarnungUebermittlung),
            const SizedBox(height: AppSpacing.md),
            _Warnzeile(
                symbol: Icons.cloud_off_outlined,
                text: t.einstEigeneKarteWarnungOffline),
            const SizedBox(height: AppSpacing.md),
            _Warnzeile(
                symbol: Icons.gavel_outlined,
                text: t.einstEigeneKarteWarnungBedingungen),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t.allgAbbrechen),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(t.einstEigeneKarteWarnungAnnehmen),
        ),
      ],
    ),
  );
}
