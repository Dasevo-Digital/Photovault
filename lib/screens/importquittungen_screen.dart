import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_auswahl.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../services/backup_service.dart';
import '../services/backup_verification_service.dart';
import '../services/importquittungen.dart';
import '../services/meldungsdienst.dart';
import '../services/sicherungsziel.dart';
import '../state/library_state.dart';
import '../widgets/pin_dialogs.dart';

Future<void> zeigeImportquittungen(
  BuildContext context,
  LibraryState library, {
  String? id,
}) async {
  final t = AppTexte.of(context);
  final Importquittungen ablage;
  try {
    ablage = await Importquittungen.fuer(library.paths.root);
  } on Object {
    if (context.mounted) melde.fehler(t.quittungLesefehler);
    return;
  }
  if (!context.mounted) return;
  Future<String?> ziel() async {
    final settings = await library.db.backupSettingsRow();
    if (settings?.autoBackupDestination case final pfad?
        when settings?.autoBackupEnabled == true) {
      return p.join(
        await Sicherungsziel.oeffne(pfad),
        BackupService.autoBackupFolderName,
      );
    }
    return (await library.db.lastBackupRecord())?.destinationPath;
  }

  final db = library.db;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => id == null
          ? _Quittungsliste(ablage: ablage, ziel: ziel, db: db)
          : _Quittungsdetail(ablage: ablage, id: id, ziel: ziel, db: db),
    ),
  );
}

class _Quittungsliste extends StatefulWidget {
  const _Quittungsliste({
    required this.ablage,
    required this.ziel,
    required this.db,
  });
  final Importquittungen ablage;
  final Future<String?> Function() ziel;
  final AppDatabase db;

  @override
  State<_Quittungsliste> createState() => _QuittungslisteState();
}

