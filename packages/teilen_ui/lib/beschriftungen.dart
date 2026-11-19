import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'geteilte_alben.dart';

class Beschriftungsknopf extends StatelessWidget {
  const Beschriftungsknopf({
    super.key,
    required this.ort,
    this.aufnahme,
    this.geaendert,
  });
  final Aktivitaetsort ort;
  final String? aufnahme;
  final VoidCallback? geaendert;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: teilenTexte(context).beschriftungTitel,
    icon: const Icon(Icons.edit_note_outlined),
    onPressed: () async {
      await zeigeBeschriftungen(context, ort, aufnahme: aufnahme);
      geaendert?.call();
    },
  );
}

Future<void> zeigeBeschriftungen(
  BuildContext context,
  Aktivitaetsort ort, {
  String? aufnahme,
}) => showDialog<void>(
  context: context,
  builder: (_) => _Beschriftungen(ort: ort, aufnahme: aufnahme),
);

class _Beschriftungen extends StatefulWidget {
  const _Beschriftungen({required this.ort, this.aufnahme});
  final Aktivitaetsort ort;
  final String? aufnahme;
  @override
  State<_Beschriftungen> createState() => _BeschriftungenState();
}

class _BeschriftungenState extends State<_Beschriftungen> {
  final _wert = TextEditingController();
  Map<String, Object?>? _daten;
  var _art = 'ort', _fehler = false, _busy = false;
  String? _gesicht;
  int _seite = 0;
  int _ladeStand = 0;
  final _personen = <String, String?>{};
  String get _route => '${widget.ort.basis}/beschriftungen';

  @override
  void initState() {
    super.initState();
    _laden();
  }

  @override
  void dispose() {
    _wert.dispose();
    super.dispose();
  }

  Future<void> _laden() async {
    final lauf = ++_ladeStand;
    try {
      final daten = await widget.ort.verbindung.hole(
        _route,
        parameter: {
          'seite': '$_seite',
          if (widget.aufnahme != null) 'aufnahme': widget.aufnahme!,
        },
      );
      if (mounted && lauf == _ladeStand) {
        setState(() {
          _daten = daten;
          _fehler = false;
          final gesichter = (daten['gesichter'] as List).cast<Map>();
          if (!gesichter.any((f) => f['id'] == _gesicht)) _gesicht = null;
          if (_art == 'person' && gesichter.isEmpty) _art = 'ort';
          _personen.clear();
        });
      }
    } on Object {
      if (mounted && lauf == _ladeStand) {
        setState(() {
          _fehler = true;
        });
      }
    }
  }

