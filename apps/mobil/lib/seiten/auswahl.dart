import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../bilder.dart';
import '../einfuegbares_menue.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';

/// Das Blatt unter einem Raster, sobald etwas ausgewählt ist (Issue
/// #128), aufgebaut wie in Immich: oben wie viele, darunter die Aktionen
/// – Favorit, Teilen, aufs Telefon, Papierkorb – und ein Streifen mit den
/// Alben, in die ein Tipp die Auswahl legt. Jede Aktion ist ein Befehl aus
/// dem Kern, also auch am Rechner und auf dem Server sichtbar.
class Auswahlleiste extends StatefulWidget {
  const Auswahlleiste({
    super.key,
    required this.sitzung,
    required this.zeilen,
    required this.aufheben,
  });

  final Sitzung sitzung;
  final List<Rasterzeile> zeilen;
  final VoidCallback aufheben;

  @override
  State<Auswahlleiste> createState() => _AuswahlleisteState();
}

class _AuswahlleisteState extends State<Auswahlleiste> {
  // Einmal je Blatt gelesen, nicht bei jedem Neubau – das Blatt baut sich
  // mit jeder gewählten Kachel neu.
  late final Future<List<AlbumData>> _alben = _db.alleAlben();
  final _titelbilder = <String, Future<AssetData?>>{};

  Sitzung get sitzung => widget.sitzung;
  List<Rasterzeile> get zeilen => widget.zeilen;
  void aufheben() => widget.aufheben();

  List<String> get _ids => [for (final z in zeilen) z.id];

  AppDatabase get _db => sitzung.db;

  Future<void> _favorit() async {
    // Sind schon alle Favoriten, nimmt der Tipp es allen wieder weg.
    final alle = zeilen.every((z) => z.isFavorite);
    await _db.fuehreAus(FavoritSetzen(_ids, !alle));
    aufheben();
  }

