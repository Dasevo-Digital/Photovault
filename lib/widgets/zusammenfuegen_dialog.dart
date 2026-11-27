import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/zusammenfuegen/zusammenfuegen.dart';

import '../l10n/app_localizations.dart';
import '../services/meldungsdienst.dart';
import '../services/zusammenfuegen_dienst.dart';
import '../state/hintergrundlauf.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';

/// Der Eintrag „Zusammenfügen" der Auswahlleiste (#498): `null` unter zwei
/// ausgewählten Aufnahmen – dann erscheint er gar nicht. [danach] hebt
/// etwa die Auswahl auf, sobald der Lauf eingereiht ist.
void Function(Fuegeart art)? zusammenfuegenAktion(
  BuildContext context,
  LibraryState library,
  List<String> ausgewaehlt, {
  VoidCallback? danach,
}) {
  if (ausgewaehlt.length < 2) return null;
  return (art) => unawaited(
    starteZusammenfuegen(context, library, ausgewaehlt, art, danach: danach),
  );
}

/// Fragt die Optionen ab, reiht das Zusammenfügen in die Aufgabenleiste
/// ein (Fortschritt und „Abbrechen" wie bei jeder Aufgabe) und meldet am
/// Ende, was daraus wurde.
///
/// Am Rechner und mit Server gleich: Gerechnet wird hier, abgelegt über
/// den Import bzw. das Hochladen (siehe [zusammenfuegenLauf]).
Future<void> starteZusammenfuegen(
  BuildContext context,
  LibraryState library,
  List<String> ids,
  Fuegeart art, {
  VoidCallback? danach,
}) async {
  final t = AppTexte.of(context);
  final (:quellen, :ausgelassen) = await zusammenfuegbare(library.db, ids);
  if (!context.mounted) return;
  if (quellen.length < art.mindestens || quellen.length > art.hoechstens) {
    melde.warnung(t.zusfAnzahl(art.mindestens, art.hoechstens));
    return;
  }
  final wahl = await showDialog<_Fuegewahl>(
    context: context,
    builder: (_) => _ZusammenfuegenDialog(
      art: art,
      anzahl: quellen.length,
      ausgelassen: ausgelassen,
    ),
  );
  if (wahl == null || !context.mounted) return;

  Fuegeausgang? ausgang;
  final titel = art == Fuegeart.hdr ? t.zusfLaufHdr : t.zusfLaufPanorama;
  // Nicht als rechenintensiv eingereiht: Solche Läufe warten, bis die
  // Hintergrundanalyse durch ist – nach einem grossen Import Stunden. Wer
  // hier ausdrücklich zusammenfügt, wartet auf genau dieses Bild. Den
  // Speicher begrenzen die Obergrenzen der Ausgabe (HDR 24 MP, Panorama
  // 50 MP) und der feste Schlüssel: Es läuft immer nur eines.
  final abweisung = library.reiheAufgabeEin(
    schluessel: zusammenfuegenSchluessel,
    titel: titel,
    leermeldung: titel,
    auchVerbunden: true,
    strom: () => zusammenfuegenLauf(
      library,
      quellen: quellen,
      art: art,
      ausrichten: wahl.ausrichten,
      drehung: wahl.drehung,
      zuschneiden: wahl.zuschneiden,
      fertig: (a) => ausgang = a,
    ),
  );
  if (abweisung != null) {
    melde.hinweis(
      abweisung == Startabweisung.laeuftBereits
          ? t.zusfLaeuftSchon
          : abweisungstext(t, abweisung),
    );
    return;
  }
  danach?.call();
  final lauf = library.lauf(zusammenfuegenSchluessel);
  if (lauf == null) return;
  await lauf.abschluss;
  // Eine Runde später: `beendet` setzt die Bibliothek erst, nachdem der
  // Abschluss gemeldet ist – sonst bliebe die Zeile stehen.
  await Future<void>(() {});
  final fehler = lauf.fehler;
  final a = ausgang;
  if (lauf.abgebrochen) {
    // Wer abbricht, weiss es schon.
  } else if (fehler != null) {
    melde.fehler(zusammenfuegeFehlertext(t, fehler, quellen, art));
  } else if (a != null) {
    melde.erfolg(art == Fuegeart.hdr ? t.zusfFertigHdr : t.zusfFertigPanorama);
    if (a.verwendet < a.angeboten) {
      melde.warnung(t.zusfTeilweise(a.angeboten - a.verwendet));
    }
  }
  library.verwerfeLauf(zusammenfuegenSchluessel);
}

