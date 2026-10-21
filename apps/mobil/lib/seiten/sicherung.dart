import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:photo_manager/photo_manager.dart';

import '../l10n/app_localizations.dart';
import '../sicherung/dienst.dart';
import '../sicherung/photo_manager_rolle.dart';

/// Kamerarolle sichern: ein- und ausschalten, sehen, wie weit es ist, und
/// was mitgeht.
class Sicherungsseite extends StatelessWidget {
  const Sicherungsseite({super.key, required this.dienst, this.db});

  final Sicherungsdienst dienst;

  /// Die Kopie der Bibliothek – für „Speicher freigeben“; ohne sie fehlt
  /// der Punkt.
  final AppDatabase? db;

  Future<void> _freigeben(BuildContext context, AppDatabase db) async {
    final t = AppTexte.of(context);
    final bote = ScaffoldMessenger.of(context);
    bote.showSnackBar(SnackBar(content: Text(t.sicherungFreigebenSucht)));
    final f = dienst.freigabe(db);
    final ids = await f.kandidaten();
    bote.hideCurrentSnackBar();
    if (!context.mounted) return;
    if (ids.isEmpty) {
      bote.showSnackBar(SnackBar(content: Text(t.sicherungFreigebenNichts)));
      return;
    }
    final ja = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.sicherungFreigebenTitel(ids.length)),
        content: Text(t.sicherungFreigebenText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.abbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.sicherungFreigebenLoeschen),
          ),
        ],
      ),
    );
    if (ja != true) return;
    final n = await f.gib(ids);
    bote.showSnackBar(SnackBar(content: Text(t.sicherungFreigegeben(n))));
  }

  Future<void> _einschalten(BuildContext context, bool an) async {
    if (!an) return dienst.schalteAus();
    await dienst.schalteEin();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return ListenableBuilder(
      listenable: dienst,
      builder: (context, _) {
        final e = dienst.einstellungen;
        return Scaffold(
          appBar: AppBar(title: Text(t.sicherungTitel)),
          body: ListView(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.backup_outlined),
                title: Text(t.sicherungAn),
                subtitle: Text(t.sicherungAnHinweis),
                value: e.an,
                onChanged: (an) => _einschalten(context, an),
              ),
              ..._zugriff(t),
              if (e.an) ..._stand(context, t),
              if (e.an && db != null)
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: Text(t.sicherungFreigeben),
                  subtitle: Text(t.sicherungFreigebenHinweis),
                  onTap: () => _freigeben(context, db!),
                ),
              const Divider(),
              SwitchListTile(
                secondary: const Icon(Icons.videocam_outlined),
                title: Text(t.sicherungVideos),
                value: e.videos,
                onChanged: (v) => dienst.setze(e.mit(videos: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.wifi),
                title: Text(t.sicherungNurWlan),
                value: e.nurWlan,
                onChanged: (v) => dienst.setze(e.mit(nurWlan: v)),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.battery_charging_full),
                title: Text(t.sicherungNurBeimLaden),
                value: e.nurBeimLaden,
                onChanged: (v) => dienst.setze(e.mit(nurBeimLaden: v)),
              ),
              ListTile(
                leading: const Icon(Icons.photo_album_outlined),
                title: Text(t.sicherungAlben),
                subtitle: Text(
                  e.alben.isEmpty
                      ? t.sicherungAlleFotos
                      : t.sicherungAlbenAnzahl(e.alben.length),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _Albenwahl(dienst: dienst),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Text(
                  Platform.isIOS
                      ? t.sicherungHinweisIos
                      : t.sicherungHinweisAndroid,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _zugriff(AppTexte t) => switch (dienst.zugriff) {
    Zugriff.verweigert => [
      ListTile(
        leading: const Icon(Icons.no_photography_outlined),
        title: Text(t.sicherungKeinZugriff),
        subtitle: Text(t.sicherungKeinZugriffHinweis),
        trailing: TextButton(
          onPressed: dienst.oeffneEinstellungen,
          child: Text(t.sicherungEinstellungenOeffnen),
        ),
      ),
    ],
    Zugriff.teilweise => [
      ListTile(
        leading: const Icon(Icons.photo_library_outlined),
        title: Text(t.sicherungTeilweise),
        subtitle: Text(t.sicherungTeilweiseHinweis),
        trailing: TextButton(
          onPressed: dienst.auswahlAendern,
          child: Text(t.sicherungAuswahlAendern),
        ),
      ),
    ],
    _ => const [],
  };

  List<Widget> _stand(BuildContext context, AppTexte t) {
    final f = dienst.fortschritt;
    final b = dienst.letzterLauf;
    final gesamt = f?.gesamt ?? b?.gesamt;
    final sicher =
        f?.sicher ?? (b == null ? null : b.gesamt - b.offen - b.fehlgeschlagen);
    final probleme = dienst.fehlgeschlagen.length + dienst.abgelehnt;
    final sprache = Localizations.localeOf(context).toLanguageTag();
    final warte = switch (dienst.wartet) {
      Wartegrund.wlan => t.sicherungWartetWlan,
      Wartegrund.netz => t.sicherungWartetNetz,
      Wartegrund.hintergrund => t.sicherungImHintergrund,
      null => null,
    };
    final fehler = dienst.fehler;
    return [
      ListTile(
        leading: dienst.laeuft
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Icon(
                gesamt != null && sicher == gesamt
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_upload_outlined,
              ),
        title: Text(
          gesamt == null
              ? t.sicherungNochNicht
              : t.sicherungStand(sicher ?? 0, gesamt),
        ),
        subtitle: Text(
          f?.datei != null
              ? t.sicherungLaedt(f!.datei!)
              : warte ??
                    (b == null
                        ? t.sicherungNochNicht
                        : t.sicherungZuletzt(
                            DateFormat.yMd(sprache).add_Hm().format(b.ende),
                          )),
        ),
      ),
      if (gesamt != null && gesamt > 0)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LinearProgressIndicator(
            value: f?.von != null && f!.von! > 0
                ? f.bytes! / f.von!
                : (sicher ?? 0) / gesamt,
          ),
        ),
      if (fehler != null)
        ListTile(
          leading: const Icon(Icons.error_outline),
          title: Text(
            fehler is Serverfehler && fehler.abgemeldet
                ? t.abgemeldetHinweis
                : t.sicherungFehler,
          ),
        ),
      if (probleme > 0)
        ListTile(
          leading: const Icon(Icons.warning_amber_outlined),
          title: Text(t.sicherungProbleme(probleme)),
          subtitle: switch ((
            dienst.fehlgeschlagen.values,
            dienst.abgelehntGruende.values,
          )) {
            (final f, _) when f.isNotEmpty => Text(f.first),
            (_, final g) when g.isNotEmpty => Text(g.first),
            _ => null,
          },
          trailing: TextButton(
            onPressed: dienst.versucheFehlerErneut,
            child: Text(t.sicherungErneut),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: FilledButton.tonalIcon(
          icon: const Icon(Icons.sync),
          label: Text(t.sicherungJetzt),
          onPressed: dienst.laeuft
              ? null
              : () => jetztSichern(context, dienst, db: db),
        ),
      ),
    ];
  }
}

/// Welche Alben mitgehen – „Alle Fotos“ oder eine Auswahl.
class _Albenwahl extends StatefulWidget {
  const _Albenwahl({required this.dienst});

  final Sicherungsdienst dienst;

  @override
  State<_Albenwahl> createState() => _AlbenwahlState();
}

class _AlbenwahlState extends State<_Albenwahl> {
  late final Future<List<(AssetPathEntity, int)>> _alben = _lade();
  late var _gewaehlt = {...widget.dienst.einstellungen.alben};

  static Future<List<(AssetPathEntity, int)>> _lade() async => [
    for (final a in await PhotoManagerRolle.albenZurAuswahl())
      if (!a.isAll) (a, await a.assetCountAsync),
  ];

  void _speichere() {
    final e = widget.dienst.einstellungen;
    widget.dienst.setze(e.mit(alben: _gewaehlt.toList()..sort()));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.sicherungAlben)),
      body: FutureBuilder<List<(AssetPathEntity, int)>>(
        future: _alben,
        builder: (context, snap) {
          final alben = snap.data;
          if (alben == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            children: [
              CheckboxListTile(
                title: Text(t.sicherungAlleFotos),
                value: _gewaehlt.isEmpty,
                onChanged: (_) {
                  setState(() => _gewaehlt = {});
                  _speichere();
                },
              ),
              const Divider(),
              for (final (album, anzahl) in alben)
                CheckboxListTile(
                  title: Text(album.name),
                  subtitle: Text(t.karteFotos(anzahl)),
                  value: _gewaehlt.contains(album.id),
                  onChanged: (an) {
                    setState(() {
                      an == true
                          ? _gewaehlt.add(album.id)
                          : _gewaehlt.remove(album.id);
                    });
                    _speichere();
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Für die Kontoseite: eine Zeile mit dem Stand der Sicherung.
String sicherungKurz(AppTexte t, Sicherungsdienst d) {
  final e = d.einstellungen;
  if (!e.an) return t.sicherungAus;
  final b = d.letzterLauf;
  if (d.laeuft) return t.sicherungLaeuft;
  if (b == null) return t.sicherungNochNicht;
  return t.sicherungStand(b.gesamt - b.offen - b.fehlgeschlagen, b.gesamt);
}

/// „Jetzt sichern“ von Hand – überall gleich (Zeitleiste, Betrachter,
/// Sicherungsseite): sichern und **sagen, wie es ausging** (#204). Vorher
/// tat ein Tipp oft sichtbar nichts, siehe [Sicherungsdienst.sichereJetzt].
Future<void> jetztSichern(
  BuildContext context,
  Sicherungsdienst d, {
  AppDatabase? db,
  bool mobil = false,
}) async {
  final t = AppTexte.of(context);
  final bote = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  void seite() => navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => Sicherungsseite(dienst: d, db: db),
    ),
  );
  void sag(String text, [SnackBarAction? aktion]) => bote
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), action: aktion));

  final antwort = await d.sichereJetzt(mobil: mobil);
  final b = d.letzterLauf;
  switch (antwort) {
    case Sicherungsantwort.aus:
      sag(
        t.jetztAus,
        SnackBarAction(label: t.jetztEinrichten, onPressed: seite),
      );
    case Sicherungsantwort.keinZugriff:
      sag(
        t.sicherungKeinZugriff,
        SnackBarAction(
          label: t.sicherungEinstellungenOeffnen,
          onPressed: d.oeffneEinstellungen,
        ),
      );
    case Sicherungsantwort.wartetWlan:
      sag(
        t.jetztWartetWlan,
        SnackBarAction(
          label: t.jetztMobil,
          onPressed: () {
            if (context.mounted) {
              jetztSichern(context, d, db: db, mobil: true);
            }
          },
        ),
      );
    case Sicherungsantwort.wartetNetz:
      sag(t.sicherungWartetNetz);
    case Sicherungsantwort.imHintergrund:
      sag(t.sicherungImHintergrund);
    case Sicherungsantwort.laeuft:
      sag(t.sicherungLaeuft);
    case Sicherungsantwort.fehler:
      final f = d.fehler;
      sag(
        f is Serverfehler && f.abgemeldet
            ? t.abgemeldetHinweis
            : t.sicherungFehler,
      );
    case Sicherungsantwort.fertig when b != null && b.fehlgeschlagen > 0:
      sag(
        t.jetztTeils(b.hochgeladen + b.vorhanden, b.fehlgeschlagen),
        SnackBarAction(label: t.jetztDetails, onPressed: seite),
      );
    case Sicherungsantwort.fertig when b != null && b.hochgeladen > 0:
      sag(t.jetztGesichert(b.hochgeladen));
    case Sicherungsantwort.fertig:
      sag(t.jetztAllesSicher);
  }
}