  Future<void> _teile(BuildContext context) async {
    final t = AppTexte.of(context);
    final bote = ScaffoldMessenger.of(context);
    bote.showSnackBar(SnackBar(content: Text(t.auswahlLaedt)));
    try {
      final dateien = <XFile>[];
      final namen = <String>[];
      for (final z in zeilen) {
        final f = await sitzung.paths.bereit(z.relativePath);
        dateien.add(XFile(f.path));
        namen.add(z.originalFileName);
      }
      bote.hideCurrentSnackBar();
      await SharePlus.instance.share(
        ShareParams(files: dateien, fileNameOverrides: namen),
      );
      aufheben();
    } catch (_) {
      bote
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(t.betrachterNichtGeladen)));
    }
  }

  /// In [album] legen – oder, ohne Album, erst eines anlegen.
  Future<void> _insAlbum(BuildContext context, AlbumData? album) async {
    final t = AppTexte.of(context);
    final String albumId;
    final String name;
    if (album != null) {
      albumId = album.id;
      name = album.name;
    } else {
      final neu = await showDialog<String>(
        context: context,
        builder: (_) => const _AlbumNameDialog(),
      );
      if (neu == null) return;
      albumId = const Uuid().v4();
      name = neu;
      await _db.fuehreAus(AlbumAnlegen(albumId, name, DateTime.now()));
    }
    await _db.fuehreAus(AlbumFuellen(albumId, _ids));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.auswahlImAlbum(zeilen.length, name))),
    );
    aufheben();
  }

  Future<void> _aufsTelefon(BuildContext context) async {
    final t = AppTexte.of(context);
    final bote = ScaffoldMessenger.of(context);
    final recht = await PhotoManager.requestPermissionExtend();
    if (!recht.hasAccess) {
      bote.showSnackBar(SnackBar(content: Text(t.auswahlKeinZugriff)));
      return;
    }
    bote.showSnackBar(SnackBar(content: Text(t.auswahlLaedt)));
    var n = 0;
    try {
      for (final z in zeilen) {
        final File f = await sitzung.paths.bereit(z.relativePath);
        if (z.type == 'VIDEO') {
          await PhotoManager.editor.saveVideo(f, title: z.originalFileName);
        } else {
          await PhotoManager.editor.saveImageWithPath(
            f.path,
            title: z.originalFileName,
          );
        }
        n++;
      }
      bote
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(t.auswahlGespeichert(n))));
      aufheben();
    } catch (_) {
      bote
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(t.betrachterNichtGeladen)));
    }
  }

  Future<void> _papierkorb(BuildContext context) async {
    final t = AppTexte.of(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.auswahlPapierkorbTitel(zeilen.length)),
        content: Text(t.auswahlPapierkorbText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.abbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.betrachterPapierkorb),
          ),
        ],
      ),
    );
    if (ja != true) return;
    await _db.fuehreAus(InDenPapierkorb(_ids));
    aufheben();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final alleFavorit = zeilen.every((z) => z.isFavorite);
    return Material(
      elevation: 12,
      color: farben.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: farben.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: t.auswahlAufheben,
                  icon: const Icon(Icons.close),
                  onPressed: aufheben,
                ),
                Text(
                  t.auswahlAnzahl(zeilen.length),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            Row(
              children: [
                _Aktion(
                  icon: Icons.share_outlined,
                  text: t.auswahlTeilen,
                  onPressed: () => _teile(context),
                ),
                _Aktion(
                  icon: alleFavorit ? Icons.favorite : Icons.favorite_border,
                  text: t.auswahlFavorit,
                  onPressed: _favorit,
                ),
                _Aktion(
                  icon: Icons.download_outlined,
                  text: t.auswahlHerunterladen,
                  onPressed: () => _aufsTelefon(context),
                ),
                _Aktion(
                  icon: Icons.delete_outline,
                  text: t.auswahlPapierkorb,
                  onPressed: () => _papierkorb(context),
                ),
              ],
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  t.auswahlAlbumTitel,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
            SizedBox(
              height: 100,
              child: FutureBuilder<List<AlbumData>>(
                future: _alben,
                builder: (context, snap) => ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _Albumkachel(
                      text: t.auswahlAlbumNeu,
                      onTap: () => _insAlbum(context, null),
                      bild: ColoredBox(
                        color: farben.surfaceContainerHighest,
                        child: Icon(Icons.add, color: farben.primary),
                      ),
                    ),
                    for (final a in snap.data ?? const <AlbumData>[])
                      _Albumkachel(
                        text: a.name,
                        onTap: () => _insAlbum(context, a),
                        bild: FutureBuilder<AssetData?>(
                          future: _titelbilder.putIfAbsent(
                            a.id,
                            () => _db.albumTitelbild(a),
                          ),
                          builder: (context, bild) => Miniatur(
                            paths: sitzung.paths,
                            relativ: bild.data?.thumbnailRelativePath,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

/// Ein Album im Streifen des Auswahlblatts: Titelbild und Name.
class _Albumkachel extends StatelessWidget {
  const _Albumkachel({
    required this.text,
    required this.onTap,
    required this.bild,
  });

  final String text;
  final VoidCallback onTap;
  final Widget bild;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox.square(dimension: 72, child: bild),
            ),
            const SizedBox(height: 4),
            Text(
              text,
              style: Theme.of(context).textTheme.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Ein Knopf der Leiste: Symbol über kurzem Text, gleich breit wie die
/// anderen.
class _Aktion extends StatelessWidget {
  const _Aktion({
    required this.icon,
    required this.text,
    required this.onPressed,
  });

  final IconData icon;
  final String text;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(height: 2),
            Text(
              text,
              style: Theme.of(context).textTheme.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Fragt nach dem Namen eines neuen Albums. Der Controller gehört dem
/// Dialog – freigegeben erst, wenn der Dialog ganz verschwunden ist.
class _AlbumNameDialog extends StatefulWidget {
  const _AlbumNameDialog();

  @override
  State<_AlbumNameDialog> createState() => _AlbumNameDialogState();
}

class _AlbumNameDialogState extends State<_AlbumNameDialog> {
  final _feld = TextEditingController();

  @override
  void dispose() {
    _feld.dispose();
    super.dispose();
  }

  void _fertig() {
    final name = _feld.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return AlertDialog(
      title: Text(t.auswahlAlbumNeu),
      content: TextField(
        contextMenuBuilder: einfuegbaresMenue,
        controller: _feld,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: t.auswahlAlbumName),
        onSubmitted: (_) => _fertig(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.abbrechen),
        ),
        FilledButton(onPressed: _fertig, child: Text(t.auswahlAlbumAnlegen)),
      ],
    );
  }
}