/// Der Satz zu einem gescheiterten Zusammenfügen: die bekannten Gründe in
/// der Sprache der Oberfläche, mit dem Namen der betroffenen Quelle, wo es
/// einen gibt; alles andere als Text des Fehlers.
String zusammenfuegeFehlertext(
  AppTexte t,
  Object fehler,
  List<AssetData> quellen,
  Fuegeart art,
) {
  if (fehler is! Zusammenfuegefehler) return t.zusfFehlerAllgemein('$fehler');
  final stelle = fehler.quelle;
  final name = stelle != null && stelle >= 0 && stelle < quellen.length
      ? quellen[stelle].originalFileName
      : '?';
  return switch (fehler.grund) {
    Fuegegrund.anzahl => t.zusfAnzahl(art.mindestens, art.hoechstens),
    Fuegegrund.groessenUngleich => t.zusfFehlerGroesse(name),
    Fuegegrund.keineUeberlappung => t.zusfFehlerUeberlappung,
    Fuegegrund.nichtAusrichtbar => t.zusfFehlerAusrichtung,
    Fuegegrund.unlesbar => t.zusfFehlerUnlesbar(name),
  };
}

/// Was im Dialog gewählt wurde.
class _Fuegewahl {
  const _Fuegewahl({
    required this.ausrichten,
    required this.drehung,
    required this.zuschneiden,
  });

  final bool ausrichten;
  final bool drehung;
  final bool zuschneiden;
}

class _ZusammenfuegenDialog extends StatefulWidget {
  const _ZusammenfuegenDialog({
    required this.art,
    required this.anzahl,
    required this.ausgelassen,
  });

  final Fuegeart art;
  final int anzahl;
  final int ausgelassen;

  @override
  State<_ZusammenfuegenDialog> createState() => _ZusammenfuegenDialogState();
}

class _ZusammenfuegenDialogState extends State<_ZusammenfuegenDialog> {
  bool _ausrichten = true;
  bool _drehung = true;
  bool _zuschneiden = true;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final hdr = widget.art == Fuegeart.hdr;
    final klein = Theme.of(context).textTheme.bodySmall;
    return AlertDialog(
      title: Text(hdr ? t.zusfHdrTitel : t.zusfPanoramaTitel),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hdr
                    ? t.zusfHdrText(widget.anzahl)
                    : t.zusfPanoramaText(widget.anzahl),
              ),
              if (widget.ausgelassen > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(t.zusfAusgelassen(widget.ausgelassen), style: klein),
              ],
              const SizedBox(height: AppSpacing.sm),
              if (hdr) ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _ausrichten,
                  onChanged: (v) => setState(() => _ausrichten = v ?? true),
                  title: Text(t.zusfAusrichten),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _ausrichten && _drehung,
                  onChanged: _ausrichten
                      ? (v) => setState(() => _drehung = v ?? true)
                      : null,
                  title: Text(t.zusfDrehung),
                ),
              ] else
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _zuschneiden,
                  onChanged: (v) => setState(() => _zuschneiden = v ?? true),
                  title: Text(t.zusfZuschneiden),
                  subtitle: _zuschneiden
                      ? null
                      : Text(t.zusfZuschneidenHinweis),
                ),
              const SizedBox(height: AppSpacing.sm),
              Text(t.zusfGeisterHinweis, style: klein),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.allgAbbrechen),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _Fuegewahl(
              ausrichten: _ausrichten,
              drehung: _ausrichten && _drehung,
              zuschneiden: _zuschneiden,
            ),
          ),
          child: Text(t.zusfStarten),
        ),
      ],
    );
  }
}