  Future<void> _senden() async {
    if (_busy || _wert.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _fehler = false;
    });
    try {
      await widget.ort.verbindung.schicke(_route, {
        'aufnahme': widget.aufnahme,
        'art': _art,
        'wert': _wert.text.trim(),
        if (_art == 'person') 'gesicht': _gesicht,
      });
      _wert.clear();
      await _laden();
    } on Object {
      if (mounted) {
        setState(() {
          _fehler = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _entscheiden(Map v, bool annehmen) async {
    setState(() {
      _busy = true;
      _fehler = false;
    });
    try {
      await widget.ort.verbindung.schicke(
        '$_route/${Uri.encodeComponent(v['id'] as String)}',
        {
          'annehmen': annehmen,
          'stand': v['stand'],
          'person': ?_personen[v['id']],
        },
      );
      await _laden();
    } on Object {
      if (mounted) {
        setState(() {
          _fehler = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = teilenTexte(context);
    final daten = _daten;
    final gesichter = (daten?['gesichter'] as List? ?? const []).cast<Map>();
    final vorschlaege = (daten?['vorschlaege'] as List? ?? const [])
        .cast<Map>();
    String art(String wert) => switch (wert) {
      'person' => t.beschriftungPerson,
      'jahr' => t.beschriftungJahr,
      _ => t.beschriftungOrt,
    };
    return AlertDialog(
      title: Text(t.beschriftungTitel),
      content: SizedBox(
        width: 600,
        height: math.min(560, MediaQuery.sizeOf(context).height * .65),
        child: daten == null && !_fehler
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  Text(t.beschriftungHinweis),
                  if (_fehler)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(t.beschriftungFehler),
                    ),
                  if (widget.aufnahme case final aufnahme?) ...[
                    SizedBox(
                      height: 180,
                      child: LayoutBuilder(
                        builder: (c, box) => Center(
                          child: SizedBox(
                            width: 240,
                            height: 180,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: Image(
                                    image: widget.ort.miniatur(aufnahme),
                                    fit: BoxFit.fill,
                                  ),
                                ),
                                for (var i = 0; i < gesichter.length; i++)
                                  Positioned(
                                    left:
                                        (gesichter[i]['x'] as num)
                                            .toDouble()
                                            .clamp(0, 1) *
                                        240,
                                    top:
                                        (gesichter[i]['y'] as num)
                                            .toDouble()
                                            .clamp(0, 1) *
                                        180,
                                    width:
                                        (gesichter[i]['breite'] as num)
                                            .toDouble()
                                            .clamp(0, 1) *
                                        240,
                                    height:
                                        (gesichter[i]['hoehe'] as num)
                                            .toDouble()
                                            .clamp(0, 1) *
                                        180,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Colors.amber,
                                          width: 2,
                                        ),
                                      ),
                                      child: Align(
                                        alignment: Alignment.topLeft,
                                        child: ColoredBox(
                                          color: Colors.black,
                                          child: Text(
                                            '${i + 1}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _art,
                      items: [
                        for (final a in [
                          'ort',
                          'jahr',
                          if (gesichter.isNotEmpty) 'person',
                        ])
                          DropdownMenuItem(value: a, child: Text(art(a))),
                      ],
                      onChanged: _busy
                          ? null
                          : (a) => setState(() {
                              _art = a!;
                            }),
                    ),
                    if (_art == 'person')
                      DropdownButtonFormField<String>(
                        initialValue: _gesicht,
                        hint: Text(t.beschriftungGesichtWaehlen),
                        items: [
                          for (var i = 0; i < gesichter.length; i++)
                            DropdownMenuItem(
                              value: gesichter[i]['id'] as String,
                              child: Text(t.beschriftungGesicht(i + 1)),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (id) => setState(() {
                                _gesicht = id;
                              }),
                      ),
                    TextField(
                      controller: _wert,
                      maxLength: 200,
                      decoration: InputDecoration(labelText: art(_art)),
                      keyboardType: _art == 'jahr'
                          ? TextInputType.number
                          : TextInputType.text,
                    ),
                    FilledButton(
                      onPressed: _busy || (_art == 'person' && _gesicht == null)
                          ? null
                          : _senden,
                      child: Text(t.beschriftungVorschlagen),
                    ),
                  ],
                  for (final v in vorschlaege)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${v['von']} · ${DateFormat.yMd(Localizations.localeOf(context).toString()).format(DateTime.parse(v['angelegt'] as String).toLocal())}',
                            ),
                            Text('${art(v['art'] as String)} · ${v['wert']}'),
                            if (v['aktuell'] case final String wert)
                              Text(t.beschriftungAktuell(wert)),
                            Text(switch (v['zustand']) {
                              'angenommen' => t.beschriftungAngenommen,
                              'abgelehnt' => t.beschriftungAbgelehnt,
                              _ => t.beschriftungOffen,
                            }),
                            if (daten?['besitzer'] == true &&
                                v['zustand'] == 'offen') ...[
                              if (v['art'] == 'person')
                                DropdownButton<String>(
                                  isExpanded: true,
                                  value: _personen[v['id']],
                                  hint: Text(t.beschriftungPersonAutomatisch),
                                  items: [
                                    for (final p
                                        in (daten?['personen'] as List? ??
                                                const [])
                                            .cast<Map>())
                                      if (p['name'] == v['wert'])
                                        DropdownMenuItem(
                                          value: p['id'] as String,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (p['bild']
                                                  case final String bild) ...[
                                                CircleAvatar(
                                                  radius: 16,
                                                  backgroundImage: FernBild(
                                                    widget.ort.verbindung,
                                                    'api/v1/dateien/${bild.split('/').map(Uri.encodeComponent).join('/')}',
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                              ],
                                              Flexible(
                                                child: Text(
                                                  '${p['name']} (${(p['id'] as String).substring(0, math.min(8, (p['id'] as String).length))})',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                  ],
                                  onChanged: _busy
                                      ? null
                                      : (id) => setState(() {
                                          _personen[v['id'] as String] = id;
                                        }),
                                ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _entscheiden(v, false),
                                    child: Text(t.beschriftungAblehnen),
                                  ),
                                  FilledButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _entscheiden(v, true),
                                    child: Text(t.beschriftungAnnehmen),
                                  ),
                                  if (widget.aufnahme == null)
                                    TextButton(
                                      onPressed: () => zeigeBeschriftungen(
                                        context,
                                        widget.ort,
                                        aufnahme: v['aufnahme'] as String,
                                      ),
                                      child: Text(t.beschriftungFoto),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        if (_seite > 0)
          IconButton(
            tooltip: t.beschriftungZurueck,
            icon: const Icon(Icons.chevron_left),
            onPressed: _busy
                ? null
                : () {
                    _seite--;
                    _laden();
                  },
          ),
        if (daten?['mehr'] == true)
          IconButton(
            tooltip: t.beschriftungWeiter,
            icon: const Icon(Icons.chevron_right),
            onPressed: _busy
                ? null
                : () {
                    _seite++;
                    _laden();
                  },
          ),
        TextButton(
          onPressed: _busy ? null : _laden,
          child: Text(t.beschriftungAktualisieren),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(t.schliessen),
        ),
      ],
    );
  }
}
