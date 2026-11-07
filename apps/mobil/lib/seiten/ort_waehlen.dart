import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';

import '../einfuegbares_menue.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';

/// Ort von Hand für [ids]. Das Ortsverzeichnis liegt auf dem Server, darum
/// braucht die Suche eine Verbindung; die Namen gehen mit dem Befehl auf alle
/// Geräte. Gibt zurück, ob sich etwas geändert hat.
Future<bool> ortWaehlen(
  BuildContext context,
  Sitzung sitzung,
  List<String> ids, {
  bool hatOrt = false,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OrtBlatt(sitzung: sitzung, ids: ids, hatOrt: hatOrt),
    ) ??
    false;

class _OrtBlatt extends StatefulWidget {
  const _OrtBlatt({
    required this.sitzung,
    required this.ids,
    required this.hatOrt,
  });

  final Sitzung sitzung;
  final List<String> ids;
  final bool hatOrt;

  @override
  State<_OrtBlatt> createState() => _OrtBlattState();
}

class _OrtBlattState extends State<_OrtBlatt> {
  final _feld = TextEditingController();
  Timer? _uhr;
  var _anfrage = 0;
  var _treffer = const <Map<String, Object?>>[];
  String? _meldung;

  @override
  void dispose() {
    _uhr?.cancel();
    _feld.dispose();
    super.dispose();
  }

  void _eingabe(String _) {
    _uhr?.cancel();
    _uhr = Timer(const Duration(milliseconds: 200), _suche);
  }

  Future<void> _suche() async {
    final t = AppTexte.of(context);
    final text = _feld.text.trim();
    final nummer = ++_anfrage;
    if (text.length < 2) {
      setState(() {
        _treffer = const [];
        _meldung = null;
      });
      return;
    }
    final verbindung = widget.sitzung.abgleich?.verbindung;
    if (verbindung == null) {
      setState(() => _meldung = t.ortKeineVerbindung);
      return;
    }
    try {
      final d = await verbindung.hole(
        'api/v1/orte/suche',
        parameter: {'text': text},
      );
      // Inzwischen weitergetippt: Diese Antwort ist überholt.
      if (!mounted || nummer != _anfrage) return;
      final treffer = [
        for (final z in (d['treffer'] as List? ?? const []))
          if (z is Map) z.cast<String, Object?>(),
      ];
      setState(() {
        _treffer = treffer;
        _meldung = d['verzeichnis'] != true
            ? t.ortKeinVerzeichnis
            : treffer.isEmpty
            ? t.ortKeinTreffer
            : null;
      });
    } on Exception {
      if (mounted && nummer == _anfrage) {
        setState(() => _meldung = t.ortKeineVerbindung);
      }
    }
  }

  Future<void> _setze(Map<String, Object?> o) async {
    await widget.sitzung.db.fuehreAus(
      OrtSetzen(
        widget.ids,
        (o['breite']! as num).toDouble(),
        (o['laenge']! as num).toDouble(),
        land: o['land'] as String?,
        region: o['region'] as String?,
        stadt: o['stadt'] as String?,
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _entferne() async {
    await widget.sitzung.db.fuehreAus(OrtSetzen(widget.ids, null, null));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final meldung = _meldung;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.ids.length > 1
                    ? t.ortFuerAufnahmen(widget.ids.length)
                    : t.ortSetzen,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                contextMenuBuilder: einfuegbaresMenue,
                controller: _feld,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _eingabe,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: t.ortSuchenBeispiel,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (meldung != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(meldung),
                ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final o in _treffer)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.place_outlined),
                        title: Text('${o['name']}'),
                        subtitle: Text('${o['herkunft'] ?? ''}'),
                        onTap: () => _setze(o),
                      ),
                  ],
                ),
              ),
              if (widget.hatOrt)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _entferne,
                    child: Text(t.ortEntfernen),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
