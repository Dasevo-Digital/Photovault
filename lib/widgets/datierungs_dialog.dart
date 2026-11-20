import 'package:flutter/material.dart';
import 'einfuegbares_menue.dart';
import 'package:kern/db/database.dart';
import '../l10n/app_localizations.dart';

Future<AufnahmeDatierung?> frageDatierung(BuildContext context, AssetData a) =>
    showDialog<AufnahmeDatierung>(context: context, builder: (_) => _Dialog(a));

class _Dialog extends StatefulWidget {
  const _Dialog(this.asset);
  final AssetData asset;
  @override
  State<_Dialog> createState() => _DialogState();
}

class _DialogState extends State<_Dialog> {
  late final TextEditingController von, bis, hinweis;
  late Datierungsgenauigkeit genauigkeit;
  late Datierungsquelle quelle;
  bool fehler = false;
  @override
  void initState() {
    super.initState();
    final d = widget.asset.kalenderdatierung;
    genauigkeit = d?.genauigkeit ?? Datierungsgenauigkeit.jahr;
    quelle = d?.quelle ?? Datierungsquelle.manuell;
    von = TextEditingController(
      text: _eingabe(d?.von ?? widget.asset.fileCreatedAt),
    );
    bis = TextEditingController(
      text:
          (d?.bis.subtract(const Duration(days: 1)) ??
                  widget.asset.fileCreatedAt)
              .toIso8601String()
              .substring(0, 10),
    );
    hinweis = TextEditingController(text: d?.hinweis);
  }

  String _eingabe(DateTime d) => switch (genauigkeit) {
    Datierungsgenauigkeit.jahr => '${d.year}',
    Datierungsgenauigkeit.monat => d.toIso8601String().substring(0, 7),
    _ => d.toIso8601String().substring(0, 10),
  };
  @override
  void dispose() {
    von.dispose();
    bis.dispose();
    hinweis.dispose();
    super.dispose();
  }

  void _speichern() {
    try {
      final text = von.text.trim();
      late AufnahmeDatierung d;
      if (genauigkeit == Datierungsgenauigkeit.jahr) {
        if (!RegExp(r'^[0-9]{4}$').hasMatch(text)) {
          throw const FormatException();
        }
        d = AufnahmeDatierung.jahr(
          int.parse(text),
          quelle: quelle,
          hinweis: hinweis.text.trim(),
        );
      } else if (genauigkeit == Datierungsgenauigkeit.monat) {
        if (!RegExp(r'^[0-9]{4}-[0-9]{2}$').hasMatch(text)) {
          throw const FormatException();
        }
        d = AufnahmeDatierung.monat(
          int.parse(text.substring(0, 4)),
          int.parse(text.substring(5)),
          quelle: quelle,
          hinweis: hinweis.text.trim(),
        );
      } else {
        DateTime tag(String s) {
          if (!RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$').hasMatch(s)) {
            throw const FormatException();
          }
          final d = DateTime.parse('${s}T00:00:00Z');
          if (d.toIso8601String().substring(0, 10) != s) {
            throw const FormatException();
          }
          return d;
        }

        d = genauigkeit == Datierungsgenauigkeit.tag
            ? AufnahmeDatierung.tag(
                tag(text),
                quelle: quelle,
                hinweis: hinweis.text.trim(),
              )
            : AufnahmeDatierung.zeitraum(
                tag(text),
                tag(bis.text.trim()),
                quelle: quelle,
                hinweis: hinweis.text.trim(),
              );
      }
      Navigator.pop(context, d);
    } on Object {
      setState(() => fehler = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final namen = [
      t.datierungTag,
      t.datierungMonat,
      t.datierungJahr,
      t.datierungZeitraum,
    ];
    final quellen = [
      t.datierungManuell,
      t.datierungBeschriftung,
      t.datierungUeberlieferung,
      t.datierungDatei,
      t.datierungDateiname,
      t.datierungUnbekannt,
    ];
    return AlertDialog(
      title: Text(t.datierungTitel),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t.datierungErklaerung),
              DropdownButtonFormField<Datierungsgenauigkeit>(
                isExpanded: true,
                itemHeight: null,
                initialValue: genauigkeit,
                items: [
                  for (final g in Datierungsgenauigkeit.values)
                    DropdownMenuItem(value: g, child: Text(namen[g.index])),
                ],
                onChanged: (g) {
                  if (g == null) return;
                  setState(() {
                    genauigkeit = g;
                    von.text = _eingabe(
                      widget.asset.kalenderdatierung?.von ??
                          widget.asset.fileCreatedAt,
                    );
                  });
                },
              ),
              TextField(
                contextMenuBuilder: einfuegbaresMenue,
                controller: von,
                decoration: InputDecoration(
                  labelText: t.datierungVon,
                  hintText: switch (genauigkeit) {
                    Datierungsgenauigkeit.jahr => t.datierungBeispielJahr,
                    Datierungsgenauigkeit.monat => t.datierungBeispielMonat,
                    _ => t.datierungBeispielTag,
                  },
                ),
              ),
              if (genauigkeit == Datierungsgenauigkeit.zeitraum)
                TextField(
                  contextMenuBuilder: einfuegbaresMenue,
                  controller: bis,
                  decoration: InputDecoration(
                    labelText: t.datierungBis,
                    hintText: t.datierungBeispielTag,
                  ),
                ),
              DropdownButtonFormField<Datierungsquelle>(
                isExpanded: true,
                itemHeight: null,
                initialValue: quelle,
                decoration: InputDecoration(labelText: t.datierungQuelle),
                items: [
                  for (final q in Datierungsquelle.values)
                    DropdownMenuItem(value: q, child: Text(quellen[q.index])),
                ],
                onChanged: (q) {
                  if (q != null) setState(() => quelle = q);
                },
              ),
              TextField(
                contextMenuBuilder: einfuegbaresMenue,
                controller: hinweis,
                maxLength: 160,
                decoration: InputDecoration(labelText: t.datierungHinweis),
              ),
              if (fehler)
                Text(
                  t.datierungUngueltig,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.allgAbbrechen),
        ),
        FilledButton(onPressed: _speichern, child: Text(t.allgSpeichern)),
      ],
    );
  }
}
