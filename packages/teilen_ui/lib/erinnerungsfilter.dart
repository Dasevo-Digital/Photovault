import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/erinnerungsfilter.dart';

import 'geteilte_alben.dart';

Future<bool> zeigeErinnerungsfilter(
  BuildContext context,
  AppDatabase db,
) async {
  Erinnerungsfilter filter;
  var beschaedigt = false;
  try {
    filter = await db.erinnerungsfilter();
  } on Object {
    beschaedigt = true;
    filter = Erinnerungsfilter();
  }
  final personen = {for (final p in await db.allePersonen()) p.id: p.name};
  final alben = {
    for (final a in await db.select(db.albums).get()) a.id: a.name,
  };
  if (!context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        builder: (_) => _Filter(
          db: db,
          filter: filter,
          personen: personen,
          alben: alben,
          beschaedigt: beschaedigt,
        ),
      ) ??
      false;
}

class _Filter extends StatefulWidget {
  const _Filter({
    required this.db,
    required this.filter,
    required this.personen,
    required this.alben,
    required this.beschaedigt,
  });
  final AppDatabase db;
  final bool beschaedigt;
  final Erinnerungsfilter filter;
  final Map<String, String> personen, alben;
  @override
  State<_Filter> createState() => _FilterState();
}

class _FilterState extends State<_Filter> {
  late final _personen = widget.filter.personen.toSet();
  late final _alben = widget.filter.alben.toSet();
  late final _zeiten = [...widget.filter.zeitraeume];
  bool _speichert = false, _fehler = false;

  Future<void> _speichern() async {
    setState(() {
      _speichert = true;
      _fehler = false;
    });
    try {
      await widget.db.fuehreAus(
        ErinnerungsfilterSetzen(
          widget.filter.mitAuswahl(
            personen: _personen,
            alben: _alben,
            zeitraeume: _zeiten,
          ),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on Object {
      if (mounted) {
        setState(() {
          _speichert = false;
          _fehler = true;
        });
      }
    }
  }

  Widget _wahl(Map<String, String> namen, Set<String> auswahl) {
    final ids = {...namen.keys, ...auswahl}.toList()
      ..sort((a, b) => (namen[a] ?? a).compareTo(namen[b] ?? b));
    return ListView(
      children: [
        for (final id in ids)
          CheckboxListTile(
            value: auswahl.contains(id),
            title: Text(
              namen[id] ?? teilenTexte(context).erinnerungEintragFehlt,
            ),
            onChanged: _speichert
                ? null
                : (wert) => setState(() {
                    wert == true ? auswahl.add(id) : auswahl.remove(id);
                  }),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = teilenTexte(context);
    return DefaultTabController(
      length: 3,
      child: AlertDialog(
        title: Text(t.erinnerungsfilterTitel),
        content: SizedBox(
          width: 540,
          height: 430,
          child: Column(
            children: [
              Flexible(
                flex: 2,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Text(t.erinnerungsfilterHinweis),
                      if (widget.beschaedigt) Text(t.erinnerungsfilterDefekt),
                      if (widget.filter.zeitbezugFehlt)
                        Text(t.erinnerungsfilterZeitbezug),
                    ],
                  ),
                ),
              ),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: t.erinnerungPersonen),
                  Tab(text: t.erinnerungAlben),
                  Tab(text: t.erinnerungZeiten),
                ],
              ),
              Expanded(
                flex: 5,
                child: TabBarView(
                  children: [
                    _wahl(widget.personen, _personen),
                    _wahl(widget.alben, _alben),
                    ListView(
                      children: [
                        for (var i = 0; i < _zeiten.length; i++)
                          ListTile(
                            title: Text(
                              '${_zeiten[i].von} – ${_zeiten[i].bis}',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: t.erinnerungZeitraumEntfernen,
                              onPressed: _speichert
                                  ? null
                                  : () => setState(() {
                                      _zeiten.removeAt(i);
                                    }),
                            ),
                          ),
                        TextButton.icon(
                          icon: const Icon(Icons.add),
                          label: Text(t.erinnerungZeitraumHinzufuegen),
                          onPressed: _speichert || _zeiten.length >= 50
                              ? null
                              : () async {
                                  final zeit = await showDateRangePicker(
                                    context: context,
                                    firstDate: DateTime(1),
                                    lastDate: DateTime(9999, 12, 31),
                                  );
                                  if (zeit != null && mounted) {
                                    String tag(DateTime d) =>
                                        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                                    setState(() {
                                      _zeiten.add((
                                        von: tag(zeit.start),
                                        bis: tag(zeit.end),
                                      ));
                                    });
                                  }
                                },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_fehler) Text(t.erinnerungsfilterFehler),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _speichert ? null : () => Navigator.pop(context),
            child: Text(t.abbrechen),
          ),
          FilledButton(
            onPressed: _speichert ? null : _speichern,
            child: Text(t.erinnerungsfilterSpeichern),
          ),
        ],
      ),
    );
  }
}
