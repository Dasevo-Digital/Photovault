part of '../develop_screen.dart';

mixin _Varianten on _EntwickelnBasis {
  Future<void> _farbenKonfigurieren() async {
    _farbverwaltung ??= await Farbverwaltung.fuer(
      widget.farbpfade ?? widget.paths,
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FarbverwaltungScreen(dienst: _farbverwaltung!),
      ),
    );
    if (!mounted) return;
    try {
      _monitorprofil = (await _farbverwaltung!.laden()).bildschirm != 'system';
      _originalPreviewBytes = null;
      await _requestPreview();
      if (!_farbeAktiv) unawaited(_initShaderVorschau(unbearbeitet: false));
    } on Object {
      if (mounted) melde.fehler(AppTexte.of(context).farbraumFehler);
    }
  }

  Future<void> _farboption(String wert) async {
    _farbverwaltung ??= await Farbverwaltung.fuer(
      widget.farbpfade ?? widget.paths,
    );
    try {
      if ((await _farbverwaltung!.laden()).druck == null) {
        await _farbenKonfigurieren();
        if ((await _farbverwaltung!.laden()).druck == null) return;
      }
      if (!mounted) return;
      setState(() {
        if (wert == 'proof') _druckvorschau = !_druckvorschau;
        if (wert == 'gamut') _gamutwarnung = !_gamutwarnung;
        if (wert == 'papier') {
          _papierfarbe = !_papierfarbe;
          _druckvorschau = true;
        }
        _originalPreviewBytes = null;
        _dragging = false;
      });
      await _requestPreview();
    } on Object {
      if (mounted) melde.fehler(AppTexte.of(context).farbraumFehler);
    }
  }

  Future<void> _arbeitsVorbereiten() async {
    final t = AppTexte.of(context);
    setState(() => _saving = true);
    try {
      await Arbeitsvorschauen(
        widget.db,
        widget.paths,
      ).vorbereiten(widget.asset);
      if (mounted) melde.erfolg(t.arbeitskopienBereit);
    } on Object {
      if (mounted) melde.fehler(t.arbeitskopienFehler);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _arbeitsOeffnen() async {
    final angewandt = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ArbeitsvorschauenScreen(db: widget.db, paths: widget.paths),
      ),
    );
    if (angewandt == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _varianteSpeichern() async {
    final t = AppTexte.of(context);
    final name = await frageNamen(
      context,
      titel: t.variantenSichern,
      feldbeschriftung: t.ausbauName,
    );
    if (name == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final quelle = await _originalOderMeldung();
      if (quelle == null) return;
      _merkeMaskenentwurf();
      final jpeg = await NativeImageConverter.developImage(
        quelle,
        adjustments: _currentAdjustments(),
        masks: _currentMaskLayers(),
        maxDimension: 4096,
        quality: 0.92,
      );
      if (jpeg == null) throw StateError('pv_variante_rendern');
      await EntwicklungsvariantenDienst(widget.db, widget.paths).speichern(
        asset: widget.asset,
        name: name,
        einstellungen: _aktuellerDatensatz(),
        masken: [
          for (final m in _masks)
            m.copyWithCompanion(
              _geaenderteMasken[m.id] ?? const DevelopMasksCompanion(),
            ),
        ],
        jpeg: jpeg,
      );
      if (mounted) melde.erfolg(t.ausbauSpeichern);
    } on Object {
      if (mounted) melde.fehler(t.variantenFehler);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _variantenOeffnen() async {
    final t = AppTexte.of(context);
    final dienst = EntwicklungsvariantenDienst(widget.db, widget.paths);
    var zeilen = await widget.db.variantenFuer(widget.asset.id);
    if (!mounted) return;
    final auswahl = await showDialog<DevelopVariantData>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, neu) => AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.variantenTitel),
              Text(
                t.variantenText,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          content: SizedBox(
            width: 700,
            height: 420,
            child: zeilen.isEmpty
                ? Center(child: Text(t.variantenLeer))
                : ListView.builder(
                    itemCount: zeilen.length,
                    itemBuilder: (context, i) {
                      final v = zeilen[i];
                      return ListTile(
                        leading: SizedBox(
                          width: 64,
                          height: 56,
                          child: bibliotheksbild(
                            widget.paths,
                            v.previewRelativePath,
                            fit: BoxFit.contain,
                            cacheWidth: 128,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                        title: Text(v.name),
                        subtitle: Text(t.variantenAktivieren),
                        onTap: () => Navigator.of(dialog).pop(v),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              tooltip: t.ausbauUmbenennen,
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () async {
                                final name = await frageNamen(
                                  dialog,
                                  titel: t.ausbauUmbenennen,
                                  feldbeschriftung: t.ausbauName,
                                  vorgabe: v.name,
                                );
                                if (name == null) return;
                                try {
                                  await dienst.umbenennen(v, name);
                                  final aktuell = await widget.db.variantenFuer(
                                    widget.asset.id,
                                  );
                                  if (dialog.mounted) {
                                    neu(() => zeilen = aktuell);
                                  }
                                } on Object {
                                  if (dialog.mounted) {
                                    melde.fehler(t.variantenFehler);
                                  }
                                }
                              },
                            ),
                            IconButton(
                              tooltip: t.ausbauLoeschen,
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                if (!await confirmDialog(
                                  dialog,
                                  t.ausbauLoeschen,
                                  t.variantenLoeschenFrage,
                                )) {
                                  return;
                                }
                                try {
                                  await dienst.entfernen(v);
                                  final aktuell = await widget.db.variantenFuer(
                                    widget.asset.id,
                                  );
                                  if (dialog.mounted) {
                                    neu(() => zeilen = aktuell);
                                  }
                                } on Object {
                                  if (dialog.mounted) {
                                    melde.fehler(t.variantenFehler);
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            if (zeilen.length > 1)
              TextButton(
                onPressed: () => Navigator.of(dialog).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _VariantenVergleich(
                      paths: widget.paths,
                      varianten: zeilen,
                    ),
                  ),
                ),
                child: Text(t.variantenVergleichen),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(),
              child: Text(t.ausbauSchliessen),
            ),
          ],
        ),
      ),
    );
    if (auswahl == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await dienst.aktivieren(auswahl);
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (mounted) melde.fehler(t.variantenFehler);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _zuschnittAendern() async {
    final quelle = await _originalOderMeldung();
    if (quelle == null) return;
    final jpeg = await NativeImageConverter.developImage(
      quelle,
      adjustments: DevelopAdjustments.neutral,
      maxDimension: 800,
    );
    if (!mounted) return;
    final z = await showDialog<Bildzuschnitt>(
      context: context,
      builder: (_) => _ZuschnittDialog(start: _zuschnitt, jpeg: jpeg),
    );
    if (z == null || !mounted) return;
    setState(() {
      _zuschnitt = z;
      _dragging = false;
    });
    _scheduleRerender();
  }
}

class _VariantenVergleich extends StatefulWidget {
  const _VariantenVergleich({required this.paths, required this.varianten});
  final StoragePaths paths;
  final List<DevelopVariantData> varianten;
  @override
  State<_VariantenVergleich> createState() => _VariantenVergleichState();
}

class _VariantenVergleichState extends State<_VariantenVergleich> {
  int _links = 0, _rechts = 1;
  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    Widget seite(int n, ValueChanged<int?> waehlen) => Expanded(
      child: Column(
        children: [
          DropdownButton<int>(
            value: n,
            items: [
              for (var i = 0; i < widget.varianten.length; i++)
                DropdownMenuItem(
                  value: i,
                  child: Text(widget.varianten[i].name),
                ),
            ],
            onChanged: waehlen,
          ),
          Expanded(
            child: bibliotheksbild(
              widget.paths,
              widget.varianten[n].previewRelativePath,
              fit: BoxFit.contain,
              cacheWidth: 1600,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.broken_image_outlined),
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(t.variantenVergleichen)),
      body: Row(
        children: [
          seite(_links, (n) {
            if (n != null) setState(() => _links = n);
          }),
          const VerticalDivider(),
          seite(_rechts, (n) {
            if (n != null) setState(() => _rechts = n);
          }),
        ],
      ),
    );
  }
}

class _ZuschnittDialog extends StatefulWidget {
  const _ZuschnittDialog({required this.start, this.jpeg});
  final Uint8List? jpeg;
  final Bildzuschnitt start;
  @override
  State<_ZuschnittDialog> createState() => _ZuschnittDialogState();
}

class _ZuschnittDialogState extends State<_ZuschnittDialog> {
  late final _werte = [
    for (final x in [
      widget.start.links,
      widget.start.oben,
      widget.start.breite,
      widget.start.hoehe,
    ])
      TextEditingController(text: (x * 100).toStringAsFixed(2)),
  ];
  late int _drehungen = widget.start.drehungen;
  bool _fehler = false;
  Bildzuschnitt get _auswahl {
    try {
      final w = [
        for (final e in _werte) double.parse(e.text.replaceAll(',', '.')) / 100,
      ];
      return Bildzuschnitt(
        links: w[0],
        oben: w[1],
        breite: w[2],
        hoehe: w[3],
        drehungen: _drehungen,
      );
    } on Object {
      return Bildzuschnitt(drehungen: _drehungen);
    }
  }

  void _auswahlSetzen(Bildzuschnitt z) {
    setState(() {
      final w = [z.links, z.oben, z.breite, z.hoehe];
      for (var i = 0; i < 4; i++) {
        _werte[i].text = (w[i] * 100).toStringAsFixed(4);
      }
      _fehler = false;
    });
  }

  @override
  void dispose() {
    for (final w in _werte) {
      w.dispose();
    }
    super.dispose();
  }

  void _speichern() {
    try {
      final w = [
        for (final e in _werte) double.parse(e.text.replaceAll(',', '.')) / 100,
      ];
      final z = Bildzuschnitt(
        links: w[0],
        oben: w[1],
        breite: w[2],
        hoehe: w[3],
        drehungen: _drehungen,
      );
      Navigator.of(context).pop(z);
    } on Object {
      setState(() => _fehler = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final labels = [
      t.zuschnittLinks,
      t.zuschnittOben,
      t.zuschnittBreite,
      t.zuschnittHoehe,
    ];
    return AlertDialog(
      title: Text(t.zuschnittTitel),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.jpeg != null) ...[
                SizedBox(
                  height: 260,
                  child: ZuschnittAuswahl(
                    jpeg: widget.jpeg!,
                    wert: _auswahl,
                    beiAuswahl: _auswahlSetzen,
                    beschreibung: t.zuschnittZiehen,
                  ),
                ),
                Text(t.zuschnittZiehen),
                const SizedBox(height: 12),
              ],
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _werte[i],
                    contextMenuBuilder: einfuegbaresMenue,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    maxLength: 10,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(labelText: labels[i]),
                  ),
                ),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _drehungen = (_drehungen + 1) % 4),
                icon: const Icon(Icons.rotate_right),
                label: Text('${t.zuschnittDrehen} · ${_drehungen * 90}°'),
              ),
              if (_fehler) Text(t.variantenFehler),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.ausbauAbbrechen),
        ),
        FilledButton(onPressed: _speichern, child: Text(t.ausbauSpeichern)),
      ],
    );
  }
}
