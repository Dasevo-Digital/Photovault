import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kern/abgleich/verbindung.dart';

import 'geteilte_alben.dart';

// Der Nachlasskontakt (#300) – wie im Browser (web/app.js, zeigeNachlass):
// Ein Konto benennt andere, die Zugang zu seiner Bibliothek verlangen
// dürfen. Widerspricht es nicht binnen der Frist, sehen sie sie danach wie
// ein Partner. Gerechnet wird am Server; die Geräte zeigen die Anfrage.

String _k(String s) => Uri.encodeComponent(s);

/// Ein Eintrag aus der Sicht des Kontos: ein Kontakt, den es benannt hat,
/// oder ein Konto, für das es benannt ist.
class Nachlasseintrag {
  const Nachlasseintrag({
    required this.konto,
    required this.name,
    required this.frist,
    this.angefordert,
    this.faellig,
    this.freigegeben,
    this.abgelehnt,
  });

  factory Nachlasseintrag.aus(Map<String, Object?> j) {
    DateTime? zeit(String k) => switch (j[k]) {
      final String s => DateTime.tryParse(s)?.toLocal(),
      _ => null,
    };
    return Nachlasseintrag(
      konto: '${j['konto']}',
      name: '${j['name'] ?? ''}',
      frist: (j['frist'] as num?)?.toInt() ?? 30,
      angefordert: zeit('angefordert'),
      faellig: zeit('faellig'),
      freigegeben: zeit('freigegeben'),
      abgelehnt: zeit('abgelehnt'),
    );
  }

  final String konto;
  final String name;
  final int frist;
  final DateTime? angefordert;
  final DateTime? faellig;
  final DateTime? freigegeben;
  final DateTime? abgelehnt;

  bool get offen => angefordert != null && freigegeben == null;
}

/// Was der Server zum Nachlass dieses Kontos weiss.
class Nachlassstand {
  const Nachlassstand({
    this.kontakte = const [],
    this.fuerMich = const [],
    this.fristen = const [7, 14, 30, 90],
  });

  static Future<Nachlassstand> hole(Serververbindung v) async {
    final d = await v.hole('api/v1/nachlass');
    List<Nachlasseintrag> liste(String k) => [
      for (final x in (d[k] as List? ?? const []))
        if (x is Map) Nachlasseintrag.aus(x.cast<String, Object?>()),
    ];
    return Nachlassstand(
      kontakte: liste('kontakte'),
      fuerMich: liste('fuerMich'),
      fristen: [
        for (final f in (d['fristen'] as List? ?? const [7, 14, 30, 90]))
          if (f is num) f.toInt(),
      ],
    );
  }

  final List<Nachlasseintrag> kontakte;
  final List<Nachlasseintrag> fuerMich;
  final List<int> fristen;
}

Future<void> _ohneInhalt(
  Serververbindung v,
  String methode,
  String pfad, [
  Object? inhalt,
]) async {
  final r = await v.anfrage(
    methode,
    pfad,
    kopf: inhalt == null
        ? const {}
        : const {'content-type': 'application/json'},
    inhalt: inhalt == null ? null : utf8.encode(jsonEncode(inhalt)),
  );
  if (r.statusCode >= 300) throw Serverfehler(r.statusCode, r.body);
}

String _datum(BuildContext context, DateTime t) =>
    DateFormat.yMd(Localizations.localeOf(context).toString()).format(t);

/// „Nachlasskontakt“: wen dieses Konto benennt, und für wen es benannt ist
/// – am Rechner als Dialog, am Telefon als Blatt von unten.
Future<void> nachlassVerwalten(
  BuildContext context,
  Serververbindung? verbindung,
) async {
  if (verbindung == null) return;
  final blatt = _Nachlassblatt(verbindung: verbindung);
  if (MediaQuery.sizeOf(context).width >= 600) {
    await showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(child: SingleChildScrollView(child: blatt)),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 12, 12),
                child: TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: Text(teilenTexte(c).schliessen),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => SingleChildScrollView(child: blatt),
  );
}

