import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../einfuegbares_menue.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';

/// Die Leiste unter einem Raster, sobald etwas ausgewählt ist (Issue
/// #128): wie viele, und was man mit ihnen tut – Favorit, Teilen, ins
/// Album, aufs Telefon, Papierkorb. Jede Aktion ist ein Befehl aus dem
/// Kern, also auch am Rechner und auf dem Server sichtbar.
class Auswahlleiste extends StatelessWidget {
  const Auswahlleiste({
    super.key,
    required this.sitzung,
    required this.zeilen,
    required this.aufheben,
  });

  final Sitzung sitzung;
  final List<Rasterzeile> zeilen;
  final VoidCallback aufheben;

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

  Future<void> _album(BuildContext context) async {
    final t = AppTexte.of(context);
    final alben = await _db.alleAlben();
    if (!context.mounted) return;
    final wahl = await showDialog<Object>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(t.auswahlAlbumTitel),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, true),
            child: Row(
              children: [
                const Icon(Icons.add),
                const SizedBox(width: 12),
                Text(t.auswahlAlbumNeu),
              ],
            ),
          ),
          for (final a in alben)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, a),
              child: Text(a.name),
            ),
        ],
      ),
    );
    if (wahl == null || !context.mounted) return;
    final String albumId;
    final String name;
    if (wahl is AlbumData) {
      albumId = wahl.id;
      name = wahl.name;
    } else {
      final neu = await _neuesAlbum(context);
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

  Future<String?> _neuesAlbum(BuildContext context) => showDialog<String>(
    context: context,
    builder: (_) => const _AlbumNameDialog(),
  );

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
    final alleFavorit = zeilen.every((z) => z.isFavorite);
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                  icon: alleFavorit ? Icons.favorite : Icons.favorite_border,
                  text: t.auswahlFavorit,
                  onPressed: _favorit,
                ),
                _Aktion(
                  icon: Icons.share_outlined,
                  text: t.auswahlTeilen,
                  onPressed: () => _teile(context),
                ),
                _Aktion(
                  icon: Icons.photo_album_outlined,
                  text: t.auswahlAlbum,
                  onPressed: () => _album(context),
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
          ],
        ),
      ),
    );
  }
}

/// Ein Knopf der Leiste: Symbol über kurzem Text, gleich breit wie die
/// anderen – fünf davon passen auf jedes Telefon.
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
