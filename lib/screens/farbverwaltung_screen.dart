import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/farbverwaltung.dart';
import '../services/meldungsdienst.dart';

class FarbverwaltungScreen extends StatefulWidget {
  const FarbverwaltungScreen({super.key, required this.dienst});
  final Farbverwaltung dienst;
  @override
  State<FarbverwaltungScreen> createState() => _FarbverwaltungScreenState();
}

class _FarbverwaltungScreenState extends State<FarbverwaltungScreen> {
  Farbeinstellungen? _werte;
  bool _fehler = false, _arbeitet = false;
  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    try {
      final w = await widget.dienst.laden();
      if (mounted) setState(() => _werte = w);
    } on Object {
      if (mounted) setState(() => _fehler = true);
    }
  }

  Future<void> _aendern(Profilrolle rolle, String? kennung) async {
    setState(() => _arbeitet = true);
    try {
      final w = (_werte ?? const Farbeinstellungen()).mit(rolle, kennung);
      await widget.dienst.speichern(w);
      if (mounted) {
        setState(() {
          _werte = w;
          _fehler = false;
        });
      }
    } on Object {
      if (mounted) melde.fehler(AppTexte.of(context).farbraumFehler);
    } finally {
      if (mounted) setState(() => _arbeitet = false);
    }
  }

  Future<void> _waehlen(Profilrolle rolle) async {
    final aus = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['icc', 'icm'],
      dialogTitle: AppTexte.of(context).farbraumProfilWaehlen,
    );
    if (aus?.path == null || !mounted) return;
    setState(() => _arbeitet = true);
    try {
      final w = await widget.dienst.uebernehmen(File(aus!.path!), rolle);
      if (mounted) setState(() => _werte = w);
    } on Object {
      if (mounted) melde.fehler(AppTexte.of(context).farbraumFehler);
    } finally {
      if (mounted) setState(() => _arbeitet = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context), w = _werte;
    Widget profil(Profilrolle rolle, String titel, String? wert) {
      final standard = rolle == Profilrolle.bildschirm
          ? 'system'
          : rolle == Profilrolle.ausgabe
          ? 'original'
          : null;
      final liste = <String?, String>{
        standard: rolle == Profilrolle.bildschirm
            ? t.farbraumSystem
            : rolle == Profilrolle.ausgabe
            ? t.farbraumBeibehalten
            : t.farbraumKeinProfil,
        'srgb': t.farbraumStandard,
        'p3': t.farbraumP3,
        if (wert != null &&
            !['system', 'original', 'srgb', 'p3'].contains(wert))
          wert: t.farbraumEigenesProfil,
      };
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titel, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              DropdownButton<String?>(
                isExpanded: true,
                value: wert,
                items: [
                  for (final e in liste.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: _arbeitet ? null : (x) => _aendern(rolle, x),
              ),
              TextButton.icon(
                onPressed: _arbeitet ? null : () => _waehlen(rolle),
                icon: const Icon(Icons.folder_open),
                label: Text(t.farbraumProfilWaehlen),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(t.farbraumTitel)),
      body: w == null && !_fehler
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_fehler) Text(t.farbraumFehler),
                Text(t.farbraumVerwendung),
                profil(
                  Profilrolle.bildschirm,
                  t.farbraumBildschirm,
                  w?.bildschirm ?? 'system',
                ),
                profil(Profilrolle.druck, t.farbraumDruck, w?.druck),
                profil(
                  Profilrolle.ausgabe,
                  t.farbraumAusgabe,
                  w?.ausgabe ?? 'original',
                ),
                if (w != null)
                  DropdownButton<int>(
                    isExpanded: true,
                    value: w.intent,
                    items: [
                      for (var i = 0; i < 4; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            [
                              t.farbraumIntentWahrnehmung,
                              t.farbraumIntentRelativ,
                              t.farbraumIntentSaettigung,
                              t.farbraumIntentAbsolut,
                            ][i],
                          ),
                        ),
                    ],
                    onChanged: _arbeitet
                        ? null
                        : (i) async {
                            if (i == null) return;
                            setState(() => _arbeitet = true);
                            try {
                              final neu = Farbeinstellungen(
                                bildschirm: w.bildschirm,
                                druck: w.druck,
                                ausgabe: w.ausgabe,
                                intent: i,
                              );
                              await widget.dienst.speichern(neu);
                              if (mounted) setState(() => _werte = neu);
                            } on Object {
                              if (mounted) melde.fehler(t.farbraumFehler);
                            } finally {
                              if (mounted) setState(() => _arbeitet = false);
                            }
                          },
                  ),
                Text(t.farbraumHinweis),
              ],
            ),
    );
  }
}
