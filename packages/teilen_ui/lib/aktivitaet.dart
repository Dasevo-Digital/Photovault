import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kern/abgleich/verbindung.dart';

import 'geteilte_alben.dart';

// Kommentare und „Gefällt mir“ in geteilten Alben (#297) – wie im Browser
// (web/app.js, kommentarBereich): für den Besitzer und für jeden, mit dem
// das Album geteilt ist. Die Einträge liegen am Server neben den Konten,
// nicht in der Bibliothek; ein Gerät holt sie jedes Mal frisch.

String _k(String s) => Uri.encodeComponent(s);

/// Ein Kommentar – zum Album ([aufnahme] leer) oder zu einem Foto darin.
class Albumkommentar {
  const Albumkommentar({
    required this.id,
    required this.name,
    required this.text,
    required this.angelegt,
    this.aufnahme,
    this.eigener = false,
    this.loeschbar = false,
  });

  factory Albumkommentar.aus(Map<String, Object?> j) => Albumkommentar(
    id: '${j['id']}',
    aufnahme: j['aufnahme'] as String?,
    name: '${j['name'] ?? ''}',
    text: '${j['text'] ?? ''}',
    angelegt:
        DateTime.tryParse('${j['angelegt']}') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    eigener: j['eigener'] == true,
    loeschbar: j['loeschbar'] == true,
  );

  final String id;
  final String? aufnahme;
  final String name;
  final String text;
  final DateTime angelegt;
  final bool eigener;

  /// Der eigene – oder, für den Besitzer des Albums, jeder.
  final bool loeschbar;
}

/// Wem ein Foto gefällt.
class Gefallen {
  const Gefallen({this.anzahl = 0, this.ich = false, this.namen = const []});

  factory Gefallen.aus(Map<String, Object?> j) => Gefallen(
    anzahl: (j['anzahl'] as num?)?.toInt() ?? 0,
    ich: j['ich'] == true,
    namen: [for (final n in (j['namen'] as List? ?? const [])) '$n'],
  );

  final int anzahl;
  final bool ich;
  final List<String> namen;
}

/// Was in einem Album gesagt wurde: Kommentare und „Gefällt mir“.
class Albumaktivitaet {
  const Albumaktivitaet({this.kommentare = const [], this.gefaellt = const {}});

  factory Albumaktivitaet.aus(Map<String, Object?> j) => Albumaktivitaet(
    kommentare: [
      for (final k in (j['kommentare'] as List? ?? const []))
        Albumkommentar.aus((k as Map).cast<String, Object?>()),
    ],
    gefaellt: {
      for (final MapEntry(:key, :value)
          in ((j['gefaellt'] as Map?) ?? const {}).entries)
        '$key': Gefallen.aus((value as Map).cast<String, Object?>()),
    },
  );

  final List<Albumkommentar> kommentare;
  final Map<String, Gefallen> gefaellt;

  /// Die Kommentare zu [aufnahme]; ohne sie die zum Album.
  List<Albumkommentar> zu(String? aufnahme) => [
    for (final k in kommentare)
      if (k.aufnahme == aufnahme) k,
  ];

  Gefallen gefallenVon(String aufnahme) =>
      gefaellt[aufnahme] ?? const Gefallen();
}

/// Wo die Aktivität eines Albums am Server liegt – für den Besitzer unter
/// seinem Album, für einen Empfänger unter der Teilung.
class Aktivitaetsort {
  Aktivitaetsort.besitzer(this.verbindung, String album)
    : basis = 'api/v1/alben/${_k(album)}',
      _miniatur = ((a) => 'api/v1/aufnahmen/${_k(a)}/miniatur');

  Aktivitaetsort.geteilt(this.verbindung, GeteiltesAlbum album)
    : basis = 'api/v1/geteilt/${_k(album.id)}',
      _miniatur = ((a) => album.datei(a, 'miniatur'));

  final Serververbindung verbindung;
  final String basis;
  final String Function(String aufnahme) _miniatur;

  ImageProvider miniatur(String aufnahme) =>
      FernBild(verbindung, _miniatur(aufnahme));

  Future<Albumaktivitaet> lade() async =>
      Albumaktivitaet.aus(await verbindung.hole('$basis/aktivitaet'));

  Future<void> kommentiere(String text, {String? aufnahme}) => verbindung
      .schicke('$basis/kommentare', {'text': text, 'aufnahme': ?aufnahme});

  Future<void> entferne(String kommentar) =>
      _ohneInhalt('DELETE', '$basis/kommentare/${_k(kommentar)}');

  Future<void> gefaellt(String aufnahme, {required bool an}) =>
      _ohneInhalt(an ? 'PUT' : 'DELETE', '$basis/gefaellt/${_k(aufnahme)}');

  Future<void> _ohneInhalt(String methode, String pfad) async {
    final r = await verbindung.anfrage(methode, pfad);
    if (r.statusCode >= 300) throw Serverfehler(r.statusCode, r.body);
  }
}

/// Die Kommentare als Blatt von unten: mit [aufnahme] die zu diesem Foto,
/// sonst alle – die zu einzelnen Fotos mit ihrer Miniatur. Geschrieben
/// wird dann zum Album. [geaendert] meldet, dass sich etwas getan hat.
Future<void> zeigeKommentare(
  BuildContext context,
  Aktivitaetsort ort, {
  String? aufnahme,
  VoidCallback? geaendert,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) =>
      _Kommentarblatt(ort: ort, aufnahme: aufnahme, geaendert: geaendert),
);

class _Kommentarblatt extends StatefulWidget {
  const _Kommentarblatt({required this.ort, this.aufnahme, this.geaendert});

