import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:share_plus/share_plus.dart';

import '../einfuegbares_menue.dart';
import '../l10n/app_localizations.dart';

/// Als Link teilen (Issue #106) – wie im Browser (web/app.js,
/// oeffneLinkDialog): ein Album oder eine Auswahl, mit Ablauf, auf Wunsch
/// mit Passwort, Originale nur, wenn erlaubt. Der Link geht über den
/// Server; ohne Verbindung gibt es keinen.
Future<void> alsLinkTeilen(
  BuildContext context,
  Serververbindung? verbindung, {
  String? albumId,
  List<String>? ids,
  required String titel,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: _LinkBlatt(
      verbindung: verbindung,
      albumId: albumId,
      ids: ids,
      titel: titel,
    ),
  ),
);

class _LinkBlatt extends StatefulWidget {
  const _LinkBlatt({
    required this.verbindung,
    required this.titel,
    this.albumId,
    this.ids,
  });

  /// `null` ohne Verbindung zum Server.
  final Serververbindung? verbindung;
  final String titel;
  final String? albumId;
  final List<String>? ids;

  @override
  State<_LinkBlatt> createState() => _LinkBlattState();
}

class _LinkBlattState extends State<_LinkBlatt> {
  late final _titel = TextEditingController(text: widget.titel);
  final _passwort = TextEditingController();
  int? _tage = 7;
  var _herunterladen = false;
  var _laeuft = false;
  String? _link;
  String? _meldung;

  @override
  void dispose() {
    _titel.dispose();
    _passwort.dispose();
    super.dispose();
  }

  Future<void> _erstellen() async {
    final t = AppTexte.of(context);
    final titel = _titel.text.trim();
    if (titel.isEmpty) {
      setState(() => _meldung = t.linkTitelFehlt);
      return;
    }
    final passwort = _passwort.text;
    if (passwort.isNotEmpty && passwort.length < 4) {
      setState(() => _meldung = t.linkPasswortKurz);
      return;
    }
    final verbindung = widget.verbindung;
    if (verbindung == null) {
      setState(() => _meldung = t.linkOhneServer);
      return;
    }
    setState(() {
      _laeuft = true;
      _meldung = null;
    });
    try {
      final d = await verbindung.schicke('api/v1/freigaben', {
        'titel': titel,
        'album': ?widget.albumId,
        'ids': ?widget.ids,
        'tage': ?_tage,
        if (passwort.isNotEmpty) 'passwort': passwort,
        'herunterladen': _herunterladen,
      });
      setState(() => _link = '${d['link']}');
    } on Serverfehler catch (f) {
      setState(() => _meldung = f.text.isEmpty ? '${f.status}' : f.text);
    } catch (x) {
      setState(() => _meldung = '$x');
    } finally {
      if (mounted) setState(() => _laeuft = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final link = _link;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(t.linkTitel, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (link == null) ...[
            TextField(
              controller: _titel,
              contextMenuBuilder: einfuegbaresMenue,
              decoration: InputDecoration(
                labelText: t.linkFeldTitel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _tage,
              decoration: InputDecoration(
                labelText: t.linkGueltig,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: 1, child: Text(t.linkTag1)),
                DropdownMenuItem(value: 7, child: Text(t.linkTage(7))),
                DropdownMenuItem(value: 30, child: Text(t.linkTage(30))),
                DropdownMenuItem(value: 365, child: Text(t.linkJahr1)),
                DropdownMenuItem(value: null, child: Text(t.linkUnbegrenzt)),
              ],
              onChanged: (w) => setState(() => _tage = w),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwort,
              obscureText: true,
              contextMenuBuilder: einfuegbaresMenue,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: t.linkPasswort,
                border: const OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.linkHerunterladen),
              value: _herunterladen,
              onChanged: (w) => setState(() => _herunterladen = w),
            ),
            Text(
              t.linkOhneMetadaten,
              style: TextStyle(fontSize: 12, color: farben.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _laeuft ? null : _erstellen,
              child: Text(t.linkErstellen),
            ),
          ] else ...[
            Text(t.linkWerHatSieht),
            const SizedBox(height: 8),
            SelectableText(
              link,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            if (nurImHeimnetz(link))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  t.linkNurHeimnetz,
                  style: TextStyle(fontSize: 12, color: farben.error),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _kopiere(context, link),
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(t.linkKopieren),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(uri: Uri.parse(link), subject: _titel.text),
                    ),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: Text(t.linkTeilen),
                  ),
                ),
              ],
            ),
          ],
          if (_meldung != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_meldung!, style: TextStyle(color: farben.error)),
            ),
        ],
      ),
    );
  }
}

