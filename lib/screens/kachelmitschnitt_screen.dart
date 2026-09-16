import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../services/kachelmitschnitt.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Zeigt, was beim Laden der Kartenkacheln wirklich passiert.
///
/// **Warum es diesen Bildschirm gibt.** Die grauen Löcher in der Karte
/// waren bis hierher nur von aussen zu messen: mit `log show` auf dem Mac,
/// mit einer Nachrechnung der Dateinamen im Kachelspeicher. Das Ergebnis
/// – 5702 TLS-Verbindungen für 496 angekommene Kacheln – liess sich nicht
/// erklären, weil es zwei völlig verschiedene Ursachen haben kann und
/// beide von aussen gleich aussehen: zu viele Abrufe, oder zu viele
/// Verbindungen für dieselben Abrufe.
///
/// Auf der Konsole stand dazu nichts, und das ist kein Zufall: flutter_map
/// hängt an den Bildstrom jeder Kachel einen eigenen Fehlerbehandler.
/// Damit gilt jeder Fehlschlag als behandelt und erreicht `FlutterError`
/// nie. **Die Abwesenheit von Meldungen war also nie ein Beleg.**
///
/// Hier stehen beide Zahlen nebeneinander, dazu jeder einzelne Abruf mit
/// Statuscode, Ausnahme und Dauer. Beim nächsten Mal muss niemand mehr
/// raten.
class KachelmitschnittScreen extends StatefulWidget {
  const KachelmitschnittScreen({super.key, Kachelmitschnitt? mitschnitt})
      : _mitschnitt = mitschnitt;

  /// Nur für den Prüfstand – sonst der eine, den die Karten benutzen.
  final Kachelmitschnitt? _mitschnitt;

  Kachelmitschnitt get mitschnitt => _mitschnitt ?? Kachelmitschnitt.instanz;

  @override
  State<KachelmitschnittScreen> createState() => _KachelmitschnittScreenState();
}

/// Wie oft die Anzeige nachgeführt wird, solange mitgeschrieben wird.
///
/// Der Mitschnitt meldet sich absichtlich **nicht** von sich aus: Bei
/// sechzig Kacheln in einer Sekunde wäre das sechzig Neuaufbauten, und
/// eine Uhr, die niemandem gehört, überlebt jeden Test. So gehört sie
/// diesem Bildschirm und wird in `dispose` abgestellt.
const _taktung = Duration(milliseconds: 500);

class _KachelmitschnittScreenState extends State<KachelmitschnittScreen> {
  Timer? _takt;

  @override
  void initState() {
    super.initState();
    if (widget.mitschnitt.laeuft) _taktStarten();
  }

  void _taktStarten() {
    _takt?.cancel();
    _takt = Timer.periodic(_taktung, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _takt?.cancel();
    super.dispose();
  }

  void _umschalten() {
    setState(() {
      if (widget.mitschnitt.laeuft) {
        widget.mitschnitt.halteAn();
        _takt?.cancel();
        _takt = null;
      } else {
        widget.mitschnitt.starte();
        _taktStarten();
      }
    });
  }

  Future<void> _kopieren() async {
    final t = AppTexte.of(context);
    await Clipboard.setData(ClipboardData(text: berichtAus(widget.mitschnitt)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.mitschnittKopiert)));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final laeuft = widget.mitschnitt.laeuft;
    final bilanz = widget.mitschnitt.bilanz;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.mitschnittTitel),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: t.mitschnittKopieren,
            onPressed: bilanz.abrufe == 0 ? null : _kopieren,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            t.mitschnittErklaerung,
            style: TextStyle(fontSize: 12, color: farben.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _umschalten,
                icon: Icon(laeuft ? Icons.stop : Icons.fiber_manual_record),
                label: Text(laeuft ? t.mitschnittAnhalten : t.mitschnittStarten),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton(
                onPressed: bilanz.abrufe == 0 ? null : () => setState(widget.mitschnitt.leere),
                child: Text(t.mitschnittLeeren),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            laeuft ? t.mitschnittLaeuft : t.mitschnittAus,
            style: TextStyle(
              fontSize: 12,
              color: laeuft ? context.semantik.erfolg : farben.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (bilanz.abrufe == 0)
            Text(t.mitschnittNochNichts, style: TextStyle(color: farben.onSurfaceVariant))
          else ...[
            _Verhaeltnisse(bilanz: bilanz),
            const SizedBox(height: AppSpacing.md),
            _Zahlen(bilanz: bilanz),
            if (bilanz.nachStatus.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              _Verteilung(
                titel: t.mitschnittStatusTitel,
                zeilen: {
                  for (final e in bilanz.nachStatus.entries) '${e.key}': e.value,
                },
              ),
            ],
            if (bilanz.nachFehler.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              _Verteilung(
                titel: t.mitschnittFehlerTitel,
                zeilen: bilanz.nachFehler,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            _Liste(eintraege: widget.mitschnitt.eintraege),
          ],
        ],
      ),
    );
  }
}

/// Die beiden Zahlen, wegen derer der Mitschnitt gebaut wurde – gross und
/// nebeneinander, weil erst der Vergleich die Frage beantwortet.
class _Verhaeltnisse extends StatelessWidget {
  const _Verhaeltnisse({required this.bilanz});
  final Kachelbilanz bilanz;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    // [IntrinsicHeight], damit beide Karten gleich hoch bleiben, auch
    // wenn eine Beschriftung umbricht. `CrossAxisAlignment.stretch` wäre
    // der kürzere Weg gewesen und wirft in einer scrollenden Liste
    // „BoxConstraints forces an infinite height".
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _GrosseZahl(
              wert: bilanz.verbindungenJeAbruf,
              beschriftung: t.mitschnittVerbJeAbruf,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _GrosseZahl(
              wert: bilanz.abrufeJeAdresse,
              beschriftung: t.mitschnittAbrufeJeKachel,
            ),
          ),
        ],
      ),
    );
  }
}

