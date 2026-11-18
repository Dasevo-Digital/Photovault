import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kern/services/backup_auswahl.dart';

import '../l10n/app_localizations.dart';
import '../widgets/einfuegbares_menue.dart';

/// Durchsucht genau den geöffneten Sicherungsstand.
class BackupAuswahlScreen extends StatefulWidget {
  const BackupAuswahlScreen({
    super.key,
    required this.katalog,
    required this.bibliothek,
  });

  final BackupAuswahl katalog;
  final Directory bibliothek;

  @override
  State<BackupAuswahlScreen> createState() => _BackupAuswahlScreenState();
}

class _BackupAuswahlScreenState extends State<BackupAuswahlScreen> {
  final _auswahl = <String>{};
  late var _treffer = widget.katalog.aufnahmen;
  bool _laeuft = false;
  bool _fehler = false;
  AuswahlExportStand? _stand;

  Future<void> _exportiere() async {
    setState(() {
      _laeuft = true;
      _fehler = false;
      _stand = null;
    });
    try {
      final ziel = await FilePicker.getDirectoryPath(
        dialogTitle: AppTexte.of(context).einstBackupZielWaehlen,
      );
      if (ziel == null || !mounted) return;
      await for (final stand in widget.katalog.exportiere(
        Set.of(_auswahl),
        Directory(ziel),
        bibliothek: widget.bibliothek,
      )) {
        if (!mounted) break;
        setState(() => _stand = stand);
      }
    } on Object {
      if (mounted) setState(() => _fehler = true);
    } finally {
      if (mounted) setState(() => _laeuft = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final locale = Localizations.localeOf(context).toString();
    final dateien = _treffer;
    final sichtbar = dateien.where((a) => a.liegtVor).map((a) => a.pruefsumme);
    final stand = _stand;
    return Scaffold(
      appBar: AppBar(title: Text(t.backupAuswahlTitel)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              contextMenuBuilder: einfuegbaresMenue,
              onChanged: (text) => setState(
                () => _treffer = widget.katalog.aufnahmen
                    .where((a) => a.passtZu(text))
                    .toList(),
              ),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                labelText: t.backupAuswahlSuche,
                helperText: t.backupAuswahlDatum,
              ),
            ),
          ),
          Expanded(
            child: dateien.isEmpty
                ? Center(child: Text(t.backupAuswahlLeer))
                : ListView.builder(
                    itemCount: dateien.length,
                    itemBuilder: (context, i) {
                      final a = dateien[i];
                      final details = [
                        if (a.datum case final datum?)
                          DateFormat.yMd(locale).format(datum),
                        ...a.alben,
                        if (!a.liegtVor) t.backupAuswahlDateiFehlt,
                      ];
                      return CheckboxListTile(
                        title: Text(a.name),
                        subtitle: details.isEmpty
                            ? null
                            : Text(details.join(' · ')),
                        value: _auswahl.contains(a.pruefsumme),
                        onChanged: !a.liegtVor || _laeuft
                            ? null
                            : (v) => setState(() {
                                if (v == true) {
                                  _auswahl.add(a.pruefsumme);
                                } else {
                                  _auswahl.remove(a.pruefsumme);
                                }
                              }),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_laeuft)
                    LinearProgressIndicator(
                      value: stand == null
                          ? null
                          : stand.erledigt / stand.gesamt,
                    ),
                  if (_fehler) Text(t.backupAuswahlExportFehler),
                  if (!_laeuft && stand != null && !_fehler)
                    SelectableText(
                      stand.erledigt == stand.fehler.length
                          ? t.backupAuswahlExportNull
                          : t.backupAuswahlExportFertig(
                              stand.erledigt - stand.fehler.length,
                              stand.fehler.length,
                              stand.ordner.path,
                            ),
                    ),
                  if (!_laeuft && stand != null && stand.fehler.isNotEmpty)
                    Text(
                      stand.fehler.take(8).join(', '),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _laeuft || sichtbar.isEmpty
                            ? null
                            : () => setState(() => _auswahl.addAll(sichtbar)),
                        child: Text(t.backupAuswahlTreffer),
                      ),
                      TextButton(
                        onPressed: _laeuft || _auswahl.isEmpty
                            ? null
                            : () => setState(_auswahl.clear),
                        child: Text(t.backupAuswahlLeeren),
                      ),
                      FilledButton.icon(
                        onPressed: _laeuft || _auswahl.isEmpty
                            ? null
                            : _exportiere,
                        icon: const Icon(Icons.file_download_outlined),
                        label: Text(
                          t.backupAuswahlExportieren(_auswahl.length),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