class _Nachlassblatt extends StatefulWidget {
  const _Nachlassblatt({required this.verbindung});

  final Serververbindung verbindung;

  @override
  State<_Nachlassblatt> createState() => _NachlassblattState();
}

class _NachlassblattState extends State<_Nachlassblatt> {
  Nachlassstand? _stand;
  List<(String, String)> _andere = const [];
  String? _neu;
  int _frist = 30;
  String? _fehler;

  @override
  void initState() {
    super.initState();
    _lade();
  }

  Future<void> _lade() async {
    try {
      final (s, k) = await (
        Nachlassstand.hole(widget.verbindung),
        widget.verbindung.hole('api/v1/konten/andere'),
      ).wait;
      if (!mounted) return;
      final schon = {for (final e in s.kontakte) e.konto};
      setState(() {
        _stand = s;
        _andere = [
          for (final x in (k['konten'] as List? ?? const []))
            if (x case {'id': final id, 'name': final name})
              if (!schon.contains('$id')) ('$id', '$name'),
        ];
        _neu = _andere.isEmpty ? null : _andere.first.$1;
        if (!s.fristen.contains(_frist) && s.fristen.isNotEmpty) {
          _frist = s.fristen.contains(30) ? 30 : s.fristen.first;
        }
        _fehler = null;
      });
    } on ParallelWaitError<dynamic, dynamic> {
      if (mounted) {
        setState(() => _fehler = teilenTexte(context).geteiltOffline);
      }
    }
  }

  Future<void> _tue(Future<void> Function() schritt) async {
    try {
      await schritt();
    } on Serverfehler catch (e) {
      if (mounted) setState(() => _fehler = e.text);
      return;
    } on KeineVerbindung {
      if (mounted) {
        setState(() => _fehler = teilenTexte(context).geteiltOffline);
      }
      return;
    }
    await _lade();
  }