class _GrosseZahl extends StatelessWidget {
  const _GrosseZahl({required this.wert, required this.beschriftung});
  final double wert;
  final String beschriftung;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    // Ab dem Doppelten wird es auffällig, ab dem Vierfachen ist es die
    // Grössenordnung, um die es bei den grauen Kacheln ging.
    final farbe = wert >= 4
        ? Theme.of(context).colorScheme.error
        : wert >= 2
            ? context.semantik.warnung
            : farben.onSurface;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              wert.toStringAsFixed(1),
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(color: farbe, fontFeatures: const [
                FontFeature.tabularFigures(),
              ]),
            ),
            Text(
              beschriftung,
              style: TextStyle(fontSize: 12, color: farben.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Zahlen extends StatelessWidget {
  const _Zahlen({required this.bilanz});
  final Kachelbilanz bilanz;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final mb = (bilanz.bytes / (1024 * 1024)).toStringAsFixed(1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Zeile(t.mitschnittAbrufe, '${bilanz.abrufe}'),
            _Zeile(t.mitschnittVerbindungen, '${bilanz.verbindungen}'),
            _Zeile(t.mitschnittKacheln, '${bilanz.adressen}'),
            _Zeile(t.mitschnittGeglueckt, '${bilanz.geglueckt}'),
            _Zeile(t.mitschnittFehlgeschlagen, '${bilanz.fehlgeschlagen}'),
            _Zeile(t.mitschnittWiederholte, '${bilanz.wiederholte}'),
            _Zeile(t.mitschnittAbgebrochen, '${bilanz.abgebrochen}'),
            _Zeile(t.mitschnittOhneDauer, '${bilanz.ohneDauerverbindung}'),
            const SizedBox(height: AppSpacing.sm),
            Text(
              t.mitschnittDauer(
                bilanz.mittlereDauer.inMilliseconds,
                bilanz.laengsteDauer.inMilliseconds,
              ),
              style: TextStyle(fontSize: 12, color: farben.onSurfaceVariant),
            ),
            Text(
              t.mitschnittDaten(mb),
              style: TextStyle(fontSize: 12, color: farben.onSurfaceVariant),
            ),
            if (bilanz.verworfen > 0)
              Text(
                t.mitschnittVerworfen(bilanz.verworfen),
                style: TextStyle(fontSize: 12, color: context.semantik.warnung),
              ),
          ],
        ),
      ),
    );
  }
}

class _Zeile extends StatelessWidget {
  const _Zeile(this.beschriftung, this.wert);
  final String beschriftung;
  final String wert;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(beschriftung, style: Theme.of(context).textTheme.bodyMedium),
            ),
            Text(
              wert,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
}

class _Verteilung extends StatelessWidget {
  const _Verteilung({required this.titel, required this.zeilen});
  final String titel;
  final Map<String, int> zeilen;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titel, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in zeilen.entries) _Zeile(e.key, t.mitschnittMalGeholt(e.value)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Wie viele Abrufe die Liste zeigt.
///
/// Die neuesten, denn danach sucht, wer gerade eben eine graue Kachel
/// gesehen hat. Alle fünftausend in eine `ListView` zu setzen wäre in
/// dieser Ansicht (die selbst schon scrollt) eine Vollmaterialisierung.
const _listenLaenge = 100;

class _Liste extends StatelessWidget {
  const _Liste({required this.eintraege});
  final List<Kachelabruf> eintraege;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final neueste = eintraege.reversed.take(_listenLaenge).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.mitschnittLetzteTitel, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (final a in neueste)
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(
                      a.geglueckt
                          ? Icons.check
                          : a.abgebrochen
                              ? Icons.block
                              : Icons.close,
                      size: 18,
                      color: a.geglueckt
                          ? context.semantik.erfolg
                          : a.abgebrochen
                              ? farben.onSurfaceVariant
                              : Theme.of(context).colorScheme.error,
                    ),
                    title: Text(a.kachel, style: Theme.of(context).textTheme.bodyMedium),
                    subtitle: Text(
                      a.fehler ?? '${a.status} · ${a.bytes} B',
                      style: TextStyle(fontSize: 11, color: farben.onSurfaceVariant),
                    ),
                    trailing: Text(
                      '${a.dauer.inMilliseconds} ms',
                      style: TextStyle(
                        fontSize: 11,
                        color: farben.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