  final Aktivitaetsort ort;
  final String? aufnahme;
  final VoidCallback? geaendert;

  @override
  State<_Kommentarblatt> createState() => _KommentarblattState();
}

class _KommentarblattState extends State<_Kommentarblatt> {
  final _feld = TextEditingController();
  Albumaktivitaet? _stand;
  bool _sendet = false;
  bool _fehler = false;

  @override
  void initState() {
    super.initState();
    _lade();
  }

  @override
  void dispose() {
    _feld.dispose();
    super.dispose();
  }

  Future<void> _lade() async {
    try {
      final s = await widget.ort.lade();
      if (mounted) setState(() => _stand = s);
    } on Object {
      if (mounted) setState(() => _fehler = true);
    }
  }

  void _melde() {
    final t = teilenTexte(context);
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(t.kommentarFehler)));
  }

  Future<void> _sende() async {
    final text = _feld.text.trim();
    if (text.isEmpty || _sendet) return;
    setState(() => _sendet = true);
    try {
      await widget.ort.kommentiere(text, aufnahme: widget.aufnahme);
      _feld.clear();
      widget.geaendert?.call();
      await _lade();
    } on Object {
      if (mounted) _melde();
    } finally {
      if (mounted) setState(() => _sendet = false);
    }
  }

  Future<void> _entferne(Albumkommentar k) async {
    final t = teilenTexte(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(t.kommentarEntfernenFrage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(t.abbrechen),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(t.entfernen),
          ),
        ],
      ),
    );
    if (ja != true || !mounted) return;
    try {
      await widget.ort.entferne(k.id);
      widget.geaendert?.call();
      await _lade();
    } on Object {
      if (mounted) _melde();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = teilenTexte(context);
    final sprache = Localizations.localeOf(context).toLanguageTag();
    final zeit = DateFormat.yMMMd(sprache).add_Hm();
    final s = _stand;
    final liste = s == null
        ? const <Albumkommentar>[]
        : widget.aufnahme == null
        ? s.kommentare
        : s.zu(widget.aufnahme);
    final klein = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                t.kommentare,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(t.kommentareHinweis, style: klein),
            ),
            Flexible(
              child: s == null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: _fehler
                            ? Text(t.geteiltOffline)
                            : const CircularProgressIndicator(),
                      ),
                    )
                  : liste.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(child: Text(t.kommentareKeine)),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final k in liste)
                          ListTile(
                            leading:
                                k.aufnahme != null && widget.aufnahme == null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image(
                                      image: widget.ort.miniatur(k.aufnahme!),
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const SizedBox(
                                        width: 44,
                                        height: 44,
                                        child: Icon(Icons.image_outlined),
                                      ),
                                    ),
                                  )
                                : CircleAvatar(
                                    child: Text(
                                      k.name.isEmpty
                                          ? '?'
                                          : k.name.characters.first
                                                .toUpperCase(),
                                    ),
                                  ),
                            title: Text(
                              '${k.name} · ${zeit.format(k.angelegt.toLocal())}'
                              '${k.aufnahme != null && widget.aufnahme == null ? ' · ${t.kommentarZuFoto}' : ''}',
                              style: klein,
                            ),
                            subtitle: Text(
                              k.text,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            trailing: k.loeschbar
                                ? IconButton(
                                    tooltip: t.kommentarEntfernen,
                                    icon: const Icon(Icons.close),
                                    onPressed: () => _entferne(k),
                                  )
                                : null,
                          ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _feld,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: t.kommentarSchreiben,
                        counterText: '',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _sende(),
                    ),
                  ),
                  IconButton(
                    tooltip: t.kommentarSenden,
                    icon: _sendet
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    onPressed: _sende,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Der Knopf zu den Kommentaren eines Albums, mit ihrer Zahl. Für den
/// Besitzer ([nurWennGeteilt]) nur, solange das Album mit jemandem geteilt
/// ist oder schon Kommentare hat; ohne Server, der es kann, gar nicht.
class Kommentarknopf extends StatefulWidget {
  const Kommentarknopf({
    super.key,
    required this.ort,
    this.nurWennGeteilt = false,
  });

  final Aktivitaetsort ort;
  final bool nurWennGeteilt;

  @override
  State<Kommentarknopf> createState() => _KommentarknopfState();
}

class _KommentarknopfState extends State<Kommentarknopf> {
  Albumaktivitaet? _stand;
  bool _geteilt = false;

  @override
  void initState() {
    super.initState();
    _lade();
  }

  Future<void> _lade() async {
    try {
      final s = await widget.ort.lade();
      var geteilt = !widget.nurWennGeteilt;
      if (!geteilt) {
        final t = await widget.ort.verbindung.hole(
          '${widget.ort.basis}/teilungen',
        );
        geteilt = (t['teilungen'] as List? ?? const []).isNotEmpty;
      }
      if (mounted) {
        setState(() {
          _stand = s;
          _geteilt = geteilt;
        });
      }
    } on Object {
      // Älterer Server, kein Netz: dann eben ohne Kommentare.
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _stand;
    if (s == null || (!_geteilt && s.kommentare.isEmpty)) {
      return const SizedBox.shrink();
    }
    final n = s.kommentare.length;
    return IconButton(
      tooltip: teilenTexte(context).kommentare,
      icon: Badge(
        isLabelVisible: n > 0,
        label: Text('$n'),
        child: const Icon(Icons.chat_bubble_outline),
      ),
      onPressed: () => zeigeKommentare(context, widget.ort, geaendert: _lade),
    );
  }
}