Future<void> _kopiere(BuildContext context, String link) async {
  await Clipboard.setData(ClipboardData(text: link));
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(AppTexte.of(context).linkKopiert)));
  }
}

/// Eine Adresse, die von aussen niemand erreicht – wie im Browser.
bool nurImHeimnetz(String adresse) {
  final h = Uri.tryParse(adresse)?.host ?? '';
  return h == 'localhost' ||
      h.endsWith('.local') ||
      h.endsWith('.lan') ||
      RegExp(
        r'^(10\.|127\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|fe80:|fd[0-9a-f]{2}:)',
        caseSensitive: false,
      ).hasMatch(h);
}

/// Die geteilten Links des Kontos, unter Konto – wie im Browser.
class GeteilteLinks extends StatefulWidget {
  const GeteilteLinks({super.key, required this.verbindung});

  final Serververbindung verbindung;

  @override
  State<GeteilteLinks> createState() => _GeteilteLinksState();
}

class _GeteilteLinksState extends State<GeteilteLinks> {
  List<Map<String, Object?>>? _liste;

  @override
  void initState() {
    super.initState();
    _lade();
  }

  Future<void> _lade() async {
    try {
      final d = await widget.verbindung.hole('api/v1/freigaben');
      if (!mounted) return;
      setState(
        () => _liste = [
          for (final x in (d['freigaben'] as List? ?? const []))
            (x as Map).cast<String, Object?>(),
        ],
      );
    } catch (_) {
      // Ohne Verbindung bleibt der Abschnitt leer.
    }
  }

  Future<void> _loesche(Map<String, Object?> x) async {
    final t = AppTexte.of(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(t.linkLoeschenFrage('${x['titel']}')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.abbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.linkLoeschen),
          ),
        ],
      ),
    );
    if (ja != true || !mounted) return;
    final bote = ScaffoldMessenger.of(context);
    try {
      final r = await widget.verbindung.anfrage(
        'DELETE',
        'api/v1/freigaben/${Uri.encodeComponent('${x['id']}')}',
      );
      if (r.statusCode >= 300) throw Serverfehler(r.statusCode, r.body);
      await _lade();
    } catch (f) {
      bote.showSnackBar(SnackBar(content: Text('$f')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final liste = _liste;
    if (liste == null) return const SizedBox.shrink();
    final sprache = Localizations.localeOf(context).toLanguageTag();
    final datum = DateFormat.yMd(sprache);
    final farben = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            t.linkGeteilte,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (liste.isEmpty)
          ListTile(
            leading: const Icon(Icons.link_off_rounded),
            title: Text(
              t.linkNochNichts,
              style: TextStyle(color: farben.onSurfaceVariant),
            ),
          ),
        for (final x in liste)
          ListTile(
            leading: const Icon(Icons.link_rounded),
            title: Text('${x['titel']}'),
            subtitle: Text(
              [
                t.linkAnzahl(x['anzahl'] as int? ?? 0),
                if (DateTime.tryParse('${x['ablauf']}') case final a?)
                  a.isBefore(DateTime.now())
                      ? t.linkAbgelaufen
                      : t.linkBis(datum.format(a.toLocal()))
                else
                  t.linkUnbegrenzt,
                if (x['passwort'] == true) t.linkMitPasswort,
                t.linkAufrufe(x['aufrufe'] as int? ?? 0),
              ].join(' · '),
              style: TextStyle(color: farben.onSurfaceVariant),
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (w) {
                final link = '${x['link']}';
                switch (w) {
                  case 'kopieren':
                    _kopiere(context, link);
                  case 'teilen':
                    SharePlus.instance.share(ShareParams(uri: Uri.parse(link)));
                  case 'loeschen':
                    _loesche(x);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'kopieren', child: Text(t.linkKopieren)),
                PopupMenuItem(value: 'teilen', child: Text(t.linkTeilen)),
                PopupMenuItem(value: 'loeschen', child: Text(t.linkLoeschen)),
              ],
            ),
          ),
      ],
    );
  }
}