class _QuittungslisteState extends State<_Quittungsliste> {
  late final _belege = widget.ablage.liste();

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final format = DateFormat.yMd(
      Localizations.localeOf(context).toString(),
    ).add_Hm();
    return Scaffold(
      appBar: AppBar(title: Text(t.importQuittungenTitel)),
      body: FutureBuilder<List<QuittungKopf>>(
        future: _belege,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(t.quittungLesefehler));
          }
          final belege = snapshot.data;
          if (belege == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (belege.isEmpty) return Center(child: Text(t.quittungLeer));
          return ListView.builder(
            itemCount: belege.length,
            itemBuilder: (context, i) {
              final beleg = belege[i];
              return ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text(format.format(beleg.am)),
                subtitle: Text(t.quittungDateien(beleg.anzahl)),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => _Quittungsdetail(
                      ablage: widget.ablage,
                      id: beleg.id,
                      ziel: widget.ziel,
                      db: widget.db,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Quittungsdetail extends StatefulWidget {
  const _Quittungsdetail({
    required this.ablage,
    required this.id,
    required this.ziel,
    required this.db,
  });
  final Importquittungen ablage;
  final String id;
  final Future<String?> Function() ziel;
  final AppDatabase db;

  @override
  State<_Quittungsdetail> createState() => _QuittungsdetailState();
}

class _QuittungsdetailState extends State<_Quittungsdetail> {
  late var _beleg = _lies();

  Future<Importquittung> _lies() async {
    final beleg = await widget.ablage.lies(widget.id);
    final gesperrt = await widget.db.alleGesperrten();
    return beleg.mitVerdecktenDateinamen({
      for (final a in gesperrt) a.checksum,
    });
  }

  bool _laeuft = false, _fehler = false;
  double? _fortschritt;

  Future<void> _pruefe(
    Importquittung beleg, {
    required bool ordnerWaehlen,
  }) async {
    setState(() {
      _laeuft = true;
      _fortschritt = null;
      _fehler = false;
    });
    try {
      final t = AppTexte.of(context);
      var ziel = ordnerWaehlen ? null : await widget.ziel();
      if (!mounted) return;
      ziel ??= await FilePicker.getDirectoryPath(
        dialogTitle: t.einstBackupOrdnerWaehlen,
      );
      if (ziel == null || !mounted) return;

      final wurzel = await BackupPruefdienst.findeBackupWurzel(ziel);
      if (!await File(p.join(wurzel, 'metadata.json')).exists()) {
        throw const BackupOrdnerFehlt();
      }
      String? passphrase;
      if (await File(p.join(wurzel, 'vault.key')).exists()) {
        if (!mounted) return;
        passphrase = await showEnterPassphraseDialog(
          context,
          title: t.einstBackupPassphraseEingeben,
        );
        if (passphrase == null) return;
      }
      final sicherung = await BackupAuswahl.oeffne(
        wurzel,
        schemaVersion: widget.db.schemaVersion,
        passphrase: passphrase,
        nurPruefsummen: beleg.pruefsummen,
      );
      await widget.ablage.pruefeKopien(
        beleg,
        sicherung,
        p.basename(wurzel),
        fortschritt: (fertig, gesamt) {
          if (mounted) setState(() => _fortschritt = fertig / gesamt);
        },
      );
      if (mounted) setState(() => _beleg = _lies());
    } on Object {
      if (mounted) setState(() => _fehler = true);
    } finally {
      if (mounted) setState(() => _laeuft = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final format = DateFormat.yMd(
      Localizations.localeOf(context).toString(),
    ).add_Hm();
    return Scaffold(
      appBar: AppBar(title: Text(t.quittungTitel)),
      body: FutureBuilder<Importquittung>(
        future: _beleg,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(t.quittungLesefehler));
          }
          final beleg = snapshot.data;
          if (beleg == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final pruefung = beleg.pruefung;
          final kopienPruefbar = beleg.dateien.any((a) => a.pruefbar);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                title: Text(format.format(beleg.kopf.am)),
                subtitle: Text(
                  [
                    t.quittungDateien(beleg.dateien.length),
                    if (!beleg.fertig) t.quittungUnvollstaendig,
                    if (pruefung != null)
                      t.quittungPruefdatum(
                        format.format(pruefung.am),
                        pruefung.ziel,
                      ),
                  ].join('\n'),
                ),
              ),
              if (_laeuft) LinearProgressIndicator(value: _fortschritt),
              if (_fehler)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(t.quittungPrueffehler),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: beleg.dateien.length,
                  itemBuilder: (context, i) {
                    final a = beleg.dateien[i];
                    final ergebnis = switch (a.ergebnis) {
                      ImportErgebnis.importiert => t.quittungImportiert,
                      ImportErgebnis.kammer => t.quittungKammer,
                      ImportErgebnis.duplikat => t.quittungDuplikat,
                      ImportErgebnis.ausgelassen => t.quittungAusgelassen,
                      ImportErgebnis.fehler => t.quittungDateifehler,
                      ImportErgebnis.offen => t.quittungOffen,
                    };
                    final kopie = a.pruefbar
                        ? switch (pruefung?.befunde[a.pruefsumme]) {
                            Kopienbefund.bestaetigt => t.quittungKopieGeprueft,
                            Kopienbefund.fehlt => t.quittungKopieFehlt,
                            Kopienbefund.unlesbar => t.quittungKopieDefekt,
                            null => t.quittungKopieUngeprueft,
                          }
                        : null;
                    return ListTile(
                      title: Text(a.name.isEmpty ? t.kammerGesperrt : a.name),
                      subtitle: Text(
                        kopie == null ? ergebnis : '$ergebnis · $kopie',
                      ),
                    );
                  },
                ),
              ),
              if (kopienPruefbar)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: _laeuft
                              ? null
                              : () => _pruefe(beleg, ordnerWaehlen: true),
                          child: Text(t.quittungZielWaehlen),
                        ),
                        FilledButton(
                          onPressed: _laeuft
                              ? null
                              : () => _pruefe(beleg, ordnerWaehlen: false),
                          child: Text(t.quittungKopienPruefen),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
