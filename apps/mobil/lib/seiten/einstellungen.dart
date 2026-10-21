import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/bibliothekseinstellungen.dart';

import '../einfuegbares_menue.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'sicherung.dart';

/// Die Einstellungen der Bibliothek – dieselben Zeilen wie im Browser
/// (web/app.js, zeigeEinstellungen): oben die Sprache dieser App, darunter
/// was der Bibliothek gehört und für alle Geräte gilt. Geändert wird über
/// dieselben Befehle; der Abgleich bringt es zum Server.
class Einstellungen extends StatefulWidget {
  const Einstellungen({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  State<Einstellungen> createState() => _EinstellungenState();
}

class _EinstellungenState extends State<Einstellungen> {
  Bibliothekseinstellungen? _e;
  final _tage = TextEditingController();
  var _leeren = false;
  var _vorschlaegeAn = false;
  var _vorschlaegeAb = 0.9;
  var _schwelle = 0.5;

  AppDatabase get _db => widget.sitzung.db;

  @override
  void initState() {
    super.initState();
    _lade();
  }

  @override
  void dispose() {
    _tage.dispose();
    super.dispose();
  }

  Future<void> _lade() async {
    final e = await bibliothekseinstellungen(_db);
    if (!mounted) return;
    setState(() {
      _e = e;
      _leeren = e.papierkorbLeeren;
      _tage.text = '${e.papierkorbTage}';
      _vorschlaegeAn = e.vorschlaegeAb != null;
      _vorschlaegeAb = e.vorschlaegeAb ?? 0.9;
      _schwelle = e.gesichtsschwelle;
    });
  }

  Future<void> _sende(Befehl<void> b) async {
    final t = AppTexte.of(context);
    final bote = ScaffoldMessenger.of(context);
    await _db.fuehreAus(b);
    bote
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t.einstGespeichert)));
    await _lade();
  }

  int get _tageZahl => (int.tryParse(_tage.text) ?? 30).clamp(1, 3650);

  static String _prozent(double w) => '${(w * 100).round()} %';

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final e = _e;
    if (e == null) return const Center(child: CircularProgressIndicator());
    final farben = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        _Zeile(
          titel: t.einstSprache,
          text: t.einstSpracheHinweis,
          zusatz: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'auto', label: Text(t.einstAutomatisch)),
                const ButtonSegment(value: 'de', label: Text('Deutsch')),
                const ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {widget.sitzung.sprache ?? 'auto'},
              onSelectionChanged: (w) => widget.sitzung.setzeSprache(
                w.first == 'auto' ? null : w.first,
              ),
            ),
          ),
        ),
        // Gilt wie die Sprache nur für dieses Telefon – darum über den
        // Einstellungen der Bibliothek. Dieselbe Seite wie unter „Konto“
        // (#204: dort fand man sie nicht).
        if (widget.sitzung.sicherung case final d?)
          ListenableBuilder(
            listenable: d,
            builder: (context, _) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: const Icon(Icons.backup_outlined),
              title: Text(t.einstSicherung),
              subtitle: Text('${t.einstSicherungText}\n${sicherungKurz(t, d)}'),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      Sicherungsseite(dienst: d, db: widget.sitzung.db),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
          child: Text(
            t.einstTitel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            t.einstHinweis,
            style: TextStyle(color: farben.onSurfaceVariant, fontSize: 12),
          ),
        ),
        _Zeile(
          titel: t.einstPapierkorb,
          text: t.einstPapierkorbText,
          an: _leeren,
          beiAenderung: (an) {
            setState(() => _leeren = an);
            _sende(PapierkorbFristSetzen(an: an, tage: _tageZahl));
          },
          zusatz: Row(
            children: [
              Text(t.einstNach),
              const SizedBox(width: 8),
              SizedBox(
                width: 72,
                child: TextField(
                  controller: _tage,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  contextMenuBuilder: einfuegbaresMenue,
                  decoration: const InputDecoration(isDense: true),
                  onSubmitted: (_) => _sende(
                    PapierkorbFristSetzen(an: _leeren, tage: _tageZahl),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(t.einstTagen),
            ],
          ),
        ),
        _Zeile(
          titel: t.einstVorschlaege,
          text: t.einstVorschlaegeText,
          an: _vorschlaegeAn,
          beiAenderung: (an) {
            setState(() => _vorschlaegeAn = an);
            _sende(VorschlaegeAutomatischSetzen(an ? _vorschlaegeAb : null));
          },
          zusatz: _Regler(
            wert: _vorschlaegeAb,
            min: 0.8,
            max: 0.99,
            schritte: 19,
            anzeige: (v) => t.einstAb(_prozent(v)),
            beiAenderung: (v) => setState(() => _vorschlaegeAb = v),
            fertig: (v) {
              if (_vorschlaegeAn) _sende(VorschlaegeAutomatischSetzen(v));
            },
          ),
        ),
        _Zeile(
          titel: t.einstAuswerten,
          text: t.einstAuswertenText,
          an: e.auswertenNachImport,
          beiAenderung: (an) => _sende(AuswertenNachImportSetzen(an)),
        ),
        _Zeile(
          titel: t.einstUebersetzen,
          text: t.einstUebersetzenText,
          an: e.sucheUebersetzen,
          beiAenderung: (an) => _sende(SucheUebersetzenSetzen(an)),
        ),
        _Zeile(
          titel: t.einstSchuetzen,
          text: t.einstSchuetzenText,
          an: e.angabenSchuetzen,
          beiAenderung: (an) => _sende(AngabenSchuetzenSetzen(an)),
        ),
        _Zeile(
          titel: t.einstSchwelle,
          text: t.einstSchwelleText,
          zusatz: _Regler(
            wert: _schwelle,
            min: 0.2,
            max: 0.8,
            schritte: 60,
            anzeige: (v) => v.toStringAsFixed(2),
            beiAenderung: (v) => setState(() => _schwelle = v),
            fertig: (v) => _sende(GesichtsschwelleSetzen(v)),
          ),
        ),
      ],
    );
  }
}

/// Eine Zeile: Titel, Erklärung, auf Wunsch ein Schalter und darunter, was
/// zur Einstellung gehört (Frist, Regler).
class _Zeile extends StatelessWidget {
  const _Zeile({
    required this.titel,
    required this.text,
    this.an,
    this.beiAenderung,
    this.zusatz,
  });

  final String titel;
  final String text;
  final bool? an;
  final ValueChanged<bool>? beiAenderung;
  final Widget? zusatz;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final an = this.an;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: farben.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titel,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      text,
                      style: TextStyle(
                        color: farben.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (an != null) Switch(value: an, onChanged: beiAenderung),
            ],
          ),
          ?zusatz,
        ],
      ),
    );
  }
}

class _Regler extends StatelessWidget {
  const _Regler({
    required this.wert,
    required this.min,
    required this.max,
    required this.schritte,
    required this.anzeige,
    required this.beiAenderung,
    required this.fertig,
  });

  final double wert;
  final double min;
  final double max;
  final int schritte;
  final String Function(double) anzeige;
  final ValueChanged<double> beiAenderung;
  final ValueChanged<double> fertig;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Slider(
          value: wert.clamp(min, max),
          min: min,
          max: max,
          divisions: schritte,
          onChanged: beiAenderung,
          onChangeEnd: fertig,
        ),
      ),
      SizedBox(width: 64, child: Text(anzeige(wert))),
    ],
  );
}
