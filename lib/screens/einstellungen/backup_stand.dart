import 'package:flutter/material.dart';
import 'package:kern/services/backup_service.dart';

import '../../l10n/app_localizations.dart';
import '../../services/groessentext.dart';
import 'gemeinsam.dart';

/// Wie viel des automatischen Backups im Zielordner liegt und wie viel
/// noch aussteht (#303).
///
/// Entsperrt zählt sie im Ziel selbst; gesperrt zeigt sie, was der letzte
/// Lauf gesehen hat, mit seinem Datum (siehe `BackupStand`).
class BackupStandAnzeige extends StatefulWidget {
  const BackupStandAnzeige({
    super.key,
    required this.ziel,
    required this.letzterLauf,
    required this.entsperrt,
    required this.zaehle,
    required this.gemerkt,
    this.entsperren,
  });

  final String ziel;
  final DateTime? letzterLauf;
  final bool entsperrt;
  final Future<Sicherungsstand?> Function(String ziel) zaehle;
  final Future<Sicherungsstand?> Function(String ziel) gemerkt;
  final VoidCallback? entsperren;

  @override
  State<BackupStandAnzeige> createState() => _BackupStandAnzeigeState();
}

class _BackupStandAnzeigeState extends State<BackupStandAnzeige> {
  Sicherungsstand? _stand;
  var _aktuell = false;
  var _zaehlt = true;
  var _nichtErreichbar = false;
  var _lauf = 0;

  @override
  void initState() {
    super.initState();
    _lade();
  }

  @override
  void didUpdateWidget(BackupStandAnzeige alt) {
    super.didUpdateWidget(alt);
    if (alt.ziel != widget.ziel ||
        alt.letzterLauf != widget.letzterLauf ||
        alt.entsperrt != widget.entsperrt) {
      _lade();
    }
  }

  Future<void> _lade() async {
    final nummer = ++_lauf;
    final entsperrt = widget.entsperrt;
    setState(() => _zaehlt = true);
    try {
      final s = await (entsperrt ? widget.zaehle : widget.gemerkt)(widget.ziel);
      if (!mounted || nummer != _lauf) return;
      setState(() {
        _stand = s;
        _aktuell = entsperrt;
        _zaehlt = false;
        _nichtErreichbar = false;
      });
    } on Object {
      // Eine Platte, die gerade fehlt, ist kein leeres Backup.
      if (!mounted || nummer != _lauf) return;
      setState(() {
        _stand = null;
        _zaehlt = false;
        _nichtErreichbar = true;
      });
    }
  }

  List<String> _zeilen(AppTexte t, Sicherungsstand s) => [
    if (s.gesamt == 0)
      t.backupStandLeer
    else if (s.vollstaendig)
      t.backupStandAlles(s.gesamt, groessentext(s.gesamtBytes))
    else ...[
      t.backupStandGesichert(
        s.gesichert,
        s.gesamt,
        groessentext(s.gesichertBytes),
        groessentext(s.gesamtBytes),
      ),
      t.backupStandOffen(s.offen, groessentext(s.offenBytes)),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final klein = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final s = _stand;
    final kinder = <Widget>[
      if (s != null) ...[
        for (final z in _zeilen(t, s)) Text(z),
        if (s.gesamt > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: LinearProgressIndicator(value: s.anteil),
          ),
        if (!_aktuell)
          Text(t.backupStandVom(datumZeitText(context, s.am)), style: klein)
        else
          Text(t.backupStandHinweis, style: klein),
      ] else if (_zaehlt)
        Text(t.backupStandZaehlt)
      else if (_nichtErreichbar)
        Text(t.backupStandNichtErreichbar)
      else
        Text(t.backupStandGesperrt),
    ];
    return ListTile(
      leading: const Icon(Icons.pie_chart_outline),
      title: Text(t.backupStandTitel),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: kinder,
      ),
      trailing: widget.entsperrt
          ? IconButton(
              tooltip: t.backupStandNeuZaehlen,
              icon: const Icon(Icons.refresh),
              onPressed: _zaehlt ? null : _lade,
            )
          : (widget.entsperren == null
                ? null
                : TextButton(
                    onPressed: widget.entsperren,
                    child: Text(t.serverKontoEntsperren),
                  )),
    );
  }
}