  Future<void> _verlangen(Nachlasseintrag e) async {
    final t = teilenTexte(context);
    final ja = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.nachlassVerlangen),
        content: Text(t.nachlassVerlangenFrage(e.name, e.frist)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(t.abbrechen),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(t.nachlassVerlangen),
          ),
        ],
      ),
    );
    if (ja != true) return;
    await _tue(
      () => _ohneInhalt(
        widget.verbindung,
        'POST',
        'api/v1/nachlass/von/${_k(e.konto)}/anfordern',
      ),
    );
  }

  String _zustandText(
    BuildContext context,
    Nachlasseintrag e, {
    required bool eigen,
  }) {
    final t = teilenTexte(context);
    if (e.freigegeben case final f?) {
      return eigen
          ? t.nachlassHatZugang(_datum(context, f))
          : t.nachlassDuHastZugang(_datum(context, f));
    }
    if (e.faellig case final f? when e.offen) {
      return t.nachlassOffen(_datum(context, f));
    }
    return t.nachlassFristTage(e.frist);
  }

  @override
  Widget build(BuildContext context) {
    final t = teilenTexte(context);
    final s = _stand;
    final klein = Theme.of(context).textTheme.bodySmall;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.nachlass, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(t.nachlassHinweis, style: klein),
            const SizedBox(height: 12),
            if (s == null && _fehler == null)
              const Center(child: CircularProgressIndicator())
            else if (s != null) ...[
              Text(
                t.nachlassMeine,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (s.kontakte.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(t.nachlassKeine),
                ),
              for (final e in s.kontakte)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.name),
                  subtitle: Text(_zustandText(context, e, eigen: true)),
                  trailing: Wrap(
                    children: [
                      if (e.offen)
                        TextButton(
                          onPressed: () => _tue(
                            () => _ohneInhalt(
                              widget.verbindung,
                              'POST',
                              'api/v1/nachlass/${_k(e.konto)}/ablehnen',
                            ),
                          ),
                          child: Text(t.nachlassAblehnen),
                        ),
                      IconButton(
                        tooltip: t.entfernen,
                        icon: const Icon(Icons.close),
                        onPressed: () => _tue(
                          () => _ohneInhalt(
                            widget.verbindung,
                            'DELETE',
                            'api/v1/nachlass/${_k(e.konto)}',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_andere.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _neu,
                        items: [
                          for (final (id, name) in _andere)
                            DropdownMenuItem(value: id, child: Text(name)),
                        ],
                        onChanged: (w) => setState(() => _neu = w),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _frist,
                      items: [
                        for (final f in s.fristen)
                          DropdownMenuItem(
                            value: f,
                            child: Text(t.nachlassFristTage(f)),
                          ),
                      ],
                      onChanged: (w) => setState(() => _frist = w ?? _frist),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _neu == null
                          ? null
                          : () => _tue(
                              () => _ohneInhalt(
                                widget.verbindung,
                                'PUT',
                                'api/v1/nachlass/${_k(_neu!)}',
                                {'frist': _frist},
                              ),
                            ),
                      child: Text(t.nachlassBenennen),
                    ),
                  ],
                ),
              if (s.fuerMich.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  t.nachlassFuerMich,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final e in s.fuerMich)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(e.name),
                    subtitle: Text(_zustandText(context, e, eigen: false)),
                    trailing: e.freigegeben != null
                        ? null
                        : e.offen
                        ? TextButton(
                            onPressed: () => _tue(
                              () => _ohneInhalt(
                                widget.verbindung,
                                'DELETE',
                                'api/v1/nachlass/von/${_k(e.konto)}/anfordern',
                              ),
                            ),
                            child: Text(t.nachlassZurueckziehen),
                          )
                        : TextButton(
                            onPressed: () => _verlangen(e),
                            child: Text(t.nachlassVerlangen),
                          ),
                  ),
              ],
            ],
            if (_fehler case final f?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  f,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Steht da, solange jemand Zugang zur eigenen Bibliothek verlangt (#300)
/// – mit „Ablehnen“. Sonst nichts. Fragt beim Start und alle 15 Minuten.
class NachlassHinweis extends StatefulWidget {
  const NachlassHinweis({super.key, required this.verbindung});

  final Serververbindung verbindung;

  @override
  State<NachlassHinweis> createState() => _NachlassHinweisState();
}

class _NachlassHinweisState extends State<NachlassHinweis> {
  List<Nachlasseintrag> _offen = const [];
  Timer? _uhr;

  @override
  void initState() {
    super.initState();
    _lade();
    _uhr = Timer.periodic(const Duration(minutes: 15), (_) => _lade());
  }

  @override
  void dispose() {
    _uhr?.cancel();
    super.dispose();
  }

  Future<void> _lade() async {
    try {
      final s = await Nachlassstand.hole(widget.verbindung);
      if (mounted) {
        setState(
          () => _offen = [
            for (final e in s.kontakte)
              if (e.offen) e,
          ],
        );
      }
    } on Object {
      // Älterer Server oder kein Netz: dann eben nichts.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_offen.isEmpty) return const SizedBox.shrink();
    final t = teilenTexte(context);
    final farben = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in _offen)
          Material(
            color: farben.errorContainer,
            child: ListTile(
              dense: true,
              leading: Icon(Icons.key_outlined, color: farben.onErrorContainer),
              title: Text(
                t.nachlassAnfrage(e.name, _datum(context, e.faellig!)),
                style: TextStyle(color: farben.onErrorContainer),
              ),
              trailing: TextButton(
                onPressed: () async {
                  try {
                    await _ohneInhalt(
                      widget.verbindung,
                      'POST',
                      'api/v1/nachlass/${_k(e.konto)}/ablehnen',
                    );
                  } on Object {
                    return;
                  }
                  await _lade();
                },
                child: Text(t.nachlassAblehnen),
              ),
            ),
          ),
      ],
    );
  }
}
